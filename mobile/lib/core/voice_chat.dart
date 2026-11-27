import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Lightweight, room-scoped mesh voice chat for four-player Okey tables.
/// Signalling travels through Supabase Realtime broadcast; media is peer-to-peer.
/// TURN credentials can be supplied at build time for restrictive mobile networks.
class VoiceChatService {
  VoiceChatService({
    required this.client,
    required this.roomId,
    required this.playerId,
    required this.onSpeakingChanged,
    required this.onError,
  });

  final SupabaseClient client;
  final String roomId;
  final String playerId;
  final ValueChanged<Set<String>> onSpeakingChanged;
  final ValueChanged<String> onError;

  static const _turnUrl = String.fromEnvironment('OKEYX_TURN_URL');
  static const _turnUser = String.fromEnvironment('OKEYX_TURN_USER');
  static const _turnCredential = String.fromEnvironment('OKEYX_TURN_CREDENTIAL');

  RealtimeChannel? _channel;
  MediaStream? _localStream;
  final Map<String, RTCPeerConnection> _peers = {};
  final Set<String> _knownPlayers = {};
  final Set<String> _muted = {};
  final Set<String> _speaking = {};
  Timer? _levelTimer;
  bool _enabled = false;
  bool _disposed = false;

  bool get enabled => _enabled;
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

  Future<void> enable(Iterable<String> peers) async {
    if (_disposed || _enabled) {
      await syncPeers(peers);
      return;
    }
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
      await Helper.setSpeakerphoneOn(true);
      _enabled = true;
      await _subscribe();
      await syncPeers(peers);
      _startLevelMeter();
      await _broadcast({'type': 'presence', 'enabled': true});
    } catch (e) {
      _enabled = false;
      onError('Mikrofon açılamadı: $e');
      rethrow;
    }
  }

  Future<void> disable() async {
    if (!_enabled && _localStream == null) return;
    try {
      await _broadcast({'type': 'presence', 'enabled': false});
    } catch (_) {}
    _enabled = false;
    for (final pc in _peers.values) {
      try {
        await pc.close();
      } catch (_) {}
    }
    _peers.clear();
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
        if (track?.kind == 'audio') track?.enabled = !muted;
      }
    }
  }

  Future<void> syncPeers(Iterable<String> peerIds) async {
    if (!_enabled || _disposed) return;
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
      // Stable lexical ordering prevents offer glare when two players join at once.
      if (playerId.compareTo(id) < 0) await _makeOffer(id, pc);
    }
  }

  Future<void> _subscribe() async {
    if (_channel != null) return;
    final channel = client.channel('okeyx_voice_$roomId');
    channel.onBroadcast(
      event: 'signal',
      callback: (payload) {
        unawaited(_handleSignal(Map<String, dynamic>.from(payload)));
      },
    );
    channel.subscribe();
    _channel = channel;
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
      if (track.kind == 'audio') track.enabled = !_muted.contains(remoteId);
    };
    pc.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        if (_speaking.remove(remoteId)) onSpeakingChanged(Set.unmodifiable(_speaking));
      }
    };
    return pc;
  }

  Future<void> _makeOffer(String remoteId, RTCPeerConnection pc) async {
    final offer = await pc.createOffer({'offerToReceiveAudio': 1});
    await pc.setLocalDescription(offer);
    await _sendTo(remoteId, {'type': 'offer', 'sdp': offer.sdp});
  }

  Future<void> _handleSignal(Map<String, dynamic> payload) async {
    if (!_enabled || _disposed) return;
    final from = '${payload['from'] ?? ''}';
    final to = '${payload['to'] ?? ''}';
    if (from.isEmpty || from == playerId || (to.isNotEmpty && to != playerId)) return;
    final dataRaw = payload['data'];
    final data = dataRaw is Map ? Map<String, dynamic>.from(dataRaw) : <String, dynamic>{};
    final type = '${data['type'] ?? ''}';
    if (type == 'presence') {
      if (data['enabled'] == true && _knownPlayers.contains(from)) {
        final pc = _peers[from] ?? await _createPeer(from);
        _peers[from] = pc;
        if (playerId.compareTo(from) < 0) await _makeOffer(from, pc);
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
        await pc.setRemoteDescription(RTCSessionDescription('${data['sdp'] ?? ''}', 'offer'));
        final answer = await pc.createAnswer({'offerToReceiveAudio': 1});
        await pc.setLocalDescription(answer);
        await _sendTo(from, {'type': 'answer', 'sdp': answer.sdp});
      } else if (type == 'answer') {
        await pc.setRemoteDescription(RTCSessionDescription('${data['sdp'] ?? ''}', 'answer'));
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
      unawaited(_pollRemoteAudioLevels());
    });
  }

  Future<void> _pollRemoteAudioLevels() async {
    if (!_enabled || _disposed) return;
    final nowSpeaking = <String>{};
    for (final entry in _peers.entries) {
      final remoteId = entry.key;
      if (_muted.contains(remoteId)) continue;
      try {
        final reports = await entry.value.getStats();
        var active = false;
        for (final report in reports) {
          if (report.type != 'inbound-rtp') continue;
          final values = report.values;
          final kind = '${values['kind'] ?? values['mediaType'] ?? ''}'.toLowerCase();
          if (kind.isNotEmpty && kind != 'audio') continue;
          final raw = values['audioLevel'];
          final level = raw is num ? raw.toDouble() : double.tryParse('$raw') ?? 0;
          if (level >= .012) {
            active = true;
            break;
          }
        }
        if (active) nowSpeaking.add(remoteId);
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
