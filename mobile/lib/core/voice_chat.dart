import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Masa içi sesli sohbet (4 kişilik mesh).
///
/// * Sinyalleşme Supabase Realtime broadcast ile, ses eşler arası (WebRTC).
/// * [join] mikrofon izni istemeden masayı DİNLEMEYE başlar; böylece biri
///   konuştuğunda mikrofonunu açmamış oyuncular da duyar.
/// * [setMic] mikrofonu açar/kapatır (bas-konuş ve sürekli açık için).
/// * Kanal gerçekten abone olmadan mesaj gönderilmez (eski sürümde ilk teklif
///   kayboluyor, bağlantı hiç kurulmuyordu).
class VoiceChatService {
  VoiceChatService({
    required this.client,
    required this.roomId,
    required this.playerId,
    required this.onSpeakingChanged,
    required this.onError,
    this.onRemoteMic,
  });

  /// Dinlemiyorken biri mikrofonunu açınca haber verir (ses moduna dokunmadan).
  final ValueChanged<String>? onRemoteMic;

  final SupabaseClient client;
  final String roomId;
  final String playerId;
  final ValueChanged<Set<String>> onSpeakingChanged;
  final ValueChanged<String> onError;

  static const _turnUrl = String.fromEnvironment('OKEYX_TURN_URL');
  static const _turnUser = String.fromEnvironment('OKEYX_TURN_USER');
  static const _turnCredential = String.fromEnvironment('OKEYX_TURN_CREDENTIAL');

  RealtimeChannel? _channel;
  Completer<void>? _subscribed;
  MediaStream? _localStream;
  final Map<String, RTCPeerConnection> _peers = {};
  final Map<String, bool> _makingOffer = {};
  final Set<String> _knownPlayers = {};
  final Set<String> _muted = {};
  final Set<String> _speaking = {};
  Timer? _levelTimer;
  bool _joined = false;
  bool _micOn = false;
  bool _disposed = false;

  bool get joined => _joined;
  bool get micOn => _micOn;
  bool get enabled => _joined;
  Set<String> get mutedPlayers => Set.unmodifiable(_muted);

  List<Map<String, dynamic>> get _iceServers {
    final out = <Map<String, dynamic>>[
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ];
    if (_turnUrl.trim().isNotEmpty) {
      out.add({
        'urls': _turnUrl.trim(),
        if (_turnUser.trim().isNotEmpty) 'username': _turnUser.trim(),
        if (_turnCredential.trim().isNotEmpty) 'credential': _turnCredential.trim(),
      });
    }
    return out;
  }

  /// Yalnızca sinyal kanalını izle: ses donanımına dokunmaz, oyun sesleri etkilenmez.
  Future<void> watch() async {
    if (_disposed) return;
    await _subscribe();
  }

  /// Masayı dinlemeye başla (mikrofon izni gerekmez).
  Future<void> join(Iterable<String> peers) async {
    if (_disposed) return;
    if (!_joined) {
      _joined = true;
      try {
        await Helper.setSpeakerphoneOn(true);
      } catch (_) {}
      await _subscribe();
      _startLevelMeter();
      await _broadcast({'data': {'type': 'presence', 'enabled': true}});
    }
    await syncPeers(peers);
  }

  /// Eski arayüz uyumluluğu: dinle + mikrofonu aç.
  Future<void> enable(Iterable<String> peers) async {
    await join(peers);
    await setMic(true);
  }

  /// Mikrofonu aç/kapat. İlk açılışta izin istenir ve tüm eşlerle yeniden anlaşılır.
  Future<void> setMic(bool on) async {
    if (_disposed) return;
    if (on && _localStream == null) {
      try {
        _localStream = await navigator.mediaDevices.getUserMedia({
          'audio': {
            'echoCancellation': true,
            'noiseSuppression': true,
            'autoGainControl': true,
            'channelCount': 1,
          },
          'video': false,
        });
      } catch (e) {
        onError('Mikrofon açılamadı. Ayarlardan mikrofon iznini kontrol et.');
        rethrow;
      }
      for (final entry in _peers.entries) {
        for (final track in _localStream!.getAudioTracks()) {
          await entry.value.addTrack(track, _localStream!);
        }
        await _makeOffer(entry.key, entry.value);
      }
    }
    for (final track in _localStream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = on;
      // Bazı Android cihazlarda yalnızca enabled=false yetmiyor: mikrofonu da sustur.
      try {
        await Helper.setMicrophoneMute(!on, track);
      } catch (_) {}
    }
    _micOn = on;
  }

  Future<void> disable() async {
    if (!_joined && _localStream == null) return;
    try {
      await _broadcast({'data': {'type': 'presence', 'enabled': false}});
    } catch (_) {}
    _joined = false;
    _micOn = false;
    for (final pc in _peers.values) {
      try {
        await pc.close();
      } catch (_) {}
    }
    _peers.clear();
    _makingOffer.clear();
    for (final track in _localStream?.getTracks() ?? <MediaStreamTrack>[]) {
      try {
        track.stop();
      } catch (_) {}
    }
    try {
      await _localStream?.dispose();
    } catch (_) {}
    _localStream = null;
    final channel = _channel;
    _channel = null;
    _subscribed = null;
    if (channel != null) {
      try {
        await client.removeChannel(channel);
      } catch (_) {}
    }
    _levelTimer?.cancel();
    _levelTimer = null;
    _speaking.clear();
    onSpeakingChanged(Set.unmodifiable(_speaking));
  }

  final Map<String, List<MediaStreamTrack>> _remoteTracks = {};

  /// Uzak oyuncuyu sustur: izi kapat ve çalma sesini sıfırla (iki yolla da).
  Future<void> _applyRemoteMute(MediaStreamTrack track, bool muted) async {
    track.enabled = !muted;
    try {
      await Helper.setVolume(muted ? 0.0 : 1.0, track);
    } catch (_) {}
  }

  Future<void> setMuted(String targetPlayerId, bool muted) async {
    if (muted) {
      _muted.add(targetPlayerId);
    } else {
      _muted.remove(targetPlayerId);
    }
    final pc = _peers[targetPlayerId];
    if (pc != null) {
      for (final receiver in await pc.getReceivers()) {
        final track = receiver.track;
        if (track != null && track.kind == 'audio') await _applyRemoteMute(track, muted);
      }
    }
    for (final track in _remoteTracks[targetPlayerId] ?? const <MediaStreamTrack>[]) {
      await _applyRemoteMute(track, muted);
    }
  }

  Future<void> syncPeers(Iterable<String> peerIds) async {
    if (!_joined || _disposed) return;
    final next = peerIds.where((e) => e.isNotEmpty && e != playerId).toSet();
    _knownPlayers
      ..clear()
      ..addAll(next);
    final stale = _peers.keys.where((id) => !next.contains(id)).toList();
    for (final id in stale) {
      try {
        await _peers.remove(id)?.close();
      } catch (_) {}
    }
    for (final id in next) {
      if (_peers.containsKey(id)) continue;
      final pc = await _createPeer(id);
      _peers[id] = pc;
      // Kararlı sıralama: aynı anda katılan iki oyuncu çakışan teklif göndermez.
      if (playerId.compareTo(id) < 0) await _makeOffer(id, pc);
    }
  }

  Future<void> _subscribe() async {
    if (_channel != null) {
      await _subscribed?.future.timeout(const Duration(seconds: 8), onTimeout: () {});
      return;
    }
    final done = Completer<void>();
    _subscribed = done;
    final channel = client.channel('okeyx_voice_$roomId');
    channel.onBroadcast(
      event: 'signal',
      callback: (payload) {
        unawaited(_handleSignal(Map<String, dynamic>.from(payload)));
      },
    );
    channel.subscribe((status, error) {
      if (status == RealtimeSubscribeStatus.subscribed) {
        if (!done.isCompleted) done.complete();
      } else if (status == RealtimeSubscribeStatus.channelError || status == RealtimeSubscribeStatus.timedOut) {
        debugPrint('OKEYX_VOICE_CHANNEL $status $error');
      }
    });
    _channel = channel;
    await done.future.timeout(const Duration(seconds: 8), onTimeout: () {
      onError('Sesli sohbet sunucusuna bağlanılamadı.');
    });
  }

  Future<RTCPeerConnection> _createPeer(String remoteId) async {
    final pc = await createPeerConnection({
      'iceServers': _iceServers,
      'sdpSemantics': 'unified-plan',
    }, {
      'mandatory': {},
      'optional': [
        {'DtlsSrtpKeyAgreement': true},
      ],
    });
    // Mikrofonu açmamış oyuncu da karşı tarafı duyabilsin diye alıcı hattı hep var.
    await pc.addTransceiver(
      kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
      init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
    );
    for (final track in _localStream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      await pc.addTrack(track, _localStream!);
    }
    pc.onIceCandidate = (candidate) {
      if (candidate.candidate == null) return;
      unawaited(_sendTo(remoteId, {
        'type': 'candidate',
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      }));
    };
    pc.onTrack = (event) {
      final track = event.track;
      if (track.kind != 'audio') return;
      _remoteTracks.putIfAbsent(remoteId, () => <MediaStreamTrack>[]).add(track);
      unawaited(_applyRemoteMute(track, _muted.contains(remoteId)));
    };
    pc.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        // Bağlantı koptu: kısa süre sonra yeniden dene.
        Future<void>.delayed(const Duration(seconds: 2), () async {
          if (!_joined || _disposed || _peers[remoteId] != pc) return;
          try {
            await pc.close();
          } catch (_) {}
          final fresh = await _createPeer(remoteId);
          _peers[remoteId] = fresh;
          await _makeOffer(remoteId, fresh);
        });
      }
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        if (_speaking.remove(remoteId)) onSpeakingChanged(Set.unmodifiable(_speaking));
      }
    };
    return pc;
  }

  Future<void> _makeOffer(String remoteId, RTCPeerConnection pc) async {
    try {
      _makingOffer[remoteId] = true;
      final offer = await pc.createOffer({'offerToReceiveAudio': 1});
      await pc.setLocalDescription(offer);
      await _sendTo(remoteId, {'type': 'offer', 'sdp': offer.sdp});
    } catch (e) {
      debugPrint('OKEYX_VOICE_OFFER $e');
    } finally {
      _makingOffer[remoteId] = false;
    }
  }

  Future<void> _handleSignal(Map<String, dynamic> payload) async {
    if (_disposed) return;
    final from = '${payload['from'] ?? ''}';
    if (!_joined) {
      final raw = payload['data'];
      if (raw is Map && raw['type'] == 'presence' && raw['enabled'] == true && from.isNotEmpty && from != playerId) {
        onRemoteMic?.call(from);
      }
      return;
    }
    final to = '${payload['to'] ?? ''}';
    if (from.isEmpty || from == playerId || (to.isNotEmpty && to != playerId)) return;
    final dataRaw = payload['data'];
    final data = dataRaw is Map ? Map<String, dynamic>.from(dataRaw) : <String, dynamic>{};
    final type = '${data['type'] ?? ''}';
    if (type == 'presence') {
      if (data['enabled'] == true) {
        _knownPlayers.add(from);
        var pc = _peers[from];
        if (pc == null) {
          pc = await _createPeer(from);
          _peers[from] = pc;
        }
        if (playerId.compareTo(from) < 0) await _makeOffer(from, pc);
      } else {
        try {
          await _peers.remove(from)?.close();
        } catch (_) {}
      }
      return;
    }
    var pc = _peers[from];
    if (pc == null) {
      pc = await _createPeer(from);
      _peers[from] = pc;
    }
    try {
      if (type == 'offer') {
        // Çakışma: iki taraf aynı anda teklif ettiyse "kibar" taraf geri adım atar.
        final polite = playerId.compareTo(from) > 0;
        final collision = _makingOffer[from] == true || pc.signalingState == RTCSignalingState.RTCSignalingStateHaveLocalOffer;
        if (collision && !polite) return;
        if (collision) {
          await pc.setLocalDescription(RTCSessionDescription('', 'rollback'));
        }
        await pc.setRemoteDescription(RTCSessionDescription('${data['sdp'] ?? ''}', 'offer'));
        final answer = await pc.createAnswer({'offerToReceiveAudio': 1});
        await pc.setLocalDescription(answer);
        await _sendTo(from, {'type': 'answer', 'sdp': answer.sdp});
      } else if (type == 'answer') {
        if (pc.signalingState == RTCSignalingState.RTCSignalingStateHaveLocalOffer) {
          await pc.setRemoteDescription(RTCSessionDescription('${data['sdp'] ?? ''}', 'answer'));
        }
      } else if (type == 'candidate') {
        final candidate = '${data['candidate'] ?? ''}';
        if (candidate.isNotEmpty) {
          await pc.addCandidate(RTCIceCandidate(
            candidate,
            data['sdpMid'] as String?,
            (data['sdpMLineIndex'] as num?)?.toInt(),
          ));
        }
      }
    } catch (e) {
      debugPrint('OKEYX_VOICE_SIGNAL[$type/$from] $e');
    }
  }

  Future<void> _sendTo(String remoteId, Map<String, dynamic> data) =>
      _broadcast({'to': remoteId, 'data': data});

  Future<void> _broadcast(Map<String, dynamic> message) async {
    final channel = _channel;
    if (channel == null) return;
    await _subscribed?.future.timeout(const Duration(seconds: 8), onTimeout: () {});
    await channel.sendBroadcastMessage(
      event: 'signal',
      payload: {
        'from': playerId,
        'to': message['to'] ?? '',
        'data': message['data'] ?? message,
        'at': DateTime.now().millisecondsSinceEpoch,
      },
    );
  }

  void _startLevelMeter() {
    _levelTimer?.cancel();
    _levelTimer = Timer.periodic(const Duration(milliseconds: 280), (_) {
      unawaited(_pollAudioLevels());
    });
  }

  Future<void> _pollAudioLevels() async {
    if (!_joined || _disposed) return;
    final nowSpeaking = <String>{};
    for (final entry in _peers.entries) {
      final remoteId = entry.key;
      if (_muted.contains(remoteId)) continue;
      try {
        final reports = await entry.value.getStats();
        var active = false;
        var localActive = false;
        for (final report in reports) {
          final values = report.values;
          final kind = '${values['kind'] ?? values['mediaType'] ?? ''}'.toLowerCase();
          if (kind.isNotEmpty && kind != 'audio') continue;
          final raw = values['audioLevel'];
          final level = raw is num ? raw.toDouble() : double.tryParse('$raw') ?? 0;
          if (report.type == 'inbound-rtp' && level >= .012) active = true;
          if (report.type == 'media-source' && level >= .02) localActive = true;
        }
        if (active) nowSpeaking.add(remoteId);
        if (localActive && _micOn) nowSpeaking.add(playerId);
      } catch (_) {}
    }
    if (setEquals(nowSpeaking, _speaking)) return;
    _speaking
      ..clear()
      ..addAll(nowSpeaking);
    onSpeakingChanged(Set.unmodifiable(_speaking));
  }

  Future<void> dispose() async {
    _disposed = true;
    _levelTimer?.cancel();
    _levelTimer = null;
    await disable();
  }
}
