import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_theme.dart';
import '../../core/game_audio.dart';
import '../../core/live_features.dart';
import '../../core/voice_chat.dart';
import '../../widgets/okx_kit.dart';
import '../../widgets/tile_widget.dart';
import '../../widgets/premium_radio_panel.dart';
import '../../widgets/real_rack.dart';
import '../auth/profile_repository.dart';
import '../lobby/lobby_api.dart';
import 'game_api.dart';
import 'table_fx.dart';

class TableScreen extends StatefulWidget {
  final PlayerProfile profile;
  final UserPreferences preferences;
  final Future<void> Function()? onClose;
  final GameSession? initialSession;
  final ValueChanged<UserPreferences>? onPreferencesChanged;

  const TableScreen({
    super.key,
    required this.profile,
    required this.preferences,
    this.onClose,
    this.initialSession,
    this.onPreferencesChanged,
  });

  @override
  State<TableScreen> createState() => _TableScreenState();
}

class _TableScreenState extends State<TableScreen> with WidgetsBindingObserver {
  late final GameApiClient _api;
  Map<String, dynamic> _state = const {};
  final TableFxController _fx = TableFxController();
  Timer? _clock;
  bool _loading = true;
  bool _busy = false;
  bool _online = false;
  String _connection = 'BAĞLANIYOR';
  String _error = '';
  String? _selectedTileId;
  static const int _rackCols = 15;
  static const int _rackRows = 2;
  static const int _rackSlotCount = _rackCols * _rackRows;

  final GlobalKey _rackKey = GlobalKey();
  final List<String?> _rackSlots = List<String?>.filled(_rackSlotCount, null);
  final List<GlobalKey> _rackSlotKeys =
      List<GlobalKey>.generate(_rackSlotCount, (_) => GlobalKey());
  final Set<String> _rackGroupStarts = <String>{};
  // Yardımsız modda gerçek okey basılı tutulup arka yüzüne çevrilebilir.
  // İsim eski sürümden kalma; sette bulunması artık 'kapalı' anlamına gelir.
  final Set<String> _revealedJokerIds = <String>{};
  List<String> _longPressRackGroupIds = const <String>[];
  Offset? _longPressStartGlobal;
  Offset _longPressRackGroupDelta = Offset.zero;
  bool _longPressRackGroupMoved = false;
  String? _rackHandKey;
  bool _rackManuallyEdited = false;
  String? _draggingRackId;
  int _rackHoverSlot = -1;
  bool _rackHoverInsertAfter = false;
  String? _rackDropPulseId;
  String? _lastRackTapId;
  int _lastRackTapMs = 0;
  final ValueNotifier<int> _nowMsNotifier =
      ValueNotifier<int>(DateTime.now().millisecondsSinceEpoch);
  int _seenEventSequence = 0;
  String _lastStateRevision = '';
  String _eventText = '';
  String _eventType = '';
  String? _shownRoundKey;
  String? _seenChatId;
  String? _seenReactionId;
  String _giftText = '';
  String _giftKind = '';
  int? _giftFromSeat;
  int? _giftToSeat;
  String? _giftEventId;
  int? _impactSeat;
  final Map<int, GlobalKey> _avatarKeys = {};
  bool _reactionsPrimed = false;
  int _canakSeenAt = -1;
  Map<String, dynamic>? _canakBreak;
  final Set<String> _peekJokerIds = <String>{};
  List<List<Map<String, dynamic>>> _lastLocalSeriesGroups = const [];
  String _impactKind = '';
  String? _impactEventId;
  int? _rageSeat;
  String? _rageEventKey;
  final Map<int, String> _chatBubbles = <int, String>{};
  final Map<int, String> _chatBubbleIds = <int, String>{};
  int _lastTurnSeat = -1;
  int _turnCueSeq = 0;
  bool _showTurnCue = false;
  int _turboFxSeq = 0;
  int _turboFxCount = 1;
  int _lastWarningSecond = -1;
  int _drawRevealSeq = 0;
  Map<String, dynamic>? _drawRevealTile;
  bool _drawRevealHot = false;
  String _drawRevealText = '';
  String? _openingSplashKey;
  int _openingSplashSeat = -1;
  String _openingSplashMode = '';
  int _openingSplashValue = 0;
  int _lastIntroUntilMs = 0;
  int _lastIntroCountdown = -1;
  int _dealSequence = 0;
  bool _dealAnimating = false;
  bool _autoRematchScheduled = false;
  String? _playedMusicKitRoundKey;
  String _activeSoundPack = 'sound_classic';
  final Map<int,String> _penaltyBadges=<int,String>{};
  final Map<int, _StuckGift> _stuckGifts = <int, _StuckGift>{};
  final Map<String, int> _giftCooldownUntil = <String, int>{};
  String? _giftId;
  _BigGift? _bigGift;
  late bool _soundEnabled;
  late bool _musicEnabled;
  late bool _ambienceEnabled;
  late bool _radioEnabled;
  late String _tableRadioStation;
  late bool _vibrationEnabled;
  late double _sfxVolume;
  late double _radioVolume;
  OkeyXNowPlaying _radioNowPlaying = const OkeyXNowPlaying('', '');
  late double _ambienceVolume;
  OkeyXLiveFeatures _liveFeatures = const OkeyXLiveFeatures();
  VoiceChatService? _voiceChat;
  bool _voiceEnabled = false;
  bool _voiceMicOn = false;
  int _micPulse = 0;
  String? _voiceInvite;
  bool _voiceAutoTried = false;
  bool _voiceBusy = false;
  final Set<String> _voiceMutedPlayers = <String>{};
  Set<String> _voiceSpeakingPlayers = <String>{};
  int _fidgetTicks = 0;
  bool _fidgetCoinFace = false;

  /// Uygulama arka plandan dönünce masayı hemen yenile ve soketi yeniden kur
  /// (telefon uyku/ağ değişimi sonrası el ve sıra bilgisi doğru gelsin).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      unawaited(_api.refresh());
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _soundEnabled = widget.preferences.soundEnabled;
    _musicEnabled = widget.preferences.musicEnabled;
    _ambienceEnabled = widget.preferences.tableAmbienceEnabled;
    _radioEnabled = widget.preferences.radioEnabled;
    _tableRadioStation = widget.preferences.radioStation;
    _vibrationEnabled = widget.preferences.vibrationEnabled;
    _sfxVolume = widget.preferences.sfxVolume;
    _radioVolume = widget.preferences.radioVolume;
    _ambienceVolume = widget.preferences.ambienceVolume;
    unawaited(_initTableAudio());
    _api = GameApiClient(
      profile: widget.profile,
      onState: _receiveState,
      initialSession: widget.initialSession,
      onConnection: (online, message) {
        if (!mounted) return;
        setState(() {
          _online = online;
          _connection = message;
        });
      },
    );
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      _nowMsNotifier.value = now;
      final introUntil = _integer(_state['intro_until_ms']);
      final introLeft = introUntil > now ? ((introUntil - now) / 1000).ceil().clamp(1, 5).toInt() : 0;
      if (introLeft > 0 && introLeft != _lastIntroCountdown) {
        _lastIntroCountdown = introLeft;
        unawaited(GameAudio.sfx('countdown', enabled: _soundEnabled, volume: .58));
        if (_vibrationEnabled && introLeft <= 3) unawaited(HapticFeedback.selectionClick());
      } else if (introLeft == 0) {
        _lastIntroCountdown = -1;
      }
      final left = _secondsLeftAt(now);
      if (_myTurn && left > 0 && left <= 5 && _lastWarningSecond != left) {
        _lastWarningSecond = left;
        unawaited(GameAudio.sfx('warning', enabled: _soundEnabled, volume: .56));
        if (_vibrationEnabled) {
          unawaited(HapticFeedback.mediumImpact());
        }
      } else if (!_myTurn || left > 5) {
        _lastWarningSecond = -1;
      }
    });
    unawaited(_start());
    Future<void>.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) unawaited(GameAudio.prewarm());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clock?.cancel();
    _nowMsNotifier.dispose();
    unawaited(_api.dispose());
    unawaited(_voiceChat?.dispose());
    unawaited(GameAudio.setVoiceDucked(false));
    unawaited(GameAudio.stopAmbience());
    unawaited(GameAudio.stopRadio());
    super.dispose();
  }

  Iterable<String> _voicePeerIds([Map<String,dynamic>? snapshot]) {
    final source = snapshot ?? _state;
    return _list(source['players'])
        .map(_map)
        .where((p) => p['bot'] != true && p['connected'] != false)
        .map((p) => '${p['player_id'] ?? ''}'.trim())
        .where((id) => id.isNotEmpty && id != widget.profile.userId);
  }

  VoiceChatService _ensureVoice(String roomId) => _voiceChat ??= VoiceChatService(
        client: Supabase.instance.client,
        roomId: roomId,
        playerId: widget.profile.userId,
        onSpeakingChanged: (speaking) {
          if (!mounted) return;
          setState(() => _voiceSpeakingPlayers = speaking);
          unawaited(GameAudio.setVoiceDucked(speaking.any((id) => id != widget.profile.userId)));
        },
        onError: (message) {
          if (mounted) _tableNotice(message);
        },
        onRemoteMic: (from) {
          if (!mounted || _voiceEnabled) return;
          final p = _list(_state['players']).map(_map).firstWhere((x) => '${x['player_id']}' == from, orElse: () => const <String, dynamic>{});
          setState(() => _voiceInvite = '${p['name'] ?? 'Bir oyuncu'}');
          Future<void>.delayed(const Duration(seconds: 8), () { if (mounted) setState(() => _voiceInvite = null); });
        },
      );

  /// Dinlemeden önce yalnızca kanalı izle: biri mikrofon açarsa "dinle" daveti çıkar.
  Future<void> _autoJoinVoice() async {
    if (_voiceEnabled || _voiceBusy || _voiceAutoTried) return;
    final roomId = '${_state['room_id'] ?? _api.roomId ?? ''}'.trim();
    if (roomId.isEmpty) return;
    _voiceAutoTried = true;
    try {
      await _ensureVoice(roomId).watch();
    } catch (_) {}
  }

  /// Dokun: mikrofonu aç/kapat. Basılı tut: bas-konuş.
  Future<void> _toggleVoice({bool? talk}) async {
    if (_voiceBusy) return;
    final roomId = '${_state['room_id'] ?? _api.roomId ?? ''}'.trim();
    if (roomId.isEmpty) {
      _tableNotice('Sesli sohbet için önce masaya bağlan.');
      return;
    }
    setState(() => _voiceBusy = true);
    try {
      final voice = _ensureVoice(roomId);
      if (!voice.joined) {
        await voice.join(_voicePeerIds());
        _voiceEnabled = true;
      }
      final next = talk ?? !_voiceMicOn;
      await voice.setMic(next);
      if (!mounted) return;
      setState(() => _voiceMicOn = next);
      try { await LobbyApiClient(widget.profile).setVoice(enabled: next); } catch (_) {}
      if (talk == null) _tableNotice(next ? 'Mikrofon açık. Herkes seni duyuyor.' : 'Mikrofon kapalı. Masayı dinlemeye devam ediyorsun.');
      if (_vibrationEnabled) unawaited(HapticFeedback.selectionClick());
    } catch (_) {
      if (mounted) _tableNotice('Mikrofon izni verilmedi veya sesli sohbet başlatılamadı.');
    } finally {
      if (mounted) setState(() => _voiceBusy = false);
    }
  }

  Future<void> _syncVoicePeers(Map<String,dynamic> snapshot) async {
    if (!_voiceEnabled) return;
    try { await _voiceChat?.syncPeers(_voicePeerIds(snapshot)); } catch (_) {}
  }

  Future<void> _toggleVoiceMute(String targetId, String name) async {
    if (targetId.isEmpty) return;
    final muted = !_voiceMutedPlayers.contains(targetId);
    if (muted) {
      _voiceMutedPlayers.add(targetId);
    } else {
      _voiceMutedPlayers.remove(targetId);
    }
    if (mounted) setState(() {});
    try { await _voiceChat?.setMuted(targetId, muted); } catch (_) {}
    try { await LobbyApiClient(widget.profile).setVoice(mutePlayerId:targetId, muted:muted); } catch (_) {}
    _tableNotice(muted ? '$name sesi kapatıldı.' : '$name sesi açıldı.');
  }

  // ═══════════════════════ KAHVEHANE MASA DÜZENİ ═══════════════════════
  // Tüm konumlar onaylanan taslağın 1000×450 çerçevesinden ölçeklenir
  // (bkz. _Frame). Böylece telefon, katlanabilir ve tablette aynı düzen korunur.

  bool get _bigNumbers => widget.preferences.bigTileNumbers;
  bool get _reducedFx => widget.preferences.reducedMotionEnabled || widget.preferences.dataSaverEnabled;

  String? _avatarUrlOf(Map<String, dynamic> player) {
    final seat = _integer(player['seat'], fallback: -9);
    final own = seat == _viewerSeat ? (widget.profile.avatarUrl ?? '') : '';
    final url = own.isNotEmpty ? own : '${player['avatar_url'] ?? ''}'.trim();
    return url.isEmpty || url == 'null' ? null : url;
  }

  Widget? _cosmeticIcon(String id, double size) => switch (id) {
        'avatar_fox' => Icon(Icons.pets_rounded, size: size * .52, color: const Color(0xFFFFD17A)),
        'avatar_samurai' => Icon(Icons.shield_rounded, size: size * .52, color: const Color(0xFFE5E9F4)),
        'avatar_cat' => Icon(Icons.pets_rounded, size: size * .52, color: const Color(0xFFFFF1C7)),
        'avatar_phoenix' => Icon(Icons.local_fire_department_rounded, size: size * .55, color: const Color(0xFFFFB36B)),
        _ => null,
      };

  Widget _gameSurface() => LayoutBuilder(
        builder: (context, constraints) {
          final f = _Frame(constraints.maxWidth, constraints.maxHeight);
          final phase = '${_state['phase']}';
          final started = _state['started'] == true;
          final canTakeLeft = _canMove && phase == 'draw';
          final hint = _leftHint();
          final gap = f.s(8);
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(child: RepaintBoundary(child: OkxFelt(theme: widget.preferences.tableTheme, photo: true))),
              // Üst çubuk
              Positioned(left: f.x(12), top: f.y(10), child: ConstrainedBox(constraints: BoxConstraints(maxWidth: f.x(400)), child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: _stakeHud(f)))),
              // Turbo: masaya yeni işlenen her yıldızlı taş için bir yıldız,
              // seri alanından çarpana uçar ve ×N rozeti büyüyerek güncellenir.
              if (_turboFxSeq > 0)
                for (var k = 0; k < _turboFxCount.clamp(1, 6); k++)
                  TweenAnimationBuilder<double>(
                    key: ValueKey('turbo-star-fly-$_turboFxSeq-$k'),
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: Duration(milliseconds: 820 + k * 140),
                    curve: Curves.easeInOutCubic,
                    builder: (context, raw, child) {
                      final delay = k * 140 / (820 + k * 140);
                      final progress = ((raw - delay) / (1 - delay)).clamp(0.0, 1.0).toDouble();
                      if (progress <= 0 || progress >= 1) return const SizedBox.shrink();
                      final sx = f.x(400 + k * 24), sy = f.y(150);
                      final ex = f.x(112), ey = f.y(14);
                      final x = sx + (ex - sx) * progress;
                      final y = sy + (ey - sy) * progress - math.sin(progress * math.pi) * f.y(60);
                      return Positioned(left: x, top: y, child: Transform.rotate(angle: progress * math.pi * 2, child: Transform.scale(scale: 1 + .6 * math.sin(progress * math.pi), child: child)));
                    },
                    child: const Text('★', style: TextStyle(fontSize: 28, color: Color(0xFFFFD15C), shadows: [Shadow(color: Color(0xFFFFB52E), blurRadius: 18)])),
                  ),
              Positioned(
                right: f.x(12),
                top: f.y(10),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  _roundIcon(_online ? Icons.wifi_rounded : Icons.wifi_off_rounded, () => _tableNotice(_connection), f, color: _online ? const Color(0xFFFFE9B0) : OkeyXColors.danger),
                  SizedBox(width: gap),
                  _roundIcon(Icons.settings_rounded, () => unawaited(_showTableMenu()), f),
                  SizedBox(width: gap),
                  _roundIcon(Icons.logout_rounded, () => unawaited(_requestLeaveTable()), f),
                ]),
              ),
              // Seri ve çift alanları (ıstaka genişliğinde, ıstakaya kadar)
              Positioned(left: f.x(214), top: f.y(60), width: f.x(386), height: f.y(188), child: RepaintBoundary(child: _seriZone(f))),
              Positioned(left: f.x(608), top: f.y(60), width: f.x(178), height: f.y(188), child: RepaintBoundary(child: _ciftZone(f))),
              // Deste ve gösterge
              Positioned(left: f.x(770), top: f.y(64), width: f.x(46), child: _deckColumn(f)),
              // Turn guidance is conveyed by the active stock/discard hit target;
              // avoid floating text pills that cover tiles or player controls.
              ..._opponents(f),
              // Atılan taşlar: her oyuncunun kendi sağında
              _positionedDiscard(_relativeSeat(2), f, cx: 127, cy: 104),
              _positionedDiscard(_relativeSeat(1), f, cx: 923, cy: 104),
              _positionedDiscard(_relativeSeat(3), f, cx: 188, cy: 270, canTake: canTakeLeft),
              _positionedDiscard(_viewerSeat, f, cx: 866, cy: 290),
              // Açılış çubuğu / soldan alma ipucu
              if (started)
                Positioned(
                  left: f.x(214),
                  top: f.y(254),
                  width: f.x(572),
                  height: f.y(38),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: KeyedSubtree(
                      key: ValueKey('openbar-${hint == null ? 'plain' : hint['tile_id']}'),
                      child: _openBar(f, leftHint: hint),
                    ),
                  ),
                ),
              // Istaka
              Positioned(left: f.x(214), top: f.y(296), width: f.x(572), bottom: f.y(6), child: RepaintBoundary(child: Align(alignment: Alignment.bottomCenter, child: AspectRatio(aspectRatio: RealRackGeometry.aspect, child: _rack(f.k < .8))))),
              // Ben
              Positioned(left: f.x(12), top: f.y(330), width: f.x(116), child: _meBlock(f)),
              if (started && _assisted && !_isDuz)
                Positioned(
                  left: f.x(146),
                  top: f.y(338),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    _squareButton(Icons.view_week_rounded, 'SERİ DİZ', () => _sortRackLocal(true), f),
                    SizedBox(height: gap),
                    _squareButton(Icons.copy_all_rounded, 'ÇİFT DİZ', () => _sortRackLocal(false), f),
                  ]),
                ),
              Positioned(
                right: f.x(146),
                top: f.y(338),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  _squareButton(Icons.card_giftcard_rounded, 'HEDİYE', _state['gifts_enabled'] == false ? null : () => unawaited(_openGiftPicker()), f),
                  SizedBox(height: gap),
                  _squareButton(Icons.chat_bubble_rounded, 'SOHBET', _state['chat_enabled'] == false ? null : () => unawaited(_showChatPanel()), f, dot: _list(_state['chat']).map(_map).any((e) => '${e['kind']}' != 'gift')),
                ]),
              ),
              Positioned(
                right: f.x(18),
                top: f.y(344),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  _voiceButton(f),
                  SizedBox(height: gap),
                  _squareButton(Icons.emoji_emotions_rounded, '', _state['chat_enabled'] == false ? null : () => unawaited(_showChatPanel()), f, small: true),
                ]),
              ),
              ..._chatBubbleWidgets(f),
            ],
          );
        },
      );

  static const _hudText = TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .4, color: OkeyXColors.cream);

  Widget _stakeHud(_Frame f) {
    final stake = _integer(_state['entry_fee']);
    final x = _integer(_state['multiplier']).clamp(1, 99);
    final variant = _isDuz ? 'KLASİK OKEY' : (_state['variant'] == 'fold' ? '101 KATLAMALI' : '101 KATLAMASIZ');
    final canak = _map(_state['canak']);
    final round = _integer(_state['round_index']);
    final maxRounds = _integer(_state['max_rounds']);
    Widget sep() => Container(width: 1, height: 12, margin: const EdgeInsets.symmetric(horizontal: 8), color: OkeyXColors.line2);
    return OkxLeather(
      radius: 999,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shadows: const [BoxShadow(color: Color(0x66000000), blurRadius: 10, offset: Offset(0, 4))],
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const OkxCoin(size: 14),
        const SizedBox(width: 6),
        Text(_formatNumber(stake), style: _hudText),
        if (_state['turbo'] == true) ...[sep(), AnimatedSwitcher(duration: const Duration(milliseconds: 280), transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child), child: Text(x > 1 ? 'TURBO • PUAN ×$x' : 'TURBO', key: ValueKey('turbo-$x'), style: _hudText.copyWith(color: OkeyXColors.gold, fontSize: 13, fontWeight: FontWeight.w900)))],
        sep(),
        Text(variant, style: _hudText),
        if (maxRounds > 0) ...[sep(), Text('EL ${math.max(1, round)}/$maxRounds', style: _hudText)],
        if (canak['enabled'] == true) ...[sep(), _canakBadge()],
      ]),
    );
  }

  Widget _roundIcon(IconData icon, VoidCallback? onTap, _Frame f, {Color color = const Color(0xFFFFE9B0)}) {
    final size = f.s(34).clamp(30.0, 48.0).toDouble();
    return GestureDetector(
      onTap: onTap,
      child: OkxLeather(
        radius: 999,
        width: size,
        height: size,
        padding: EdgeInsets.zero,
        shadows: const [BoxShadow(color: Color(0x66000000), blurRadius: 8, offset: Offset(0, 3))],
        child: Center(child: Icon(icon, size: size * .48, color: color)),
      ),
    );
  }

  Widget _squareButton(IconData icon, String label, VoidCallback? onTap, _Frame f, {bool active = false, bool small = false, bool dot = false}) {
    final s = f.s(small ? 38 : 42).clamp(34.0, 58.0).toDouble();
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? .45 : 1,
        child: OkxLeather(
          radius: 12,
          width: s,
          height: s,
          padding: EdgeInsets.zero,
          borderColor: active ? OkeyXColors.cyan : OkeyXColors.line2,
          shadows: const [BoxShadow(color: Color(0x73000000), blurRadius: 10, offset: Offset(0, 5))],
          child: Stack(clipBehavior: Clip.none, children: [
            Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: s * (label.isEmpty ? .46 : .38), color: active ? OkeyXColors.cyan : const Color(0xFFFFE9B0)),
                if (label.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(label, maxLines: 1, style: TextStyle(fontSize: s * .19, fontWeight: FontWeight.w800, letterSpacing: .4, color: OkeyXColors.cream)),
                ],
              ]),
            ),
            if (dot) const Positioned(right: 5, top: 5, child: CircleAvatar(radius: 3.5, backgroundColor: OkeyXColors.cyan)),
          ]),
        ),
      ),
    );
  }

  /// Mikrofon: dokun = aç/kapat, basılı tut = bas-konuş. Konuşurken nabız gibi atar.
  Widget _voiceButton(_Frame f) {
    final talking = _voiceMicOn && _voiceSpeakingPlayers.contains(widget.profile.userId);
    return GestureDetector(
      onLongPressStart: _voiceBusy ? null : (_) => unawaited(_toggleVoice(talk: true)),
      onLongPressEnd: _voiceBusy ? null : (_) => unawaited(_toggleVoice(talk: false)),
      child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
        if (_voiceMicOn)
          TweenAnimationBuilder<double>(
            key: ValueKey('mic-pulse-$_micPulse'),
            tween: Tween(begin: 0, end: 1),
            duration: Duration(milliseconds: talking ? 700 : 1600),
            onEnd: () { if (mounted && _voiceMicOn) setState(() => _micPulse++); },
            builder: (context, v, _) {
              return Container(
              width: f.s(44) * (1 + .25 * v),
              height: f.s(44) * (1 + .25 * v),
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: OkeyXColors.mint.withValues(alpha: (1 - v) * .8), width: 2)),
            );
            },
          ),
        _squareButton(
          _voiceMicOn ? Icons.mic_rounded : Icons.mic_off_rounded,
          '',
          _voiceBusy ? null : () => unawaited(_toggleVoice()),
          f,
          active: _voiceMicOn,
          small: true,
        ),
      ]),
    );
  }

  // ───────────── Seri ve çift alanları ─────────────

  List<Map<String, dynamic>> _meldsOf({required bool pairs}) =>
      _list(_state['melds']).map(_map).where((m) => (m['kind'] == 'pair') == pairs).toList();

  Widget _zoneShell({required String label, required bool gold, required Widget child}) => Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: gold ? const Color(0x2E140D3A) : const Color(0x29000000),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: gold ? const Color(0x4DFFCE6E) : const Color(0x24FFECBE), width: 1.4),
              ),
            ),
          ),
          Positioned.fill(child: Padding(padding: const EdgeInsets.fromLTRB(8, 12, 8, 6), child: child)),
          Positioned(
            left: 12,
            top: -8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: gold ? const Color(0xFF1C1250) : const Color(0xFF123D2C),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: gold ? const Color(0x66FFCE6E) : const Color(0x33FFECBE)),
              ),
              child: Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.6, color: gold ? const Color(0xFFFFD98A) : const Color(0xFFBFE9D2))),
            ),
          ),
        ],
      );

  Widget _zoneEmpty(String text) => Center(
        child: Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0x80FFECBE))),
      );

  Widget _miniSeatAvatar(Map<String, dynamic> player, double size) {
    final name = '${player['name'] ?? '?'}';
    final url = _avatarUrlOf(player);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF1C1251),
        border: Border.all(color: const Color(0xFFC8963F), width: 1.2),
        image: url == null ? null : DecorationImage(image: NetworkImage(url), fit: BoxFit.cover),
      ),
      child: url == null ? Text(name.isEmpty ? '?' : name.substring(0, 1).toUpperCase(), style: TextStyle(fontSize: size * .5, fontWeight: FontWeight.w800, color: OkeyXColors.cream, fontFamily: OkeyXFonts.serif)) : null,
    );
  }

  Widget _ownerHeader(int seat, String text, {bool dim = false}) {
    final p = _playerAtSeat(seat);
    final name = seat == _viewerSeat ? 'SEN' : '${p['name'] ?? 'Oyuncu'}'.toUpperCase();
    return Padding(
      padding: const EdgeInsets.only(top: 3, bottom: 4),
      child: Opacity(
        opacity: dim ? .55 : 1,
        child: Row(children: [
          _miniSeatAvatar(p.isEmpty ? {'name': name, 'seat': seat} : p, 16),
          const SizedBox(width: 6),
          Flexible(child: Text('$name • $text', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: .8, color: Color(0xB3FFECBE)))),
        ]),
      ),
    );
  }

  Widget _meldChip(Map<String, dynamic> meld, double tw) {
    final owner = _integer(meld['owner_seat']);
    final tiles = _list(meld['tiles']).map(_map).toList();
    final meldKey = '${meld['id'] ?? tiles.map((t) => t['id']).join('-')}';
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 3, 3, 4),
      decoration: BoxDecoration(color: const Color(0x2E000000), borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < tiles.length; i++)
          Padding(
            padding: const EdgeInsets.only(right: 1.5),
            // Yeni açılan per: taşlar sırayla yukarıdan masaya dizilir.
            child: TweenAnimationBuilder<double>(
              key: ValueKey('meld-$meldKey-${tiles[i]['id']}'),
              tween: Tween(begin: 0, end: 1),
              duration: _reducedFx ? Duration.zero : Duration(milliseconds: 260 + i * 70),
              curve: Interval((i * 70) / (260 + i * 70), 1, curve: Curves.easeOutBack),
              builder: (context, v, child) => Opacity(
                opacity: v.clamp(0.0, 1.0).toDouble(),
                child: Transform.translate(offset: Offset(0, -tw * .9 * (1 - v)), child: child),
              ),
              child: SizedBox(width: tw, height: tw * 1.42, child: TileWidget(tile: _tile(tiles[i]), skinId: _tileSkinForSeat(owner), bigNumber: _bigNumbers)),
            ),
          ),
      ]),
    );
  }

  Widget _seriZone(_Frame f) {
    final melds = _meldsOf(pairs: false);
    final owners = <int>[];
    for (final m in melds) {
      final o = _integer(m['owner_seat']);
      if (!owners.contains(o)) owners.add(o);
    }
    // Tüm perler kaydırmadan sığsın: gerekiyorsa taş boyunu küçült.
    var tw = f.s(23).clamp(16.0, 32.0).toDouble();
    final zoneW = f.x(386) - 22, zoneH = f.y(188) - 34;
    double need(double t) {
      var h = 0.0;
      for (final o in owners) {
        var rowW = 0.0, rows = 1;
        for (final m in melds.where((m) => _integer(m['owner_seat']) == o)) {
          final w = _list(m['tiles']).length * (t + 1.5) + 7 + 7;
          if (rowW > 0 && rowW + w > zoneW) { rows++; rowW = 0; }
          rowW += w;
        }
        h += 23 + rows * (t * 1.42 + 7 + 6);
      }
      return h;
    }
    while (tw > 13 && need(tw) > zoneH) { tw -= 1; }
    final children = <Widget>[];
    for (final o in owners) {
      final p = _playerAtSeat(o);
      final pairsMode = '${p['opening_mode']}' == 'pairs';
      children.add(_ownerHeader(o, pairsMode ? 'İŞLEDİ' : '${_integer(p['opening_score'])}'));
      children.add(Wrap(spacing: 7, runSpacing: 6, children: [
        for (final m in melds.where((m) => _integer(m['owner_seat']) == o)) _meldChip(m, tw),
      ]));
    }
    final started = _state['started'] == true;
    if (started && !_isDuz && _viewer['opened'] != true && !owners.contains(_viewerSeat)) {
      children.add(_ownerHeader(_viewerSeat, 'HENÜZ AÇMADIN', dim: true));
    }
    return _zoneShell(
      label: 'SERİ ALANI',
      gold: false,
      child: _isDuz
          ? _zoneEmpty('Klasik Okeyde açılış yok.\n14 taşı diz, son taşla bitir.')
          : owners.isEmpty
              ? (children.isEmpty ? _zoneEmpty('Açılan seriler burada görünür') : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [...children, Expanded(child: _zoneEmpty('Açılan seriler burada görünür'))]))
              : SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children)),
    );
  }

  Widget _ciftZone(_Frame f) {
    final melds = _meldsOf(pairs: true);
    final owners = <int>[];
    for (final m in melds) {
      final o = _integer(m['owner_seat']);
      if (!owners.contains(o)) owners.add(o);
    }
    var tw = f.s(20).clamp(14.0, 28.0).toDouble();
    final zoneW = f.x(178) - 20, zoneH = f.y(188) - 34;
    double need(double t) {
      var h = 0.0;
      for (final o in owners) {
        final n = melds.where((m) => _integer(m['owner_seat']) == o).length;
        final per = math.max(1, (zoneW / (2 * (t + 1.5) + 7 + 6)).floor());
        h += 23 + (n / per).ceil() * (t * 1.42 + 7 + 6);
      }
      return h;
    }
    while (tw > 12 && need(tw) > zoneH) { tw -= 1; }
    return _zoneShell(
      label: 'ÇİFT ALANI',
      gold: true,
      child: owners.isEmpty
          ? _zoneEmpty(_isDuz ? 'Klasik Okey' : 'Çift açanlar\nburada görünür')
          : SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final o in owners) ...[
                  _ownerHeader(o, '${melds.where((m) => _integer(m['owner_seat']) == o).length} ÇİFT'),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final m in melds.where((m) => _integer(m['owner_seat']) == o)) _meldChip(m, tw),
                  ]),
                ],
              ]),
            ),
    );
  }

  // ───────────── Deste ve gösterge ─────────────

  Widget _deckColumn(_Frame f) {
    final tw = f.s(36).clamp(26.0, 54.0).toDouble();
    final th = tw * 1.45;
    final stock = _integer(_state['stock_count']);
    final canDraw = _canMove && '${_state['phase']}' == 'draw' && stock > 0;
    final indicator = _map(_state['indicator']);
    const back = GameTile(id: 'deck-back', number: 1, colorIndex: 2, faceDown: true);
    final layers = stock >= 3 ? 3 : (stock <= 0 ? 1 : stock);
    Widget label(String t, {Color color = const Color(0xA6FFECBE)}) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: FittedBox(fit: BoxFit.scaleDown, child: Text(t, maxLines: 1, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1.5, color: color))),
        );
    Widget pile(bool ghost) => SizedBox(
          width: tw,
          height: th + 7,
          child: Stack(clipBehavior: Clip.none, children: [
            for (var i = 0; i < layers; i++)
              Positioned(
                left: 0,
                top: (layers - 1 - i) * 3.5,
                width: tw,
                height: th,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(tw * .16),
                    boxShadow: i == layers - 1 && canDraw && !ghost ? [BoxShadow(color: const Color(0xFFFFC24A).withValues(alpha: .80), spreadRadius: 2), BoxShadow(color: const Color(0xFFFFC24A).withValues(alpha: .42), blurRadius: 16)] : const [],
                  ),
                  child: const TileWidget(tile: back),
                ),
              ),
          ]),
        );
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Draggable<String>(
        data: '__stock__',
        maxSimultaneousDrags: canDraw && !_busy ? 1 : 0,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        rootOverlay: true,
        hitTestBehavior: HitTestBehavior.opaque,
        feedback: Material(color: Colors.transparent, child: SizedBox(width: tw, height: th, child: const TileWidget(tile: back))),
        childWhenDragging: Opacity(opacity: .4, child: pile(true)),
        onDragEnd: (details) => _handleExternalDragEnd('__stock__', details, tw, th),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: canDraw ? () => _drawStockInto(null) : null,
          child: pile(false),
        ),
      ),
      label(stock <= 5 && stock > 0 ? 'SON $stock TAŞ' : 'DESTE $stock', color: stock <= 5 && stock > 0 ? OkeyXColors.danger : canDraw ? OkeyXColors.mint : const Color(0xA6FFECBE)),
      SizedBox(height: f.s(10)),
      if (indicator.isNotEmpty) SizedBox(width: tw, height: th, child: TileWidget(tile: _tile(indicator), bigNumber: _bigNumbers)),
      label('GÖSTERGE'),
    ]);
  }

  /// Masa çanağı (üst bilgi çubuğunda): okeyle ya da çiftten biten kırar, kırılmazsa birikir.
  Widget _canakBadge() {
    final c = _map(_state['canak']);
    final pot = _integer(c['pot']);
    return Tooltip(
      message: 'Çanak okey: her el başında ${_compactMoney(_integer(c['fee']))} altın çanağa girer. Okey atarak ya da çiftten biten çanağı kırar ve hepsini alır.',
      triggerMode: TooltipTriggerMode.tap,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Text('🏺', style: TextStyle(fontSize: 13, height: 1)),
        const SizedBox(width: 4),
        TweenAnimationBuilder<double>(
          tween: Tween(end: pot.toDouble()),
          duration: const Duration(milliseconds: 700),
          builder: (context, v, _) => Text('ÇANAK ${_compactMoney(v.round())}', style: _hudText.copyWith(color: OkeyXColors.gold, fontWeight: FontWeight.w900)),
        ),
      ]),
    );
  }

  Widget _canakBreakOverlay() {
    final c = _canakBreak ?? const <String, dynamic>{};
    final amount = _integer(c['amount']);
    final how = '${c['kind']}' == 'okey' ? 'OKEY ATARAK BİTİRDİ' : 'ÇİFTTEN BİTİRDİ';
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 3200),
      builder: (context, t, _) {
        final pop = Curves.elasticOut.transform((t / .35).clamp(0.0, 1.0));
        final fade = t > .85 ? (1 - (t - .85) / .15) : 1.0;
        return Opacity(
          opacity: fade.clamp(0.0, 1.0),
          child: Container(
            color: Colors.black.withValues(alpha: .45 * fade),
            alignment: Alignment.center,
            child: Stack(alignment: Alignment.center, children: [
              // Kırılan çanaktan saçılan altınlar
              for (var i = 0; i < 18; i++)
                Transform.translate(
                  offset: Offset(math.cos(i * 0.349) * 170 * Curves.easeOut.transform(t.clamp(0.0, 1.0)), math.sin(i * 0.349) * 110 * Curves.easeOut.transform(t.clamp(0.0, 1.0)) + 60 * t * t),
                  child: Opacity(opacity: (1 - t).clamp(0.0, 1.0), child: const Text('🪙', style: TextStyle(fontSize: 22))),
                ),
              Transform.scale(
                scale: .4 + .6 * pop,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFE36B), Color(0xFFFFA928)]),
                    boxShadow: const [BoxShadow(color: Color(0xAA000000), blurRadius: 24, offset: Offset(0, 10))],
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Text('🏺💥', style: TextStyle(fontSize: 34)),
                    const Text('ÇANAK KIRILDI!', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 1.2, color: Color(0xFF150E3D))),
                    const SizedBox(height: 4),
                    Text('${c['name'] ?? ''} • $how', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF231664))),
                    const SizedBox(height: 6),
                    Text('+${_compactMoney(amount)} altın', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF1F6B2E))),
                  ]),
                ),
              ),
            ]),
          ),
        );
      },
    );
  }

  // ───────────── Rakipler ve avatarlar ─────────────

  List<Widget> _opponents(_Frame f) {
    final av = f.s(46).clamp(36.0, 66.0).toDouble();
    final sideAv = f.s(40).clamp(34.0, 48.0).toDouble();
    return [
      Positioned(left: 0, right: 0, top: f.y(5) + 6, child: Align(alignment: Alignment.topCenter, child: _opponent(_playerAtSeat(_relativeSeat(2)), f.s(36).clamp(30.0, 50.0).toDouble(), f, side: 0))),
      // Kenarlardan pay: avatar çerçevesi (%26 taşar) ve süre halkası ekrana sığsın.
      Positioned(left: f.x(10) + sideAv * .2 + 4, top: f.y(150), child: _opponent(_playerAtSeat(_relativeSeat(3)), sideAv, f, side: -1)),
      Positioned(right: f.x(4) + sideAv * .2 + 6, top: f.y(150), child: _opponent(_playerAtSeat(_relativeSeat(1)), sideAv, f, side: 1)),
    ];
  }

  Widget _seatTag(String text, {bool gold = false, bool mint = false, bool danger = false}) {
    final color = danger ? OkeyXColors.danger : gold ? const Color(0xFFFFD98A) : mint ? OkeyXColors.mint : OkeyXColors.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: .42)),
      ),
      child: Text(text, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: .6, color: color)),
    );
  }

  Widget _opponent(Map<String, dynamic> player, double av, _Frame f, {required int side}) {
    if (player.isEmpty) return const SizedBox.shrink();
    final seat = _integer(player['seat']);
    final name = '${player['name'] ?? 'Oyuncu'}';
    final vip = _integer(player['vip_level']);
    final opened = player['opened'] == true;
    final pairs = '${player['opening_mode']}' == 'pairs';
    final streak = _integer(_map(player['public_stats'])['current_streak']);
    final hand = _integer(player['hand_count']);
    final nearFinish = hand > 0 && hand <= 1 && opened;
    final plate = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: side == 1 ? f.s(78).clamp(66.0, 94.0).toDouble() : side == 0 ? f.s(210).clamp(150.0, 280.0).toDouble() : f.s(118).clamp(92.0, 170.0).toDouble(), minWidth: side == 1 ? f.s(64).clamp(58.0, 78.0).toDouble() : f.s(84).clamp(70.0, 130.0).toDouble()),
      child: OkxLeather(
        radius: 12,
        padding: const EdgeInsets.fromLTRB(10, 5, 10, 6),
        shadows: const [BoxShadow(color: Color(0x66000000), blurRadius: 10, offset: Offset(0, 4))],
        child: side == 0
            // Karşıdaki oyuncu: tek satır, seri alanının üstüne binmesin.
            ? Row(mainAxisSize: MainAxisSize.min, children: [
                if (_state['team_mode'] == 'paired') ...[_seatTag('EŞİN', mint: true), const SizedBox(width: 5)],
                Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: vip > 0 ? const Color(0xFFFFE3A0) : OkeyXColors.cream))),
                if (vip > 0) ...[const SizedBox(width: 3), const Icon(Icons.workspace_premium_rounded, size: 11, color: OkeyXColors.gold)],
                const SizedBox(width: 6),
                Text('LV ${_integer(player['level'])}', style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: OkeyXColors.muted)),
                if (opened) ...[const SizedBox(width: 5), _seatTag(pairs ? 'ÇİFT ${_integer(player['opening_pairs'])}' : 'AÇTI ${_integer(player['opening_score'])}', gold: !pairs, mint: pairs)]
                else if (_state['started'] == true && hand > 0) ...[const SizedBox(width: 5), Text('$hand taş', style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: OkeyXColors.dim))],
                if (nearFinish) ...[const SizedBox(width: 4), _seatTag('SON TAŞ', danger: true)],
              ])
            : Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: side == 1 ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: vip > 0 ? const Color(0xFFFFE3A0) : OkeyXColors.cream))),
              if (vip > 0) ...[const SizedBox(width: 4), const Icon(Icons.workspace_premium_rounded, size: 12, color: OkeyXColors.gold)],
            ]),
            const SizedBox(height: 3),
            Wrap(spacing: 5, runSpacing: 3, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text('LV ${_integer(player['level'])}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: OkeyXColors.muted)),
              if (opened) _seatTag(pairs ? 'ÇİFT ${_integer(player['opening_pairs'])}' : 'AÇTI ${_integer(player['opening_score'])}', gold: !pairs, mint: pairs)
              else if (_state['started'] == true && hand > 0) Text('$hand taş', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: OkeyXColors.dim)),
              if (nearFinish) _seatTag('SON TAŞ', danger: true),
            ]),
          ],
        ),
      ),
    );
    final avatar = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => unawaited(_showPlayerCard(player)),
      child: _seatAvatar(player, av, timerBelow: side == 0),
    );
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: side == 1 ? [plate, SizedBox(width: av * .18), avatar] : [avatar, SizedBox(width: av * .26), plate],
    );
    return Stack(clipBehavior: Clip.none, children: [
      row,
      if (streak >= 2)
        Positioned(
          left: side == 1 ? null : 0,
          right: side == 1 ? 0 : null,
          top: side == 0 ? null : -14,
          bottom: side == 0 ? -14 : null,
          child: _seatTag('SERİ ×$streak', gold: true),
        ),
      if (_penaltyBadges[seat] != null)
        Positioned(
          left: side == 1 ? null : av * .7,
          right: side == 1 ? av * .7 : null,
          bottom: -10,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 240),
            builder: (context, v, child) => Transform.scale(scale: .7 + .3 * v, child: child),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(color: OkeyXColors.danger, borderRadius: BorderRadius.circular(9), boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 6)]),
              child: Text(_penaltyBadges[seat]!, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: Colors.white)),
            ),
          ),
        ),
    ]);
  }

  Widget _timerChip(int left) {
    final danger = left <= 5;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        color: const Color(0xFF090619),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: danger ? OkeyXColors.danger : const Color(0xFF7CF2B8), width: 1.5),
      ),
      child: Text('$left', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: danger ? OkeyXColors.danger : OkeyXColors.mint, height: 1.2)),
    );
  }

  Widget _seatAvatar(Map<String, dynamic> player, double size, {bool timerBelow = false}) {
    final seat = _integer(player['seat'], fallback: -9);
    if (seat < 0 || seat > 3) return _seatAvatarInner(player, size, timerBelow: timerBelow);
    return KeyedSubtree(key: _avatarKeys.putIfAbsent(seat, () => GlobalKey()), child: _seatAvatarInner(player, size, timerBelow: timerBelow));
  }

  Widget _seatAvatarInner(Map<String, dynamic> player, double size, {bool timerBelow = false}) {
    final seat = _integer(player['seat'], fallback: -9);
    final phase = '${_state['phase']}';
    final active = _state['started'] == true && seat == _integer(_state['current_seat']) && !const {'waiting', 'finished'}.contains(phase) && !_introActive;
    final pid = '${player['player_id'] ?? ''}'.trim();
    final speaking = _voiceEnabled && pid.isNotEmpty && _voiceSpeakingPlayers.contains(pid);
    final muted = pid.isNotEmpty && _voiceMutedPlayers.contains(pid);
    final online = player['connected'] != false && player['bot'] != true;
    final cosmetic = '${_map(player['loadout'])['avatar'] ?? ''}'.trim();
    final stuck = _stuckGifts[seat];
    final name = '${player['name'] ?? (seat == _viewerSeat ? widget.profile.displayName : 'Oyuncu')}';
    Widget avatar(double? ring) => OkxAvatar(
          name: name,
          imageUrl: _avatarUrlOf(player),
          size: size,
          ring: ring,
          online: online,
          highlight: speaking,
          child: _cosmeticIcon(cosmetic, size),
        );
    final core = active
        ? ValueListenableBuilder<int>(
            valueListenable: _nowMsNotifier,
            builder: (context, now, _) {
              final total = _integer(_state['turn_seconds'], fallback: 35).clamp(5, 300);
              final left = _secondsLeftAt(now);
              return Stack(clipBehavior: Clip.none, children: [
                avatar(left <= 0 ? 0.0 : left / total),
                // Üstteki oyuncunun sayacı ekranın dışına taşmasın diye avatarın altında.
                if (left > 0)
                  Positioned(
                    left: -20,
                    right: -20,
                    top: timerBelow ? null : -size * .18 - 8,
                    bottom: timerBelow ? -size * .18 - 8 : null,
                    child: Center(child: _timerChip(left)),
                  ),
              ]);
            },
          )
        : avatar(null);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(clipBehavior: Clip.none, children: [
        core,
        if (stuck != null)
          Positioned(
            right: -size * .34,
            top: -size * .30,
            child: _StuckGiftBadge(key: ValueKey(stuck.key), emoji: stuck.emoji, size: size * .66, reduced: _reducedFx),
          ),
        if (_voiceEnabled && pid.isNotEmpty && seat != _viewerSeat)
          Positioned(
            left: -3,
            bottom: -3,
            child: GestureDetector(
              onTap: () => unawaited(_toggleVoiceMute(pid, name)),
              child: Container(
                width: size * .34,
                height: size * .34,
                decoration: BoxDecoration(
                  color: const Color(0xFF0E0A22),
                  shape: BoxShape.circle,
                  border: Border.all(color: speaking ? OkeyXColors.cyan : OkeyXColors.line2),
                ),
                child: Icon(muted ? Icons.mic_off_rounded : Icons.mic_rounded, size: size * .2, color: muted ? OkeyXColors.dim : (speaking ? OkeyXColors.cyan : OkeyXColors.muted)),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _meBlock(_Frame f) {
    final size = f.s(52).clamp(40.0, 76.0).toDouble();
    final coins = _integer(_state['viewer_chips'], fallback: widget.profile.coins);
    final me = _viewer.isEmpty ? <String, dynamic>{'name': widget.profile.displayName, 'seat': _viewerSeat} : _viewer;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      GestureDetector(onTap: () => unawaited(_showPlayerProfile(me)), child: _seatAvatar(me, size)),
      SizedBox(height: size * .2),
      OkxLeather(
        radius: 12,
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        shadows: const [BoxShadow(color: Color(0x66000000), blurRadius: 10, offset: Offset(0, 4))],
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(widget.profile.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: OkeyXColors.cream)),
          FittedBox(fit: BoxFit.scaleDown, child: Row(mainAxisSize: MainAxisSize.min, children: [
            const OkxCoin(size: 11),
            const SizedBox(width: 4),
            Text(_formatNumber(coins), style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: OkeyXColors.muted)),
            if (_viewer['opened'] == true) ...[
              const SizedBox(width: 5),
              _seatTag('${_viewer['opening_mode']}' == 'pairs' ? 'ÇİFT' : 'AÇTI', gold: '${_viewer['opening_mode']}' != 'pairs', mint: '${_viewer['opening_mode']}' == 'pairs'),
            ],
          ])),
        ]),
      ),
    ]);
  }

  // ───────────── Sohbet balonları ─────────────

  List<Widget> _chatBubbleWidgets(_Frame f) {
    final widgets = <Widget>[];
    for (final entry in _chatBubbles.entries) {
      final relative = (entry.key - _viewerSeat + 4) % 4;
      final bubble = _tableChatBubble(entry.value, relative);
      switch (relative) {
        case 0:
          widgets.add(Positioned(left: f.x(96), top: f.y(300), child: bubble));
          break;
        case 1:
          widgets.add(Positioned(right: f.x(150), top: f.y(156), child: bubble));
          break;
        case 2:
          widgets.add(Positioned(left: 0, right: 0, top: f.y(66), child: Align(alignment: Alignment.topCenter, child: bubble)));
          break;
        case 3:
          widgets.add(Positioned(left: f.x(150), top: f.y(156), child: bubble));
          break;
      }
    }
    return widgets;
  }

  Widget _tableChatBubble(String text, int relative) {
    const bg = Color(0xF7F4EAD2);
    var tailAlign = Alignment.bottomCenter;
    var tailOffset = const Offset(0, 5);
    if (relative == 1) {
      tailAlign = Alignment.centerRight;
      tailOffset = const Offset(5, 0);
    } else if (relative == 2) {
      tailAlign = Alignment.topCenter;
      tailOffset = const Offset(0, -5);
    } else if (relative == 3) {
      tailAlign = Alignment.centerLeft;
      tailOffset = const Offset(-5, 0);
    }
    return IgnorePointer(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: .6, end: 1),
        duration: _reducedFx ? Duration.zero : const Duration(milliseconds: 220),
        curve: Curves.easeOutBack,
        builder: (context, v, child) => Transform.scale(scale: v, child: child),
        child: Stack(clipBehavior: Clip.none, children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(13), boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 3))]),
              child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF150E3D), fontSize: 11.5, fontWeight: FontWeight.w700)),
            ),
          ),
          Positioned.fill(
            child: Align(
              alignment: tailAlign,
              child: Transform.translate(
                offset: tailOffset,
                child: Transform.rotate(angle: .785398, child: const SizedBox(width: 10, height: 10, child: ColoredBox(color: bg))),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  // ───────────── Atılan taşlar ─────────────

  Widget _positionedDiscard(int seat, _Frame f, {required double cx, required double cy, bool canTake = false}) {
    final trails = _map(_state['discard_trails']);
    var trail = _list(trails['$seat']).map(_map).where((x) => x.isNotEmpty).toList();
    if (trail.isEmpty) {
      final latest = _map(_map(_state['discards'])['$seat']);
      if (latest.isNotEmpty) trail = <Map<String, dynamic>>[latest];
    }
    if (trail.isEmpty) return const SizedBox.shrink();
    if (trail.length > 3) trail = trail.sublist(trail.length - 3);
    final tw = f.s(34).clamp(26.0, 50.0).toDouble();
    final th = tw * 1.45;
    final value = trail.last;
    final useful = '${_state['left_useful_tile_id'] ?? ''}' == '${value['id']}';
    final reason = useful ? '${_state['left_useful_reason'] ?? 'İŞİNE YARAR'}' : '';
    final pileBase = _discardPileView(trail, seat, tw, th, useful: useful, canTake: canTake, reason: reason);
    final pile = useful && !_reducedFx ? _UsefulDiscardPulse(child: pileBase) : pileBase;
    return Positioned(
      left: f.x(cx) - tw / 2 - 6,
      top: f.y(cy) - th / 2 - 6,
      child: canTake
          ? Draggable<String>(
              data: '__left__',
              maxSimultaneousDrags: !_busy ? 1 : 0,
              dragAnchorStrategy: pointerDragAnchorStrategy,
              rootOverlay: true,
              hitTestBehavior: HitTestBehavior.opaque,
              feedback: Material(
                color: Colors.transparent,
                child: SizedBox(width: tw, height: th, child: TileWidget(tile: _tile({...value, 'useful': false}), skinId: _tileSkinForSeat(seat), bigNumber: _bigNumbers)),
              ),
              childWhenDragging: Opacity(opacity: .28, child: pile),
              onDragEnd: (details) => _handleExternalDragEnd('__left__', details, tw, th),
              child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => _takeLeftInto(null), child: pile),
            )
          : pile,
    );
  }

  Widget _discardPileView(List<Map<String, dynamic>> trail, int seat, double tw, double th, {bool useful = false, bool canTake = false, String reason = ''}) {
    final count = trail.length;
    final glow = useful || canTake;
    return TweenAnimationBuilder<double>(
      key: ValueKey('discard-pile-$seat-${trail.last['id']}-$count'),
      duration: _reducedFx ? Duration.zero : const Duration(milliseconds: 360),
      curve: Curves.easeOutBack,
      tween: Tween(begin: 0, end: 1),
      // Atılan taş yukarıdan hafif dönerek düşer ve çuhaya "oturur".
      builder: (context, v, child) => Transform.translate(
        offset: Offset(0, -th * .55 * (1 - v)),
        child: Transform.rotate(angle: .22 * (1 - v), child: Transform.scale(scale: 1.18 - .18 * v, child: child)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: tw + 12,
          height: th + 12,
          child: Stack(clipBehavior: Clip.none, children: [
            for (var i = 0; i < count; i++)
              Positioned(
                left: 6.0 - (count - 1 - i) * 3,
                top: 6.0 - (count - 1 - i) * 3,
                width: tw,
                height: th,
                child: Opacity(
                  opacity: i == count - 1 ? 1 : .55,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(tw * .16),
                      boxShadow: i == count - 1 && glow
                          ? [
                              BoxShadow(color: const Color(0xFFFFC24A).withValues(alpha: .85), spreadRadius: 2.2),
                              BoxShadow(color: const Color(0xFFFFC24A).withValues(alpha: .45), blurRadius: 18),
                            ]
                          : const [],
                    ),
                    child: TileWidget(tile: _tile({...trail[i], 'useful': false}), skinId: _tileSkinForSeat(seat), bigNumber: _bigNumbers),
                  ),
                ),
              ),
          ]),
        ),
      ]),
    );
  }

  // ───────────── Soldan al ipucu ─────────────

  Map<String, dynamic>? _leftHint() {
    if (!_assisted || !_canMove || _busy || '${_state['phase']}' != 'draw' || _viewer['opened'] == true || _isDuz) return null;
    final opp = _map(_state['left_opening_opportunity']);
    if (opp.isEmpty) return null;
    final latest = _map(_map(_state['discards'])['${_relativeSeat(3)}']);
    if (latest.isEmpty || '${latest['id']}' != '${opp['tile_id']}') return null;
    return {...opp, 'tile': latest};
  }

  String _tileColorName(Map<String, dynamic> t) => switch ('${t['c']}') {
        'red' => 'kırmızı',
        'blue' => 'mavi',
        'black' => 'siyah',
        'yellow' => 'sarı',
        _ => '',
      };

  Widget _leftHintBar(Map<String, dynamic> hint, _Frame f) {
    final kind = '${hint['kind'] ?? ''}';
    final tile = _map(hint['tile']);
    final pairsOnly = kind == 'pairs';
    final value = pairsOnly
        ? '${_integer(hint['current_pair_count'])}/5 → ${_integer(hint['pair_count'])}/5'
        : '${_integer(hint['current_series_score'])} → ${_integer(hint['series_score'])}';
    final tileName = tile['joker'] == true ? 'okey' : '${_tileColorName(tile)} ${_integer(tile['n'])}'.trim();
    return OkxLeather(
      radius: 14,
      padding: const EdgeInsets.fromLTRB(10, 4, 5, 4),
      borderColor: OkeyXColors.cyan.withValues(alpha: .55),
      shadows: [BoxShadow(color: OkeyXColors.cyan.withValues(alpha: .18), blurRadius: 18)],
      child: Row(children: [
        const Icon(Icons.auto_awesome_rounded, size: 16, color: OkeyXColors.cyan),
        const SizedBox(width: 7),
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text.rich(TextSpan(children: [
                const TextSpan(text: 'Soldaki '),
                TextSpan(text: tileName, style: const TextStyle(color: OkeyXColors.mint, fontWeight: FontWeight.w900)),
                TextSpan(text: pairsOnly ? ' ile çift açabilirsin' : ' ile açabilirsin'),
              ]), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: OkeyXColors.cream)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: const Color(0x66000000), borderRadius: BorderRadius.circular(8)),
                child: Text(value, style: const TextStyle(fontFamily: OkeyXFonts.number, fontSize: 12, color: OkeyXColors.cream)),
              ),
            ]),
          ),
        ),
        const SizedBox(width: 6),
        OkxButton.ghost(label: 'SADECE AL', height: 28, fontSize: 10.5, padding: const EdgeInsets.symmetric(horizontal: 10), onTap: _busy ? null : () => _takeLeftInto(null)),
        const SizedBox(width: 6),
        OkxButton.green(label: 'AL VE AÇ', icon: Icons.layers_rounded, height: 28, fontSize: 10.5, padding: const EdgeInsets.symmetric(horizontal: 10), onTap: _busy ? null : () => unawaited(_takeLeftAndOpen(kind))),
      ]),
    );
  }

  Future<void> _takeLeftAndOpen(String kind) async {
    await _takeLeftIntoSlot(null);
    if (!mounted || '${_state['phase']}' != 'discard') return;
    if (kind != 'pairs' && _actions['open_series'] == true) {
      await _openSeriesRespectingRack();
    } else if (kind != 'series' && _actions['open_pairs'] == true) {
      await _act('open_pairs');
    } else {
      _tableNotice('Taş alındı. Taşları dizip SERİ AÇ’a bas.');
    }
  }

  // ───────────── Açılış çubuğu ve aksiyonlar ─────────────

  Widget _barButton(String label, IconData icon, bool enabled, VoidCallback action, {bool primary = false}) => Padding(
        padding: const EdgeInsets.only(left: 5),
        child: OkxButton(
          label: label,
          icon: icon,
          height: 30,
          fontSize: 10.5,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          radius: 10,
          style: primary ? OkxButtonStyle.brass : OkxButtonStyle.ghost,
          onTap: enabled && !_busy ? action : null,
        ),
      );

  Widget _infoBar(String title, String detail, {bool ready = false}) => OkxLeather(
        radius: 10,
        padding: const EdgeInsets.fromLTRB(9, 4, 9, 4),
        shadows: const [BoxShadow(color: Color(0x59000000), blurRadius: 7, offset: Offset(0, 2))],
        child: Row(children: [
          Text(title, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: ready ? const Color(0xFF3CCF8E) : const Color(0xFFFFD98A))),
          const SizedBox(width: 7),
          Expanded(child: Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: OkeyXColors.muted))),
        ]),
      );

  /// 101 açılış sayacı: büyük rakam, pirinç çerçeve, dolan altın şerit.
  /// Hazır olunca zümrüt ışık; hiçbir zaman ıstakanın üstüne taşmaz.
  Widget _openingMeterBar(int value, int target, {required bool canOpen}) {
    final t = target <= 0 ? 1 : target;
    final ready = canOpen;
    final reached = value >= t;
    final p = (value / t).clamp(0.0, 1.0).toDouble();
    const emerald = Color(0xFF3CCF8E);
    final accent = ready || reached ? emerald : value >= t * .8 ? const Color(0xFFFFC24A) : const Color(0xFFFFE3A0);
    return LayoutBuilder(builder: (context, c) {
      final tight = c.maxWidth < 190;
      return AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.fromLTRB(9, 2, 9, 3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(11),
          gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xF2110A30), Color(0xF209061A)]),
          border: Border.all(color: ready ? emerald : const Color(0xCCD9A94A), width: ready ? 1.8 : 1.3),
          boxShadow: [
            const BoxShadow(color: Color(0x80000000), blurRadius: 8, offset: Offset(0, 3)),
            if (ready) BoxShadow(color: emerald.withValues(alpha: .45), blurRadius: 14),
          ],
        ),
        child: Row(children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
              TweenAnimationBuilder<double>(
                tween: Tween(end: value.toDouble()),
                duration: const Duration(milliseconds: 380),
                curve: Curves.easeOutCubic,
                builder: (context, v, _) => Text('${v.round()}', style: TextStyle(fontFamily: OkeyXFonts.number, fontSize: 21, height: 1, color: accent, shadows: [Shadow(color: accent.withValues(alpha: .45), blurRadius: 8)])),
              ),
              Text(' / $t', style: const TextStyle(fontFamily: OkeyXFonts.number, fontSize: 12, height: 1, color: Color(0xB3FFE9B0))),
            ]),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (!tight)
                Text(
                  ready ? 'AÇABİLİRSİN' : reached ? 'PERLERİ DÜZENLE' : 'AÇILIŞ • ${t - value} KALDI',
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w900, letterSpacing: .7, color: accent),
                ),
              const SizedBox(height: 3),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  height: 6,
                  child: Stack(fit: StackFit.expand, children: [
                    const ColoredBox(color: Color(0x66000000)),
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: p,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: ready || reached ? const [Color(0xFF1F8F5D), emerald] : const [Color(0xFFFFA928), Color(0xFFFFE36B)]),
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
            ]),
          ),
        ]),
      );
    });
  }

  Widget _openBar(_Frame f, {Map<String, dynamic>? leftHint}) {
    final phase = '${_state['phase']}';
    if (_state['started'] != true || phase == 'finished' || phase == 'waiting') return const SizedBox.shrink();
    final arrangedScore = _localRackSeriesScore();
    final arrangedPairs = _localRackPairCount();
    final score = _assisted ? math.max(arrangedScore, _integer(_state['assisted_series_score'])) : arrangedScore;
    final pairs = _assisted ? math.max(arrangedPairs, _integer(_state['opening_preview_pairs'])) : arrangedPairs;
    final threshold = _integer(_state['min_opening_score'], fallback: 101);
    final pairThreshold = _integer(_state['min_opening_pairs'], fallback: 5);
    final opened = _viewer['opened'] == true;
    final pairOpened = opened && '${_viewer['opening_mode']}' == 'pairs';
    final rackValue = _integer(_viewer['rack_value']);
    final handCount = _integer(_viewer['hand_count'], fallback: _serverHand.length);

    final buttons = <Widget>[];
    if (_myTurn && phase == 'discard') {
      if (_isDuz) {
        buttons.add(_barButton('BİTİR', Icons.emoji_events_rounded, _actions['finish'] == true, () => unawaited(_duzFinish()), primary: true));
      } else {
        if (_actions['return_left'] == true) {
          buttons.add(_barButton('GERİ BIRAK', Icons.keyboard_return_rounded, true, () => _act('return_left')));
        } else if (_actions['undo_opening'] == true || _actions['undo_layoff'] == true) {
          buttons.add(_barButton('GERİ TOPLA', Icons.restore_rounded, true, () => _act(_actions['undo_opening'] == true ? 'undo_opening' : 'undo_layoff')));
        }
        if (opened || _actions['auto_layoff'] == true) {
          buttons.add(_barButton('İŞLE', Icons.call_merge_rounded, _actions['auto_layoff'] == true, () => _act('auto_layoff')));
        }
        // Pair-opening is a distinct 101 lane: once a player opens pairs,
        // do not offer a misleading series-opening action.
        if (!pairOpened) {
          final canOpenSeries = _actions['open_series'] == true;
          final seriesLabel = canOpenSeries ? 'SERİ AÇ' : score < threshold ? 'SERİ AÇ −${threshold - score}' : 'DİZİMİ DÜZENLE';
          buttons.add(_barButton(seriesLabel, Icons.layers_rounded, canOpenSeries, () => unawaited(_openSeriesRespectingRack()), primary: true));
        }
        // Seriyle açan oyuncu, masada çift alanı varsa ÇİFT EKLE ile çift işler.
        final pairArea = _list(_state['melds']).any((m) => '${_map(m)['kind']}' == 'pair');
        final addMode = pairOpened || (opened && pairArea);
        buttons.add(_barButton(
          addMode ? 'ÇİFT EKLE' : 'ÇİFT AÇ $pairs/$pairThreshold',
          Icons.copy_all_rounded,
          addMode ? _actions['add_pairs'] == true : _actions['open_pairs'] == true,
          () => _act(addMode ? 'add_pairs' : 'open_pairs'),
        ));
      }
    } else if (_myTurn && phase == 'draw') {
      if (leftHint != null) {
        final kind = '${leftHint['kind'] ?? ''}';
        buttons.add(_barButton('SADECE AL', Icons.call_received_rounded, true, () => _takeLeftInto(null)));
        buttons.add(_barButton('AL VE AÇ', Icons.auto_awesome_rounded, true, () => unawaited(_takeLeftAndOpen(kind)), primary: true));
      } else {
        // Draw phase is communicated by the stock itself (ruby pulse/glow and
        // tap target). Do not fill the action rail with inert ÇEK/AT buttons.
      }
    } else if (!_isDuz && phase != 'finished' && phase != 'waiting') {
      // Keep the action rail in a predictable place even while another seat
      // is drawing or discarding. Disabled controls explain the next action.
      if (pairOpened) {
        buttons.add(_barButton('ÇİFT MODU', Icons.copy_all_rounded, false, () {}, primary: true));
      } else {
        final seriesLabel = score < threshold ? 'SERİ AÇ −${threshold - score}' : 'SIRA BEKLENİYOR';
        buttons.add(_barButton(seriesLabel, Icons.layers_rounded, false, () {}, primary: true));
        buttons.add(_barButton('ÇİFT $pairs/$pairThreshold', Icons.copy_all_rounded, false, () {}));
      }
    }

    final Widget meter;
    if (_isDuz) {
      meter = _infoBar('KLASİK OKEY', _state['duz_can_finish'] == true ? 'BİTİR’e bas!' : 'Taş çek • diz • son taşla bitir', ready: _state['duz_can_finish'] == true);
    } else if (opened) {
      meter = _infoBar(
        pairOpened ? 'ÇİFT AÇTIN • ${_integer(_viewer['opening_pairs'])}' : 'AÇTIN • ${_integer(_viewer['opening_score'])}',
        'Elinde $handCount taş • $rackValue puan',
        ready: true,
      );
    } else {
      meter = _openingMeterBar(score, threshold, canOpen: _actions['open_series'] == true);
    }

    return LayoutBuilder(builder: (context, constraints) {
      // Çubuk ıstakanın üstündeki 42 tasarım pikseline sığar. İkinci satıra
      // geçmez; işlem butonları kendi yatay kaydırma alanında kalır.
      final available = constraints.maxWidth;
      final meterWidth = (available * (buttons.isEmpty ? .56 : .36)).clamp(120.0, 250.0).toDouble();
      return SizedBox(
        height: f.y(36),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          SizedBox(width: meterWidth, child: meter),
          const SizedBox(width: 5),
          Expanded(
            child: buttons.isEmpty
                ? const SizedBox.shrink()
                // Kaydırma yok: butonlar satıra sığar, gerekirse yazıları küçülür.
                : Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    for (final b in buttons) Flexible(child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: b)),
                  ]),
          ),
        ]),
      );
    });
  }

  // ───────────── Istaka ─────────────

  String get _viewerRackStyle {
    for (final raw in _list(_state['players'])) {
      final p = _map(raw);
      if (_integer(p['seat']) == _viewerSeat) {
        return realRackStyle(equipped: '${_map(p['loadout'])['rack'] ?? ''}', local: widget.preferences.rackStyle);
      }
    }
    return realRackStyle(local: widget.preferences.rackStyle);
  }

  Widget _rack(bool compact) {
    final byId = <String, Map<String, dynamic>>{
      for (final tile in _serverHand) '${tile['id']}': tile,
    };
    return KeyedSubtree(
      key: _rackKey,
      child: RealRack(
        style: _viewerRackStyle,
        active: _myTurn && _state['started'] == true,
        row0: _rackSlotRow(0, byId, compact),
        row1: _rackSlotRow(_rackCols, byId, compact),
      ),
    );
  }

  // ───────────── Oyuncu kartı ve hediyeler ─────────────

  int _giftCooldownLeft(String id, int nowMs) {
    final until = _giftCooldownUntil[id] ?? 0;
    return until > nowMs ? ((until - nowMs) / 1000).ceil() : 0;
  }

  Future<void> _showPlayerCard(Map<String, dynamic> player) async {
    final seat = _integer(player['seat']);
    if (seat == _viewerSeat) {
      await _showPlayerProfile(player);
      return;
    }
    final relative = (seat - _viewerSeat + 4) % 4;
    final align = switch (relative) {
      1 => const Alignment(.92, -.15),
      2 => const Alignment(0, -.55),
      _ => const Alignment(-.92, -.15),
    };
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'kapat',
      barrierColor: const Color(0x66000000),
      transitionDuration: _reducedFx ? Duration.zero : const Duration(milliseconds: 200),
      transitionBuilder: (context, anim, _, child) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(scale: Tween<double>(begin: .92, end: 1).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutBack)), alignment: align, child: child),
      ),
      pageBuilder: (dialogContext, _, __) => SafeArea(
        child: Align(
          alignment: align,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Material(
              color: Colors.transparent,
              child: _PlayerCardBody(
                state: this,
                player: player,
                onClose: () => Navigator.of(dialogContext).pop(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openGiftPicker() async {
    final others = [_relativeSeat(1), _relativeSeat(2), _relativeSeat(3)].map(_playerAtSeat).where((p) => p.isNotEmpty).toList();
    if (others.isEmpty) {
      _tableNotice('Masada hediye gönderecek kimse yok.');
      return;
    }
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'kapat',
      barrierColor: const Color(0x66000000),
      transitionDuration: _reducedFx ? Duration.zero : const Duration(milliseconds: 200),
      transitionBuilder: (context, anim, _, child) => FadeTransition(opacity: anim, child: child),
      pageBuilder: (dialogContext, _, __) => SafeArea(
        child: Align(
          alignment: const Alignment(.72, .35),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Material(
              color: Colors.transparent,
              child: _PlayerCardBody(
                state: this,
                player: others.first,
                giftMode: true,
                targets: others,
                onClose: () => Navigator.of(dialogContext).pop(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<bool> _sendGift(String giftId, int toSeat) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_giftCooldownLeft(giftId, now) > 0) {
      _tableNotice('Bu hediyeyi ${_giftCooldownLeft(giftId, now)} sn sonra tekrar atabilirsin.');
      return false;
    }
    final ok = await _sendChat('gift', giftId, toSeat: toSeat);
    if (ok) {
      _giftCooldownUntil[giftId] = DateTime.now().millisecondsSinceEpoch + 10000;
      if (mounted) setState(() {});
    }
    return ok;
  }

  // ───────────── Hediye efektleri ─────────────

  Offset _reactionAnchor(int? seat, Size size) {
    if (seat == null) return Offset(size.width * .5, size.height * .45);
    final relative = (seat - _viewerSeat + 4) % 4;
    final p = switch (relative) {
      0 => const Offset(64, 356),
      1 => const Offset(958, 173),
      2 => const Offset(447, 35),
      _ => const Offset(42, 173),
    };
    // Üst oyuncu ortalanmış satırda; avatar, isim plakasının solunda durur.
    return Offset(p.dx / 1000 * size.width, p.dy / 450 * size.height);
  }

  /// Hediyenin uçacağı/çarpacağı noktayı, oyuncunun gerçek avatar
  /// konumundan bulur (ekran boyutundan bağımsız). Bulunamazsa koltuk
  /// haritasındaki yaklaşık konuma düşer.
  Offset _giftAnchor(int? seat, Size size, BuildContext overlayContext) {
    if (seat != null && seat >= 0) {
      try {
        final avatar = _avatarKeys[seat]?.currentContext?.findRenderObject();
        final overlay = overlayContext.findRenderObject();
        if (avatar is RenderBox && overlay is RenderBox && avatar.hasSize && overlay.hasSize && avatar.attached && overlay.attached) {
          final global = avatar.localToGlobal(avatar.size.center(Offset.zero));
          return overlay.globalToLocal(global);
        }
      } catch (_) {}
    }
    return _reactionAnchor(seat, size);
  }

  Widget _giftOverlay() => LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          final def = _giftByIdOrName(_giftId, _giftKind);
          if (def?.style == 'big') return const SizedBox.shrink();
          final tableGift = _giftToSeat == -1;
          final emoji = def?.emoji ?? '🎁';
          final fxId = def?.id ?? _giftKind.toLowerCase();
          final thrown = def?.style == 'stick';
          return TweenAnimationBuilder<double>(
            key: ValueKey('${_giftEventId ?? ''}-$_giftKind'),
            tween: Tween(begin: 0.0, end: 1.0),
            // Hediye animasyonu "azaltılmış efekt" modunda da oynar (hediyenin kendisi bu).
            duration: const Duration(milliseconds: 2600),
            builder: (context, value, _) {
              final from = _giftAnchor(_giftFromSeat, size, context);
              final to = tableGift ? Offset(size.width * .5, size.height * .40) : _giftAnchor(_giftToSeat, size, context);
              const flight = .30;
              final travel = Curves.easeInCubic.transform((value / flight).clamp(0.0, 1.0));
              final point = Offset.lerp(from, to, travel) ?? to;
              final arc = math.sin(math.pi * travel) * math.min(110.0, (to - from).distance * .30);
              final artSize = math.max(40.0, size.shortestSide * .12);
              final impact = ((value - flight) / (1 - flight)).clamp(0.0, 1.0);
              final targets = tableGift ? [_viewerSeat, _relativeSeat(1), _relativeSeat(2), _relativeSeat(3)].map((s) => _giftAnchor(s, size, context)).toList() : [to];
              return Stack(clipBehavior: Clip.none, children: [
                if (value < flight)
                  Positioned(
                    left: point.dx - artSize / 2,
                    top: point.dy - artSize / 2 - arc,
                    child: Transform.rotate(
                      angle: thrown ? travel * math.pi * 4 : math.sin(travel * math.pi) * .3,
                      child: Transform.scale(
                        scale: .7 + .5 * math.sin(travel * math.pi),
                        child: Text(emoji, style: TextStyle(fontSize: artSize * .9, shadows: const [Shadow(color: Color(0x99000000), blurRadius: 10, offset: Offset(0, 6))])),
                      ),
                    ),
                  ),
                if (value >= flight)
                  for (final t in targets)
                    Positioned(
                      left: t.dx - artSize * 2,
                      top: t.dy - artSize * 2,
                      width: artSize * 4,
                      height: artSize * 4,
                      child: CustomPaint(painter: _GiftFxPainter(kind: fxId, emoji: emoji, t: impact, unit: artSize)),
                    ),
              ]);
            },
          );
        },
      );

  /// Büyük hediye: TikTok tarzı tam ekran kısa gösteri.
  Widget _bigGiftOverlay() {
    final big = _bigGift;
    if (big == null) return const SizedBox.shrink();
    return IgnorePointer(
      child: TweenAnimationBuilder<double>(
        key: ValueKey(big.key),
        tween: Tween(begin: 0, end: 1),
        duration: _reducedFx ? const Duration(milliseconds: 1) : const Duration(milliseconds: 2600),
        builder: (context, v, _) {
          final appear = Curves.easeOutBack.transform((v / .22).clamp(0.0, 1.0));
          final fade = v < .82 ? 1.0 : (1 - (v - .82) / .18).clamp(0.0, 1.0);
          return Opacity(
            opacity: fade,
            child: Stack(alignment: Alignment.center, children: [
              Positioned.fill(child: ColoredBox(color: Color.fromRGBO(0, 0, 0, .45 * appear.clamp(0.0, 1.0)))),
              Transform.rotate(
                angle: v * math.pi * .6,
                child: CustomPaint(size: const Size(520, 520), painter: _RaysPainter(alpha: .22 * appear.clamp(0.0, 1.0))),
              ),
              Column(mainAxisSize: MainAxisSize.min, children: [
                Transform.scale(
                  scale: .3 + .7 * appear,
                  child: Transform.translate(
                    offset: Offset(0, -8 * math.sin(v * math.pi * 4)),
                    child: Text(big.emoji, style: const TextStyle(fontSize: 120, shadows: [Shadow(color: Color(0xAAFFC864), blurRadius: 40)])),
                  ),
                ),
                const SizedBox(height: 6),
                Opacity(
                  opacity: ((v - .12) / .2).clamp(0.0, 1.0),
                  child: OkxLeather(
                    radius: 999,
                    stitch: true,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                    borderColor: OkeyXColors.gold,
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(text: big.from, style: const TextStyle(color: Color(0xFFFFE3A0))),
                        TextSpan(text: big.to.isEmpty ? '  masaya  ' : '  →  '),
                        if (big.to.isNotEmpty) TextSpan(text: big.to, style: const TextStyle(color: Color(0xFFFFE3A0))),
                        TextSpan(text: '  •  ${big.name}', style: const TextStyle(color: OkeyXColors.mint)),
                      ]),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: OkeyXColors.cream),
                    ),
                  ),
                ),
              ]),
            ]),
          );
        },
      ),
    );
  }

  // ───────────── Açılış duyurusu ─────────────

  Widget _openingSplash() {
    final player = _playerAtSeat(_openingSplashSeat);
    final pairs = _openingSplashMode == 'pairs';
    final value = _openingSplashValue;
    final mine = _openingSplashSeat == _viewerSeat;
    final name = mine ? 'SEN' : '${player['name'] ?? 'Oyuncu'}'.toUpperCase();
    final melds = _list(_state['melds']).map(_map).where((m) => _integer(m['owner_seat']) == _openingSplashSeat && ((m['kind'] == 'pair') == pairs)).toList();
    return IgnorePointer(
      child: LayoutBuilder(builder: (context, c) {
        final f = _Frame(c.maxWidth, c.maxHeight);
        final tw = f.s(19).clamp(14.0, 26.0).toDouble();
        return Align(
          alignment: const Alignment(0, -.12),
          child: TweenAnimationBuilder<double>(
            key: ValueKey(_openingSplashKey),
            duration: _reducedFx ? Duration.zero : const Duration(milliseconds: 460),
            tween: Tween(begin: 0, end: 1),
            curve: Curves.easeOutBack,
            builder: (context, v, child) => Opacity(opacity: v.clamp(0.0, 1.0), child: Transform.scale(scale: .7 + .3 * v, child: child)),
            child: SizedBox(
              width: f.x(452),
              child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
                Positioned(
                  left: -60,
                  right: -60,
                  top: -80,
                  bottom: -80,
                  child: CustomPaint(painter: _RaysPainter(alpha: .16)),
                ),
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.fromLTRB(16, f.s(12), 16, f.s(12)),
                  decoration: BoxDecoration(
                    color: const Color(0xF2110A30),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFD9A94E), width: 1.6),
                    boxShadow: const [
                      BoxShadow(color: Color(0x66FFC864), blurRadius: 34),
                      BoxShadow(color: Color(0xB3000000), blurRadius: 24, offset: Offset(0, 12)),
                    ],
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      _miniSeatAvatar(player.isEmpty ? {'name': name} : player, 24),
                      const SizedBox(width: 8),
                      Text(name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1.6, color: OkeyXColors.cream)),
                    ]),
                    const SizedBox(height: 2),
                    ShaderMask(
                      shaderCallback: (r) => const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFF0B8), Color(0xFFE3A740), Color(0xFFA8661C)]).createShader(r),
                      child: Text(pairs ? 'Çift açtı!' : 'Seri açtı!', style: TextStyle(fontFamily: OkeyXFonts.serif, fontWeight: FontWeight.w700, fontSize: f.s(34).clamp(24.0, 48.0).toDouble(), color: Colors.white, height: 1.15)),
                    ),
                    if (melds.isNotEmpty) ...[
                      SizedBox(height: f.s(8)),
                      Wrap(alignment: WrapAlignment.center, spacing: 7, runSpacing: 6, children: [for (final m in melds.take(8)) _meldChip(m, tw)]),
                    ],
                  ]),
                ),
                Positioned(
                  right: -14,
                  top: -22,
                  child: Transform.rotate(
                    angle: .08,
                    child: Container(
                      width: f.s(62).clamp(48.0, 84.0).toDouble(),
                      height: f.s(62).clamp(48.0, 84.0).toDouble(),
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(center: Alignment(-.3, -.4), colors: [Color(0xFFFFF0B8), Color(0xFFE3A740), Color(0xFFA8661C)]),
                        boxShadow: [BoxShadow(color: Color(0x99FFC864), blurRadius: 18), BoxShadow(color: Color(0xFF231664), spreadRadius: 2)],
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Text(pairs ? '$value\nÇİFT' : '$value', textAlign: TextAlign.center, style: TextStyle(fontFamily: OkeyXFonts.number, fontSize: pairs ? 16 : 22, height: 1, color: const Color(0xFF150E3D))),
                        ),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        );
      }),
    );
  }

  Widget _eventBanner() {
    final penalty = _eventType == 'rule_penalty' || _eventType == 'useful_discard' || _eventType == 'okey_discard';
    return TweenAnimationBuilder<double>(
      key: ValueKey('$_seenEventSequence-$_eventType-$_eventText'),
      duration: _reducedFx ? Duration.zero : const Duration(milliseconds: 260),
      tween: Tween(begin: 0, end: 1),
      curve: Curves.easeOutBack,
      builder: (context, value, child) => Transform.translate(offset: Offset(0, -14 * (1 - value)), child: Opacity(opacity: value.clamp(0.0, 1.0), child: child)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 460),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: penalty ? const Color(0xF27A2218) : const Color(0xF2130D2C),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: penalty ? OkeyXColors.danger : OkeyXColors.line2),
          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 12)],
        ),
        child: Text(_eventText, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: Color(0xFFFFE9B0))),
      ),
    );
  }

  Widget _turnCueOverlay() => TweenAnimationBuilder<double>(
        key: ValueKey(_turnCueSeq),
        tween: Tween(begin: 0, end: 1),
        duration: _reducedFx ? Duration.zero : const Duration(milliseconds: 260),
        curve: Curves.easeOut,
        builder: (context, value, child) => Opacity(opacity: value.clamp(0, 1), child: child),
        child: Align(
          alignment: const Alignment(0, .12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xE6130D2C),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0xFFFFC24A).withValues(alpha: .82)),
              boxShadow: [BoxShadow(color: const Color(0xFFFFC24A).withValues(alpha: .30), blurRadius: 16)],
            ),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.touch_app_rounded, color: const Color(0xFFFFC24A), size: 15),
              SizedBox(width: 6),
              Text('SIRA SENDE', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 1.1, color: OkeyXColors.cream)),
            ]),
          ),
        ),
      );

  // Efekt katmanı konumları (1000×450 taslak çerçevesinin oranları).
  Offset _fxSeatAnchor(int seat) {
    final relative = (seat - _viewerSeat + 4) % 4;
    return switch (relative) {
      0 => const Offset(.64, .80),
      1 => const Offset(.958, .385),
      2 => const Offset(.447, .078),
      _ => const Offset(.042, .385),
    };
  }

  Offset _fxPileAnchor(int seat) {
    final relative = (seat - _viewerSeat + 4) % 4;
    return switch (relative) {
      0 => const Offset(.866, .644),
      1 => const Offset(.923, .231),
      2 => const Offset(.127, .231),
      _ => const Offset(.188, .60),
    };
  }
  Future<void> _initTableAudio() async {
    // Lobby music never leaks into the table. Table ambience and radio are
    // explicit, independently controllable table audio sources.
    await GameAudio.stopLobby();
    await GameAudio.setVolumes(
      music: widget.preferences.musicVolume,
      radio: _radioVolume,
      ambience: _ambienceVolume,
      sfx: _sfxVolume,
    );
    final live = await LiveFeatureService().load();
    if (!mounted) return;
    setState(() => _liveFeatures = live);
    await _applyTableAudio();
  }

  Future<void> _applyTableAudio() async {
    if (_radioEnabled && _liveFeatures.radioEnabled) {
      await GameAudio.stopAmbience();
      final station = _liveFeatures.station(_tableRadioStation);
      try {
        await GameAudio.startRadio(source: station.source, remote: station.remote);
      } catch (_) {
        _radioEnabled = false;
      }
      return;
    }
    await GameAudio.stopRadio();
    if (_ambienceEnabled) {
      await GameAudio.startAmbience();
    } else {
      await GameAudio.stopAmbience();
    }
  }


  UserPreferences get _tablePreferences => widget.preferences.copyWith(
        soundEnabled: _soundEnabled,
        vibrationEnabled: _vibrationEnabled,
        radioEnabled: _radioEnabled,
        radioStation: _tableRadioStation,
        sfxVolume: _sfxVolume,
        radioVolume: _radioVolume,
        ambienceVolume: _ambienceVolume,
        tableAmbienceEnabled: _ambienceEnabled,
      );

  void _notifyTablePreferences() {
    widget.onPreferencesChanged?.call(_tablePreferences);
  }

  void _setTableSfxVolume(double value) {
    setState(() => _sfxVolume = value.clamp(0.0, 1.0).toDouble());
    unawaited(GameAudio.setVolumes(sfx: _sfxVolume));
  }

  void _setTableRadioVolume(double value) {
    setState(() => _radioVolume = value.clamp(0.0, 1.0).toDouble());
    unawaited(GameAudio.setVolumes(radio: _radioVolume));
  }

  void _setTableAmbienceVolume(double value) {
    setState(() => _ambienceVolume = value.clamp(0.0, 1.0).toDouble());
    unawaited(GameAudio.setVolumes(ambience: _ambienceVolume));
  }

  Future<void> _showTableRadioPicker() async {
    if (!_liveFeatures.radioEnabled || _liveFeatures.radioStations.isEmpty) {
      _tableNotice('Radyo kanalları şu anda yüklenemedi.');
      return;
    }
    if (_radioEnabled) {
      final station = _liveFeatures.station(_tableRadioStation);
      final nowPlaying = await RadioNowPlayingService.fetch(station);
      if (mounted && nowPlaying.available) {
        setState(() => _radioNowPlaying = nowPlaying);
      }
    }
    if (!mounted) return;
    final selected = await showDialog<String>(
      context: context,
      barrierColor: const Color(0xCC00070C),
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(8),
        backgroundColor: Colors.transparent,
        child: PremiumRadioPanel(
          stations: _liveFeatures.radioStations,
          activeStationId: _tableRadioStation,
          playing: _radioEnabled,
          nowPlaying: _radioNowPlaying,
          title: 'MASA RADYOSU',
          subtitle: 'Oyun kesilmeden istasyonunu değiştir',
          compact: MediaQuery.sizeOf(context).height < 470,
        ),
      ),
    );
    if (selected == null) return;
    if (selected == '__off__') {
      setState(() => _radioEnabled = false);
      await _applyTableAudio();
      _notifyTablePreferences();
      return;
    }
    final stationId = selected == '__play__' ? _tableRadioStation : selected;
    final station = _liveFeatures.station(stationId);
    setState(() { _radioEnabled = true; _tableRadioStation = stationId; });
    await GameAudio.stopAmbience();
    try {
      await GameAudio.startRadio(source: station.source, remote: station.remote);
      _tableNotice('${station.title} açıldı.');
      _notifyTablePreferences();
    } catch (_) {
      if (mounted) setState(() => _radioEnabled = false);
      _notifyTablePreferences();
      _tableNotice('Radyo bağlantısı açılamadı.');
    }
  }

  // Kept temporarily for migration readability; the live route above is the
  // fixed, paged, scroll-free premium panel.
  String _stateRevision(Map<String, dynamic> value) {
    final players = _list(value['players']).map(_map).toList();
    final viewerSeat = _integer(value['viewer_seat']);
    final viewer = players.firstWhere((p) => _integer(p['seat']) == viewerSeat, orElse: () => const <String, dynamic>{});
    final hand = _list(viewer['hand']).map((t) => '${_map(t)['id']}').join(',');
    final melds = _list(value['melds']).map((m) {
      final mm = _map(m);
      return '${mm['id']}:${_list(mm['tiles']).map((t) => '${_map(t)['id']}').join(',')}';
    }).join('|');
    final discards = _map(value['discards']).entries.map((e) => '${e.key}:${_map(e.value)['id'] ?? ''}').join('|');
    final lastEvent = _map(value['last_event']);
    final chat = _list(value['chat']);
    final reactions = _list(value['reactions']);
    final chatId = chat.isEmpty ? '' : '${_map(chat.last)['id']}';
    final reactionId = reactions.isEmpty ? '' : '${_map(reactions.last)['id']}';
    final settlement = _map(value['settlement']);
    final playerPulse=players.map((p)=>'${p['seat']}:${p['afk_bot']}:${p['hand_count']}:${p['chips']}:${_map(p['public_stats'])['current_streak']}').join('|');
    final canak = _map(value['canak']);
    return '${value['viewer_chips']}:${canak['pot']}:${_map(canak['last'])['at']}:${value['phase']}:${value['current_seat']}:${value['turn_no']}:${value['stock_count']}:${value['multiplier']}:${value['intro_until_ms']}:${lastEvent['seq'] ?? 0}:$chatId:$reactionId:$hand:$melds:$discards:${value['viewer_afk_bot']}:$playerPulse:${settlement['status'] ?? ''}:${_list(settlement['rankings']).length}';
  }

  Future<void> _start() async {
    try {
      await _api.startOrRestore();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _online = true;
        _connection = 'CANLI';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _friendlyCode('$error');
      });
    }
  }

  String _tileImpactSfx(Map<String,dynamic> player,{String fallback='discard'}) {
    final id='${_map(player['loadout'])['tiles']??'tiles_classic'}';
    if(id.contains('marble'))return 'tile_material_marble';
    if(id.contains('neon'))return 'tile_material_neon';
    if(id.contains('royal')||id.contains('ember'))return 'tile_material_royal';
    if(id.contains('ice'))return 'tile_material_ice';
    return fallback;
  }

  // --- Masa efektleri: rakip hamlelerinde uçan taş + duman -------------------
  // Konumlar ekranın oranı olarak verilir (yaklaşık yerleşim; gerçek cihazda
  // ince ayar gerekirse yalnızca bu iki tablo değişir).
  /// Dağıtım: oyun başlayınca masa ortasından ıstakaya ve rakip koltuklarına taşlar saçılır.
  void _fxDeal() {
    if (widget.preferences.reducedMotionEnabled || widget.preferences.dataSaverEnabled) return;
    for (var i = 0; i < 12; i++) {
      Future<void>.delayed(Duration(milliseconds: 70 * i), () {
        if (!mounted) return;
        try {
          final target = i % 4 == 0 ? _fxSeatAnchor(_viewerSeat) : _fxSeatAnchor((_viewerSeat + i % 4) % 4);
          _fx.flyTileFrac(
            tile: const GameTile(id: 'fx-deal', number: 1, colorIndex: 2, faceDown: true),
            from: const Offset(.815, .22),
            to: target,
            puffOnLand: false,
            duration: const Duration(milliseconds: 380),
          );
        } catch (_) {}
      });
    }
  }

  void _fxOnTableEvent(String type, int seat, Map<String, dynamic> next) {
    if (widget.preferences.reducedMotionEnabled || widget.preferences.dataSaverEnabled) return;
    if (_state['started'] != true || _viewerSeat < 0) return;
    const stock = Offset(.815, .22);
    switch (type) {
      case 'draw_stock':
        _fx.flyTileFrac(
          tile: const GameTile(id: 'fx-back', number: 1, colorIndex: 2, faceDown: true),
          from: stock,
          to: _fxSeatAnchor(seat),
          puffOnLand: false,
          duration: const Duration(milliseconds: 420),
        );
        break;
      case 'take_left':
        final leftSeat = (seat + 3) % 4;
        final taken = _map(_map(_state['discards'])['$leftSeat']);
        if (taken.isEmpty) return;
        _fx.flyTileFrac(
          tile: _tile(taken),
          skinId: _tileSkinForSeat(leftSeat),
          from: _fxPileAnchor(leftSeat),
          to: _fxSeatAnchor(seat),
          puffOnLand: false,
          duration: const Duration(milliseconds: 420),
        );
        break;
      case 'discard':
      case 'useful_discard':
      case 'okey_discard':
        final latest = _map(_map(next['discards'])['$seat']);
        if (latest.isEmpty) return;
        if (seat == _viewerSeat) {
          // Kendi atışımız: ıstakadan ıskarta yığınına uçuş + inme dumanı.
          _fx.flyTileFrac(
            tile: _tile({...latest, 'face_down': false}),
            skinId: _tileSkinForSeat(seat),
            from: _fxSeatAnchor(seat),
            to: _fxPileAnchor(seat),
            puffOnLand: true,
            duration: const Duration(milliseconds: 360),
          );
          return;
        }
        _fx.flyTileFrac(
          tile: _tile({...latest, 'face_down': false}),
          skinId: _tileSkinForSeat(seat),
          from: _fxSeatAnchor(seat),
          to: _fxPileAnchor(seat),
          puffOnLand: true,
        );
        break;
    }
  }

  void _receiveState(Map<String, dynamic> value) {
    if (!mounted || value.isEmpty) return;
    final revision = _stateRevision(value);
    if (revision == _lastStateRevision) return;
    _lastStateRevision = revision;
    final viewerSeatForAudio = _integer(value['viewer_seat']);
    final viewerForAudio = _list(value['players']).map(_map).firstWhere((p) => _integer(p['seat']) == viewerSeatForAudio, orElse: () => const <String,dynamic>{});
    final nextSoundPack = '${_map(viewerForAudio['loadout'])['sound_pack'] ?? 'sound_classic'}';
    final viewerLoadoutForAudio=_map(viewerForAudio['loadout']);
    GameAudio.setMaterialProfile(
      tiles:'${viewerLoadoutForAudio['tiles'] ?? 'tiles_ivory'}',
      rack:'${viewerLoadoutForAudio['rack'] ?? 'rack_classic'}',
    );
    if (nextSoundPack != _activeSoundPack) {
      _activeSoundPack = nextSoundPack;
      GameAudio.setSoundPack(nextSoundPack);
    }
    try {
      if (_state['started'] != true && value['started'] == true && _viewerSeat >= 0) _fxDeal();
    } catch (_) {}
    try {
      if ('${_state['phase']}' != 'finished' && '${value['phase']}' == 'finished' &&
          !widget.preferences.reducedMotionEnabled && !widget.preferences.dataSaverEnabled) {
        _fx.confetti();
      }
    } catch (_) {}
    final previousMultiplier = _integer(_state['multiplier'], fallback: 1);
    final nextMultiplier = _integer(value['multiplier'], fallback: 1);
    if (value['turbo'] == true && nextMultiplier > previousMultiplier && _state.isNotEmpty) {
      _turboFxSeq++;
      _turboFxCount = nextMultiplier - previousMultiplier;
      unawaited(GameAudio.sfx('shockwave', enabled: _soundEnabled, volume: .62));
    }
    final previousTurn = _lastTurnSeat;
    final previousIntro = _integer(_state['intro_until_ms']);
    final currentIntro = _integer(value['intro_until_ms']);
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final previousAfk = _state['viewer_afk_bot'] == true;
    final previousPlayers=_list(_state['players']).map(_map).toList();
    final lastEvent = _map(value['last_event']);
    final sequence = _integer(lastEvent['seq']);
    final chatRows = _list(value['chat']).map(_map).where((e) => '${e['kind']}' != 'gift').toList();
    if (chatRows.isNotEmpty) {
      _handleChatEvent(chatRows.last, rebuild: false);
    }
    final canakLast = _map(_map(value['canak'])['last']);
    final canakAt = _integer(canakLast['at']);
    if (_canakSeenAt < 0) {
      _canakSeenAt = canakAt;
    } else if (canakAt > _canakSeenAt) {
      _canakSeenAt = canakAt;
      _canakBreak = canakLast;
      unawaited(GameAudio.sfx('coin_shower', enabled: _soundEnabled));
      if (_vibrationEnabled) unawaited(HapticFeedback.heavyImpact());
      Future<void>.delayed(const Duration(milliseconds: 3400), () {
        if (mounted) setState(() => _canakBreak = null);
      });
    }
    final reactionRows = _list(value['reactions']).map(_map).toList();
    if (!_reactionsPrimed) {
      // Masaya ilk girişte eski hediyeleri yeniden oynatma.
      _reactionsPrimed = true;
      if (reactionRows.isNotEmpty) _seenReactionId = '${reactionRows.last['id'] ?? ''}';
    } else if (reactionRows.isNotEmpty) {
      _handleChatEvent(reactionRows.last, rebuild: false);
    }
    for(final next in _list(value['players']).map(_map)){
      final seat=_integer(next['seat']);
      final before=previousPlayers.firstWhere((p)=>_integer(p['seat'])==seat,orElse:()=>const <String,dynamic>{});
      if(before.isNotEmpty&&before['afk_bot']!=true&&next['afk_bot']==true){
        _rageSeat=seat;
        _rageEventKey='rage-$seat-${DateTime.now().millisecondsSinceEpoch}';
        unawaited(GameAudio.sfx('rage_robot',enabled:_soundEnabled,volume:.86));
        Future<void>.delayed(const Duration(milliseconds:2100),(){if(mounted&&_rageSeat==seat)setState((){_rageSeat=null;_rageEventKey=null;});});
      }
    }

    if (sequence > _seenEventSequence) {
      _seenEventSequence = sequence;
      _eventType = '${lastEvent['type'] ?? ''}';
      final eventSeat = _integer(lastEvent['seat']);
      const silentTableEvents={'draw_stock','take_left','return_left','discard'};
      _eventText = silentTableEvents.contains(_eventType) ? '' : '${lastEvent['message'] ?? ''}';
      if(const {'rule_penalty','useful_discard','okey_discard'}.contains(_eventType)){
        final badge=_eventType=='okey_discard'?'OKEY +101':_eventType=='useful_discard'?'İŞLER +101':'+101';
        _penaltyBadges[eventSeat]=badge;
        Future<void>.delayed(const Duration(milliseconds:3000),(){if(mounted&&_penaltyBadges[eventSeat]==badge)setState(()=>_penaltyBadges.remove(eventSeat));});
      }
      // Local actions already play instantly on touch. Server events add the
      // corresponding physical table sound for the other three players so a
      // multiplayer table never feels silent.
      try { _fxOnTableEvent(_eventType, eventSeat, value); } catch (_) {}
      if (eventSeat != _viewerSeat) {
        switch (_eventType) {
          case 'draw_stock':
            unawaited(GameAudio.sfx('tile_pick', enabled: _soundEnabled, volume: .82));
            break;
          case 'take_left':
            unawaited(GameAudio.sfx('take_left', enabled: _soundEnabled, volume: .84));
            break;
          case 'return_left':
            unawaited(GameAudio.sfx('tile_drop', enabled: _soundEnabled, volume: .78));
            break;
          case 'discard':
          case 'useful_discard':
          case 'okey_discard':
            unawaited(GameAudio.sfx('discard', enabled: _soundEnabled, volume: .86));
            break;
        }
      }
      if (_eventType == 'opened') {
        final data = _map(lastEvent['data']);
        final mode = '${data['mode'] ?? ''}';
        _openingSplashKey = '$sequence-$mode-${data['value'] ?? ''}';
        _openingSplashSeat = _integer(lastEvent['seat']);
        _openingSplashMode = mode;
        _openingSplashValue = _integer(data['value']);
        unawaited(GameAudio.sfx(
          mode == 'pairs' ? 'pair_open' : 'series_open',
          enabled: _soundEnabled,
          volume: .64,
        ));
      } else if (_eventType == 'one_tile') {
        final seat = _integer(lastEvent['seat']);
        final bubbleId = 'one-tile-$sequence';
        _chatBubbles[seat] = 'TEK TAŞ KALDI!';
        _chatBubbleIds[seat] = bubbleId;
        unawaited(GameAudio.sfx('turn', enabled: _soundEnabled, volume: .52));
        Future<void>.delayed(const Duration(milliseconds: 2400), () {
          if (!mounted || _chatBubbleIds[seat] != bubbleId) return;
          setState(() {
            _chatBubbles.remove(seat);
            _chatBubbleIds.remove(seat);
          });
        });
      }
      if (_vibrationEnabled &&
          _eventType != 'draw_stock' &&
          _eventType != 'take_left' &&
          _eventType != 'return_left' &&
          _eventType != 'discard') {
        unawaited(
          _eventType == 'one_tile' || _eventType == 'opened'
              ? HapticFeedback.mediumImpact()
              : _eventType == 'rule_penalty' ||
                      _eventType == 'useful_discard' ||
                      _eventType == 'okey_discard'
                  ? HapticFeedback.heavyImpact()
                  : HapticFeedback.selectionClick(),
        );
      }
      Future<void>.delayed(
        _eventType == 'opened' ? const Duration(milliseconds: 2100) : const Duration(seconds: 3),
        () {
          if (mounted && _seenEventSequence == sequence) {
            setState(() {
              _eventText = '';
              _eventType = '';
              if (_openingSplashKey?.startsWith('$sequence-') == true) {
                _openingSplashKey = null;
              }
            });
          }
        },
      );
    }

    setState(() {
      _state = value;
      _loading = false;
      if (previousIntro > 0 && currentIntro <= 0) {
        _dealSequence++;
        _dealAnimating = !(widget.preferences.reducedMotionEnabled || widget.preferences.dataSaverEnabled);
        for (var i=0;i<8;i++){
          Future<void>.delayed(Duration(milliseconds:i*72),()=>unawaited(GameAudio.sfx(i.isEven?'tile_drop':'tile_pick',enabled:_soundEnabled,volume:.68)));
        }
        Future<void>.delayed(const Duration(milliseconds:610),()=>unawaited(GameAudio.sfx('rack_slide',enabled:_soundEnabled,volume:.70)));
        Future<void>.delayed(const Duration(milliseconds: 1050), () {
          if (mounted && _dealAnimating) setState(() => _dealAnimating = false);
        });
      }
      final serverHand = _serverHand;
      final serverIds = serverHand.map((tile) => '${tile['id']}').toList();
      final ids = serverIds.toSet();
      _syncRackSlots(serverHand, serverIds);
      if (_selectedTileId != null && !ids.contains(_selectedTileId)) {
        _selectedTileId = null;
      }
    });

    unawaited(_syncVoicePeers(value));
    if (value['started'] == true) unawaited(_autoJoinVoice());

    final currentTurn = _integer(value['current_seat']);
    final introJustEnded = previousIntro > 0 && currentIntro <= nowMs;
    final turnChanged = currentTurn != previousTurn;
    if (turnChanged) {
      debugPrint('OKEYX_TURN: room=${value['room_id']} seat=$currentTurn phase=${value['phase']} deadline=${value['turn_deadline_ms']}');
      _lastTurnSeat = currentTurn;
      _lastWarningSecond = -1;
    }
    // İlk oyuncu seat 0 olduğunda da sessiz kalmasın. Countdown devam ederken
    // cue göstermiyoruz; intro biter bitmez veya gerçek sıra değişiminde tetiklenir.
    final shouldCueViewer = currentTurn == _viewerSeat && currentIntro <= nowMs && (turnChanged || introJustEnded);
    if (shouldCueViewer) {
      final cue = ++_turnCueSeq;
      if (mounted) setState(() => _showTurnCue = true);
      unawaited(GameAudio.sfx('turn', enabled: _soundEnabled, volume: .92));
      if (_vibrationEnabled) unawaited(HapticFeedback.heavyImpact());
      Future<void>.delayed(const Duration(milliseconds: 1500), () {
        if (!mounted || cue != _turnCueSeq) return;
        setState(() => _showTurnCue = false);
      });
    } else if (turnChanged && currentTurn != _viewerSeat && _showTurnCue && mounted) {
      setState(() => _showTurnCue = false);
    }
    final introUntil = _integer(value['intro_until_ms']);
    if (introUntil > DateTime.now().millisecondsSinceEpoch && introUntil != _lastIntroUntilMs) {
      _lastIntroUntilMs = introUntil;
      unawaited(GameAudio.sfx('game_start', enabled: _soundEnabled, volume: .64));
      final spawn='${_map(viewerForAudio['loadout'])['spawn_fx'] ?? 'spawn_classic'}';
      if(spawn=='spawn_lightning')unawaited(GameAudio.sfx('spawn_lightning',enabled:_soundEnabled,volume:.82));
      if(spawn=='spawn_fire'||spawn=='spawn_royal')unawaited(GameAudio.sfx('spawn_fire',enabled:_soundEnabled,volume:.82));
    }
    if (!previousAfk && value['viewer_afk_bot'] == true) {
      debugPrint('OKEYX_AFK_ENTER: room=${value['room_id']} viewer=$_viewerSeat');
      unawaited(GameAudio.sfx('afk', enabled: _soundEnabled, volume: .60));
    } else if (previousAfk && value['viewer_afk_bot'] != true) {
      debugPrint('OKEYX_AFK_RETURN: room=${value['room_id']} viewer=$_viewerSeat');
    }
    if ('${value['phase']}' == 'finished') {
      _queueRoundResult();
      final isOwner=_viewerSeat==_integer(value['owner_seat']);
      if(value['match_finished']==true&&value['auto_rematch']==true&&isOwner&&!_autoRematchScheduled){
        _autoRematchScheduled=true;
        Future<void>.delayed(const Duration(seconds:5),()async{if(!mounted)return;try{await _requestRematch();}finally{_autoRematchScheduled=false;}});
      }
    } else {_autoRematchScheduled=false;}
  }

  void _handleChatEvent(Map<String, dynamic> newest, {bool rebuild = true}) {
    final chatId = '${newest['id'] ?? ''}';
    final kind = '${newest['kind'] ?? ''}';
    if (chatId.isEmpty) return;
    if (kind == 'gift') {
      if (chatId == _seenReactionId) return;
      _seenReactionId = chatId;
    } else {
      if (chatId == _seenChatId) return;
      _seenChatId = chatId;
    }
    final seat = _integer(newest['seat']);

    void apply() {
      if (kind == 'gift') {
        final giftName = '${newest['value'] ?? 'Hediye'}';
        final giftId = '${newest['gift_id'] ?? ''}';
        final def = _giftByIdOrName(giftId, giftName);
        final toSeatRaw = newest['to_seat'] == null ? null : _integer(newest['to_seat']);
        _giftEventId = chatId;
        _giftId = def?.id ?? giftId;
        _giftKind = giftName;
        if (def != null && def.style == 'big') {
          final toName = toSeatRaw == null || toSeatRaw < 0 ? '' : '${newest['to_name'] ?? ''}';
          _bigGift = _BigGift(def.emoji, def.name, '${newest['name'] ?? 'Oyuncu'}', toName, chatId);
          Future<void>.delayed(const Duration(milliseconds: 2700), () {
            if (mounted && _bigGift?.key == chatId) setState(() => _bigGift = null);
          });
        } else if (def != null && def.style == 'stick' && toSeatRaw != null && toSeatRaw >= 0) {
          final stickSeat = toSeatRaw;
          Future<void>.delayed(Duration(milliseconds: _reducedFx ? 0 : 560), () {
            if (!mounted) return;
            setState(() => _stuckGifts[stickSeat] = _StuckGift(def.emoji, chatId));
            Future<void>.delayed(const Duration(milliseconds: 6500), () {
              if (mounted && _stuckGifts[stickSeat]?.key == chatId) setState(() => _stuckGifts.remove(stickSeat));
            });
          });
        }
        _giftFromSeat = seat;
        _giftToSeat = newest['to_seat'] == null ? null : _integer(newest['to_seat']);
        if(_giftToSeat!=null&&_giftToSeat!=-1){
          _impactSeat=_giftToSeat;
          _impactKind=giftName;
          _impactEventId=chatId;
        }
        final toName = '${newest['to_name'] ?? ''}'.trim();
        final tableGift = _giftToSeat == -1;
        _giftText = tableGift
            ? '${newest['name'] ?? 'Oyuncu'} • Masaya $giftName'
            : toName.isEmpty
                ? '${newest['name'] ?? 'Oyuncu'} • $giftName'
                : '${newest['name'] ?? 'Oyuncu'} → $toName • $giftName';
      } else {
        final value = '${newest['value'] ?? ''}'.trim();
        if (value.isNotEmpty) {
          _chatBubbles[seat] = value;
          _chatBubbleIds[seat] = chatId;
        }
      }
    }

    if (rebuild && mounted) {
      setState(apply);
    } else {
      apply();
    }

    if (kind == 'gift') {
      final giftDef = _giftByIdOrName(_giftId, _giftKind);
      final sound = switch (giftDef?.id ?? _giftKind.toLowerCase()) {
        'tea' || 'coffee' || 'çay' || 'türk kahvesi' => 'gift_coffee',
        'rose' || 'gül' || 'heart' || 'kalp' => 'gift_rose',
        'tomato' || 'domates' => 'gift_tomato',
        'egg' || 'yumurta' => 'gift_egg',
        'slipper' || 'terlik' || 'yumruk' => 'gift_slipper',
        'fish' || 'balık tokadı' => 'gift_fish',
        'rubber_chicken' || 'lastik tavuk' => 'gift_chicken',
        'applause' || 'alkış' => 'gift_applause',
        'nazar' || 'nazar boncuğu' => 'gift_glass',
        'money_rain' || 'para yağmuru' => 'coin_shower',
        'rocket' || 'roket' => 'spawn_lightning',
        'dragon' || 'ejderha' => 'spawn_fire',
        'fireworks' || 'havai fişek' => 'shockwave',
        'crown' || 'altın taç' || 'sports_car' || 'spor araba' => 'reward',
        _ => 'gift_fun',
      };
      // Ses, hediye hedefe çarptığı anda (uçuşun sonunda) çalar.
      unawaited(GameAudio.sfx('gift_whoosh', enabled: _soundEnabled, volume: .55));
      unawaited(Future<void>.delayed(Duration(milliseconds: giftDef?.style == 'big' ? 0 : 760), () => GameAudio.sfx(sound, enabled: _soundEnabled, volume: sound == 'gift_slipper' ? .95 : .8)));
      if (_vibrationEnabled) {
        final heavy = sound == 'gift_slipper' || sound == 'gift_fish' || giftDef?.style == 'big';
        unawaited(heavy ? HapticFeedback.heavyImpact() : HapticFeedback.mediumImpact());
      }
      Future<void>.delayed(const Duration(milliseconds: 2700), () {
        if (!mounted || _giftEventId != chatId) return;
        setState(() {
          _giftText = '';
          _giftKind = '';
          _giftFromSeat = null;
          _giftToSeat = null;
          _giftEventId = null;
          _giftId = null;
          _impactSeat=null;
          _impactKind='';
          _impactEventId=null;
        });
      });
    } else {
      if(kind=='voice'){
        unawaited(GameAudio.voiceLine('${newest['value'] ?? ''}',enabled:_soundEnabled));
        if(_vibrationEnabled)unawaited(HapticFeedback.selectionClick());
      }else{
        unawaited(GameAudio.sfx('chat', enabled: _soundEnabled, volume: .522));
      }
      Future<void>.delayed(const Duration(milliseconds: 2800), () {
        if (!mounted || _chatBubbleIds[seat] != chatId) return;
        setState(() {
          _chatBubbles.remove(seat);
          _chatBubbleIds.remove(seat);
        });
      });
    }
  }

  /// Rövanş: başarısız olsa bile oyuncuyu masadan ATMAZ. Başka bir oyuncu
  /// (ya da otomatik rövanş) maçı zaten yeniden başlattıysa yeni maça devam
  /// eder; gerçekten masa kapandıysa lobiye dönülür.
  Future<void> _requestRematch() async {
    for (var i = 0; i < 20 && _busy; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (!mounted) return;
    if (_state['match_finished'] != true) return; // yeni maç zaten başladı
    try {
      _busy = true;
      await _api.action('rematch');
    } catch (error) {
      final text = '$error';
      if (text.contains('room_not_found') || text.contains('active_game_not_found')) {
        _busy = false;
        if (mounted) await _closeTable();
        return;
      }
      // match_not_finished: başka biri rövanşı başlattı; durum yayını gelecek.
      if (!text.contains('match_not_finished') && mounted) {
        setState(() => _error = _friendlyCode(text));
      }
    } finally {
      _busy = false;
      if (mounted) setState(() {});
    }
  }

  Future<Map<String, dynamic>?> _act(String kind, [Map<String, dynamic>? payload]) async {
    if (_busy) return null;
    final fastGesture = const {'draw_stock', 'discard', 'take_left', 'return_left'}.contains(kind);
    _busy = true;
    if (mounted && !fastGesture) {
      setState(() => _error = '');
    } else {
      _error = '';
    }
    if (_vibrationEnabled) unawaited(HapticFeedback.lightImpact());
    try {
      return await _api.action(kind, payload);
    } catch (error) {
      if (mounted) {
        setState(() => _error = _friendlyCode('$error'));
        if (_vibrationEnabled) unawaited(HapticFeedback.heavyImpact());
      }
      return null;
    } finally {
      _busy = false;
      // Server state broadcasts repaint the table after fast gestures; avoid a
      // redundant full-screen rebuild on every draw/discard round trip.
      if (mounted && !fastGesture) setState(() {});
    }
  }


  List<List<String>> _manualSeriesGroupsFromRack() {
    // SERİ DİZ is an assisted preview, not a declaration. If the player has
    // not touched the rack after assisted sorting, let the server's exact
    // solver choose a legal 101 opening while deliberately keeping one final
    // discard tile. This prevents the old 'rest' segment from being sent as a
    // fake manual meld and triggering must_keep_finish_tile.
    if (!_rackManuallyEdited) return const <List<String>>[];
    final groups = <List<String>>[];
    var hasManualBoundary = false;
    for (var row = 0; row < _rackRows; row++) {
      final start = row * _rackCols;
      var current = <String>[];
      void flush() {
        if (current.length >= 3) groups.add(List<String>.from(current));
        current = <String>[];
      }
      for (var col = 0; col < _rackCols; col++) {
        final id = _rackSlots[start + col];
        if (id == null) {
          if (current.isNotEmpty) { hasManualBoundary = true; flush(); }
          continue;
        }
        if (current.isNotEmpty && _rackGroupStarts.contains(id)) {
          hasManualBoundary = true;
          flush();
        }
        current.add(id);
      }
      flush();
    }
    // A completely packed rack with no explicit boundaries is the untouched
    // deal, not a manual declaration. In that case keep assisted auto-open.
    return hasManualBoundary || _rackGroupStarts.isNotEmpty ? groups : const <List<String>>[];
  }

  Future<void> _openSeriesRespectingRack() async {
    final groups=_manualSeriesGroupsFromRack();
    var out=await _act('open_series',groups.isEmpty?null:<String,dynamic>{'groups':groups});
    // Assisted mode is supposed to help, not trap the player because a visual
    // rack boundary accidentally swallowed the mandatory finish tile. Retry
    // with the exact server solver when the manual preview cannot be opened.
    final code='${out?['code'] ?? ''}';
    if(_assisted&&groups.isNotEmpty&&out?['ok']!=true&&const {'must_keep_finish_tile','invalid_meld','below_opening_threshold','run_not_consecutive','run_color_mismatch','set_number_mismatch'}.contains(code)){
      out=await _act('open_series');
    }
    if(out?['ok']==true)unawaited(GameAudio.sfx('series_open',enabled:_soundEnabled,volume:.78));
  }

  Map<String, dynamic> get _viewer {
    for (final player in _list(_state['players'])) {
      final map = _map(player);
      if (_integer(map['seat']) == _integer(_state['viewer_seat'])) return map;
    }
    return const {};
  }

  List<Map<String, dynamic>> get _serverHand =>
      _list(_viewer['hand']).map(_map).toList();

  List<Map<String, dynamic>> get _hand {
    final hand = _serverHand;
    final byId = <String, Map<String, dynamic>>{
      for (final tile in hand) '${tile['id']}': tile,
    };
    final ordered = <Map<String, dynamic>>[];
    for (final id in _rackSlots) {
      if (id == null) continue;
      final tile = byId.remove(id);
      if (tile != null) ordered.add(tile);
    }
    ordered.addAll(byId.values);
    return ordered;
  }

  bool get _canArrangeRack =>
      _state['started'] == true && '${_state['phase']}' != 'finished';
  Map<String, dynamic> get _actions => _map(_state['available_actions']);
  bool get _isDuz => '${_state['variant']}' == 'duz' || '${_state['game_type']}' == 'duz';

  /// Düz Okey: seçili taşı ortaya kapatarak eli bitir. Seçim yoksa
  /// (yardımlı modda) sunucunun bulduğu bitiren taş kullanılır.
  Future<void> _duzFinish() async {
    final options = (_state['duz_finish_tile_ids'] is List)
        ? (_state['duz_finish_tile_ids'] as List).map((e) => '$e').toList()
        : const <String>[];
    final tileId = _selectedTileId ?? (options.isNotEmpty ? options.first : null);
    if (tileId == null) {
      setState(() => _error = 'Bitirmek için ortaya atacağın taşı seç.');
      return;
    }
    final out = await _act('finish', {'tile_id': tileId});
    if (out != null && mounted) setState(() => _selectedTileId = null);
  }
  int get _viewerSeat => _integer(_state['viewer_seat']);
  bool get _myTurn => _integer(_state['current_seat']) == _viewerSeat;
  bool get _canMove =>
      _myTurn &&
      '${_state['phase']}' != 'finished' &&
      _state['started'] == true;
  bool get _assisted => _state['assisted'] != false;
  // Klasik Okey'de okey elle kapatılır; 101'de okey her zaman ters (kapalı) gelir.
  bool get _manualOkeyClose => _isDuz;

  int _rackBreakCount(int rowStart) {
    var count = 0;
    for (var col = 1; col < _rackCols; col++) {
      final id = _rackSlots[rowStart + col];
      if (id != null && _rackGroupStarts.contains(id)) count++;
    }
    return count;
  }

  List<List<String>> _rackVisualGroups({int minimum = 1}) {
    final groups = <List<String>>[];
    for (var row = 0; row < _rackRows; row++) {
      final start = row * _rackCols;
      var current = <String>[];
      void flush() {
        if (current.length >= minimum) groups.add(List<String>.from(current));
        current = <String>[];
      }
      for (var col = 0; col < _rackCols; col++) {
        final id = _rackSlots[start + col];
        if (id == null) {
          flush();
          continue;
        }
        if (current.isNotEmpty && _rackGroupStarts.contains(id)) flush();
        current.add(id);
      }
      flush();
    }
    return groups;
  }

  int? _scoreLocalMeld(List<Map<String, dynamic>> tiles) {
    if (tiles.length < 3) return null;
    final naturals = tiles.where((t) => t['joker'] != true).toList();
    if (naturals.isEmpty) return null;
    final jokers = tiles.length - naturals.length;

    // Aynı sayı / farklı renk per.
    final numbers = naturals.map((t) => _integer(t['n'])).toSet();
    final colors = naturals.map((t) => '${t['c']}').toList();
    if ((tiles.length == 3 || tiles.length == 4) &&
        numbers.length == 1 &&
        colors.toSet().length == colors.length) {
      return numbers.first * tiles.length;
    }

    // Aynı renk, 1..13 içinde sarmalanmayan seri. Okey eksikleri tamamlar.
    if (naturals.map((t) => '${t['c']}').toSet().length != 1) return null;
    final nums = naturals.map((t) => _integer(t['n'])).toList()..sort();
    if (nums.toSet().length != nums.length) return null;
    final length = tiles.length;
    var best = -1;
    for (var start = 1; start <= 14 - length; start++) {
      final seq = List<int>.generate(length, (i) => start + i);
      if (!nums.every(seq.contains)) continue;
      final missing = seq.where((n) => !nums.contains(n)).length;
      if (missing != jokers) continue;
      final score = seq.fold<int>(0, (a, b) => a + b);
      if (score > best) best = score;
    }
    return best >= 0 ? best : null;
  }

  int _bestOrderedMeldScore(
    List<String> ids,
    Map<String, Map<String, dynamic>> byId,
  ) {
    final memo = <int, int>{};
    int solve(int index) {
      if (index >= ids.length) return 0;
      final cached = memo[index];
      if (cached != null) return cached;
      var best = solve(index + 1);
      for (var end = index + 2; end < ids.length; end++) {
        final candidate = ids.sublist(index, end + 1);
        final tiles = candidate.map((value) => byId[value]).whereType<Map<String, dynamic>>().toList();
        if (tiles.length != candidate.length) continue;
        final score = _scoreLocalMeld(tiles);
        if (score == null) continue;
        final combined = score + solve(end + 1);
        if (combined > best) best = combined;
      }
      memo[index] = best;
      return best;
    }
    return solve(0);
  }

  int _localRackSeriesScore() {
    final byId = <String, Map<String, dynamic>>{for (final t in _serverHand) '${t['id']}': t};
    if (_assisted) {
      var total = 0;
      for (final raw in _list(_state['assisted_series_groups'])) {
        final ids = _list(raw).map((e) => '$e').toList();
        if (ids.length < 3) continue;
        final pos = ids.map(_rackSlots.indexOf).toList();
        if (pos.any((p) => p < 0)) continue;
        pos.sort();
        if ((pos.first ~/ _rackCols) != (pos.last ~/ _rackCols)) continue;
        var contiguous = true;
        for (var i = 1; i < pos.length; i++) {
          if (pos[i] != pos[i - 1] + 1) { contiguous = false; break; }
        }
        if (!contiguous) continue;
        final score = _scoreLocalMeld(ids.map((id) => byId[id]).whereType<Map<String, dynamic>>().toList());
        if (score != null) total += score;
      }
      return total;
    }

    // Yardımsızda sunucu çözücü ipucu vermez. Yalnız oyuncunun fiziksel olarak
    // yan yana/grup aralığıyla dizdiği perleri yerelde sayar.
    var total = 0;
    for (final ids in _rackVisualGroups(minimum: 3)) {
      total += _bestOrderedMeldScore(ids, byId);
    }
    return total;
  }

  int _localRackPairCount() {
    final byId = <String, Map<String, dynamic>>{for (final t in _serverHand) '${t['id']}': t};
    var pairs = 0;
    for (var row = 0; row < _rackRows; row++) {
      final start = row * _rackCols;
      var col = 0;
      while (col < _rackCols - 1) {
        final aId = _rackSlots[start + col];
        final bId = _rackSlots[start + col + 1];
        final a = aId == null ? null : byId[aId];
        final b = bId == null ? null : byId[bId];
        if (a != null && b != null) {
          final same = (a['joker'] == true || b['joker'] == true) ||
              (_integer(a['n']) == _integer(b['n']) && '${a['c']}' == '${b['c']}');
          if (same) { pairs++; col += 2; continue; }
        }
        col++;
      }
    }
    return pairs;
  }

  List<String> _rackGroupForTile(String id) {
    final slot = _rackSlots.indexOf(id);
    if (slot < 0) return const <String>[];
    final byId = <String, Map<String, dynamic>>{for (final t in _serverHand) '${t['id']}': t};
    final rowStart = (slot ~/ _rackCols) * _rackCols;
    final rowEnd = rowStart + _rackCols - 1;
    var left = slot;
    while (left > rowStart) {
      final currentId = _rackSlots[left];
      if (currentId != null && _rackGroupStarts.contains(currentId)) break;
      if (_rackSlots[left - 1] == null) break;
      left--;
    }
    var right = slot;
    while (right < rowEnd) {
      final nextId = _rackSlots[right + 1];
      if (nextId == null || _rackGroupStarts.contains(nextId)) break;
      right++;
    }
    final ids = <String>[];
    for (var i = left; i <= right; i++) {
      final value = _rackSlots[i];
      if (value != null) ids.add(value);
    }
    final wholeTiles = ids.map((value) => byId[value]).whereType<Map<String, dynamic>>().toList();
    if (wholeTiles.length == ids.length && _scoreLocalMeld(wholeTiles) != null) return ids;

    // Çevresinde tek taşlar olsa bile basılan taşın içinde bulunduğu geçerli
    // per/seriyi bul. Böylece oyuncu boşluk bırakmayı unutsa da tüm satır değil,
    // yalnız gerçek per taşınır.
    final pressed = slot - left;
    List<String> best = const <String>[];
    var bestScore = -1;
    for (var a = 0; a <= pressed; a++) {
      for (var b = pressed; b < ids.length; b++) {
        final length = b - a + 1;
        if (length < 3) continue;
        final candidate = ids.sublist(a, b + 1);
        final tiles = candidate.map((value) => byId[value]).whereType<Map<String, dynamic>>().toList();
        if (tiles.length != candidate.length) continue;
        final score = _scoreLocalMeld(tiles);
        if (score == null) continue;
        if (candidate.length > best.length || (candidate.length == best.length && score > bestScore)) {
          best = candidate;
          bestScore = score;
        }
      }
    }
    return best.isNotEmpty ? best : <String>[id];
  }

  void _moveRackGroupToSlot(List<String> ids, int targetSlot) {
    if (!_canArrangeRack || ids.length < 2 || targetSlot < 0 || targetSlot >= _rackSlotCount) return;
    final positions = ids.map(_rackSlots.indexOf).toList();
    if (positions.any((p) => p < 0)) return;
    positions.sort();
    final sourceRow = positions.first ~/ _rackCols;
    if (positions.any((p) => p ~/ _rackCols != sourceRow)) return;
    for (var i = 1; i < positions.length; i++) {
      if (positions[i] != positions[i - 1] + 1) return;
    }

    final length = ids.length;
    final sourceStartCol = positions.first % _rackCols;
    final targetRow = targetSlot ~/ _rackCols;
    var targetCol = (targetSlot % _rackCols).clamp(0, _rackCols - length).toInt();
    if (targetRow == sourceRow &&
        targetCol >= sourceStartCol &&
        targetCol < sourceStartCol + length) {
      return;
    }

    setState(() {
      final rows = List<List<String?>>.generate(
        _rackRows,
        (r) => List<String?>.from(_rackSlots.sublist(r * _rackCols, (r + 1) * _rackCols)),
      );
      final source = rows[sourceRow];
      source.removeRange(sourceStartCol, sourceStartCol + length);
      source.addAll(List<String?>.filled(length, null));

      if (targetRow == sourceRow) {
        if (targetCol > sourceStartCol) targetCol = (targetCol - length).clamp(0, _rackCols - length).toInt();
        source.insertAll(targetCol, ids);
        source.removeRange(_rackCols, _rackCols + length);
      } else {
        final target = rows[targetRow];
        var removable = length;
        for (var i = target.length - 1; i >= 0 && removable > 0; i--) {
          if (target[i] == null) {
            target.removeAt(i);
            if (i < targetCol) targetCol--;
            removable--;
          }
        }
        if (removable > 0) return;
        targetCol = targetCol.clamp(0, target.length).toInt();
        target.insertAll(targetCol, ids);
      }

      for (var r = 0; r < _rackRows; r++) {
        for (var c = 0; c < _rackCols; c++) {
          _rackSlots[r * _rackCols + c] = rows[r][c];
        }
      }
      _rackManuallyEdited = true;
      _rackGroupStarts.removeWhere(ids.contains);
      final newFirst = _rackSlots.indexOf(ids.first);
      if (newFirst >= 0 && newFirst % _rackCols > 0 && _rackSlots[newFirst - 1] != null) {
        _rackGroupStarts.add(ids.first);
      }
      final after = newFirst + length;
      if (newFirst >= 0 && after < _rackSlotCount && after ~/ _rackCols == newFirst ~/ _rackCols) {
        final afterId = _rackSlots[after];
        if (afterId != null) _rackGroupStarts.add(afterId);
      }
    });
    unawaited(GameAudio.sfx('rack_slide', enabled: _soundEnabled, volume: .76));
    if (_vibrationEnabled) unawaited(HapticFeedback.mediumImpact());
  }

  int _relativeSeat(int offset) => (_viewerSeat + offset) % 4;

  int _secondsLeftAt(int nowMs) {
    final deadline = _integer(_state['turn_deadline_ms']);
    if (deadline <= 0) return 0;
    return ((deadline - nowMs) / 1000).ceil().clamp(0, 999).toInt();
  }

  bool get _introActive =>
      _integer(_state['intro_until_ms']) > DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> _playerAtSeat(int seat) => _list(_state['players'])
      .map(_map)
      .firstWhere((p) => _integer(p['seat']) == seat, orElse: () => const <String, dynamic>{});

  Widget _introOverlay() => Material(
        color: const Color(0xFF020A12),
        child: Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -.1),
              radius: 1.15,
              colors: [Color(0xFF0D684B), Color(0xFF084431), Color(0xFF031D17)],
            ),
          ),
          child: ValueListenableBuilder<int>(
            valueListenable: _nowMsNotifier,
            builder: (context, now, _) {
              final until = _integer(_state['intro_until_ms']);
              final left = ((until - now) / 1000).ceil().clamp(1, 5).toInt();
              final players = _list(_state['players']).map(_map).toList()
                ..sort((a, b) => _integer(a['seat']).compareTo(_integer(b['seat'])));
              Map<String, dynamic> at(int seat) => players.firstWhere((x) => _integer(x['seat']) == seat, orElse: () => const <String, dynamic>{});
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1120, maxHeight: 520),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    padding: const EdgeInsets.fromLTRB(18, 13, 18, 12),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xF20C3328), Color(0xF208211B)]),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: OkeyXColors.gold.withValues(alpha: .72), width: 1.4),
                      boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 32, offset: Offset(0, 14)), BoxShadow(color: Color(0x33F4C542), blurRadius: 24)],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 6,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Container(
                                width: 430,
                                height: 232,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(90),
                                  gradient: const RadialGradient(colors: [Color(0xFF25A77A), Color(0xFF11734F), Color(0xFF084631)]),
                                  border: Border.all(color: const Color(0xFFB88A42), width: 5),
                                  boxShadow: const [BoxShadow(color: Color(0x5500D8C0), blurRadius: 30), BoxShadow(color: Color(0x77000000), blurRadius: 16, offset: Offset(0, 8))],
                                ),
                                child: Center(
                                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                                    const Text('OKEYX', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white54, letterSpacing: 2)),
                                    const SizedBox(height: 2),
                                    Text('$left', style: const TextStyle(fontSize: 66, height: .9, fontWeight: FontWeight.w900, color: Colors.white)),
                                    const SizedBox(height: 3),
                                    const Text('TAŞLAR HAZIRLANIYOR', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: OkeyXColors.gold, letterSpacing: .9)),
                                  ]),
                                ),
                              ),
                              Positioned(top: 0, child: _introSeatChip(at((_viewerSeat + 2) % 4), relation: 'RAKİP')),
                              Positioned(bottom: 0, child: _introSeatChip(at(_viewerSeat), relation: 'SEN')),
                              Positioned(left: 0, child: _introSeatChip(at((_viewerSeat + 3) % 4), relation: 'RAKİP')),
                              Positioned(right: 0, child: _introSeatChip(at((_viewerSeat + 1) % 4), relation: 'RAKİP')),
                            ],
                          ),
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          flex: 4,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4), decoration: BoxDecoration(color: OkeyXColors.gold.withValues(alpha: .12), borderRadius: BorderRadius.circular(10), border: Border.all(color: OkeyXColors.gold.withValues(alpha: .35))), child: Text(_state['turbo'] == true ? '★ TURBO' : (_isDuz ? 'KLASİK OKEY' : '101 OKEY'), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: OkeyXColors.gold, letterSpacing: .7))),
                                const SizedBox(width: 5),
                                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.white.withValues(alpha: .05), borderRadius: BorderRadius.circular(10)), child: Text('${_compactMoney(_integer(_state['entry_fee']))} ALTIN', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.white70))),
                              ]),
                              const SizedBox(height: 10),
                              const Text('OYUN\nBAŞLIYOR', style: TextStyle(fontSize: 38, height: .91, fontWeight: FontWeight.w900, letterSpacing: .7)),
                              const SizedBox(height: 10),
                              const Text('Hazır ol. Taşlar dağıtılıyor…', style: TextStyle(fontSize: 9, color: Colors.white60, fontWeight: FontWeight.w800)),
                              const SizedBox(height: 12),
                              Row(children: [
                                const Icon(Icons.shuffle_rounded, size: 13, color: OkeyXColors.mint),
                                const SizedBox(width: 5),
                                Text(left <= 2 ? 'MASA AÇILIYOR' : 'TAŞLAR KARIŞIYOR', style: const TextStyle(fontSize: 9, color: Colors.white54, fontWeight: FontWeight.w900, letterSpacing: .5)),
                              ]),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );

  Widget _introSeatChip(Map<String, dynamic> player, {required String relation}) {
    final name = '${player['name'] ?? 'Oyuncu'}';
    final initial = name.isEmpty ? 'O' : name.substring(0, 1).toUpperCase();
    final mine = relation == 'SEN';
    final spawn='${_map(player['loadout'])['spawn_fx'] ?? 'spawn_classic'}';
    final spawnColor=spawn=='spawn_fire'?const Color(0xFFFF7A3D):spawn=='spawn_lightning'?const Color(0xFF66E8FF):spawn=='spawn_royal'?OkeyXColors.gold:Colors.transparent;
    return Container(
      width: 92,
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xEE110B30),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: spawnColor!=Colors.transparent?spawnColor:(mine ? OkeyXColors.mint : Colors.white24), width: spawnColor!=Colors.transparent?2:mine?1.5:1),
        boxShadow: [const BoxShadow(color: Color(0x66000000), blurRadius: 10, offset: Offset(0, 5)),if(spawnColor!=Colors.transparent)BoxShadow(color:spawnColor.withValues(alpha:.38),blurRadius:16)],
      ),
      child: Row(children: [
        Stack(clipBehavior:Clip.none,children:[CircleAvatar(radius: 12, backgroundColor: mine ? const Color(0xFF55517C) : const Color(0xFF291B6E), child: Text(initial, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900))),if(spawnColor!=Colors.transparent)Positioned(right:-5,top:-6,child:Icon(spawn=='spawn_fire'?Icons.local_fire_department_rounded:spawn=='spawn_lightning'?Icons.bolt_rounded:Icons.workspace_premium_rounded,size:11,color:spawnColor))]),
        const SizedBox(width: 5),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900)),
          Text(mine ? 'SEN' : (player['bot'] == true ? 'BOT' : 'OYUNCU'), style: TextStyle(fontSize: 9, color: mine ? OkeyXColors.mint : Colors.white38, fontWeight: FontWeight.w900)),
        ])),
      ]),
    );
  }

  Widget _introPlayerChip(Map<String, dynamic> player, {required String relation}) {
    final name = '${player['name'] ?? 'Oyuncu'}';
    final initial = name.isEmpty ? 'O' : name.substring(0, 1).toUpperCase();
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: .045), borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.white12)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircleAvatar(radius: 14, backgroundColor: const Color(0xFF301F83), child: Text(initial, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900))),
          const SizedBox(height: 3),
          FittedBox(child: Text(name, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900))),
          Text(relation, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: relation == 'SEN' || relation == 'EŞİN' ? OkeyXColors.mint : Colors.white54)),
        ]),
      ),
    );
  }

  Future<void> _leaveDuringIntro() async {
    try {
      await _api.leave();
    } catch (_) {}
    await _closeTable();
  }

  Widget _afkOverlay() => Material(
        color: const Color(0xB0000710),
        child: InkWell(
          onTap: () async {
            await _act('return_to_game');
            _tableNotice('Kontrol tekrar sende.');
          },
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: const Color(0xF2191046),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: OkeyXColors.gold),
              ),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.smart_toy_rounded, color: OkeyXColors.gold, size: 38),
                  SizedBox(height: 8),
                  Text('BOT SENİN YERİNE OYNUYOR', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                  SizedBox(height: 4),
                  Text('Bot yalnızca çekip taş atar. Açma/işleme yapmaz.', style: TextStyle(fontSize: 9, color: Colors.white60)),
                  SizedBox(height: 8),
                  Text('OYUNA DÖNMEK İÇİN DOKUN', style: TextStyle(fontSize: 10, color: OkeyXColors.mint, fontWeight: FontWeight.w900)),
                ],
              ),
            ),
          ),
        ),
      );

  void _syncRackSlots(
    List<Map<String, dynamic>> hand,
    List<String> serverIds,
  ) {
    final handKey =
        '${_state['room_id']}:${_integer(_state['round_index'])}:$_viewerSeat';
    final serverSet = serverIds.toSet();
    final newHand = _rackHandKey != handKey;
    _revealedJokerIds.retainAll(serverSet);

    if (newHand) {
      _rackHandKey = handKey;
      _rackGroupStarts.clear();
      _rackManuallyEdited = false;
      for (var i = 0; i < _rackSlotCount; i++) {
        _rackSlots[i] = i < serverIds.length ? serverIds[i] : null;
      }
    } else {
      // Sunucudan çıkan taş sadece bulunduğu fiziksel yuvadan silinir.
      // Kullanıcının bıraktığı boşluklar ve per araları asla sıkıştırılmaz.
      for (var i = 0; i < _rackSlotCount; i++) {
        final id = _rackSlots[i];
        if (id != null && !serverSet.contains(id)) {
          _rackSlots[i] = null;
        }
      }

      // Yeni çekilen taş per aralarındaki ilk boşluğa sokulmaz.
      // Yeni taş ıstakanın sağ-alt tarafındaki boş yuvaya gelir.
      _rackGroupStarts.retainAll(serverSet);

      final present = _rackSlots.whereType<String>().toSet();
      for (final id in serverIds) {
        if (present.contains(id)) continue;
        final empty = _defaultIncomingRackSlot();
        if (empty >= 0) {
          _rackSlots[empty] = id;
          present.add(id);
        }
      }
    }

    // El dağıtılınca taşlar kendiliğinden en yüksek puanlı seri dizilimine
    // girer; oyuncu sonra istediği taşı istediği yere sürükleyebilir.
    if (newHand && hand.isNotEmpty && !_isDuz) {
      _applyRackArrangement(_seriesArrangementForRack(hand));
    }
  }

  void _applyRackArrangement((List<String>, Set<String>, int) result) {
    _rackManuallyEdited = false;
    for (var i = 0; i < _rackSlotCount; i++) {
      _rackSlots[i] = null;
    }

    final order = result.$1;
    if (order.isEmpty) {
      _rackGroupStarts.clear();
      return;
    }

    // 101 Plus hissi: perler arasında tam bir "boş taş yuvası" bırakmıyoruz.
    // Taşlar fiziksel yuvalarda ardışık kalıyor; grup başlangıçları ayrı
    // metadata olarak saklanıyor ve renderer yalnızca küçük bir görsel aralık
    // ekliyor. Bu sayede SERİ/ÇİFT DİZ sonrası çekilen taş perleri birleştirmez
    // ama aralar da bir taş genişliği kadar açılmaz.
    _rackGroupStarts
      ..clear()
      ..addAll(result.$2);

    final firstRowCount = result.$3.clamp(1, _rackCols).toInt();
    var topCol = 0;
    var bottomCol = 0;
    for (var i = 0; i < order.length && i < _rackSlotCount; i++) {
      if (i < firstRowCount && topCol < _rackCols) {
        _rackSlots[topCol++] = order[i];
      } else if (bottomCol < _rackCols) {
        _rackSlots[_rackCols + bottomCol++] = order[i];
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) unawaited(_requestLeaveTable());
        },
        child: Scaffold(
          backgroundColor: OkeyXColors.ink,
          body: SafeArea(
            child: Stack(
              children: [
                Positioned.fill(child: TableFxLayer(controller: _fx, child: _gameSurface())),
                if (!_loading && _state['started'] != true && '${_state['phase']}' == 'waiting')
                  Positioned.fill(child: _waitingRoomOverlay()),
                if (_loading) Positioned.fill(child: _loadingPanel()),
                if (_error.isNotEmpty && !_loading && !_error.contains('Masa artık mevcut değil'))
                  Positioned(
                    left:0,right:0,top:58,
                    child:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:560),child:_errorBanner())),
                  ),
                if (_error.contains('Masa artık mevcut değil'))
                  Positioned.fill(child: _roomClosedDialog()),
                if (_eventText.isNotEmpty && _eventType != 'opened' && _eventType != 'one_tile')
                  Positioned(
                    top: 58,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(child: Center(child: _eventBanner())),
                  ),
                if (_openingSplashKey != null)
                  Positioned.fill(child: _openingSplash()),
                if (_drawRevealTile != null)
                  Positioned.fill(child: _drawRevealOverlay()),
                if (_introActive)
                  Positioned.fill(child: _introOverlay()),
                if (_state['viewer_afk_bot'] == true)
                  Positioned.fill(child: _afkOverlay()),
                if (_giftKind.isNotEmpty)
                  Positioned.fill(
                    child: IgnorePointer(child: _giftOverlay()),
                  ),
                if (_bigGift != null)
                  Positioned.fill(child: _bigGiftOverlay()),
                if (_canakBreak != null)
                  Positioned.fill(child: IgnorePointer(child: _canakBreakOverlay())),
                if (_voiceInvite != null && !_voiceEnabled)
                  Positioned(
                    top: 56,
                    left: 0,
                    right: 0,
                    child: Center(child: GestureDetector(
                      onTap: () async {
                        final roomId = '${_state['room_id'] ?? _api.roomId ?? ''}'.trim();
                        setState(() => _voiceInvite = null);
                        try {
                          await _ensureVoice(roomId).join(_voicePeerIds());
                          if (mounted) setState(() => _voiceEnabled = true);
                          _tableNotice('Masayı dinliyorsun. Konuşmak için mikrofona dokun ya da basılı tut.');
                        } catch (_) {}
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFF1B3A2C), Color(0xFF0F241B)]),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(color: OkeyXColors.mint.withValues(alpha: .7)),
                          boxShadow: const [BoxShadow(color: Color(0x88000000), blurRadius: 12)],
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.headset_mic_rounded, size: 16, color: OkeyXColors.mint),
                          const SizedBox(width: 8),
                          Text('$_voiceInvite mikrofonu açtı • DİNLE', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: OkeyXColors.cream)),
                        ]),
                      ),
                    )),
                  ),

                if (_showTurnCue && _state['started'] == true && !_introActive && !const {'waiting','finished'}.contains('${_state['phase']}'))
                  Positioned.fill(child: IgnorePointer(child: _turnCueOverlay())),
                if ('${_state['phase']}' == 'finished' &&
                    _shownRoundKey != null)
                  Positioned.fill(child: _finishCelebration()),
                if (_busy)
                  const Positioned(
                    top: 4,
                    left: 4,
                    child: SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: OkeyXColors.gold),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );

  String _tileSkinForSeat(int seat){for(final raw in _list(_state['players'])){final p=_map(raw);if(_integer(p['seat'])==seat){final v='${_map(p['loadout'])['tiles']??'tiles_ivory'}';return v.isEmpty?'tiles_ivory':v;}}return 'tiles_ivory';}
  String get _viewerTileSkin=>_tileSkinForSeat(_viewerSeat);

  Future<void> _sendCoinsAtTable(String targetId, String name) async {
    if (_busy || targetId.isEmpty || targetId == widget.profile.userId) return;
    final wallet = _integer(_state['viewer_chips'], fallback: widget.profile.coins);
    var chosen = 100000;
    final amount = await showDialog<int>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocal) => AlertDialog(
          title: Row(children: [
            const Icon(Icons.paid_rounded, color: OkeyXColors.gold),
            const SizedBox(width: 7),
            Expanded(child: Text('$name • Altın Gönder', maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Bakiyen ${_compactMoney(wallet)} • sadece arkadaşlara gönderilir.', style: const TextStyle(fontSize: 9, color: Colors.white54)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final q in const [10000, 50000, 100000, 500000, 1000000, 2000000])
                    ChoiceChip(
                      selected: chosen == q,
                      onSelected: q <= wallet ? (_) => setLocal(() => chosen = q) : null,
                      label: Text(_compactMoney(q), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900)),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text('Gönderilecek: ${_compactMoney(chosen)} altın', style: const TextStyle(fontSize: 9, color: OkeyXColors.gold, fontWeight: FontWeight.w900)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('VAZGEÇ')),
            FilledButton.icon(
              onPressed: chosen > 0 && chosen <= wallet ? () => Navigator.pop(dialogContext, chosen) : null,
              icon: const Icon(Icons.send_rounded, size: 15),
              label: const Text('GÖNDER'),
            ),
          ],
        ),
      ),
    );
    if (amount == null || amount <= 0 || !mounted) return;
    setState(() => _busy = true);
    try {
      final out = await _api.transferCoins(targetId, amount);
      if (!mounted) return;
      if (out['ok'] == true) {
        final next = _integer(out['sender_chips'], fallback: wallet - amount);
        setState(() => _state = {..._state, 'viewer_chips': next});
        if (_vibrationEnabled) unawaited(HapticFeedback.mediumImpact());
        unawaited(GameAudio.sfx('reward', enabled: _soundEnabled, volume: .56));
        _tableNotice('$name kullanıcısına ${_compactMoney(amount)} altın gönderildi.');
      } else {
        final code = '${out['code'] ?? 'transfer_failed'}';
        _tableNotice(switch (code) {
          'friends_only' => 'Altın göndermek için önce arkadaş olmalısınız.',
          'insufficient_balance' => 'Bakiyen yetersiz.',
          'transfer_daily_limit' => 'Bugünkü arkadaş transfer hakkın doldu.',
          'transfer_too_large' => 'Tek seferde en fazla 2M gönderebilirsin.',
          _ => 'Altın gönderilemedi • $code',
        });
      }
    } catch (error) {
      if (mounted) _tableNotice(_friendlyCode('$error'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _titleLabel(String id) => switch (id) {
        'title_okey_hunter' => 'Okey Avcısı',
        'title_pair_master' => 'Çift Ustası',
        'title_series_master' => 'Seri Ustası',
        'title_night_owl' => 'Gece Kuşu',
        'title_table_legend' => 'Masa Efsanesi',
        'title_comeback' => 'Geri Dönüş Ustası',
        'title_veteran' => '101 Veteranı',
        'title_lucky' => 'Şanslı Taş',
        'title_bosphorus' => 'Boğazın Kralı',
        _ => 'OkeyX Oyuncusu',
      };

  Future<void> _sendGiftFromCard(BuildContext dialogContext,String gift,int seat) async {
    Navigator.pop(dialogContext);
    await _sendChat('gift',gift,toSeat:seat);
  }

  Future<void> _addTableFriend(String targetId,String name) async {
    try{
      final out=await _api.friendRequest(targetId);
      if(!mounted)return;
      final code='${out['code'] ?? ''}';
      _tableNotice(out['ok']==true?(code=='accepted'?'$name artık arkadaşın.':code=='already_pending'?'$name için istek zaten bekliyor.':'$name için arkadaşlık isteği gönderildi.'):_friendlyCode(code));
    }catch(error){if(mounted)setState(()=>_error=_friendlyCode('$error'));}
  }

  Future<void> _showPlayerProfile(Map<String, dynamic> player) async {
    if (!mounted || player.isEmpty) return;
    final name = '${player['name'] ?? 'Oyuncu'}';
    final stats = _map(player['public_stats']);
    final loadout=_map(player['loadout']);
    final frame='${player['profile_frame'] ?? loadout['frame'] ?? ''}';
    final accent=_cosmeticAccent(frame,_integer(player['vip_level']));
    final games = _integer(stats['games']);
    final wins = _integer(stats['wins']);
    final losses = _integer(stats['losses']);
    final streak = _integer(stats['best_streak']);
    final rate = games > 0 ? ((wins * 100) / games).round() : 0;
    final chips = _integer(player['chips']);
    final targetId='${player['player_id'] ?? ''}';
    final title=_titleLabel('${loadout['title'] ?? ''}');
    final music=_musicKitLabel('${loadout['music_kit'] ?? ''}');
    await showDialog<void>(
      context: context,
      barrierColor:const Color(0xCC00070C),
      builder: (dialogContext) {
        final size=MediaQuery.sizeOf(dialogContext);
        return Dialog(
          backgroundColor:Colors.transparent,
          insetPadding:const EdgeInsets.all(18),
          child:ConstrainedBox(
            constraints:BoxConstraints(maxWidth:560,maxHeight:size.height*.90),
            child:Container(
              decoration:BoxDecoration(gradient:const LinearGradient(begin:Alignment.topLeft,end:Alignment.bottomRight,colors:[Color(0xFF1A1049),Color(0xFF100B2D),Color(0xFF0B0721)]),borderRadius:BorderRadius.circular(24),border:Border.all(color:accent.withValues(alpha:.42)),boxShadow:[BoxShadow(color:accent.withValues(alpha:.16),blurRadius:34),const BoxShadow(color:Colors.black54,blurRadius:28,offset:Offset(0,12))]),
              child:SingleChildScrollView(
                padding:const EdgeInsets.all(16),
                child:Column(mainAxisSize:MainAxisSize.min,children:[
                  Row(children:[
                    Container(padding:const EdgeInsets.all(2.5),decoration:BoxDecoration(shape:BoxShape.circle,border:Border.all(color:accent,width:2.4),boxShadow:[BoxShadow(color:accent.withValues(alpha:.32),blurRadius:14)]),child:_playerAvatar(player,radius:27)),
                    const SizedBox(width:11),
                    Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                      Row(children:[Flexible(child:Text(name,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:17,fontWeight:FontWeight.w900))),if(_integer(player['vip_level'])>0)...[const SizedBox(width:6),_miniProfileBadge('VIP ${_integer(player['vip_level'])}',OkeyXColors.gold)]]),
                      Text('$title • LV ${_integer(player['level'])}',style:TextStyle(fontSize:9,color:accent,fontWeight:FontWeight.w800)),
                      Text('${stats['tier'] ?? 'Başlangıç'} • ${stats['city'] ?? 'Konum gizli'}',style:TextStyle(fontSize:9,color:Colors.white.withValues(alpha:.45))),
                    ])),
                    IconButton(onPressed:()=>Navigator.pop(dialogContext),icon:const Icon(Icons.close_rounded)),
                  ]),
                  const SizedBox(height:11),
                  Row(children:[
                    Expanded(child:_loadoutShowcase(Icons.library_music_rounded,'MÜZİK KİTİ',music,const Color(0xFFA788FF))),const SizedBox(width:6),
                    Expanded(child:_loadoutShowcase(Icons.grid_view_rounded,'TAŞ SETİ',_cosmeticShortLabel('${loadout['tiles'] ?? 'tiles_classic'}'),const Color(0xFF73D9FF))),const SizedBox(width:6),
                    Expanded(child:_loadoutShowcase(Icons.table_bar_rounded,'ISTAKA',_cosmeticShortLabel('${loadout['rack'] ?? 'rack_classic'}'),OkeyXColors.gold)),
                  ]),
                  const SizedBox(height:9),
                  Row(children:[Expanded(child:_profileStatCard('OYUN','$games',Icons.sports_esports_rounded)),const SizedBox(width:7),Expanded(child:_profileStatCard('GALİBİYET','$wins',Icons.emoji_events_rounded)),const SizedBox(width:7),Expanded(child:_profileStatCard('ORAN','%$rate',Icons.query_stats_rounded))]),
                  const SizedBox(height:7),
                  Row(children:[Expanded(child:_profileStatCard('MAĞLUBİYET','$losses',Icons.trending_down_rounded)),const SizedBox(width:7),Expanded(child:_profileStatCard('EN İYİ SERİ','$streak',Icons.local_fire_department_rounded)),const SizedBox(width:7),Expanded(child:_profileStatCard('ALTIN',_compactMoney(chips),Icons.monetization_on_rounded))]),
                  if (_list(player['gifts_received']).isNotEmpty) ...[
                    const SizedBox(height:10),
                    const Align(alignment:Alignment.centerLeft,child:Text('HEDİYE KOLEKSİYONU',style:TextStyle(fontSize:9,color:OkeyXColors.gold,fontWeight:FontWeight.w900))),
                    const SizedBox(height:5),
                    SizedBox(height:40,child:ListView(scrollDirection:Axis.horizontal,children:[for(final raw in _list(player['gifts_received']).take(10)) Padding(padding:const EdgeInsets.only(right:6),child:Tooltip(message:'${_map(raw)['name'] ?? 'Hediye'}',child:Container(width:38,alignment:Alignment.center,decoration:BoxDecoration(color:Colors.white10,borderRadius:BorderRadius.circular(10)),child:_GiftArt(kind:'${_map(raw)['name'] ?? 'Hediye'}',size:27))))])),
                  ],
                  const SizedBox(height:10),
                  Row(children:[
                    if(targetId.isNotEmpty) Expanded(child:FilledButton.tonalIcon(onPressed:(){Navigator.pop(dialogContext);unawaited(_addTableFriend(targetId,name));},icon:const Icon(Icons.person_add_alt_1_rounded,size:15),label:const Text('ARKADAŞ EKLE',style:TextStyle(fontSize:9,fontWeight:FontWeight.w900)))),
                    if(targetId.isNotEmpty) const SizedBox(width:7),
                    Expanded(child:OutlinedButton.icon(onPressed:(){Navigator.pop(dialogContext);unawaited(_sendChat('gift','coffee',toSeat:_integer(player['seat'])));},icon:const Icon(Icons.local_cafe_rounded,size:15),label:const Text('HEDİYE GÖNDER',style:TextStyle(fontSize:9,fontWeight:FontWeight.w900)))),
                  ]),
                  if(targetId.isNotEmpty) ...[
                    const SizedBox(height:7),
                    SizedBox(width:double.infinity,child:OutlinedButton.icon(
                      onPressed:(){Navigator.pop(dialogContext);unawaited(_sendCoinsAtTable(targetId,name));},
                      icon:const Icon(Icons.paid_rounded,size:15,color:OkeyXColors.gold),
                      label:const Text('ARKADAŞA ALTIN GÖNDER',style:TextStyle(fontSize:9,fontWeight:FontWeight.w900,color:OkeyXColors.gold)),
                    )),
                  ],
                ]),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _miniProfileBadge(String text,Color color)=>Container(padding:const EdgeInsets.symmetric(horizontal:6,vertical:2),decoration:BoxDecoration(color:color.withValues(alpha:.10),borderRadius:BorderRadius.circular(7),border:Border.all(color:color.withValues(alpha:.35))),child:Text(text,style:TextStyle(fontSize:9,color:color,fontWeight:FontWeight.w900)));
  Widget _loadoutShowcase(IconData icon,String label,String value,Color color)=>Container(padding:const EdgeInsets.symmetric(horizontal:8,vertical:8),decoration:BoxDecoration(color:color.withValues(alpha:.06),borderRadius:BorderRadius.circular(12),border:Border.all(color:color.withValues(alpha:.18))),child:Row(children:[Icon(icon,size:16,color:color),const SizedBox(width:6),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(label,style:const TextStyle(fontSize:9,color:Colors.white38,fontWeight:FontWeight.w900)),Text(value,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:9,fontWeight:FontWeight.w900))]))]));
  String _musicKitLabel(String id)=>switch(id){'music_kit_istanbul'=>'Gece İstanbul','music_kit_anadolu'=>'Anadolu Synth','music_kit_retro'=>'Retro Okey','music_kit_tokyo'=>'Tokyo Night','music_kit_ege'=>'Ege Akşamı','music_kit_bosphorus'=>'Boğaz Neon','music_kit_arcade'=>'Arcade 101','music_kit_sakura'=>'Sakura Beat','music_kit_finalboss'=>'Final Boss',_=>'OkeyX Klasik'};
  String _cosmeticShortLabel(String id)=>id.replaceFirst(RegExp(r'^(rack|tiles|cloth|frame)_'),'').replaceAll('_',' ').toUpperCase();

  Widget _profileStatCard(String title, String value, IconData icon) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: .045), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white10)),
        child: Column(children: [
          Icon(icon, size: 15, color: OkeyXColors.cyan),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
          Text(title, style: const TextStyle(fontSize: 9, color: Colors.white38, fontWeight: FontWeight.w800)),
        ]),
      );

  void _tableNotice(String text) {
    if (!mounted) return;
    final sequence = ++_seenEventSequence;
    setState(() {
      _eventText = text;
      _eventType = 'info';
    });
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (mounted && _seenEventSequence == sequence) {
        setState(() {
          _eventText = '';
          _eventType = '';
        });
      }
    });
  }

  Future<void> _setTableSafety(String targetId, String action) async {
    try {
      if (action == 'mute') {
        await _api.setMute(targetId, true);
        _tableNotice('Oyuncu susturuldu.');
      } else {
        await _api.setBlock(targetId, true);
        _tableNotice('Oyuncu engellendi.');
      }
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyCode('$error'));
    }
  }

  Future<void> _reportTablePlayer(String targetId) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Şikâyet nedeni'),
        children: [
          for (final reason in const ['Hakaret / taciz', 'Spam', 'Hile şüphesi', 'Uygunsuz isim', 'Diğer'])
            SimpleDialogOption(onPressed: () => Navigator.pop(dialogContext, reason), child: Text(reason)),
        ],
      ),
    );
    if (reason == null) return;
    try {
      await _api.reportPlayer(targetId, reason);
      _tableNotice('Şikâyet gönderildi.');
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyCode('$error'));
    }
  }

  Widget _rackSlotRow(
    int rowStart,
    Map<String, Map<String, dynamic>> byId,
    bool compact,
  ) =>
      LayoutBuilder(
        builder: (context, constraints) {
          final screen = MediaQuery.sizeOf(context);
          final narrow = screen.width <= 900 || screen.height <= 520;
          final groupGap = compact ? 7.0 : 10.0;
          final canonicalBreakCount = math.max(_rackBreakCount(0), _rackBreakCount(_rackCols));

          // 101 Plus tipi fiziksel ıstaka: yan yana yuvalar ekranın tamamına
          // yayılmaz. Taş yüksekliğinden türetilen kompakt yuvalar soldan
          // başlar; böylece komşu taşlar arasında sadece ince bir çizgi kalır.
          var tileHeight = constraints.maxHeight
              .clamp(20.0, narrow ? 69.0 : 80.0)
              .toDouble();
          var tileWidth = (tileHeight * .68)
              .clamp(narrow ? 24.0 : 30.0, narrow ? 51.0 : 55.0)
              .toDouble();
          var slotStep = tileWidth + (compact ? .35 : .55);
          var contentWidth = (_rackCols * slotStep) + (canonicalBreakCount * groupGap);
          final rackInset = compact ? 8.0 : 12.0;
          if (contentWidth > constraints.maxWidth - rackInset) {
            final factor = (constraints.maxWidth - rackInset) / contentWidth;
            tileWidth *= factor;
            tileHeight *= factor;
            slotStep = tileWidth + (compact ? .25 : .4);
            contentWidth = (_rackCols * slotStep) + (canonicalBreakCount * groupGap);
          }
          // Physical rack slots never recenter as tiles leave the hand. The
          // player's spatial memory stays intact: five remaining tiles do not
          // suddenly float in the middle of a metre-wide rack.
          final startX = (compact ? 3.0 : 5.0);

          var gapsBefore = 0;
          final lefts = List<double>.filled(_rackCols, 0);
          for (var col = 0; col < _rackCols; col++) {
            if (col > 0) {
              final id = _rackSlots[rowStart + col];
              if (id != null && _rackGroupStarts.contains(id)) gapsBefore++;
            }
            lefts[col] = startX + col * slotStep + gapsBefore * groupGap;
          }

          return SizedBox(
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (var col = 0; col < _rackCols; col++)
                  Positioned(
                    left: lefts[col],
                    top: 0,
                    width: slotStep,
                    height: constraints.maxHeight,
                    child: _rackSlotTarget(
                      rowStart + col,
                      byId[_rackSlots[rowStart + col]],
                      tileWidth,
                      constraints.maxHeight,
                      tileHeight,
                    ),
                  ),
              ],
            ),
          );
        },
      );

  Widget _rackSlotTarget(
    int slot,
    Map<String, dynamic>? json,
    double tileWidth,
    double rowHeight,
    double tileHeight,
  ) {
    final id = json == null ? null : '${json['id']}';
    final hover = _rackHoverSlot == slot && _draggingRackId != null;
    return DragTarget<String>(
      key: _rackSlotKeys[slot],
      hitTestBehavior: HitTestBehavior.opaque,
      onWillAcceptWithDetails: (details) => details.data != id,
      onMove: (details) {
        if (details.data == id) return;
        final after = _dropIsAfter(slot, details.offset);
        if (_rackHoverSlot == slot && _rackHoverInsertAfter == after) return;
        setState(() {
          _rackHoverSlot = slot;
          _rackHoverInsertAfter = after;
        });
      },
      onLeave: (_) {
        if (_rackHoverSlot != slot || !mounted) return;
        setState(() => _rackHoverSlot = -1);
      },
      onAcceptWithDetails: (details) {
        final data = details.data;
        final after = _dropIsAfter(slot, details.offset);
        if (data == '__stock__') {
          unawaited(_drawStockIntoSlot(slot, insertAfter: after));
        } else if (data == '__left__') {
          unawaited(_takeLeftIntoSlot(slot, insertAfter: after));
        } else {
          _moveRackTileToSlot(data, slot, insertAfter: after);
        }
        if (mounted) setState(() { _rackHoverSlot = -1; _rackHoverInsertAfter = false; });
      },
      builder: (context, candidates, rejected) {
        final active = candidates.isNotEmpty || hover;
        final shift = active && json != null && id != _draggingRackId
            ? Offset(_rackHoverInsertAfter ? -.10 : .10, 0)
            : Offset.zero;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 85),
          curve: Curves.easeOutCubic,
          alignment: Alignment.center,
          decoration: active
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: OkeyXColors.ruby, width: 2),
                  color: OkeyXColors.ruby.withValues(alpha: .095),
                  boxShadow: [BoxShadow(color: OkeyXColors.ruby.withValues(alpha: .20), blurRadius: 11)],
                )
              : null,
          child: json == null
              ? AnimatedOpacity(duration: const Duration(milliseconds: 85), opacity: active ? 1 : 0, child: Container(width: math.max(8.0, tileWidth * .22).toDouble(), height: tileHeight * .72, decoration: BoxDecoration(color: OkeyXColors.ruby.withValues(alpha: .32), borderRadius: BorderRadius.circular(99))))
              : AnimatedSlide(
                  duration: const Duration(milliseconds: 95),
                  curve: Curves.easeOutCubic,
                  offset: shift,
                  child: SizedBox(
                    width: tileWidth,
                    height: tileHeight.clamp(1.0, rowHeight).toDouble(),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 125),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: ScaleTransition(scale: Tween<double>(begin: .94, end: 1).animate(animation), child: child)),
                      child: KeyedSubtree(
                        key: ValueKey('rack-slot-$slot-$id'),
                        child: _rackTile(json, tileWidth, tileHeight.clamp(1.0, rowHeight).toDouble(), slot),
                      ),
                    ),
                  ),
                ),
        );
      },
    );
  }

  Widget _rackTile(
    Map<String, dynamic> json,
    double width,
    double height,
    int slot,
  ) {
    final id = '${json['id']}';
    final selected = _selectedTileId == id || _longPressRackGroupIds.contains(id);
    final pendingLeft = '${_viewer['pending_left_tile_id'] ?? ''}' == id;
    final pendingPreview = _map(_state['pending_left_opening']);
    final pendingCanOpen = pendingLeft && pendingPreview['can_open'] == true;
    final dropPulse = _rackDropPulseId == id;
    final penaltyIds = _list(_state['penalty_tile_ids']).map((e) => '$e').toSet();
    final renderJson = <String, dynamic>{
      ...json,
      'useful': penaltyIds.contains(id),
      // Okeyi kapatma: Klasik ve yardımsız masada oyuncu basılı tutarak
      // elle kapatır; diğer masalarda okey ıstakaya kapalı (ters) gelir,
      // basılı tutunca kısa süre açılıp tekrar kapanır.
      'face_down': json['joker'] == true && (_manualOkeyClose ? _revealedJokerIds.contains(id) : !_peekJokerIds.contains(id)),
    };
    final groupDelta = _longPressRackGroupIds.contains(id) ? _longPressRackGroupDelta : Offset.zero;
    Widget tile = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOutCubic,
      transform: Matrix4.translationValues(groupDelta.dx, ((selected || pendingCanOpen) ? -3 : 0) + groupDelta.dy - (_longPressRackGroupIds.contains(id) ? 6 : 0), 0),
      padding: (selected || pendingLeft) ? const EdgeInsets.all(1.5) : EdgeInsets.zero,
      decoration: (selected || pendingLeft)
          ? BoxDecoration(
              border: Border.all(color: pendingLeft || _longPressRackGroupIds.contains(id) ? OkeyXColors.gold : const Color(0xFF3CCF8E), width: pendingCanOpen ? 2.8 : 2),
              boxShadow: _longPressRackGroupIds.contains(id) ? const [BoxShadow(color: Color(0x80000000), blurRadius: 12, offset: Offset(0, 8))] : (pendingCanOpen ? [BoxShadow(color: OkeyXColors.gold.withValues(alpha: .48), blurRadius: 14, spreadRadius: 1)] : null),
              borderRadius: BorderRadius.circular(8),
            )
          : null,
      width: width,
      height: height,
      child: Stack(clipBehavior: Clip.none, children:[
        Positioned.fill(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 360),
            transitionBuilder: (child, animation) => AnimatedBuilder(
              animation: animation,
              child: child,
              builder: (context, c) {
                // Taş kendi ekseninde döner: yarıya kadar eski yüz, sonra yeni yüz.
                final angle = (1 - animation.value) * math.pi / 2;
                return Transform(alignment: Alignment.center, transform: Matrix4.identity()..setEntry(3, 2, .002)..rotateY(angle), child: c);
              },
            ),
            child: KeyedSubtree(
              key: ValueKey('face-$id-${renderJson['face_down']}'),
              child: TileWidget(tile: _tile(renderJson), skinId: _viewerTileSkin, bigNumber: _bigNumbers),
            ),
          ),
        ),
        if (pendingLeft) Positioned(right:-3,top:-5,child:Container(padding:const EdgeInsets.symmetric(horizontal:3,vertical:1),decoration:BoxDecoration(color:OkeyXColors.gold,borderRadius:BorderRadius.circular(6)),child:Text(pendingCanOpen?'AÇ':'KULLAN',style:const TextStyle(fontSize:9,color:Color(0xFF160E3F),fontWeight:FontWeight.w900)))),
      ]),
    );
    if (_dealAnimating && _dealSequence > 0) {
      tile = _DealInTile(
        key: ValueKey('deal-$_dealSequence-$id'),
        delayMs: (slot % _rackCols) * 32 + (slot ~/ _rackCols) * 120,
        child: tile,
      );
    }
    tile = AnimatedScale(duration: const Duration(milliseconds: 120), curve: Curves.easeOutBack, scale: dropPulse ? 1.055 : 1.0, child: tile);

    return Draggable<String>(
      data: id,
      maxSimultaneousDrags: _canArrangeRack ? 1 : 0,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      rootOverlay: true,
      hitTestBehavior: HitTestBehavior.opaque,
      feedback: Material(
        color: Colors.transparent,
        child: Transform.scale(
          scale: 1.065,
          child: Container(
            width: width,
            height: height,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 14, offset: Offset(0, 7))]),
            child: TileWidget(tile: _tile(renderJson), skinId: _viewerTileSkin, bigNumber: _bigNumbers),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: .10, child: tile),
      onDragStarted: () {
        setState(() { _draggingRackId = id; _rackHoverSlot = slot; _rackHoverInsertAfter = false; });
        unawaited(GameAudio.sfx('tile_pick', enabled: _soundEnabled, volume: .62));
        if (_vibrationEnabled) unawaited(HapticFeedback.selectionClick());
      },
      onDragUpdate: (details) {
        final target = _nearestRackSlot(details.globalPosition);
        if (target < 0 || target == _rackHoverSlot) return;
        setState(() => _rackHoverSlot = target);
      },
      onDragEnd: (details) {
        _handleRackDragEnd(id, details, width, height);
        if (mounted) setState(() { _draggingRackId = null; _rackHoverSlot = -1; _rackHoverInsertAfter = false; });
      },
      child: _QuickLongPress(
        onTap: () => _handleRackTap(id),
        onLongPressStart: (details) {
          final group = _rackGroupForTile(id);
          setState(() {
            _longPressRackGroupIds = group.length >= 2 ? group : <String>[id];
            _longPressStartGlobal = details.globalPosition;
            _longPressRackGroupDelta = Offset.zero;
            _longPressRackGroupMoved = false;
          });
          if (_vibrationEnabled) unawaited(HapticFeedback.selectionClick());
        },
        onLongPressMoveUpdate: (details) {
          final start = _longPressStartGlobal;
          if (start == null) return;
          final delta = details.globalPosition - start;
          final firstMove = delta.distance >= 10 && !_longPressRackGroupMoved;
          setState(() {
            _longPressRackGroupDelta = delta;
            if (delta.distance >= 10) _longPressRackGroupMoved = true;
          });
          if (firstMove && _vibrationEnabled) unawaited(HapticFeedback.lightImpact());
        },
        onLongPressEnd: (details) {
          final group = List<String>.from(_longPressRackGroupIds);
          final moved = _longPressRackGroupMoved;
          setState(() {
            _longPressRackGroupIds = const <String>[];
            _longPressStartGlobal = null;
            _longPressRackGroupDelta = Offset.zero;
            _longPressRackGroupMoved = false;
          });
          if (moved && group.length >= 2) {
            final target = _nearestRackSlot(details.globalPosition);
            if (target >= 0) _moveRackGroupToSlot(group, target);
            return;
          }
          if (json['joker'] == true) {
            if (_manualOkeyClose) {
              setState(() {
                if (!_revealedJokerIds.add(id)) _revealedJokerIds.remove(id);
              });
            } else {
              setState(() => _peekJokerIds.add(id));
              Future<void>.delayed(const Duration(milliseconds: 1600), () {
                if (mounted) setState(() => _peekJokerIds.remove(id));
              });
            }
            unawaited(GameAudio.sfx('tile_pick', enabled: _soundEnabled, volume: .7));
            if (_vibrationEnabled) unawaited(HapticFeedback.selectionClick());
          }
        },
        child: tile,
      ),
    );
  }

  void _handleRackTap(String id) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final doubleTap = _lastRackTapId == id && now - _lastRackTapMs <= 240;
    _lastRackTapId = id;
    _lastRackTapMs = now;

    if (doubleTap && _canDiscardTile(id)) {
      unawaited(_discardTile(id));
      return;
    }
    if (!_myTurn || '${_state['phase']}' != 'discard' || _busy) return;
    setState(() => _selectedTileId = _selectedTileId == id ? null : id);
  }

  bool _canDiscardTile(String id) =>
      _canMove &&
      !_busy &&
      '${_state['phase']}' == 'discard' &&
      _viewer['pending_left_tile_id'] == null &&
      _hand.any((tile) => '${tile['id']}' == id);

  Future<void> _discardTile(String id) async {
    if (!_canDiscardTile(id)) return;
    // İşler taş uyarısı: masadaki bir pere eklenebilen taşı atmak 101'de ceza yazar.
    final penaltyIds = _list(_state['penalty_tile_ids']).map((e) => '$e').toSet();
    if (penaltyIds.contains(id)) {
      if (_vibrationEnabled) unawaited(HapticFeedback.heavyImpact());
      unawaited(GameAudio.sfx('warning', enabled: _soundEnabled, volume: .8));
      final go = await _confirmUsefulDiscard();
      if (go != true || !mounted || !_canDiscardTile(id)) return;
    }
    setState(() => _selectedTileId = null);
    // Physical feedback must happen on the finger gesture, not after a
    // round-trip through the multiplayer server.
    unawaited(GameAudio.sfx(_tileImpactSfx(_viewer), enabled: _soundEnabled, volume: .94));
    await _act('discard', {'tile_id': id});
  }

  Future<bool?> _confirmUsefulDiscard() => showGeneralDialog<bool>(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'İşler taş',
        barrierColor: const Color(0x99000000),
        transitionDuration: const Duration(milliseconds: 200),
        transitionBuilder: (context, a, _, child) => Transform.scale(scale: .85 + .15 * Curves.easeOutBack.transform(a.value), child: Opacity(opacity: a.value, child: child)),
        pageBuilder: (context, _, __) => Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 400,
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF5A1030), Color(0xFF2A0B3D)]),
                border: Border.all(color: const Color(0xFFFF5470), width: 1.6),
                boxShadow: const [BoxShadow(color: Color(0x88FF2436), blurRadius: 30)],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Row(children: [
                  Icon(Icons.warning_amber_rounded, color: Color(0xFFFFCB45), size: 30),
                  SizedBox(width: 10),
                  Expanded(child: Text('Bu taş işler!', style: TextStyle(fontFamily: OkeyXFonts.number, fontSize: 21, color: Colors.white))),
                ]),
                const SizedBox(height: 8),
                const Text('Bu taş masadaki bir pere eklenebiliyor. Atarsan ceza (101 puan) yazılır. Yine de atmak istiyor musun?', style: TextStyle(fontSize: 13.5, height: 1.4, fontWeight: FontWeight.w600, color: Color(0xFFFFE3EA))),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: OkxButton.ghost(label: 'VAZGEÇ', height: 46, expand: true, onTap: () => Navigator.of(context).pop(false))),
                  const SizedBox(width: 10),
                  Expanded(child: OkxButton(label: 'YİNE DE AT', style: OkxButtonStyle.red, height: 46, expand: true, onTap: () => Navigator.of(context).pop(true))),
                ]),
              ]),
            ),
          ),
        ),
      );

  bool _dropIsAfter(int slot, Offset globalOffset) {
    if (slot < 0 || slot >= _rackSlotKeys.length) return false;
    final context = _rackSlotKeys[slot].currentContext;
    final box = context?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return false;
    final origin = box.localToGlobal(Offset.zero);
    return globalOffset.dx > origin.dx + box.size.width / 2;
  }

  void _moveRackTileToSlot(
    String draggedId,
    int targetSlot, {
    bool? insertAfter,
  }) {
    if (!_canArrangeRack || targetSlot < 0 || targetSlot >= _rackSlotCount) return;
    final from = _rackSlots.indexOf(draggedId);
    if (from < 0) return;
    if (from == targetSlot && insertAfter != true) return;
    // Otomatik dizilmiş perlerin grup sınırlarını tek bir manuel sürüklemede
    // komple silme. Önceki sürümde bir taşı oynatınca bütün per boşlukları
    // birleşiyordu. Sadece taşın kendisi grup başlangıcıysa eski işareti kaldır.
    _rackGroupStarts.remove(draggedId);
    _rackManuallyEdited = true;
    _insertRackTileAtSlot(
      draggedId,
      from,
      targetSlot,
      insertAfter: insertAfter,
    );
    if (mounted) {
      setState(() => _rackDropPulseId = draggedId);
      Future<void>.delayed(const Duration(milliseconds: 135), () { if (mounted && _rackDropPulseId == draggedId) setState(() => _rackDropPulseId = null); });
    }
    unawaited(GameAudio.sfx('tile_drop', enabled: _soundEnabled, volume: .86));
    if (_vibrationEnabled) unawaited(HapticFeedback.selectionClick());
  }

  void _insertRackTileAtSlot(
    String id,
    int from,
    int targetSlot, {
    bool? insertAfter,
  }) {
    if (targetSlot < 0 || targetSlot >= _rackSlotCount) return;
    setState(() {
      final next = List<String?>.from(_rackSlots);
      if (from >= 0 && from < next.length) {
        next[from] = null;
      }

      // Boş yuvaya bırakıldıysa taş doğrudan oraya gider. Bu, gerçek
      // ıstakadaki gibi oyuncunun istediği yerde fiziksel boşluk bırakmasını
      // sağlar; hiçbir otomatik sıkıştırma yapılmaz.
      if (next[targetSlot] == null) {
        next[targetSlot] = id;
        _rackSlots.setAll(0, next);
        return;
      }

      final rowStart = (targetSlot ~/ _rackCols) * _rackCols;
      final rowEnd = rowStart + _rackCols - 1;
      final placeAfter = insertAfter ?? (from >= 0 && from < targetSlot);
      var insertAt = targetSlot + (placeAfter ? 1 : 0);
      insertAt = insertAt.clamp(rowStart, rowEnd).toInt();

      // Sadece hedef satırdaki taşları kaydır. Önceki sürüm bütün 30 yuvayı
      // kaydırdığı için üstten alta/alttan üste taşlar "uçuyordu".
      var emptyRight = -1;
      for (var i = insertAt; i <= rowEnd; i++) {
        if (next[i] == null) {
          emptyRight = i;
          break;
        }
      }

      var emptyLeft = -1;
      for (var i = insertAt; i >= rowStart; i--) {
        if (next[i] == null) {
          emptyLeft = i;
          break;
        }
      }

      if (emptyRight >= 0) {
        for (var i = emptyRight; i > insertAt; i--) {
          next[i] = next[i - 1];
        }
        next[insertAt] = id;
        _rackSlots.setAll(0, next);
        return;
      }

      if (emptyLeft >= 0) {
        for (var i = emptyLeft; i < insertAt; i++) {
          next[i] = next[i + 1];
        }
        next[insertAt] = id;
        _rackSlots.setAll(0, next);
        return;
      }

      // Hedef satır tamamen doluysa taşları diğer satıra zincirleme itme.
      // Bunun yerine hedef taş ile sürüklenen taş yer değiştirir.
      final displaced = next[targetSlot];
      next[targetSlot] = id;
      if (from >= 0 && from < next.length && from != targetSlot) {
        next[from] = displaced;
      }
      _rackSlots.setAll(0, next);
    });
  }

  int _nearestRackSlot(Offset globalOffset) {
    var best = -1;
    var bestDistance = double.infinity;
    for (var slot = 0; slot < _rackSlotKeys.length; slot++) {
      final context = _rackSlotKeys[slot].currentContext;
      final box = context?.findRenderObject();
      if (box is! RenderBox || !box.hasSize) continue;
      final origin = box.localToGlobal(Offset.zero);
      final rect = origin & box.size;
      if (rect.inflate(5).contains(globalOffset)) return slot;
      final center = rect.center;
      final dx = center.dx - globalOffset.dx;
      final dy = center.dy - globalOffset.dy;
      final distance = dx * dx + dy * dy;
      if (distance < bestDistance) {
        bestDistance = distance;
        best = slot;
      }
    }
    return best;
  }

  void _handleExternalDragEnd(
    String source,
    DraggableDetails details,
    double feedbackWidth,
    double feedbackHeight,
  ) {
    if (details.wasAccepted) return;
    final context = _rackKey.currentContext;
    final box = context?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final origin = box.localToGlobal(Offset.zero);
    final rackRect = origin & box.size;
    final center = details.offset + Offset(feedbackWidth / 2, feedbackHeight / 2);
    if (!rackRect.inflate(8).contains(center)) return;

    final target = _nearestRackSlot(center);
    if (target < 0) return;
    final after = _dropIsAfter(target, center);
    if (source == '__stock__') {
      unawaited(_drawStockIntoSlot(target, insertAfter: after));
    } else if (source == '__left__') {
      unawaited(_takeLeftIntoSlot(target, insertAfter: after));
    }
  }

  void _handleRackDragEnd(
    String id,
    DraggableDetails details,
    double tileWidth,
    double tileHeight,
  ) {
    if (details.wasAccepted) return;
    final context = _rackKey.currentContext;
    final box = context?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final origin = box.localToGlobal(Offset.zero);
    final rackRect = origin & box.size;
    final feedbackCenter = details.offset + Offset(tileWidth / 2, tileHeight / 2);

    // Grup boşluğuna veya iki drop-zone arasındaki birkaç piksele bırakılmış
    // olsa bile en yakın gerçek yuvayı bul. Mobilde "tutmadı" hissini keser.
    if (rackRect.inflate(8).contains(feedbackCenter)) {
      final target = _nearestRackSlot(feedbackCenter);
      if (target >= 0) {
        _moveRackTileToSlot(
          id,
          target,
          insertAfter: _dropIsAfter(target, feedbackCenter),
        );
      }
      return;
    }

    if (_canDiscardTile(id)) {
      unawaited(_discardTile(id));
    }
  }

  int _defaultIncomingRackSlot() {
    // Yeni çekilen taş per aralarındaki ilk boşluğa değil, ıstakanın sağ
    // tarafındaki en boş noktaya gelir. Böylece SERİ/ÇİFT DİZ görünümü
    // çekişten sonra bozulmaz.
    for (var i = _rackSlotCount - 1; i >= _rackCols; i--) {
      if (_rackSlots[i] == null) return i;
    }
    for (var i = _rackCols - 1; i >= 0; i--) {
      if (_rackSlots[i] == null) return i;
    }
    return -1;
  }

  Future<void> _drawStockInto(String? beforeId) async {
    final slot = beforeId == null ? null : _rackSlots.indexOf(beforeId);
    await _drawStockIntoSlot(slot == null || slot < 0 ? null : slot);
  }

  Future<void> _drawStockIntoSlot(
    int? targetSlot, {
    bool? insertAfter,
  }) async {
    if (!_canMove || '${_state['phase']}' != 'draw' || _busy) return;
    final beforeHand = List<Map<String, dynamic>>.from(_serverHand);
    final beforeScore = _integer(_state['opening_preview_score']);
    final beforePairs = _integer(_state['opening_preview_pairs']);
    final oldIds = beforeHand.map((e) => '${e['id']}').toSet();
    unawaited(GameAudio.sfx('tile_pick', enabled: _soundEnabled, volume: .88));
    final out = await _act('draw_stock');
    if (out == null) return;
    final newIds = _serverHand
        .map((e) => '${e['id']}')
        .where((id) => !oldIds.contains(id))
        .toList();
    final payloadId = '${_map(out['payload'])['tile'] ?? ''}';
    final id = payloadId.isNotEmpty
        ? payloadId
        : (newIds.isNotEmpty ? newIds.first : '');
    if (id.isEmpty) return;
    _placeExternalTileAtSlot(id, targetSlot, insertAfter: insertAfter);
    final drawn = _serverHand.firstWhere((t) => '${t['id']}' == id, orElse: () => const <String, dynamic>{});
    if (drawn.isNotEmpty) {
      final hot = _isExcitingDraw(drawn, beforeHand, beforeScore, beforePairs);
      if (hot) _showDrawReveal(drawn, true);
    }
  }

  Future<void> _takeLeftInto(String? beforeId) async {
    final slot = beforeId == null ? null : _rackSlots.indexOf(beforeId);
    await _takeLeftIntoSlot(slot == null || slot < 0 ? null : slot);
  }

  Future<void> _takeLeftIntoSlot(
    int? targetSlot, {
    bool? insertAfter,
  }) async {
    if (!_canMove || '${_state['phase']}' != 'draw' || _busy) return;
    final oldIds = _serverHand.map((e) => '${e['id']}').toSet();
    unawaited(GameAudio.sfx('take_left', enabled: _soundEnabled, volume: .88));
    final out = await _act('take_left');
    if (out == null) return;
    final newIds = _serverHand
        .map((e) => '${e['id']}')
        .where((id) => !oldIds.contains(id))
        .toList();
    final payloadId = '${_map(out['payload'])['tile'] ?? ''}';
    final id = payloadId.isNotEmpty
        ? payloadId
        : (newIds.isNotEmpty ? newIds.first : '');
    if (id.isEmpty) return;
    _placeExternalTileAtSlot(id, targetSlot, insertAfter: insertAfter);
  }

  void _placeExternalTileAtSlot(
    String id,
    int? targetSlot, {
    bool? insertAfter,
  }) {
    if (!mounted) return;
    final existing = _rackSlots.indexOf(id);

    // Dokunarak çekmede _syncRackSlots yeni taşı zaten sağ-alt boş yuvaya
    // yerleştirmiş olur. Onu tekrar ilk boşluğa taşıma.
    if (targetSlot == null && existing >= 0) return;

    final target = targetSlot ?? _defaultIncomingRackSlot();
    if (target < 0 || target >= _rackSlotCount) return;
    if (existing == target) return;
    _insertRackTileAtSlot(id, existing, target, insertAfter: insertAfter);
  }

  bool _isExcitingDraw(
    Map<String, dynamic> drawn,
    List<Map<String, dynamic>> beforeHand,
    int beforeScore,
    int beforePairs,
  ) {
    if (!_assisted) return false;
    if (drawn['joker'] == true) return true;
    final afterScore = _integer(_state['opening_preview_score']);
    final afterPairs = _integer(_state['opening_preview_pairs']);
    if (afterScore > beforeScore || afterPairs > beforePairs) return true;
    final n = _integer(drawn['n']);
    final c = '${drawn['c']}';
    final sameColor = beforeHand
        .where((t) => '${t['c']}' == c && t['joker'] != true)
        .map((t) => _integer(t['n']))
        .toSet();
    if ((sameColor.contains(n - 1) && sameColor.contains(n + 1)) ||
        (sameColor.contains(n - 2) && sameColor.contains(n - 1)) ||
        (sameColor.contains(n + 1) && sameColor.contains(n + 2))) {
      return true;
    }
    final colorsAtNumber = beforeHand
        .where((t) => _integer(t['n']) == n && t['joker'] != true)
        .map((t) => '${t['c']}')
        .toSet();
    return colorsAtNumber.length >= 2 && !colorsAtNumber.contains(c);
  }

  void _showDrawReveal(Map<String, dynamic> tile, bool hot) {
    if (!mounted) return;
    final seq = ++_drawRevealSeq;
    setState(() {
      _drawRevealTile = Map<String, dynamic>.from(tile);
      _drawRevealHot = hot;
      _drawRevealText = '';
    });
    unawaited(GameAudio.sfx('hot_draw', enabled: _soundEnabled, volume: .58));
    if (hot && _vibrationEnabled) unawaited(HapticFeedback.mediumImpact());
    Future<void>.delayed(const Duration(milliseconds: 620), () {
      if (!mounted || _drawRevealSeq != seq) return;
      setState(() {
        _drawRevealTile = null;
        _drawRevealText = '';
        _drawRevealHot = false;
      });
    });
  }

  Widget _drawRevealOverlay() {
    final json = _drawRevealTile;
    if (json == null || !_drawRevealHot) return const SizedBox.shrink();
    return IgnorePointer(
      child: Align(
        alignment: const Alignment(0, .30),
        child: TweenAnimationBuilder<double>(
          key: ValueKey(_drawRevealSeq),
          duration: (widget.preferences.reducedMotionEnabled || widget.preferences.dataSaverEnabled) ? Duration.zero : const Duration(milliseconds: 430),
          tween: Tween(begin: 0, end: 1),
          curve: Curves.easeOutBack,
          builder: (context, value, child) => Transform.translate(
            offset: Offset(0, 24 * (1 - value)),
            child: Transform.scale(scale: .82 + (.18 * value), child: Opacity(opacity: value.clamp(0, 1), child: child)),
          ),
          child: Container(
            width: 66,
            height: 92,
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: const Color(0xD9180F41),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: OkeyXColors.gold, width: 1.4),
              boxShadow: const [BoxShadow(color: Color(0x88F4C542), blurRadius: 22, spreadRadius: 1)],
            ),
            child: TileWidget(tile: _tile({...json, 'useful': false}), skinId: _viewerTileSkin),
          ),
        ),
      ),
    );
  }

  int _colorRank(Map<String, dynamic> t) => switch ('${t['c']}') {
        'red' => 0,
        'yellow' => 1,
        'black' => 2,
        'blue' => 3,
        _ => 4,
      };

  void _sortRackLocal(bool series) {
    if (_serverHand.isEmpty) return;
    debugPrint('OKEYX_RACK_SORT: mode=${series ? 'series' : 'pairs'} hand=${_serverHand.length}');
    final result =
        series ? _seriesArrangementForRack(_serverHand) : _pairArrangement(_serverHand);
    setState(() {
      _applyRackArrangement(result);
      _selectedTileId = null;
    });
    unawaited(GameAudio.sfx('rack_slide', enabled: _soundEnabled, volume: .80));
    if (_vibrationEnabled) {
      unawaited(HapticFeedback.selectionClick());
    }
  }

  (List<String>, Set<String>, int) _pairArrangement(List<Map<String, dynamic>> hand) {
    final buckets = <String, List<Map<String, dynamic>>>{};
    final jokers = <Map<String, dynamic>>[];
    for (final t in hand) {
      if (t['joker'] == true) {
        jokers.add(t);
      } else {
        final key = '${t['c']}-${t['n']}';
        buckets.putIfAbsent(key, () => []).add(t);
      }
    }
    final pairs = <List<Map<String, dynamic>>>[];
    final rest = <Map<String, dynamic>>[];
    for (final arr in buckets.values) {
      var i = 0;
      while (i + 1 < arr.length) {
        pairs.add([arr[i], arr[i + 1]]);
        i += 2;
      }
      if (i < arr.length) rest.add(arr[i]);
    }
    while (jokers.isNotEmpty && rest.isNotEmpty) {
      pairs.add([rest.removeAt(0), jokers.removeAt(0)]);
    }
    while (jokers.length >= 2) {
      pairs.add([jokers.removeAt(0), jokers.removeAt(0)]);
    }
    rest.addAll(jokers);
    pairs.sort((a, b) {
      final n = _integer(a.first['n']).compareTo(_integer(b.first['n']));
      return n != 0 ? n : _colorRank(a.first).compareTo(_colorRank(b.first));
    });
    rest.sort((a, b) {
      final c = _colorRank(a).compareTo(_colorRank(b));
      return c != 0 ? c : _integer(a['n']).compareTo(_integer(b['n']));
    });
    final order = <String>[];
    final starts = <String>{};
    for (var i = 0; i < pairs.length; i++) {
      final g = pairs[i];
      if (i > 0) starts.add('${g.first['id']}');
      order.addAll(g.map((e) => '${e['id']}'));
    }
    if (rest.isNotEmpty) {
      if (order.isNotEmpty) starts.add('${rest.first['id']}');
      order.addAll(rest.map((e) => '${e['id']}'));
    }
    final rowBreak = _packedFirstRowCount(
      pairs.map((g) => g.length).toList(),
      rest.length,
    );
    return (order, starts, rowBreak);
  }

  (List<String>, Set<String>, int) _seriesArrangementForRack(
    List<Map<String, dynamic>> hand,
  ) {
    final rawGroups = _list(_state['assisted_series_groups']);
    if (rawGroups.isEmpty) return _seriesArrangement(hand);

    final byId = <String, Map<String, dynamic>>{
      for (final tile in hand) '${tile['id']}': tile,
    };
    final groups = <List<Map<String, dynamic>>>[];
    for (final raw in rawGroups) {
      final group = <Map<String, dynamic>>[];
      for (final value in _list(raw)) {
        final tile = byId['$value'];
        if (tile != null) group.add(tile);
      }
      if (group.length >= 3) groups.add(group);
    }
    if (groups.isEmpty) return _seriesArrangement(hand);
    // Sunucu önerisi açılış için bir taşı elde tutar; yerel çözücü eli tamamen
    // değerlendirir. Daha yüksek puanlı dizilimi göster.
    final local = _seriesArrangement(hand);
    if (_arrangementScore(_lastLocalSeriesGroups) > _arrangementScore(groups)) return local;

    final used = groups.expand((g) => g).map((t) => '${t['id']}').toSet();
    final rest = hand.where((t) => !used.contains('${t['id']}')).toList()
      ..sort((a, b) {
        final c = _colorRank(a).compareTo(_colorRank(b));
        return c != 0 ? c : _integer(a['n']).compareTo(_integer(b['n']));
      });
    final order = <String>[];
    final starts = <String>{};
    for (var i = 0; i < groups.length; i++) {
      final group = groups[i];
      if (i > 0) starts.add('${group.first['id']}');
      order.addAll(group.map((e) => '${e['id']}'));
    }
    if (rest.isNotEmpty) {
      if (order.isNotEmpty) starts.add('${rest.first['id']}');
      order.addAll(rest.map((e) => '${e['id']}'));
    }
    final rowBreak = _packedFirstRowCount(
      groups.map((g) => g.length).toList(),
      rest.length,
    );
    return (order, starts, rowBreak);
  }

  /// SERİ DİZ çözücüsü: eldeki taşlardan toplam puanı en yüksek geçerli per
  /// kombinasyonunu bulur. Tüm alt seriler (ör. 3-4-5-6-7 içinden 3-4-5 + 6-7-8),
  /// 3'lü/4'lü renk perleri ve okeyle tamamlanan boşluklar denenir. Okey,
  /// yerine geçtiği taşın puanını alır. Eşitlikte daha çok taş kullanan,
  /// sonra daha az okey harcayan plan seçilir. 12-13-1 geçersizdir.
  (List<String>, Set<String>, int) _seriesArrangement(List<Map<String, dynamic>> hand) {
    final jokers = hand.where((t) => t['joker'] == true).toList();
    final natural = hand.where((t) => t['joker'] != true).toList();
    // aday: (taşlar, puan, kullanılan okey sayısı)
    final candidates = <(List<Map<String, dynamic>>, int, int)>[];
    final seen = <String>{};
    void add(List<Map<String, dynamic>> tiles, int score, int jk) {
      final key = (tiles.map((t) => '${t['id']}').toList()..sort()).join(',') + '|$jk';
      if (seen.add(key)) candidates.add((tiles, score, jk));
    }
    final jCount = jokers.length.clamp(0, 2).toInt();
    // Seriler: her renk için 1..13 arası her pencere; eksikleri okey doldurur.
    for (final color in ['red', 'yellow', 'black', 'blue']) {
      final byN = <int, List<Map<String, dynamic>>>{};
      for (final t in natural.where((x) => '${x['c']}' == color)) {
        byN.putIfAbsent(_integer(t['n']), () => []).add(t);
      }
      for (var start = 1; start <= 11; start++) {
        for (var end = start + 2; end <= 13; end++) {
          final tiles = <Map<String, dynamic>>[];
          var missing = 0;
          var score = 0;
          for (var n = start; n <= end; n++) {
            score += n;
            final arr = byN[n];
            if (arr == null || arr.isEmpty) {
              missing++;
              tiles.add(const {'__joker_slot': true});
            } else {
              tiles.add(arr.first);
            }
          }
          if (missing > jCount || missing >= tiles.length - 1) continue;
          add(tiles, score, missing);
          // Aynı taştan ikincisi varsa ikinci kopyayla da aday üret (iki ayrı seri için).
          final dup = <Map<String, dynamic>>[];
          var ok = false;
          for (var n = start; n <= end; n++) {
            final arr = byN[n];
            if (arr == null || arr.isEmpty) {
              dup.add(const {'__joker_slot': true});
            } else if (arr.length > 1) {
              dup.add(arr[1]);
              ok = true;
            } else {
              dup.add(arr.first);
            }
          }
          if (ok) add(dup, score, missing);
        }
      }
    }
    // Renk perleri: aynı sayı, farklı renkler (3 ya da 4), eksik renk okeyle.
    for (var n = 1; n <= 13; n++) {
      final byColor = <String, List<Map<String, dynamic>>>{};
      for (final t in natural.where((x) => _integer(x['n']) == n)) {
        byColor.putIfAbsent('${t['c']}', () => []).add(t);
      }
      final colors = byColor.keys.toList();
      for (var mask = 1; mask < (1 << colors.length); mask++) {
        final pick = <Map<String, dynamic>>[];
        final pick2 = <Map<String, dynamic>>[];
        var hasDup = false;
        for (var i = 0; i < colors.length; i++) {
          if (mask & (1 << i) == 0) continue;
          final arr = byColor[colors[i]]!;
          pick.add(arr.first);
          if (arr.length > 1) {
            pick2.add(arr[1]);
            hasDup = true;
          } else {
            pick2.add(arr.first);
          }
        }
        for (var size = 3; size <= 4; size++) {
          final need = size - pick.length;
          if (need < 0 || need > jCount || pick.length < 2) continue;
          final slots = List<Map<String, dynamic>>.filled(need, const {'__joker_slot': true});
          add([...pick, ...slots], n * size, need);
          if (hasDup) add([...pick2, ...slots], n * size, need);
        }
      }
    }

    var best = <(List<Map<String, dynamic>>, int, int)>[];
    var bestKey = (-1, -1, 0);
    var budget = 250000;
    void dfs(int index, Set<String> used, int jokersUsed, List<(List<Map<String, dynamic>>, int, int)> groups, int score, int tiles) {
      if (--budget < 0) return;
      final key = (score, tiles, -jokersUsed);
      if (key.$1 > bestKey.$1 || (key.$1 == bestKey.$1 && (key.$2 > bestKey.$2 || (key.$2 == bestKey.$2 && key.$3 > bestKey.$3)))) {
        bestKey = key;
        best = List.of(groups);
      }
      for (var j = index; j < candidates.length; j++) {
        final c = candidates[j];
        if (jokersUsed + c.$3 > jokers.length) continue;
        var clash = false;
        for (final t in c.$1) {
          if (t['__joker_slot'] == true) continue;
          if (used.contains('${t['id']}')) {
            clash = true;
            break;
          }
        }
        if (clash) continue;
        final next = {...used, for (final t in c.$1) if (t['__joker_slot'] != true) '${t['id']}'};
        dfs(j + 1, next, jokersUsed + c.$3, [...groups, c], score + c.$2, tiles + c.$1.length);
      }
    }
    dfs(0, <String>{}, 0, const [], 0, 0);

    // Okey yuvalarına gerçek okeyleri yerleştir.
    final jokerQueue = List.of(jokers);
    final groupsOut = <List<Map<String, dynamic>>>[];
    for (final g in best) {
      groupsOut.add([for (final t in g.$1) t['__joker_slot'] == true ? jokerQueue.removeAt(0) : t]);
    }
    // Uzun per başa.
    groupsOut.sort((a, b) => b.length.compareTo(a.length));
    _lastLocalSeriesGroups = groupsOut;
    final used = groupsOut.expand((g) => g).map((t) => '${t['id']}').toSet();
    final rest = hand.where((t) => !used.contains('${t['id']}')).toList()
      ..sort((a, b) {
        final c = _colorRank(a).compareTo(_colorRank(b));
        return c != 0 ? c : _integer(a['n']).compareTo(_integer(b['n']));
      });
    final order = <String>[];
    final starts = <String>{};
    for (var i = 0; i < groupsOut.length; i++) {
      final g = groupsOut[i];
      if (i > 0) starts.add('${g.first['id']}');
      order.addAll(g.map((e) => '${e['id']}'));
    }
    if (rest.isNotEmpty) {
      if (order.isNotEmpty) starts.add('${rest.first['id']}');
      order.addAll(rest.map((e) => '${e['id']}'));
    }
    final rowBreak = _packedFirstRowCount(groupsOut.map((g) => g.length).toList(), rest.length);
    return (order, starts, rowBreak);
  }

  /// Bir dizilimin per puanı (sunucu önerisiyle karşılaştırmak için).
  int _arrangementScore(List<List<Map<String, dynamic>>> groups) {
    var total = 0;
    for (final g in groups) {
      final naturals = g.where((t) => t['joker'] != true).toList();
      if (naturals.isEmpty) continue;
      final sameNumber = naturals.every((t) => _integer(t['n']) == _integer(naturals.first['n']));
      if (sameNumber && naturals.map((t) => '${t['c']}').toSet().length == naturals.length) {
        total += _integer(naturals.first['n']) * g.length;
      } else {
        final ns = naturals.map((t) => _integer(t['n'])).toList()..sort();
        final start = (ns.first - g.indexWhere((t) => t['joker'] != true)).clamp(1, 13);
        for (var i = 0; i < g.length; i++) {
          total += start + i;
        }
      }
    }
    return total;
  }

  int _packedFirstRowCount(List<int> groupLengths, int singles) {
    var used = 0;
    var wrappedToSecondRow = false;
    for (final len in groupLengths) {
      if (used > 0 && used + len > _rackCols) {
        wrappedToSecondRow = true;
        break;
      }
      if (len > _rackCols) return _rackCols;
      used += len;
      if (used == _rackCols) return _rackCols;
    }
    if (wrappedToSecondRow) return used.clamp(1, _rackCols).toInt();
    final fill = (_rackCols - used).clamp(0, singles).toInt();
    return (used + fill).clamp(1, _rackCols).toInt();
  }

  /// "AÇILIŞ  87/101" gibi etiketli, ilerleme çubuklu sayaç.
  Widget _playerAvatar(Map<String, dynamic> player, {required double radius}) {
    final name = '${player['name'] ?? 'Oyuncu'}';
    final loadout = _map(player['loadout']);
    return _cosmeticAvatar(
      size: radius * 2,
      displayName: name,
      avatarUrl: '${player['avatar_url'] ?? ''}'.trim(),
      cosmeticId: '${loadout['avatar'] ?? ''}'.trim(),
    );
  }

  Widget _cosmeticAvatar({
    required double size,
    required String displayName,
    String avatarUrl = '',
    String cosmeticId = '',
  }) {
    Widget fallback() => Text(
          displayName.isEmpty ? 'O' : displayName.substring(0, 1).toUpperCase(),
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: size * .38),
        );

    Widget child;
    switch (cosmeticId) {
      case 'avatar_fox':
        child = Icon(Icons.pets_rounded, size: size * .55, color: const Color(0xFFFFD17A));
        break;
      case 'avatar_samurai':
        child = Icon(Icons.shield_rounded, size: size * .56, color: const Color(0xFFE5E9F4));
        break;
      case 'avatar_cat':
        child = Icon(Icons.pets_rounded, size: size * .55, color: const Color(0xFFFFF1C7));
        break;
      case 'avatar_phoenix':
        child = Icon(Icons.local_fire_department_rounded, size: size * .59, color: const Color(0xFFFFB36B));
        break;
      default:
        child = avatarUrl.isEmpty
            ? fallback()
            : Image.network(
                avatarUrl,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Center(child: fallback()),
              );
    }
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: cosmeticId == 'avatar_fox'
            ? const Color(0xFF7A3E17)
            : cosmeticId == 'avatar_samurai'
                ? const Color(0xFF374151)
                : cosmeticId == 'avatar_cat'
                    ? const Color(0xFF6E5368)
                    : cosmeticId == 'avatar_phoenix'
                        ? const Color(0xFF6E2F20)
                        : const Color(0xFF322187),
        shape: BoxShape.circle,
      ),
      child: child,
    );
  }

  Widget _avatar(double size) {
    final loadout = _map(_viewer['loadout']);
    return _cosmeticAvatar(
      size: size,
      displayName: widget.profile.displayName,
      avatarUrl: widget.profile.avatarUrl ?? '',
      cosmeticId: '${loadout['avatar'] ?? ''}'.trim(),
    );
  }

  Future<void> _showFidgetPanel() async {
    var taps=0;
    var selected='tespih';
    await showDialog<void>(
      context:context,
      builder:(dialogContext)=>StatefulBuilder(builder:(context,setLocal)=>Dialog(
        backgroundColor:const Color(0xF5140D3A),
        shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(24),side:BorderSide(color:OkeyXColors.gold.withValues(alpha:.45))),
        child:SizedBox(width:430,height:245,child:Padding(padding:const EdgeInsets.all(14),child:Column(children:[
          Row(children:[const Icon(Icons.toys_rounded,color:OkeyXColors.gold),const SizedBox(width:8),const Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('MASA ALTI OYUNCAKLARI',style:TextStyle(fontSize:13,fontWeight:FontWeight.w900)),Text('Sadece sende görünür; gerçek ıstaka ve oyun akışı değişmez.',style:TextStyle(fontSize:9,color:Colors.white54))])),IconButton(onPressed:()=>Navigator.pop(dialogContext),icon:const Icon(Icons.close_rounded))]),
          const SizedBox(height:8),
          Expanded(child:Row(children:[
            Expanded(child:_fidgetChoice(Icons.blur_circular_rounded,'TESPİH ÇEK','tespih',selected,taps,(){selected='tespih';taps++;setLocal((){});unawaited(GameAudio.sfx('fidget_bead',enabled:_soundEnabled,volume:.68));if(_vibrationEnabled)unawaited(HapticFeedback.selectionClick());})),
            const SizedBox(width:10),
            Expanded(child:_fidgetChoice(Icons.monetization_on_rounded,'ÇİP ÇEVİR','chip',selected,taps,(){selected='chip';taps++;setLocal((){});unawaited(GameAudio.sfx('coin_flip',enabled:_soundEnabled,volume:.72));if(_vibrationEnabled)unawaited(HapticFeedback.lightImpact());})),
          ])),
        ]))),
      )),
    );
  }

  Widget _fidgetChoice(IconData icon,String title,String id,String selected,int taps,VoidCallback onTap)=>Material(color:Colors.transparent,child:InkWell(onTap:onTap,borderRadius:BorderRadius.circular(20),child:AnimatedContainer(duration:const Duration(milliseconds:140),decoration:BoxDecoration(gradient:LinearGradient(colors:id==selected?[OkeyXColors.gold.withValues(alpha:.18),const Color(0xFF1D134E)]:[Colors.white.withValues(alpha:.035),const Color(0xFF100B2D)]),borderRadius:BorderRadius.circular(20),border:Border.all(color:id==selected?OkeyXColors.gold:Colors.white12)),child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[TweenAnimationBuilder<double>(key:ValueKey('$id-$taps'),tween:Tween(begin:0,end:1),duration:const Duration(milliseconds:320),curve:Curves.elasticOut,builder:(context,v,child)=>Transform.rotate(angle:id=='chip'?v*math.pi*2:math.sin(v*math.pi*3)*.28,child:Transform.scale(scale:.72+.28*v,child:child)),child:Icon(icon,size:46,color:id==selected?OkeyXColors.gold:Colors.white54)),const SizedBox(height:8),Text(title,style:const TextStyle(fontSize:9,fontWeight:FontWeight.w900)),Text('DOKUN • $taps',style:const TextStyle(fontSize:9,color:Colors.white38))]))));

  List<String> _chatEmojiSet() {
    final pack='${_map(_viewer['loadout'])['emoji_pack'] ?? ''}';
    return switch(pack){
      'emoji_party' => const ['🥳','🎉','🔥','👏','🕺','💃','✨','🏆','😂','😎'],
      'emoji_cafe' => const ['☕','🫖','🧿','🍀','👏','🤝','😄','🪑','😂','❤️'],
      'emoji_troll' => const ['😈','🤡','😏','🙃','👀','🫠','😂','🧂','🐔','🩴'],
      'emoji_neon' => const ['💜','💙','🩵','⚡','🌌','✨','🔥','😎','🎵','⭐'],
      _ => const ['😂','😎','🔥','👏','🤝','😱','🍀','⭐'],
    };
  }

  Future<void> _showChatPanel() async {
    if (!mounted) return;
    if(_state['chat_enabled']==false){_tableNotice('Bu masada sohbet kapalı.');return;}
    final controller = TextEditingController();
    const quick = [
      'İyi oyun!',
      'Bol şans!',
      'Güzel el.',
      'Hadi bakalım 😄',
      'Tebrikler!',
      'Eline sağlık.',
      'Okey sende mi?',
      'Çift gidiyorum 😄',
      'Son taş!',
      'Devam devam 🔥',
    ];
    const voiceLines=['Hadi kardeşim, ağaç olduk!','Okey bende!','Taşını at da oynayalım!','Bol şans!','Son taş!','Vay be!','Çift gidiyorum!','Eline sağlık!'];
    final emojis = _chatEmojiSet();
    try {
      // Sohbet artık yandan açılan ince panel: masa solda görünmeye devam eder.
      await showGeneralDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'Sohbet',
        barrierColor: const Color(0x33000000),
        transitionDuration: const Duration(milliseconds: 220),
        transitionBuilder: (c, a, _, child) => SlideTransition(
          position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
          child: child,
        ),
        pageBuilder: (sheetContext, _, __) => Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: math.min(360.0, MediaQuery.sizeOf(sheetContext).width * .4),
            child: Material(color: Colors.transparent, child: StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final chat = _list(_state['chat']).map(_map).where((e) => '${e['kind']}' != 'gift').toList().reversed.take(18).toList().reversed;
            return SafeArea(
              child: OkxLeather(
                stitch: true,
                radius: 22,
                padding: EdgeInsets.zero,
                child: SizedBox(
                height: MediaQuery.sizeOf(sheetContext).height,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text('MASA SOHBETİ', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                          const Spacer(),
                          IconButton(onPressed: () => Navigator.pop(sheetContext), icon: const Icon(Icons.close_rounded)),
                        ],
                      ),
                      Expanded(
                        child: ListView(
                          children: [
                            if (chat.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 10),
                                child: Text('Henüz mesaj yok.', style: TextStyle(color: Colors.white54, fontSize: 10)),
                              ),
                            for (final item in chat)
                              Container(
                                margin: const EdgeInsets.symmetric(vertical: 2),
                                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                                decoration: BoxDecoration(
                                  color: _integer(item['seat']) == _viewerSeat ? OkeyXColors.mint.withValues(alpha: .09) : Colors.white.withValues(alpha: .035),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('${item['name'] ?? 'Oyuncu'}', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: _integer(item['seat']) == _viewerSeat ? OkeyXColors.mint : OkeyXColors.gold)),
                                    const SizedBox(width: 6),
                                    Expanded(child: Text('${item['value'] ?? ''}', style: const TextStyle(fontSize: 9, color: Colors.white70))),
                                  ],
                                ),
                              ),
                            const SizedBox(height: 10),
                            const Text('HAZIR SÖZLER', style: TextStyle(fontSize: 9, color: Colors.white54, fontWeight: FontWeight.w900)),
                            const SizedBox(height: 5),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (final text in quick)
                                  ActionChip(
                                    label: Text(text, style: const TextStyle(fontSize: 9)),
                                    onPressed: () async {
                                      await _sendChat('quick', text);
                                      if (sheetContext.mounted) setSheetState(() {});
                                    },
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Row(children:[Icon(Icons.record_voice_over_rounded,size:14,color:OkeyXColors.gold),SizedBox(width:5),Text('SESLİ HAZIR REPLİKLER',style:TextStyle(fontSize:9,color:OkeyXColors.gold,fontWeight:FontWeight.w900))]),
                            const SizedBox(height:5),
                            Wrap(spacing:6,runSpacing:6,children:[for(final line in voiceLines)ActionChip(avatar:const Icon(Icons.volume_up_rounded,size:13),label:Text(line,style:const TextStyle(fontSize:9)),onPressed:()async{await _sendChat('voice',line);if(sheetContext.mounted)setSheetState((){});})]),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (final emoji in emojis)
                                  ActionChip(
                                    label: Text(emoji, style: const TextStyle(fontSize: 18)),
                                    onPressed: () async {
                                      await _sendChat('emoji', emoji);
                                      if (sheetContext.mounted) setSheetState(() {});
                                    },
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Text('Domates, terlik, çay ve diğer masa reaksiyonları için rakibin profil kartına dokun.', style: TextStyle(fontSize: 9, color: Colors.white38)),
                          ],
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: controller,
                              maxLength: 120,
                              textInputAction: TextInputAction.send,
                              decoration: const InputDecoration(counterText: '', hintText: 'Mesaj yaz…', isDense: true),
                              onSubmitted: (_) async {
                                final text = controller.text.trim();
                                if (text.isEmpty) return;
                                controller.clear();
                                await _sendChat('text', text);
                                if (sheetContext.mounted) setSheetState(() {});
                              },
                            ),
                          ),
                          const SizedBox(width: 7),
                          IconButton.filled(
                            onPressed: () async {
                              final text = controller.text.trim();
                              if (text.isEmpty) return;
                              controller.clear();
                              await _sendChat('text', text);
                              if (sheetContext.mounted) setSheetState(() {});
                            },
                            icon: const Icon(Icons.send_rounded),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              ),
            );
          },
        )),
          ),
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<bool> _sendChat(String kind, String value, {int? toSeat}) async {
    try {
      final out = await _api.chat(kind, value, toSeat: toSeat);
      if (out['ok'] == false) {
        final code = '${out['code'] ?? 'gift_failed'}';
        _tableNotice(code == 'insufficient_coins' ? 'Bu hediye için yeterli altının yok.' : _friendlyCode(code).isEmpty ? 'Hediye gönderilemedi.' : _friendlyCode(code));
        return false;
      }
      final event = _map(out['event']);
      if (event.isNotEmpty && mounted) {
        final id = '${event['id'] ?? ''}';
        if (kind == 'gift') {
          final reactions = _list(_state['reactions']).map(_map).toList();
          if (id.isNotEmpty && !reactions.any((row) => '${row['id'] ?? ''}' == id)) {
            reactions.add(event);
            setState(() => _state = {..._state, 'reactions': reactions});
          }
        } else {
          final chat = _list(_state['chat']).map(_map).where((e) => '${e['kind']}' != 'gift').toList();
          if (id.isNotEmpty && !chat.any((row) => '${row['id'] ?? ''}' == id)) {
            chat.add(event);
            setState(() => _state = {..._state, 'chat': chat});
          }
        }
        _handleChatEvent(event);
      }
      if (_vibrationEnabled) unawaited(HapticFeedback.selectionClick());
      return true;
    } catch (error) {
      if ('$error'.contains('gift_cooldown')) {
        _tableNotice('Bu hediyeyi birkaç saniye sonra tekrar atabilirsin.');
      } else if (mounted) {
        setState(() => _error = _friendlyCode('$error'));
      }
      return false;
    }
  }

  Widget _waitingRoomOverlay() {
    final players = _list(_state['players']).map(_map).toList();
    final isHost = _viewerSeat == _integer(_state['owner_seat']);
    final quickMatch = _state['quick_match'] == true;
    final derivedOccupied = players.where((p) {
      final seat = _integer(p['seat'], fallback: -1);
      if (seat < 0 || seat > 3) return false;
      return p['empty'] != true || p['explicit_bot'] == true;
    }).length.clamp(0, 4);
    final occupiedCount = _integer(_state['occupied_count'], fallback: derivedOccupied).clamp(0, 4).toInt();
    final emptyCount = _integer(_state['empty_count'], fallback: 4 - occupiedCount).clamp(0, 4).toInt();
    final botCount = _integer(_state['bot_count'], fallback: players.where((p) => p['explicit_bot'] == true).length).clamp(0, 4).toInt();
    final notReadyCount = _list(_state['players']).map(_map).where((p) => p['ready'] != true && p['bot'] != true && '${p['player_id'] ?? ''}'.isNotEmpty).length;
    final myReady = _viewer['ready'] == true;
    final tableReady = occupiedCount == 4 && notReadyCount == 0;
    final humanCount = _integer(
      _state['human_count'],
      fallback: players.where((p) => p['bot'] != true).length,
    ).clamp(0, 4).toInt();
    final required = _integer(_state['required_balance'], fallback: _integer(_state['entry_fee']) * (_state['turbo'] == true ? 10 : 1));
    final current = _integer(_state['viewer_chips'], fallback: widget.profile.coins);
    final shortViewport = MediaQuery.sizeOf(context).height < 760;
    Map<String, dynamic> at(int seat) => players.firstWhere((x) => _integer(x['seat']) == seat, orElse: () => const <String, dynamic>{});
    return ColoredBox(
      color: const Color(0xFF090619),
      child: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(center: Alignment(.02, -.15), radius: 1.18, colors: [Color(0xFF173E2E), Color(0xFF10271D), Color(0xFF080D0A)]),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 940, maxHeight: 470),
            child: Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xF21A2D22), Color(0xF20D1A14)]),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: OkeyXColors.gold.withValues(alpha: .42)),
                boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 36, offset: Offset(0, 15))],
              ),
              child: Row(children: [
                Expanded(
                  flex: 7,
                  // Masa ve koltuklar sabit bir tuvalde çizilip ekrana ölçeklenir;
                  // koltuklar masa adının üstüne binmez, yazılar kesilmez.
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: SizedBox(
                      width: 640,
                      height: 360,
                      child: Stack(children: [
                        Positioned(
                          left: 130, top: 78, width: 380, height: 204,
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: walnutDecoration(radius: BorderRadius.circular(110), rack: widget.preferences.rackStyle),
                            child: OkxFelt(theme: widget.preferences.tableTheme, borderRadius: BorderRadius.circular(100), child: Center(child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 28),
                              child: Column(mainAxisSize: MainAxisSize.min, children: [
                                FittedBox(fit: BoxFit.scaleDown, child: Text('${_state['room_name'] ?? 'OkeyX Masası'}', maxLines: 1, style: const TextStyle(fontFamily: OkeyXFonts.serif, fontSize: 21, fontWeight: FontWeight.w700, color: OkeyXColors.cream))),
                                const SizedBox(height: 6),
                                FittedBox(fit: BoxFit.scaleDown, child: Text(
                                  '${_isDuz ? 'KLASİK OKEY' : _state['variant'] == 'fold' ? '101 KATLAMALI' : '101 KATLAMASIZ'}  •  ${_state['turbo'] == true ? 'TURBO' : 'NORMAL'}  •  ${_state['assisted'] == false ? 'YARDIMSIZ' : 'YARDIMLI'}${_state['team_mode'] == 'paired' ? '  •  EŞLİ' : ''}',
                                  maxLines: 1,
                                  style: const TextStyle(fontSize: 10, color: Color(0xCCFFE3A0), fontWeight: FontWeight.w900, letterSpacing: .6),
                                )),
                              ]),
                            ))),
                          ),
                        ),
                        Positioned(left: 265, top: 0, child: _waitingSeat(at((_viewerSeat + 2) % 4), rel: 2)),
                        Positioned(left: 265, bottom: 0, child: _waitingSeat(at(_viewerSeat), mine: true, rel: 0)),
                        Positioned(left: 0, top: 128, child: _waitingSeat(at((_viewerSeat + 3) % 4), rel: 3)),
                        Positioned(right: 0, top: 128, child: _waitingSeat(at((_viewerSeat + 1) % 4), rel: 1)),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  flex: 4,
                  child: LayoutBuilder(
                    builder: (context, lobbyConstraints) => SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: lobbyConstraints.maxHeight),
                        child: IntrinsicHeight(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(quickMatch ? 'HIZLI EŞLEŞME' : 'ÖZEL MASA', style: const TextStyle(fontSize: 9, color: OkeyXColors.gold, fontWeight: FontWeight.w900, letterSpacing: 1.25)),
                              const SizedBox(height: 4),
                              if (quickMatch)
                                ValueListenableBuilder<int>(
                                  valueListenable: _nowMsNotifier,
                                  builder: (context, now, _) {
                                    final deadline = _integer(_state['quick_fill_at_ms']);
                                    final seconds = deadline > 0 ? ((deadline - now) / 1000).ceil().clamp(0, 15) : 0;
                                    final status = tableReady
                                        ? '4/4 koltuk dolu • oyun başlatılabilir'
                                        : humanCount >= 4
                                            ? 'Masa hazırlanıyor'
                                            : seconds > 0
                                                ? 'Botlar $seconds sn içinde yerleşecek'
                                                : (_state['quick_fill_error'] != null ? 'Bakiye kontrolü gerekli' : 'Botlar yerleşiyor');
                                    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text('$humanCount gerçek oyuncu', style: const TextStyle(fontSize: 20, height: 1.02, fontWeight: FontWeight.w900)),
                                      const SizedBox(height: 3),
                                      Text('$occupiedCount/4 koltuk dolu${botCount > 0 ? ' • $botCount bot' : ''}', style: const TextStyle(fontSize: 9.5, color: OkeyXColors.gold, fontWeight: FontWeight.w800)),
                                      const SizedBox(height: 3),
                                      Text(status, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: tableReady ? OkeyXColors.gold : seconds > 0 ? OkeyXColors.gold : OkeyXColors.mint)),
                                    ]);
                                  },
                                )
                              else
                                Text('$occupiedCount/4 KOLTUK DOLU', style: const TextStyle(fontSize: 22, height: 1.02, fontWeight: FontWeight.w900)),
                                if (botCount > 0) Padding(padding: const EdgeInsets.only(top: 3), child: Text('${occupiedCount - botCount} oyuncu • $botCount bot', style: const TextStyle(fontSize: 10, color: OkeyXColors.gold, fontWeight: FontWeight.w800))),
                              if (!quickMatch) ...[
                                const SizedBox(height:5),
                                Text(
                                  isHost
                                      ? (tableReady ? 'Herkes hazır • başlatma sende.' : emptyCount > 0 ? '$emptyCount boş koltuk' : '$notReadyCount oyuncu hazır değil')
                                      : (myReady ? 'Hazırsın • masa sahibi başlatacak.' : 'Hazırsan HAZIRIM\'a bas.'),
                                  maxLines:1,
                                  overflow:TextOverflow.ellipsis,
                                  style:const TextStyle(fontSize:9,color:Colors.white54,fontWeight:FontWeight.w800),
                                ),
                                if(current < required) ...[const SizedBox(height:5),_waitingMetric('BAKİYE EKSİK','${_compactMoney(required-current)} altın',Icons.account_balance_wallet_rounded,warning:true)],
                                const SizedBox(height:7),
                                Row(children:[
                                  Expanded(child:OutlinedButton.icon(onPressed:_showChatPanel,icon:const Icon(Icons.chat_bubble_rounded,size:14),label:const FittedBox(child:Text('SOHBET')))),
                                  const SizedBox(width:5),
                                  Expanded(child:OutlinedButton.icon(onPressed:isHost?_showRoomSettingsDialog:null,icon:const Icon(Icons.tune_rounded,size:14),label:const FittedBox(child:Text('AYAR')))),
                                ]),
                                if(isHost) ...[
                                  const SizedBox(height:5),
                                  Row(children:[
                                    Expanded(child:OutlinedButton.icon(onPressed:widget.profile.isGuest?_showAccountLinkRequired:_showInviteFriendDialog,icon:const Icon(Icons.person_add_alt_1_rounded,size:14),label:const FittedBox(child:Text('ARKADAŞ')))),
                                    const SizedBox(width:5),
                                    Expanded(child:FilledButton.tonalIcon(onPressed:_busy||emptyCount==0?null:_showBotFillMenu,icon:const Icon(Icons.smart_toy_rounded,size:14),label:const FittedBox(child:Text('BOT EKLE')))),
                                  ]),
                                ],
                                const SizedBox(height:7),
                                Row(children:[
                                  Expanded(flex:4,child:OutlinedButton.icon(style:OutlinedButton.styleFrom(foregroundColor:const Color(0xFFFF8E91),side:const BorderSide(color:Color(0x55FF5B63))),onPressed:_busy?null:_leaveWaitingRoom,icon:const Icon(Icons.logout_rounded,size:13),label:const FittedBox(child:Text('AYRIL')))),
                                  const SizedBox(width:6),
                                  Expanded(flex:7,child:FilledButton.icon(
                                    style:FilledButton.styleFrom(backgroundColor:current<required?const Color(0xFF9A6A2F):tableReady?const Color(0xFF8A5A1C):const Color(0xFF231665),foregroundColor:Colors.white,shadowColor:tableReady?OkeyXColors.gold:Colors.transparent,elevation:tableReady?14:2,padding:EdgeInsets.symmetric(vertical:shortViewport?9:11),side:BorderSide(color:tableReady?OkeyXColors.gold.withValues(alpha:.75):Colors.white12,width:tableReady?1.4:1)),
                                    onPressed:_busy?null:(current<required?_leaveForStore:(isHost?(tableReady?()=>_startMatchFromWaiting(required,current):null):()=>unawaited(_toggleReady(!myReady)))),
                                    icon:Icon(current<required?Icons.shopping_bag_rounded:(isHost?(tableReady?Icons.play_arrow_rounded:Icons.hourglass_bottom_rounded):(myReady?Icons.check_circle_rounded:Icons.front_hand_rounded)),size:16),
                                    label:FittedBox(child:Text(current<required?'ALTIN AL':isHost?(tableReady?'OYUNU BAŞLAT':emptyCount>0?'$emptyCount KOLTUK BOŞ':'$notReadyCount HAZIR DEĞİL'):(myReady?'HAZIRIM ✓ (İPTAL)':'HAZIRIM'),style:const TextStyle(fontWeight:FontWeight.w900))),
                                  )),
                                ]),
                              ] else ...[
                                const SizedBox(height:9),
                                Row(children:[
                                  Expanded(child:_waitingCompactMetric('GİRİŞ','${_compactMoney(_integer(_state['entry_fee']))}',Icons.monetization_on_rounded,OkeyXColors.gold)),const SizedBox(width:5),
                                  Expanded(child:_waitingCompactMetric('KOLTUK','$occupiedCount/4',Icons.event_seat_rounded,OkeyXColors.gold)),const SizedBox(width:5),
                                  Expanded(child:_waitingCompactMetric('BOT','$botCount',Icons.smart_toy_rounded,OkeyXColors.gold)),
                                ]),
                                const SizedBox(height:7),
                                Row(children: [
                                  Expanded(child: OutlinedButton.icon(onPressed:_showChatPanel,icon:const Icon(Icons.chat_bubble_rounded,size:14),label:const FittedBox(child:Text('SOHBET')))),
                                  if (isHost) ...[
                                    const SizedBox(width:6),
                                    Expanded(child: OutlinedButton.icon(
                                      onPressed:_busy || emptyCount == 0 ? null : _showBotFillMenu,
                                      icon:const Icon(Icons.smart_toy_rounded,size:14),
                                      label:const FittedBox(child:Text('BOT EKLE')),
                                    )),
                                  ],
                                ]),
                                const SizedBox(height:6),
                                Row(children: [
                                  Expanded(flex:4, child: OutlinedButton.icon(
                                    style:OutlinedButton.styleFrom(foregroundColor:const Color(0xFFFF8E91),side:const BorderSide(color:Color(0x55FF5B63))),
                                    onPressed:_busy?null:_leaveWaitingRoom,
                                    icon:const Icon(Icons.logout_rounded,size:14),
                                    label:const FittedBox(child:Text('EŞLEŞMEDEN ÇIK')),
                                  )),
                                  const SizedBox(width:6),
                                  Expanded(flex:7, child: ValueListenableBuilder<int>(
                                    valueListenable: _nowMsNotifier,
                                    builder: (context, now, _) {
                                      final deadline = _integer(_state['quick_fill_at_ms']);
                                      final seconds = deadline > 0 ? ((deadline - now) / 1000).ceil().clamp(0, 15) : 0;
                                      final insufficient = current < required;
                                      final canHostStart = isHost && tableReady;
                                      final label = insufficient
                                          ? 'ALTIN AL'
                                          : canHostStart
                                              ? 'OYUNU BAŞLAT'
                                              : humanCount >= 4
                                                  ? 'MASA HAZIRLANIYOR'
                                                  : seconds > 0
                                                      ? 'BOTLAR $seconds SN İÇİNDE YERLEŞECEK'
                                                      : 'BOTLAR YERLEŞİYOR';
                                      return FilledButton.icon(
                                        style: FilledButton.styleFrom(
                                          backgroundColor: canHostStart ? const Color(0xFF8A5A1C) : null,
                                          foregroundColor: canHostStart ? Colors.white : null,
                                          elevation: canHostStart ? 12 : 2,
                                          shadowColor: OkeyXColors.gold.withValues(alpha: .65),
                                          side: canHostStart ? BorderSide(color: OkeyXColors.gold, width: 1.4) : null,
                                        ),
                                        onPressed: insufficient
                                            ? _leaveForStore
                                            : canHostStart && !_busy
                                                ? () => _startMatchFromWaiting(required, current)
                                                : null,
                                        icon: Icon(insufficient ? Icons.shopping_bag_rounded : canHostStart ? Icons.play_arrow_rounded : Icons.smart_toy_rounded),
                                        label: FittedBox(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w900))),
                                      );
                                    },
                                  )),
                                ]),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _waitingModePill(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: .08), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withValues(alpha: .26))),
        child: Text(text, style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.w900)),
      );

  Widget _waitingCompactMetric(String label, String value, IconData icon, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: .025), borderRadius: BorderRadius.circular(11), border: Border.all(color: Colors.white10)),
        child: Row(children: [Icon(icon, size: 12, color: color), const SizedBox(width: 4), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(fontSize: 9, color: Colors.white38, fontWeight: FontWeight.w900)), Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900))]))]),
      );

  Widget _waitingSeat(Map<String, dynamic> player, {bool mine = false, int rel = 0}) {
    final bot = player['bot'] == true;
    final empty = player['empty'] == true;
    final quickMatch = _state['quick_match'] == true;
    final rawName = '${player['name'] ?? 'Boş Koltuk'}';
    final name = empty ? (quickMatch ? 'Bekleniyor' : 'Boş koltuk') : rawName;
    final explicitBot = player['explicit_bot'] == true;
    final seat = _integer(player['seat'], fallback: -1);
    final isHost = _viewerSeat == _integer(_state['owner_seat']);
    final ownerSeat = _integer(_state['owner_seat']);
    final kickable = isHost && !mine && !bot && seat >= 0;
    final botLevel = '${player['bot_level'] ?? 'medium'}';
    final paired = _state['team_mode'] == 'paired';
    // Eşli oyunda karşıdaki koltuk (rel 2) eşin, yanlar rakip.
    final partner = paired && rel == 2;
    final rival = paired && (rel == 1 || rel == 3);
    final teamColor = partner || (paired && mine) ? OkeyXColors.gold : rival ? const Color(0xFF6FA8FF) : OkeyXColors.gold;
    final connected = player['connected'] == true || bot || mine;
    // Hazır durumu: oyuncu HAZIRIM'a basar; masa sahibi ve botlar hep hazırdır.
    final ready = player['ready'] == true || bot;
    final (statusText, statusColor) = empty
        ? (isHost ? ('DAVET / BOT / GEÇ', const Color(0x99FFE3A0)) : ('BURAYA OTUR', OkeyXColors.mint))
        : !connected
            ? ('BAĞLANIYOR…', const Color(0xFFFFB86B))
            : ready
                ? ('HAZIR ✓', OkeyXColors.mint)
                : ('HAZIR DEĞİL', const Color(0xFFFFB86B));
    final roleText = empty
        ? ''
        : mine
            ? (paired ? 'SEN • TAKIM A' : 'SEN')
            : partner
                ? 'EŞİN • TAKIM A'
                : rival
                    ? 'RAKİP • TAKIM B'
                    : explicitBot
                        ? '${botLevel == 'hard' ? 'ZOR' : botLevel == 'easy' ? 'KOLAY' : 'NORMAL'} BOT'
                        : seat == ownerSeat
                            ? 'MASA SAHİBİ'
                            : 'OYUNCU';
    final avatar = (!empty && !bot) ? SizedBox(width: 62, height: 62, child: Center(child: OkxAvatar(name: rawName, imageUrl: _avatarUrlOf(player), size: 46, online: connected, highlight: partner))) : Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: empty ? null : const RadialGradient(colors: [Color(0xFF1C1250), Color(0xFF0E0928)]),
        color: empty ? const Color(0x33000000) : null,
        border: Border.all(color: empty ? const Color(0x66E8C478) : teamColor, width: empty ? 1.4 : 2.2),
        boxShadow: empty ? null : [BoxShadow(color: teamColor.withValues(alpha: .35), blurRadius: 12)],
      ),
      child: empty
          ? const Icon(Icons.add_rounded, size: 26, color: Color(0xCCE8C478))
          : bot
              ? Icon(Icons.smart_toy_rounded, size: 24, color: teamColor)
              : null,
    );
    final card = SizedBox(
      width: 110,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
          avatar,
          if (seat == ownerSeat && !empty) const Positioned(top: -10, child: Icon(Icons.workspace_premium_rounded, size: 18, color: OkeyXColors.gold)),
          if (!empty)
            Positioned(
              right: -4,
              bottom: -4,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ready && connected ? OkeyXColors.mint : const Color(0xFFFFB86B),
                  border: Border.all(color: const Color(0xFF0B071E), width: 2),
                  boxShadow: ready && connected ? [BoxShadow(color: OkeyXColors.mint.withValues(alpha: .6), blurRadius: 10)] : null,
                ),
                child: Icon(ready && connected ? Icons.check_rounded : Icons.hourglass_top_rounded, size: 13, color: const Color(0xFF0B071E)),
              ),
            ),
        ]),
        const SizedBox(height: 5),
        Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900, color: empty ? const Color(0xCCE8C478) : OkeyXColors.cream)),
        if (roleText.isNotEmpty)
          Text(roleText, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: .6, color: rival ? const Color(0xFF9CC3FF) : const Color(0xFFE8C478))),
        const SizedBox(height: 3),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: statusColor.withValues(alpha: .14), borderRadius: BorderRadius.circular(99), border: Border.all(color: statusColor.withValues(alpha: .5))),
          child: Text(statusText, maxLines: 1, style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w900, letterSpacing: .5, color: statusColor)),
        ),
      ]),
    );
    final bubble = _chatBubbles[seat];
    final wrapped = Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [card, if (bubble != null && bubble.isNotEmpty) Positioned(top: -39, child: _tableChatBubble(bubble, seat == _viewerSeat ? 0 : 2))]);
    if (empty && isHost && seat >= 0) return InkWell(borderRadius: BorderRadius.circular(18), onTap: () => _openSeatActions(seat), child: wrapped);
    if (empty && !isHost && !quickMatch && seat >= 0) return InkWell(borderRadius: BorderRadius.circular(18), onTap: () => unawaited(_sitAt(seat)), child: wrapped);
    if (explicitBot && isHost && seat >= 0) return InkWell(borderRadius: BorderRadius.circular(18), onTap: () => _showBotSeatMenu(seat), child: wrapped);
    if (!bot && seat >= 0) return InkWell(borderRadius: BorderRadius.circular(18), onTap: () => _showPlayerCard(player), onLongPress: kickable ? () => _confirmKickPlayer(seat, name) : null, child: wrapped);
    return wrapped;
  }

  Future<void> _toggleReady(bool ready) async {
    try {
      final out = await _api.setReady(ready);
      if (out['ok'] == true) {
        unawaited(GameAudio.sfx(ready ? 'reward' : 'ui_tap', enabled: _soundEnabled, volume: .7));
        if (_vibrationEnabled) unawaited(HapticFeedback.mediumImpact());
      }
    } catch (_) {
      _tableNotice('Hazır durumu gönderilemedi.');
    }
  }

  /// Oyuncu (ya da masa sahibi) bekleme odasında boş bir koltuğa geçer.
  /// Eşli oyunda karşıdaki koltuk eşi olur; böylece kiminle eş olacağını seçer.
  Future<void> _sitAt(int seat) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final out = await _api.changeSeat(seat);
      if (out['ok'] == true) {
        unawaited(GameAudio.sfx('tile_drop', enabled: _soundEnabled, volume: .7));
        if (_vibrationEnabled) unawaited(HapticFeedback.selectionClick());
        _tableNotice('${seat + 1}. koltuğa geçtin.');
      } else {
        _tableNotice(out['code'] == 'seat_not_free' ? 'Bu koltuk az önce doldu.' : 'Koltuk değiştirilemedi.');
      }
    } catch (_) {
      _tableNotice('Koltuk değiştirilemedi. Bağlantını kontrol et.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openSeatActions(int seat) async {
    if (_busy) return;
    final choice = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Koltuk seç',
      barrierColor: const Color(0x99000000),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialogContext, _, __) => SafeArea(
        minimum: const EdgeInsets.all(8),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620, maxHeight: 390),
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 11, 14, 13),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xF2170F3F), Color(0xF20F0A28)]),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: OkeyXColors.ruby.withValues(alpha: .38)),
                  boxShadow: const [BoxShadow(color: Color(0xAA000000), blurRadius: 28, offset: Offset(0, 12))],
                ),
                child: LayoutBuilder(
                  builder: (context, c) => SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        const Icon(Icons.event_seat_rounded, color: OkeyXColors.ruby),
                        const SizedBox(width: 7),
                        Text('${seat + 1}. KOLTUK', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                        const Spacer(),
                        IconButton(onPressed: () => Navigator.pop(dialogContext), icon: const Icon(Icons.close_rounded)),
                      ]),
                      const Text('Bu koltuğa arkadaş çağır, bot ekle veya gerçek oyuncuya açık bırak.', style: TextStyle(fontSize: 9, color: Colors.white54)),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _seatActionCard(dialogContext, value: 'friend', title: 'ARKADAŞ', subtitle: 'Masaya davet et', icon: Icons.person_add_alt_1_rounded, color: OkeyXColors.mint, width: 134),
                          _seatActionCard(dialogContext, value: 'easy', title: 'KOLAY BOT', subtitle: 'Sakin tempo', icon: Icons.sentiment_satisfied_alt_rounded, color: OkeyXColors.mint, width: 134),
                          _seatActionCard(dialogContext, value: 'medium', title: 'NORMAL BOT', subtitle: 'Dengeli oyun', icon: Icons.smart_toy_rounded, color: OkeyXColors.cyan, width: 134),
                          _seatActionCard(dialogContext, value: 'hard', title: 'ZOR BOT', subtitle: 'Daha güçlü', icon: Icons.psychology_alt_rounded, color: OkeyXColors.gold, width: 134),
                          _seatActionCard(dialogContext, value: 'move', title: 'BURAYA GEÇ', subtitle: 'Kendi yerini değiştir', icon: Icons.event_seat_rounded, color: OkeyXColors.ruby, width: 134),
                          _seatActionCard(dialogContext, value: 'open', title: 'AÇIK BIRAK', subtitle: 'Oyuncu bekle', icon: Icons.public_rounded, color: Colors.white60, width: 134),
                        ],
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      transitionBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: ScaleTransition(scale: Tween<double>(begin: .96, end: 1).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)), child: child)),
    );
    if (choice == null || choice == 'open') return;
    if (choice == 'move') {
      await _sitAt(seat);
      return;
    }
    if (choice == 'friend') {
      if (widget.profile.isGuest) {
        _showAccountLinkRequired();
      } else {
        await _showInviteFriendDialog();
      }
      return;
    }
    await _setBotSeat(seat, choice);
  }

  Widget _seatActionCard(BuildContext dialogContext, {required String value, required String title, required String subtitle, required IconData icon, required Color color, required double width}) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => Navigator.pop(dialogContext, value),
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            width: width,
            height: 74,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: .07),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withValues(alpha: .24)),
            ),
            child: Row(children: [
              Container(width: 34, height: 34, decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: .12)), child: Icon(icon, color: color, size: 18)),
              const SizedBox(width: 8),
              Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900)),
                Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9, color: Colors.white38)),
              ])),
            ]),
          ),
        ),
      );

  Future<void> _setBotSeat(int seat, String level) async {
    try {
      setState(() => _busy = true);
      final out = await _api.manageRoom(action: 'add_bot', targetSeat: seat, botLevel: level);
      final st = _map(out['state']);
      if (st.isNotEmpty && mounted) setState(() => _state = st);
      if (_vibrationEnabled) unawaited(HapticFeedback.mediumImpact());
    } catch (e) {
      if (mounted) setState(() => _error = _friendlyCode('$e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showBotFillMenu() async {
    if (_busy) return;
    final players = _list(_state['players']).map(_map).toList();
    final emptySeats = players.where((p) => p['empty'] == true && _integer(p['seat'], fallback: -1) >= 0 && _integer(p['seat']) != _viewerSeat).map((p) => _integer(p['seat'])).toList();
    if (emptySeats.isEmpty) {
      _tableNotice('Boş koltuk yok. Botun üstüne dokunarak zorluğunu değiştirebilirsin.');
      return;
    }
    final choice = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Bot ekle',
      barrierColor: const Color(0x99000000),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialogContext, _, __) => SafeArea(
        minimum: const EdgeInsets.all(8),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700, maxHeight: 360),
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 13),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xF2170F3F), Color(0xF20F0A28)]),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: OkeyXColors.gold.withValues(alpha: .28)),
                  boxShadow: const [BoxShadow(color: Color(0xAA000000), blurRadius: 30, offset: Offset(0, 12))],
                ),
                child: LayoutBuilder(builder: (context, c) {
                  final cardWidth = c.maxWidth < 520 ? (c.maxWidth - 8) / 2 : (c.maxWidth - 16) / 3;
                  return SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        const Icon(Icons.smart_toy_rounded, color: OkeyXColors.gold),
                        const SizedBox(width: 7),
                        const Expanded(child: Text('BOT EKLE', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
                        Text('${emptySeats.length} boş koltuk', style: const TextStyle(fontSize: 9, color: Colors.white54)),
                        IconButton(onPressed: () => Navigator.pop(dialogContext), icon: const Icon(Icons.close_rounded)),
                      ]),
                      const Text('Botları eklemek maçı başlatmaz. Koltuklar dolunca OYUNU BAŞLAT düğmesine sen basarsın.', style: TextStyle(fontSize: 9, color: Colors.white60)),
                      const SizedBox(height: 10),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        _botFillCard(dialogContext, value: 'easy', title: 'KOLAY', subtitle: 'Sakin tempo', icon: Icons.sentiment_satisfied_alt_rounded, color: OkeyXColors.mint, width: cardWidth, count: emptySeats.length),
                        _botFillCard(dialogContext, value: 'medium', title: 'NORMAL', subtitle: 'Dengeli oyun', icon: Icons.smart_toy_rounded, color: OkeyXColors.cyan, width: cardWidth, count: emptySeats.length),
                        _botFillCard(dialogContext, value: 'hard', title: 'ZOR', subtitle: 'Daha güçlü rakip', icon: Icons.psychology_alt_rounded, color: OkeyXColors.gold, width: cardWidth, count: emptySeats.length),
                      ]),
                      const SizedBox(height: 9),
                      const Row(children: [Icon(Icons.info_outline_rounded, size: 12, color: Colors.white38), SizedBox(width: 5), Expanded(child: Text('Tek bir koltuğa farklı zorluk eklemek için masadaki boş koltuğa dokun.', style: TextStyle(fontSize: 9, color: Colors.white38)))]),
                    ]),
                  );
                }),
              ),
            ),
          ),
        ),
      ),
      transitionBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: ScaleTransition(scale: Tween<double>(begin: .96, end: 1).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)), child: child)),
    );
    if (choice == null) return;
    setState(() => _busy = true);
    try {
      for (final seat in emptySeats) {
        final out = await _api.manageRoom(action: 'add_bot', targetSeat: seat, botLevel: choice);
        final st = _map(out['state']);
        if (st.isNotEmpty && mounted) setState(() => _state = st);
      }
      if (_vibrationEnabled) unawaited(HapticFeedback.mediumImpact());
      _tableNotice('${emptySeats.length} koltuk ${choice == 'hard' ? 'zor' : choice == 'easy' ? 'kolay' : 'normal'} botla doldu • OYUNU BAŞLAT düğmesine sen bas.');
    } catch (e) {
      if (mounted) setState(() => _error = _friendlyCode('$e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _botFillCard(BuildContext dialogContext, {required String value, required String title, required String subtitle, required IconData icon, required Color color, required double width, required int count}) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => Navigator.pop(dialogContext, value),
          borderRadius: BorderRadius.circular(17),
          child: Ink(
            width: width,
            height: 92,
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [color.withValues(alpha: .10), Colors.black12]),
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: color.withValues(alpha: .30)),
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, color: color, size: 25),
              const SizedBox(height: 5),
              Text('$title BOT', maxLines: 1, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900)),
              Text('$count koltuğu doldur • $subtitle', maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 9, color: Colors.white54)),
            ]),
          ),
        ),
      );

  Future<void> _showBotSeatMenu(int seat) async {
    if (_busy) return;
    final current = _list(_state['players']).map(_map).firstWhere((x) => _integer(x['seat']) == seat, orElse: () => const {});
    final explicit = current['explicit_bot'] == true;
    final choice = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Bot ayarı',
      barrierColor: const Color(0x99000000),
      pageBuilder: (dialogContext, _, __) => SafeArea(
        minimum: const EdgeInsets.all(8),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560, maxHeight: 340),
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xF2170F3F), Color(0xF20F0A28)]), borderRadius: BorderRadius.circular(22), border: Border.all(color: OkeyXColors.cyan.withValues(alpha: .25))),
                child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Row(children: [const Icon(Icons.smart_toy_rounded, color: OkeyXColors.gold), const SizedBox(width: 7), Expanded(child: Text(explicit ? 'BOT AYARI' : 'BOT EKLE', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15))), IconButton(onPressed: () => Navigator.pop(dialogContext), icon: const Icon(Icons.close_rounded))]),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    if (explicit) _seatActionCard(dialogContext, value: 'remove', title: 'BOTU KALDIR', subtitle: 'Koltuk boşalsın', icon: Icons.person_remove_rounded, color: OkeyXColors.danger, width: 120),
                    _seatActionCard(dialogContext, value: 'easy', title: 'KOLAY', subtitle: 'Sakin tempo', icon: Icons.sentiment_satisfied_alt_rounded, color: OkeyXColors.mint, width: 120),
                    _seatActionCard(dialogContext, value: 'medium', title: 'NORMAL', subtitle: 'Dengeli oyun', icon: Icons.smart_toy_rounded, color: OkeyXColors.cyan, width: 120),
                    _seatActionCard(dialogContext, value: 'hard', title: 'ZOR', subtitle: 'Güçlü rakip', icon: Icons.psychology_alt_rounded, color: OkeyXColors.gold, width: 120),
                  ]),
                ])),
              ),
            ),
          ),
        ),
      ),
    );
    if (choice == null) return;
    try {
      final out = await _api.manageRoom(action: choice == 'remove' ? 'remove_bot' : 'add_bot', targetSeat: seat, botLevel: choice == 'remove' ? null : choice);
      final st = _map(out['state']);
      if (st.isNotEmpty && mounted) setState(() => _state = st);
      if (choice != 'remove') _tableNotice('Bot hazır • Maçı sen başlatacaksın.');
    } catch (e) {
      if (mounted) setState(() => _error = _friendlyCode('$e'));
    }
  }



  Widget _waitingMetric(String label, String value, IconData icon, {bool warning = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
          decoration: BoxDecoration(color: warning ? const Color(0x33170E41) : Colors.white.withValues(alpha: .035), borderRadius: BorderRadius.circular(11), border: Border.all(color: warning ? OkeyXColors.gold.withValues(alpha: .34) : Colors.white10)),
          child: Row(children: [Icon(icon, size: 14, color: warning ? OkeyXColors.gold : Color(0x73FFFFFF)), const SizedBox(width: 7), Expanded(child: Text(label, style: const TextStyle(fontSize: 9, color: Color(0x73FFFFFF), fontWeight: FontWeight.w900))), Text(value, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: warning ? OkeyXColors.gold : Colors.white))]),
        ),
      );

  Future<void> _startMatchFromWaiting(int required, int current) async {
    if (current < required) {
      await _leaveForStore();
      return;
    }
    await _act('start_match');
  }

  Future<void> _leaveWaitingRoom() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final out = await _api.leave();
      if (out['ok'] != true) {
        if (mounted) setState(() => _error = 'Odadan ayrılamadın: ${out['code'] ?? 'hata'}');
        return;
      }
      await widget.onClose?.call();
      if (mounted) Navigator.of(context).pop('lobby');
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyCode('$error'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leaveForStore() async {
    if (_busy) return;
    setState(() => _busy = true);
    try { await _api.leave(); } catch (_) {}
    await widget.onClose?.call();
    if (mounted) Navigator.of(context).pop('store');
  }

  void _showAccountLinkRequired() {
    if (!mounted) return;
    setState(() => _error = 'Arkadaşlık ve masa daveti için Google veya e-posta hesabını bağla.');
  }

  Future<void> _showInviteFriendDialog() async {
    try {
      final friends = await _api.friends();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierColor: const Color(0xB800070C),
        builder: (dialogContext) {
          final size = MediaQuery.sizeOf(dialogContext);
          return Dialog(
            backgroundColor: const Color(0xFF160F3C),
            insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 18),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: OkeyXColors.mint.withValues(alpha: .28))),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 520, maxHeight: size.height * .78),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Row(children: [
                    const Icon(Icons.group_add_rounded, color: OkeyXColors.mint, size: 20),
                    const SizedBox(width: 8),
                    const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('ARKADAŞLARINI DAVET ET', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
                      Text('Masaya çağırmak istediğin arkadaşına dokun.', style: TextStyle(fontSize: 9, color: Colors.white54)),
                    ])),
                    IconButton(onPressed: () => Navigator.pop(dialogContext), icon: const Icon(Icons.close_rounded, size: 19)),
                  ]),
                  const SizedBox(height: 7),
                  if (friends.isEmpty)
                    const Padding(padding: EdgeInsets.symmetric(vertical: 22), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.group_off_rounded, color: Colors.white30), SizedBox(width: 8), Text('Henüz davet edebileceğin arkadaşın yok.', style: TextStyle(fontSize: 9, color: Colors.white54))]))
                  else
                    Flexible(child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: friends.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 5),
                      itemBuilder: (_, i) {
                        final friend = friends[i];
                        final online = friend['online'] == true;
                        final inGame = friend['in_game'] == true;
                        final id = '${friend['id'] ?? friend['user_id'] ?? ''}'.trim();
                        final name = '${friend['name'] ?? 'Oyuncu'}';
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: .035), borderRadius: BorderRadius.circular(13), border: Border.all(color: Colors.white10)),
                          child: Row(children: [
                            CircleAvatar(radius: 16, backgroundColor: const Color(0xFF251864), child: Text(name.isEmpty ? '?' : name.substring(0,1).toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900))),
                            const SizedBox(width: 9),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900)),
                              Text(inGame ? 'Masada' : (online ? 'Çevrimiçi' : 'Çevrimdışı'), style: TextStyle(fontSize: 9, color: online ? OkeyXColors.mint : Colors.white38)),
                            ])),
                            FilledButton.tonal(
                              onPressed: id.isEmpty || !online || inGame ? null : () async {
                                final out = await _api.inviteFriend(id);
                                if (!mounted) return;
                                Navigator.pop(dialogContext);
                                _tableNotice(out['ok'] == true ? '$name masaya davet edildi.' : 'Davet gönderilemedi: ${out['code'] ?? 'hata'}');
                              },
                              child: Text(inGame ? 'MASADA' : (online ? 'DAVET ET' : 'ÇEVRİMDIŞI'), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900)),
                            ),
                          ]),
                        );
                      },
                    )),
                ]),
              ),
            ),
          );
        },
      );
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyCode('$error'));
    }
  }

  Future<void> _confirmKickPlayer(int seat, String name) async {
    final ok = await showDialog<bool>(context:context,builder:(dialogContext)=>AlertDialog(
      title: const Text('Oyuncuyu masadan çıkar'),
      content: Text('$name bekleme odasından çıkarılsın mı?'),
      actions:[TextButton(onPressed:()=>Navigator.pop(dialogContext,false),child:const Text('VAZGEÇ')),FilledButton(onPressed:()=>Navigator.pop(dialogContext,true),child:const Text('ÇIKAR'))],
    ));
    if(ok!=true)return;
    try{final out=await _api.manageRoom(action:'kick',targetSeat:seat);if(mounted)setState(()=>_error=out['ok']==true?'$name masadan çıkarıldı.':'Oyuncu çıkarılamadı.');}catch(error){if(mounted)setState(()=>_error=_friendlyCode('$error'));}
  }

  Future<void> _showRoomSettingsDialog() async {
    final name=TextEditingController(text:'${_state['room_name'] ?? 'OkeyX Masası'}');
    var seconds=_integer(_state['turn_seconds'],fallback:35).clamp(15,90);
    var turbo=_state['turbo']==true;
    var assisted=_state['assisted']!=false;
    var chatEnabled=_state['chat_enabled']!=false;
    var giftsEnabled=_state['gifts_enabled']!=false;
    var autoRematch=_state['auto_rematch']==true;
    var variant='${_state['variant'] ?? 'non_fold'}';
    var teamMode='${_state['team_mode'] ?? 'solo'}';
    var rounds=_integer(_state['max_rounds'],fallback:3).clamp(1,3);
    var entry=_integer(_state['entry_fee'],fallback:5000).clamp(1000,1000000);
    const fees=<int>[1000,5000,10000,25000,50000,100000,250000,500000];
    try{
      final save=await showDialog<bool>(context:context,builder:(dialogContext)=>StatefulBuilder(builder:(context,setLocal)=>AlertDialog(
        backgroundColor:const Color(0xFF160E3A),
        title:const Row(children:[Icon(Icons.tune_rounded,color:OkeyXColors.gold),SizedBox(width:8),Text('Masa ayarları')]),
        content:SizedBox(width:430,child:SingleChildScrollView(padding:const EdgeInsets.only(top:12),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
          // Üstte boşluk: kayan etiket ('Masa adı') kırpılmasın.
          TextField(controller:name,maxLength:28,decoration:const InputDecoration(labelText:'Masa adı',counterText:'',prefixIcon:Icon(Icons.edit_rounded,size:18))),
          const SizedBox(height:6),
          Row(children:[const Text('Hamle süresi'),const Spacer(),Text('$seconds sn',style:const TextStyle(fontWeight:FontWeight.w900))]),
          Slider(value:seconds.toDouble(),min:15,max:90,divisions:15,label:'$seconds sn',onChanged:(v)=>setLocal(()=>seconds=v.round())),
          const Text('GİRİŞ',style:TextStyle(fontSize:9,color:OkeyXColors.gold,fontWeight:FontWeight.w900)),
          const SizedBox(height:5),
          Wrap(spacing:6,runSpacing:5,children:[for(final fee in fees) ChoiceChip(label:Text(_compactMoney(fee)),selected:entry==fee,onSelected:(_)=>setLocal(()=>entry=fee))]),
          const SizedBox(height:9),
          Row(children:[Expanded(child:DropdownButtonFormField<String>(initialValue:variant,decoration:const InputDecoration(labelText:'Kural'),items:const [DropdownMenuItem(value:'non_fold',child:Text('Katlamasız')),DropdownMenuItem(value:'fold',child:Text('Katlamalı'))],onChanged:(v)=>setLocal(()=>variant=v ?? variant))),const SizedBox(width:8),Expanded(child:DropdownButtonFormField<String>(initialValue:teamMode,decoration:const InputDecoration(labelText:'Takım'),items:const [DropdownMenuItem(value:'solo',child:Text('Herkes tek')),DropdownMenuItem(value:'paired',child:Text('Eşli'))],onChanged:(v)=>setLocal(()=>teamMode=v ?? teamMode)))]),
          const SizedBox(height:7),
          Row(children:[const Text('El sayısı'),const Spacer(),for(final n in const [1,2,3]) Padding(padding:const EdgeInsets.only(left:5),child:ChoiceChip(label:Text('$n'),selected:rounds==n,onSelected:(_)=>setLocal(()=>rounds=n)))]),
          SwitchListTile(contentPadding:EdgeInsets.zero,dense:true,title:const Text('Turbo'),subtitle:Text(turbo?'Giriş için 10× rezerv gerekir':'Standart masa'),value:turbo,onChanged:(v)=>setLocal(()=>turbo=v)),
          SwitchListTile(contentPadding:EdgeInsets.zero,dense:true,title:const Text('Yardımlı'),subtitle:const Text('İşler taş / dizme yardımı'),value:assisted,onChanged:(v)=>setLocal(()=>assisted=v)),
          SwitchListTile(contentPadding:EdgeInsets.zero,dense:true,title:const Text('Sohbet'),value:chatEnabled,onChanged:(v)=>setLocal(()=>chatEnabled=v)),
          SwitchListTile(contentPadding:EdgeInsets.zero,dense:true,title:const Text('Masa hediyeleri'),value:giftsEnabled,onChanged:(v)=>setLocal(()=>giftsEnabled=v)),
          SwitchListTile(contentPadding:EdgeInsets.zero,dense:true,title:const Text('Otomatik yeniden maç'),value:autoRematch,onChanged:(v)=>setLocal(()=>autoRematch=v)),
          const Text('Oyun başladıktan sonra masa kuralları kilitlenir.',style:TextStyle(fontSize:9,color:Colors.white38)),
        ]))),
        actions:[TextButton(onPressed:()=>Navigator.pop(dialogContext,false),child:const Text('VAZGEÇ')),FilledButton(onPressed:()=>Navigator.pop(dialogContext,true),child:const Text('KAYDET'))],
      )));
      if(save==true){
        final out=await _api.manageRoom(action:'settings',roomName:name.text,turnSeconds:seconds,turbo:turbo,variant:variant,teamMode:teamMode,entryFee:entry,rounds:rounds,assisted:assisted,chatEnabled:chatEnabled,giftsEnabled:giftsEnabled,autoRematch:autoRematch);
        if(out['ok']!=true){if(mounted)setState(()=>_error=_friendlyCode('${out['code'] ?? 'settings_failed'}'));return;}
        final state=_map(out['state']);if(state.isNotEmpty)_receiveState(state);
      }
    }catch(error){if(mounted)setState(()=>_error=_friendlyCode('$error'));}finally{name.dispose();}
  }


  Widget _loadingPanel() => ColoredBox(
        color: const Color(0xEE0B071E),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth:420),
            padding: const EdgeInsets.symmetric(horizontal:24,vertical:20),
            decoration:BoxDecoration(
              gradient:const LinearGradient(colors:[Color(0xE81B124A),Color(0xEF100A2B)]),
              borderRadius:BorderRadius.circular(24),
              border:Border.all(color:OkeyXColors.cyan.withValues(alpha:.25)),
              boxShadow:const [BoxShadow(color:Colors.black54,blurRadius:24,offset:Offset(0,12))],
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const _TableLoadingTiles(),
              const SizedBox(height: 12),
              Text(_error.isEmpty ? 'MASA HAZIRLANIYOR' : 'BAĞLANTI BEKLİYOR', style:const TextStyle(fontSize:13,fontWeight:FontWeight.w900,letterSpacing:.8)),
              const SizedBox(height:4),
              Text(_error.isEmpty ? 'Taşlar karışıyor • oyuncular senkronlanıyor' : _error, textAlign:TextAlign.center,style: TextStyle(fontSize:9,color:_error.isEmpty?Colors.white54:OkeyXColors.gold,fontWeight:FontWeight.w700)),
              const SizedBox(height:10),
              ClipRRect(borderRadius:BorderRadius.circular(99),child:const LinearProgressIndicator(minHeight:5)),
              if (_error.isNotEmpty) Padding(padding:const EdgeInsets.only(top:10),child:FilledButton.icon(onPressed:_start,icon:const Icon(Icons.refresh_rounded,size:15),label:const Text('TEKRAR DENE'))),
            ]),
          ),
        ),
      );

  Widget _roomClosedDialog() => Material(
        color: const Color(0xCC000000),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: OkxLeather(
                radius: 24,
                stitch: true,
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                borderColor: OkeyXColors.ruby.withValues(alpha: .82),
                shadows: const [BoxShadow(color: Colors.black87, blurRadius: 34, offset: Offset(0, 14))],
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 58, height: 58, decoration: BoxDecoration(shape: BoxShape.circle, color: OkeyXColors.ruby.withValues(alpha: .13), border: Border.all(color: OkeyXColors.ruby.withValues(alpha: .55))), child: const Icon(Icons.link_off_rounded, size: 27, color: OkeyXColors.ruby)),
                  const SizedBox(height: 14),
                  const Text('MASA KAPANDI', style: TextStyle(fontFamily: OkeyXFonts.serif, fontSize: 22, fontWeight: FontWeight.w800, color: OkeyXColors.cream)),
                  const SizedBox(height: 7),
                  const Text('Masa artık mevcut değil. Lobiye dönüp yeni bir masaya katılabilirsin.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, height: 1.45, color: OkeyXColors.muted, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 18),
                  OkxButton(label: 'ANA EKRANA DÖN', icon: Icons.home_rounded, style: OkxButtonStyle.red, height: 48, expand: true, onTap: _closeTable),
                ]),
              ),
            ),
          ),
        ),
      );

  Widget _errorBanner() => Material(
        color: const Color(0xF0120C35),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Color(0xAAD9A94A), width: 1.2)),
        elevation: 8,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            children: [
              const Icon(Icons.info_rounded, size: 17, color: Color(0xFFFFD98A)),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  _error,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w800),
                ),
              ),
              if (_error.contains('Masa artık mevcut değil') || _error.contains('Aktif masa bulunamadı'))
                TextButton(onPressed: _closeTable, child: const Text('LOBİYE DÖN', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900))),
              IconButton(
                onPressed: () => setState(() => _error = ''),
                icon: const Icon(Icons.close, size: 16),
              ),
            ],
          ),
        ),
      );

  Widget _rageQuitOverlay()=>LayoutBuilder(builder:(context,constraints){
    final size=Size(constraints.maxWidth,constraints.maxHeight);
    final anchor=_reactionAnchor(_rageSeat,size);
    return TweenAnimationBuilder<double>(
      key:ValueKey(_rageEventKey),
      tween:Tween(begin:0,end:1),
      duration:(widget.preferences.reducedMotionEnabled||widget.preferences.dataSaverEnabled)?Duration.zero:const Duration(milliseconds:1900),
      curve:Curves.bounceOut,
      builder:(context,v,_)=>Stack(children:[
        Positioned(left:(anchor.dx-25).clamp(2.0,size.width-50),top:(-60+(anchor.dy-44+60)*v).clamp(-60.0,size.height-50),child:Transform.rotate(angle:(1-v)*-.8,child:Container(width:50,height:50,decoration:BoxDecoration(shape:BoxShape.circle,color:const Color(0xFF22165E),border:Border.all(color:OkeyXColors.cyan,width:2),boxShadow:const [BoxShadow(color:Color(0x8866E8FF),blurRadius:15)]),child:const Icon(Icons.smart_toy_rounded,color:OkeyXColors.cyan,size:28)))),
        if(v>.58)Positioned(left:(anchor.dx-70).clamp(2.0,size.width-140),top:(anchor.dy+17).clamp(2.0,size.height-27),width:140,child:Opacity(opacity:(1-v).clamp(.15,1),child:Container(padding:const EdgeInsets.symmetric(horizontal:7,vertical:4),decoration:BoxDecoration(color:const Color(0xE9140D38),borderRadius:BorderRadius.circular(10),border:Border.all(color:OkeyXColors.cyan)),child:const Text('ROBOT KASKI İNDİ • BOT DEVİRDE',textAlign:TextAlign.center,style:TextStyle(fontSize:9,fontWeight:FontWeight.w900,color:OkeyXColors.cyan))))),
      ]),
    );
  });

  Widget _finishCelebration() {
    final flags = _map(_state['round_finish_flags']);
    final pair = flags['pair_finish'] == true;
    final joker = flags['joker_finish'] == true;
    final single = flags['single_turn_finish'] == true;
    final cancelled = '${_state['round_end_reason']}'.contains('cancel');
    final winnerSeat = _integer(_state['winner_seat'], fallback: -1);
    final winner = _list(_state['players']).map(_map).firstWhere((p) => _integer(p['seat']) == winnerSeat, orElse: () => const <String,dynamic>{});
    final victoryFx = '${_map(winner['loadout'])['victory_fx'] ?? 'victory_fx_classic'}';
    final baseIcon = joker ? Icons.auto_awesome_rounded : pair ? Icons.looks_two_rounded : cancelled ? Icons.block_rounded : Icons.emoji_events_rounded;
    final icon = switch(victoryFx){
      'victory_fx_crown'=>Icons.workspace_premium_rounded,
      'victory_fx_ice'=>Icons.ac_unit_rounded,
      'victory_fx_ember'=>Icons.local_fire_department_rounded,
      'victory_fx_rose'=>Icons.local_florist_rounded,
      'victory_fx_neon'=>Icons.bolt_rounded,
      _=>baseIcon,
    };
    final text = cancelled
        ? 'EL İPTAL'
        : winnerSeat == _viewerSeat
            ? (joker ? 'OKEY DARBESİ!' : pair ? 'ÇİFT BİTİRDİN!' : single ? 'TEK ELDE ŞOV!' : 'ELİ KAZANDIN!')
            : (joker ? 'OKEY DARBESİ' : pair ? 'ÇİFT BİTİŞ' : single ? 'TEK ELDE BİTİŞ' : 'EL TAMAMLANDI');
    final ruleColor = joker ? const Color(0xFFFFD64D) : pair ? const Color(0xFF8BFFCB) : const Color(0xFFFF8B9D);
    final color = switch(victoryFx){
      'victory_fx_gold'=>const Color(0xFFFFC54D),
      'victory_fx_mint'=>const Color(0xFF74F1C2),
      'victory_fx_neon'=>const Color(0xFF66E8FF),
      'victory_fx_rose'=>const Color(0xFFFF8FB5),
      'victory_fx_ice'=>const Color(0xFFA7EEFF),
      'victory_fx_ember'=>const Color(0xFFFF8955),
      'victory_fx_crown'=>const Color(0xFFFFD76A),
      _=>ruleColor,
    };
    final particle = switch(victoryFx){
      'victory_fx_gold'=>'✦','victory_fx_mint'=>'◆','victory_fx_neon'=>'⚡','victory_fx_rose'=>'🌹','victory_fx_ice'=>'❄','victory_fx_ember'=>'🔥','victory_fx_crown'=>'♛',_=>'✨'
    };
    final reduced=widget.preferences.reducedMotionEnabled || widget.preferences.dataSaverEnabled;
    return IgnorePointer(
      child: ColoredBox(
        color: const Color(0xA6000710),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if((joker||pair||single)&&!cancelled&&!reduced)
              for(var ring=0;ring<3;ring++)
                TweenAnimationBuilder<double>(
                  key:ValueKey('shock-$_shownRoundKey-$ring'),
                  tween:Tween(begin:0,end:1),
                  duration:Duration(milliseconds:820+ring*190),
                  curve:Curves.easeOut,
                  builder:(context,v,_)=>Opacity(opacity:(1-v).clamp(0,1),child:Transform.scale(scale:.3+v*(1.45+ring*.30),child:Container(width:150,height:150,decoration:BoxDecoration(shape:BoxShape.circle,border:Border.all(color:color.withValues(alpha:.9),width:3-ring*.55),boxShadow:[BoxShadow(color:color.withValues(alpha:.25),blurRadius:18)])))),
                ),
            if((joker||pair||single)&&!cancelled&&!reduced)
              for(var i=0;i<8;i++)
                TweenAnimationBuilder<double>(
                  key:ValueKey('fly-tile-$_shownRoundKey-$i'),
                  tween:Tween(begin:0,end:1),
                  duration:Duration(milliseconds:850+(i%3)*150),
                  curve:Curves.easeOutCubic,
                  builder:(context,v,child){final a=(i/8)*math.pi*2;return Transform.translate(offset:Offset(math.cos(a)*185*v,math.sin(a)*105*v-46*v),child:Transform.rotate(angle:(i.isEven?1:-1)*v*4.5,child:Opacity(opacity:(1-v*.75).clamp(0,1),child:child)));},
                  child:Container(width:23,height:32,alignment:Alignment.center,decoration:BoxDecoration(color:const Color(0xFFFFFBEB),borderRadius:BorderRadius.circular(4),border:Border.all(color:color),boxShadow:const [BoxShadow(color:Colors.black54,blurRadius:4)]),child:Text('${(i%13)+1}',style:TextStyle(color:[const Color(0xFFD12C37),const Color(0xFF245FB4),const Color(0xFF141414),const Color(0xFFE09A16)][i%4],fontSize:11,fontWeight:FontWeight.w900))),
                ),
            if(!cancelled && !reduced)
              for(var i=0;i<12;i++)
                TweenAnimationBuilder<double>(
                  key: ValueKey('fx-$victoryFx-$_shownRoundKey-$i'),
                  tween: Tween(begin:0,end:1),
                  duration: Duration(milliseconds:650+(i%4)*120),
                  curve: Curves.easeOutCubic,
                  builder:(context,v,child){
                    final angle=(i/12)*6.28318;
                    final radius=54+92*v;
                    return Transform.translate(offset:Offset(math.cos(angle)*radius,math.sin(angle)*radius*.48),child:Opacity(opacity:(1-v).clamp(0,1),child:Transform.scale(scale:.55+.55*(1-v),child:child)));
                  },
                  child:Text(particle,style:TextStyle(fontSize:14+(i%3)*3.0,color:color,shadows:[Shadow(color:color,blurRadius:9)])),
                ),
            TweenAnimationBuilder<double>(
              key: ValueKey(_shownRoundKey),
              duration: reduced ? Duration.zero : const Duration(milliseconds: 720),
              tween: Tween(begin: 0, end: 1),
              curve: Curves.elasticOut,
              builder: (context, value, child) => Opacity(
                opacity: value.clamp(0, 1),
                child: Transform.scale(scale: .25 + (.75 * value), child: child),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [color.withValues(alpha: .34), Colors.black87]),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: color, width: 2),
                  boxShadow: [BoxShadow(color: color.withValues(alpha: .45), blurRadius: 30)],
                ),
                child: Column(mainAxisSize:MainAxisSize.min,children:[
                  if(joker&&!cancelled)TweenAnimationBuilder<double>(tween:Tween(begin:-1,end:0),duration:reduced?Duration.zero:const Duration(milliseconds:560),curve:Curves.bounceOut,builder:(context,v,child)=>Transform.translate(offset:Offset(0,v*120),child:Transform.rotate(angle:v*.6,child:child)),child:Container(width:34,height:48,alignment:Alignment.center,decoration:BoxDecoration(color:const Color(0xFFFFFBEB),borderRadius:BorderRadius.circular(6),border:Border.all(color:color,width:2)),child:const Text('★',style:TextStyle(color:Color(0xFFE83945),fontSize:23,fontWeight:FontWeight.w900)))),
                  if(joker&&!cancelled)const SizedBox(height:7),
                  Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, color: color, size: 42),const SizedBox(width: 13),Text(text, style: TextStyle(color: color,fontSize:25,fontWeight:FontWeight.w900,letterSpacing:1.4))]),
                  if(joker&&!cancelled)const Padding(padding:EdgeInsets.only(top:4),child:Text('ŞOK DALGASI • TAŞLAR HAVADA',style:TextStyle(fontSize:9,color:Colors.white60,fontWeight:FontWeight.w900,letterSpacing:.8))),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _musicKitAsset(String id)=>switch(id){
    'music_kit_anadolu'=>'music_kit_anadolu.wav',
    'music_kit_retro'=>'music_kit_retro.wav',
    'music_kit_tokyo'=>'music_kit_tokyo.wav',
    'music_kit_istanbul'=>'music_kit_istanbul.wav',
    'music_kit_ege'=>'music_kit_ege.wav',
    'music_kit_bosphorus'=>'music_kit_bosphorus.wav',
    'music_kit_arcade'=>'music_kit_arcade.wav',
    'music_kit_sakura'=>'music_kit_sakura.wav',
    'music_kit_finalboss'=>'music_kit_finalboss.wav',
    _=>'victory_soft.wav'
  };
  void _playWinnerKit(){if(_state['match_finished']!=true)return;final key='${_state['room_id']}-${_state['round_index']}-${_state['winner_seat']}';if(_playedMusicKitRoundKey==key)return;_playedMusicKitRoundKey=key;final settlement=_map(_state['settlement']);final ws=_integer(settlement['winner_seat'],fallback:_integer(_state['winner_seat'],fallback:-1));if(ws<0||(ws!=_viewerSeat&&!widget.preferences.opponentMusicKits))return;final winner=_list(_state['players']).map(_map).firstWhere((x)=>_integer(x['seat'])==ws,orElse:()=>const<String,dynamic>{});final kit='${_map(winner['loadout'])['music_kit']??'music_kit_classic'}';unawaited(GameAudio.playMusicKit(_musicKitAsset(kit),enabled:widget.preferences.musicEnabled||widget.preferences.radioEnabled));}

  void _queueRoundResult() {
    final key =
        '${_state['room_id']}-${_state['round_index']}-${_state['round_end_reason']}';
    if (_shownRoundKey == key) return;
    _shownRoundKey = key;
    _playWinnerKit();
    final flags=_map(_state['round_finish_flags']);
    final cinematic=flags['joker_finish']==true||flags['pair_finish']==true||flags['single_turn_finish']==true;
    if(cinematic){
      unawaited(GameAudio.sfx('shockwave',enabled:_soundEnabled,volume:.94));
      Future<void>.delayed(const Duration(milliseconds:180),()=>unawaited(GameAudio.sfx('glass_break',enabled:_soundEnabled,volume:.74)));
    }
    if (_vibrationEnabled) {
      unawaited(HapticFeedback.heavyImpact());
    }
    final wait = widget.preferences.reducedMotionEnabled || widget.preferences.dataSaverEnabled
        ? const Duration(milliseconds: 80)
        : Duration(milliseconds:cinematic?1950:900);
    Future<void>.delayed(wait, () {
      if (mounted && '${_state['phase']}' == 'finished') {
        unawaited(_showRoundResult());
      }
    });
  }

  Future<void> _showRoundResult() async {
    final players = _list(_state['players']).map(_map).toList();
    final scores = _map(_state['round_scores']);
    final totals = _map(_state['total_scores']);
    final breakdown = _map(_state['round_breakdown']);
    final finished = _state['match_finished'] == true;
    final flags = _map(_state['round_finish_flags']);
    final settlement = _map(_state['settlement']);
    final rankings = _list(settlement['rankings']).map(_map).toList();
    final viewerSeat = _integer(_state['viewer_seat']);
    final viewerSettlement = rankings.firstWhere(
      (row) => _integer(row['seat']) == viewerSeat,
      orElse: () => const <String, dynamic>{},
    );
    final viewerDelta = _integer(viewerSettlement['delta']);
    if (finished && settlement.isNotEmpty) {
      debugPrint('OKEYX_SETTLEMENT: room=${_state['room_id']} stake=${settlement['stake']} multiplier=${settlement['multiplier']} delta=$viewerDelta commission=${viewerSettlement['commission']} balance=${viewerSettlement['balance_after']}');
    }
    final viewerRank = _integer(viewerSettlement['rank'], fallback: 99);
    final winningSeats = _list(settlement['winner_seats']).map((e) => _integer(e)).toSet();
    final viewerWon = finished && (winningSeats.isNotEmpty ? winningSeats.contains(viewerSeat) : viewerRank <= 2);
    if (finished) {
      unawaited(GameAudio.sfx(viewerWon ? 'win' : 'lose', enabled: _soundEnabled, volume: .70));
      if (viewerWon && viewerDelta > 0) {
        Future<void>.delayed(const Duration(milliseconds: 650), () => unawaited(GameAudio.sfx('coin_shower', enabled: _soundEnabled, volume: .7)));
      }
    }

    final rows = <Map<String, dynamic>>[];
    if (rankings.isNotEmpty) {
      final sorted = List<Map<String, dynamic>>.from(rankings)
        ..sort((a, b) => _integer(a['rank']).compareTo(_integer(b['rank'])));
      for (final r in sorted) {
        final seat = _integer(r['seat']);
        final p = players.firstWhere((x) => _integer(x['seat']) == seat, orElse: () => const <String, dynamic>{});
        rows.add({
          'rank': _integer(r['rank']),
          'seat': seat,
          'name': r['name'] ?? p['name'] ?? 'Oyuncu',
          'remaining': _integer(r['remaining_points'], fallback: _integer(r['remaining'], fallback: _integer(_map(breakdown['$seat'])['remaining_points'], fallback: _integer(_map(breakdown['$seat'])['rack'])))),
          'remaining_count': _integer(r['remaining_tile_count'], fallback: _integer(_map(breakdown['$seat'])['remaining_tile_count'])),
          'round_score': _integer(scores['$seat']),
          'total': _integer(totals['$seat']),
          'delta': _integer(r['delta']),
          'note': _map(breakdown['$seat'])['note'] ?? '',
          'opening_mode': p['opening_mode'],
          'opening_value': p['opening_mode'] == 'pairs' ? _integer(p['opening_pairs']) : _integer(p['opening_score']),
        });
      }
    } else {
      final temp = <Map<String, dynamic>>[];
      for (final p in players) {
        final seat = _integer(p['seat']);
        temp.add({
          'seat': seat,
          'name': p['name'] ?? 'Oyuncu',
          'remaining': _integer(_map(breakdown['$seat'])['remaining_points'], fallback: _integer(_map(breakdown['$seat'])['rack'])),
          'remaining_count': _integer(_map(breakdown['$seat'])['remaining_tile_count']),
          'round_score': _integer(scores['$seat']),
          'total': _integer(totals['$seat']),
          'delta': 0,
          'note': _map(breakdown['$seat'])['note'] ?? '',
          'opening_mode': p['opening_mode'],
          'opening_value': p['opening_mode'] == 'pairs' ? _integer(p['opening_pairs']) : _integer(p['opening_score']),
        });
      }
      temp.sort((a, b) {
        final c = _integer(a['round_score']).compareTo(_integer(b['round_score']));
        return c != 0 ? c : _integer(a['remaining']).compareTo(_integer(b['remaining']));
      });
      for (var i = 0; i < temp.length; i++) {
        rows.add({...temp[i], 'rank': i + 1});
      }
    }

    final winnerSeat = _integer(settlement['winner_seat'], fallback: _integer(_state['winner_seat'], fallback: -1));
    final winner = players.firstWhere((p) => _integer(p['seat']) == winnerSeat, orElse: () => const <String, dynamic>{});
    final title = _state['round_end_reason'] == 'four_pairs_cancelled'
        ? 'EL İPTAL EDİLDİ'
        : finished
            ? (viewerWon ? 'KAZANDIN!' : 'KAYBETTİN')
            : winner.isNotEmpty
                ? (winnerSeat == viewerSeat ? 'ELİ KAZANDIN!' : '${winner['name']} ELİ KAZANDI')
                : 'EL TAMAMLANDI';
    final finishTag = flags['joker_finish'] == true
        ? 'OKEYLE BİTİŞ'
        : flags['pair_finish'] == true
            ? 'ÇİFT BİTİŞ'
            : flags['single_turn_finish'] == true
                ? 'TEK ELDE BİTİŞ'
                : _state['round_end_reason'] == 'stock_empty'
                    ? 'DESTE TÜKENDİ • PUANLAR HESAPLANDI'
                    : 'NORMAL BİTİŞ';

    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RoundResultDialog(
        title: title,
        finishTag: finishTag,
        rows: rows,
        matchFinished: finished,
        roundIndex: _integer(_state['round_index']),
        maxRounds: _integer(_state['max_rounds']),
        turbo: _state['turbo'] == true,
        multiplier: _integer(_state['multiplier']).clamp(1, 99).toInt(),
        stake: _integer(_state['entry_fee']),
        variant: _state['variant'] == 'fold' ? 'Katlamalı' : 'Katlamasız',
        viewerSeat: viewerSeat,
        viewerCommission: _integer(viewerSettlement['commission']),
        viewerBalance: viewerSettlement['balance_after'] == null ? null : _integer(viewerSettlement['balance_after']),
      ),
    );

    if (!mounted) return;
    if (!finished) {
      if (choice == 'next') {
        _shownRoundKey = null;
        await _act('new_hand');
      } else {
        await _closeTable();
      }
      return;
    }
    if (choice == 'rematch') {
      _shownRoundKey = null;
      await _requestRematch();
    } else {
      await _closeTable();
    }
  }

  Widget _settlementLine(String label, String value, {bool strong = false, bool? highlight}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(child: Text(label, style: TextStyle(fontSize: strong ? 8.5 : 7.5, color: strong ? Colors.white : Colors.white54, fontWeight: strong ? FontWeight.w900 : FontWeight.w600))),
            Text(
              value,
              style: TextStyle(
                fontSize: strong ? 10 : 8,
                fontWeight: FontWeight.w900,
                color: highlight == null ? Colors.white : (highlight ? OkeyXColors.mint : OkeyXColors.danger),
              ),
            ),
          ],
        ),
      );

  String _formatNumber(int value) => _compactMoney(value);

  String _compactMoney(int value) {
    final negative = value < 0;
    final abs = value.abs();
    String scaled(double divisor, String suffix, int digits) {
      var text = (abs / divisor).toStringAsFixed(digits);
      text = text.replaceFirst(RegExp(r'\.0+$'), '');
      text = text.replaceFirst(RegExp(r'(\.\d*[1-9])0+$'), r'$1');
      return '${negative ? '-' : ''}$text$suffix';
    }
    if (abs >= 1000000000) return scaled(1000000000.0, 'B', 2);
    if (abs >= 1000000) return scaled(1000000.0, 'M', 2);
    if (abs >= 1000) return scaled(1000.0, 'K', abs >= 100000 ? 1 : 2);
    return '$value';
  }
  String _money(int value) => '${value.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.')} altın';
  String _signedMoney(int value) => '${value >= 0 ? '+' : '-'}${_money(value.abs())}';

  Future<void> _showTableMenu() async {
    if (!mounted) return;
    final active = _state['started'] == true && '${_state['phase']}' != 'finished' && '${_state['phase']}' != 'waiting';
    final turbo = _state['turbo'] == true;
    final stake = _integer(_state['entry_fee']);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocal) => Dialog(
          backgroundColor: const Color(0xFF110B30),
          insetPadding: const EdgeInsets.symmetric(horizontal: 48, vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: OkeyXColors.mint.withValues(alpha: .28)),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 680,
              maxHeight: (MediaQuery.sizeOf(dialogContext).height - 20).clamp(300.0, 620.0),
            ),
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: OkeyXColors.mint.withValues(alpha: .10),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: OkeyXColors.ruby.withValues(alpha: .38)),
                    ),
                    child: const Icon(Icons.tune_rounded, color: OkeyXColors.mint, size: 19),
                  ),
                  const SizedBox(width: 9),
                  const Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('MASA KONTROL MERKEZİ', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: .55)),
                      Text('Ses, radyo ve masa ayarları • oyundan çıkmadan değiştir', style: TextStyle(fontSize: 9, color: Colors.white38)),
                    ]),
                  ),
                  IconButton(onPressed: () => Navigator.pop(dialogContext), icon: const Icon(Icons.close_rounded, size: 19)),
                ]),
                const SizedBox(height: 7),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [Colors.white.withValues(alpha: .035), OkeyXColors.mint.withValues(alpha: .025)]),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(children: [
                    Expanded(child: Text('${turbo ? 'Turbo ×${_integer(_state['multiplier']).clamp(1, 99)}' : 'Standart'} • ${_state['variant'] == 'fold' ? 'Katlamalı' : 'Katlamasız'} • ${_state['team_mode'] == 'paired' ? 'Eşli' : 'Tek'} • ${_assisted ? 'Yardımlı' : 'Yardımsız'}', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800))),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(color: OkeyXColors.gold.withValues(alpha: .10), borderRadius: BorderRadius.circular(9)),
                      child: Text('🟡 ${_formatNumber(stake)}', style: const TextStyle(fontSize: 9, color: OkeyXColors.gold, fontWeight: FontWeight.w900)),
                    ),
                  ]),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: _menuQuickTile(
                    _soundEnabled ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                    'OYUN SESİ',
                    _soundEnabled ? 'Açık' : 'Kapalı',
                    () {
                      setState(() => _soundEnabled = !_soundEnabled);
                      setLocal(() {});
                      _notifyTablePreferences();
                    },
                  )),
                  const SizedBox(width: 6),
                  Expanded(child: _menuQuickTile(
                    _ambienceEnabled ? Icons.surround_sound_rounded : Icons.spatial_audio_off_rounded,
                    'MASA AMBİYANSI',
                    _ambienceEnabled ? 'Açık' : 'Kapalı',
                    () {
                      setState(() => _ambienceEnabled = !_ambienceEnabled);
                      setLocal(() {});
                      unawaited(_applyTableAudio());
                      _notifyTablePreferences();
                    },
                  )),
                  const SizedBox(width: 6),
                  Expanded(child: _menuQuickTile(
                    _radioEnabled ? Icons.graphic_eq_rounded : Icons.radio_rounded,
                    'OKEYX RADYO',
                    _radioEnabled ? 'Çalıyor' : 'Kapalı',
                    () {
                      Navigator.pop(dialogContext);
                      unawaited(_showTableRadioPicker());
                    },
                  )),
                  const SizedBox(width: 6),
                  Expanded(child: _menuQuickTile(
                    Icons.vibration_rounded,
                    'TİTREŞİM',
                    _vibrationEnabled ? 'Açık' : 'Kapalı',
                    () {
                      setState(() => _vibrationEnabled = !_vibrationEnabled);
                      setLocal(() {});
                      _notifyTablePreferences();
                    },
                  )),
                ]),
                const SizedBox(height: 8),
                _menuVolumeSlider(
                  icon: Icons.graphic_eq_rounded,
                  label: 'Oyun sesleri',
                  value: _sfxVolume,
                  enabled: _soundEnabled,
                  onChanged: (v) { _setTableSfxVolume(v); setLocal(() {}); },
                  onChangeEnd: (_) => _notifyTablePreferences(),
                ),


                if (active && turbo) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                    decoration: BoxDecoration(color: OkeyXColors.gold.withValues(alpha: .07), borderRadius: BorderRadius.circular(10), border: Border.all(color: OkeyXColors.gold.withValues(alpha: .25))),
                    child: const Row(children: [
                      Icon(Icons.lock_rounded, color: OkeyXColors.gold, size: 14),
                      SizedBox(width: 6),
                      Expanded(child: Text('Turbo maç başladı. Maç bitene kadar gönüllü çıkış kapalı.', style: TextStyle(fontSize: 9, color: Colors.white70))),
                    ]),
                  ),
                ],
                const SizedBox(height: 9),
                Row(children: [
                  Expanded(child: FilledButton.tonal(onPressed: () => Navigator.pop(dialogContext), child: const Text('OYUNA DÖN'))),
                  const SizedBox(width: 8),
                  Expanded(child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: active && turbo ? const Color(0xFF27196C) : OkeyXColors.danger),
                    onPressed: active && turbo ? null : () { Navigator.pop(dialogContext); unawaited(_requestLeaveTable()); },
                    icon: Icon(active && turbo ? Icons.lock_rounded : Icons.logout_rounded, size: 15),
                    label: Text(active && turbo ? 'ÇIKIŞ KİLİTLİ' : 'MASADAN AYRIL'),
                  )),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _menuVolumeSlider({
    required IconData icon,
    required String label,
    required double value,
    required bool enabled,
    required ValueChanged<double> onChanged,
    required ValueChanged<double> onChangeEnd,
  }) => Container(
        padding: const EdgeInsets.fromLTRB(9, 2, 8, 2),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .025),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(children: [
          Icon(icon, size: 15, color: enabled ? OkeyXColors.mint : Colors.white30),
          const SizedBox(width: 7),
          SizedBox(width: 88, child: Text(label, style: TextStyle(fontSize: 9, color: enabled ? Colors.white70 : Colors.white30, fontWeight: FontWeight.w900))),
          Expanded(
            child: Slider(
              value: value.clamp(0.0, 1.0).toDouble(),
              min: 0,
              max: 1,
              onChanged: enabled ? onChanged : null,
              onChangeEnd: enabled ? onChangeEnd : null,
            ),
          ),
          SizedBox(width: 34, child: Text('%${(value * 100).round()}', textAlign: TextAlign.right, style: TextStyle(fontSize: 9, color: enabled ? OkeyXColors.mint : Colors.white24, fontWeight: FontWeight.w900))),
        ]),
      );

  Color _cosmeticAccent(String itemId, int vipLevel) {
    if (itemId.isEmpty && vipLevel <= 0) return Colors.white24;
    final explicit=switch(itemId){
      'frame_mint'=>OkeyXColors.mint,
      'frame_gold'=>OkeyXColors.gold,
      'frame_bosphorus'=>const Color(0xFF69D7EE),
      'frame_sakura'=>const Color(0xFFFF9FBE),
      'frame_neon'=>const Color(0xFF5AF2D7),
      'frame_royal'=>const Color(0xFFC29BFF),
      'frame_ice'=>const Color(0xFFA5F0FF),
      'frame_ember'=>const Color(0xFFFF8B55),
      'frame_dragon'=>const Color(0xFFFF7059),
      'frame_veteran'=>const Color(0xFFFFD36C),
      'frame_founder'=>const Color(0xFFFFE18A),
      _=>null,
    };
    if(explicit!=null)return explicit;
    const palette = <Color>[Color(0xFFFFD76A), Color(0xFF62E9C0), Color(0xFF7EE8FF), Color(0xFFD58CFF), Color(0xFFFF8FD8)];
    final seed = itemId.isNotEmpty ? itemId.codeUnits.fold<int>(0, (a, b) => a + b) : vipLevel;
    return palette[seed.abs() % palette.length];
  }

  Widget _menuQuickTile(IconData icon, String title, String value, VoidCallback onTap) => Material(
        color: Colors.white.withValues(alpha: .035),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white12)),
            child: Row(children: [Icon(icon, size: 16, color: Colors.white70), const SizedBox(width: 6), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 9, color: Colors.white54, fontWeight: FontWeight.w900)), Text(value, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900))]))]),
          ),
        ),
      );

  Future<void> _requestLeaveTable() async {
    final phase = '${_state['phase']}';
    final active = _state['started'] == true && phase != 'finished' && phase != 'waiting';
    final turbo = _state['turbo'] == true;
    final stake = _integer(_state['entry_fee']);
    if (_introActive) {
      await _leaveDuringIntro();
      return;
    }
    if (active && turbo) {
      _tableNotice('Turbo maç aktifken masadan çıkamazsın.');
      unawaited(GameAudio.sfx('warning', enabled: _soundEnabled, volume: .52));
      return;
    }
    if (active) {
      final leave = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: const Color(0xFF170E40),
          title: const Text('Masadan ayrıl?'),
          content: Text('Maç devam ediyor. Ayrılırsan ${_compact(stake)} altın masa bedelini kaybedersin ve koltuğunu bot devralır.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('OYUNA DÖN')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: OkeyXColors.danger),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('AYRIL'),
            ),
          ],
        ),
      );
      if (leave != true) return;
    }
    try {
      final out = await _api.leave();
      if (out['ok'] != true && '${out['code']}' == 'turbo_leave_locked') {
        _tableNotice('Turbo maç aktifken çıkış kilitli.');
        return;
      }
    } catch (_) {}
    await _closeTable();
  }

  Future<void> _closeTable() async {
    await widget.onClose?.call();
    if (mounted) Navigator.of(context).pop();
  }

  GameTile _tile(Map<String, dynamic> json) {
    final id = '${json['id'] ?? 'tile'}';
    return GameTile(
      id: id,
      number: _integer(json['n']).clamp(1, 13).toInt(),
      colorIndex: switch ('${json['c']}') {
        'red' => 0,
        'blue' => 1,
        'black' => 2,
        'yellow' => 3,
        _ => 2,
      },
      isJoker: json['joker'] == true,
      isFakeJoker: json['fake'] == true,
      faceDown: json['face_down'] == true,
      useful: json['useful'] == true,
      turboStar: _state['turbo'] == true && json['star'] == true,
    );
  }

  String _friendlyCode(String raw) {
    final code = raw.replaceFirst('GameApiException: ', '');
    final key = code.split(':').first;
    // Bekleme odası durumları hata değildir; geri sayım zaten görünür.
    if (key == 'quick_match_waiting_for_players' || key == 'round_intro') return '';
    final messages = {
      'below_opening_threshold': 'Açılış ${_integer(_state['min_opening_score'], fallback: 101)} puanın altında kaldı. +101 ceza.',
      'not_enough_pairs': 'Çift açmak için en az ${_integer(_state['min_opening_pairs'], fallback: 5)} çift gerekli. +101 ceza.',
      'must_use_left_tile_first':
          'Soldan aldığın taşı kullanmalı veya geri bırakmalısın.',
      'left_tile_must_be_in_opening':
          'Soldan alınan taş açılışta kullanılmalı.',
      'illegal_layoff': 'Bu taş o pere işlenemez. +101 ceza.',
      'must_keep_finish_tile': 'Bitmek için son taşı elde bırakıp atmalısın.',
      'must_discard_first': 'Eli 22 taşla başlattın; çekmeden bir taş at.',
      'not_your_turn': 'Sıra sende değil.',
      'chat_cooldown': 'Biraz yavaş 😄 Mesaj/reaksiyon için bir an bekle.',
      'gift_not_found': 'Bu masa reaksiyonu bulunamadı.',
      'round_intro': 'Yeni el hazırlanıyor.',
      'game_finished': 'Bu masa tamamlandı.',
      'room_not_found': 'Masa artık mevcut değil. Lobiye dönüp başka bir masaya katılabilirsin.',
      'host_only': 'Bu işlemi yalnızca masa sahibi yapabilir.',
      'empty_seats': 'Başlatmak için 4 koltuğun da dolu olması gerekiyor.',
      'players_not_ready': 'Herkes HAZIRIM demeden masa başlatılamaz.',
      'seat_has_player': 'Bu koltukta zaten bir oyuncu var.',
      'invalid_seat': 'Bu koltuk seçilemiyor.',
      'room_player_insufficient_balance': 'Masadaki bir oyuncunun bakiyesi bu masa için yetersiz.',
      'turbo_leave_locked': 'Turbo masada el bitmeden ayrılamazsın.',
      'leave_forfeit_insufficient_balance': 'Ayrılma cezası için bakiyen yetersiz.',
      'player_kicked': 'Masa sahibi seni masadan çıkardı.',
      'message_rejected': 'Mesaj gönderilemedi. Daha nazik bir ifade dene.',
      'socket_action_failed': 'Hamle iletilemedi. Bağlantı yenileniyor, tekrar dene.',
      'state_invariant_error': 'Masa durumu yenilendi. Hamleni tekrar yapabilirsin.',
      'cannot_gift_self': 'Kendine hediye gönderemezsin.',
      'insufficient_coins': 'Bu işlem için yeterli altının yok.',
      'active_game_not_found': 'Aktif masa bulunamadı. Lobiye dön.',
      'SUPABASE_URL is not configured':
          'Backend Supabase bağlantısı yapılandırılmamış.',
      'invalid_token': 'Oturum doğrulanamadı. Uygulamaya yeniden giriş yap.',
      'not_enough_chips': 'Bu masa için gerekli minimum altına sahip değilsin. Daha düşük masa seç veya altın paketlerine göz at.',
      'insufficient_balance': 'Bu işlem için yeterli altının yok. Bakiyene uygun seçeneklere göz at.',
      'account_link_required': 'Arkadaş servisi bu oturumda hazır değil. Oturumu yenileyip tekrar dene.',
      'social_rpc_401': 'Arkadaş servisi oturumu doğrulayamadı. Girişini yenileyip tekrar dene.',
      'social_rpc_403': 'Arkadaş servisi bu işlem için izin vermedi. Oturumu yenileyip tekrar dene.',
      'social_service_unavailable': 'Arkadaş servisine ulaşılamadı. Bağlantıyı yenileyip tekrar dene.',
      'already_pending': 'Arkadaşlık isteğin zaten bekliyor.',
      'already_friends': 'Bu oyuncu zaten arkadaşın.',
    };
    final lower = key.toLowerCase();
    if (lower.contains('socketexception') || lower.contains('timeout') || lower.contains('connection')) return 'Bağlantı zayıf. Masa yeniden bağlanıyor…';
    return messages[key] ?? 'İşlem şu an tamamlanamadı. Lütfen tekrar dene.';
  }

  String _compact(int value) => _compactMoney(value);

  Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
  List<dynamic> _list(dynamic value) =>
      value is List ? value : const <dynamic>[];
  int _integer(dynamic value, {int fallback = 0}) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? fallback;
}


class _DealInTile extends StatefulWidget {
  final int delayMs;
  final Widget child;

  const _DealInTile({super.key, required this.delayMs, required this.child});

  @override
  State<_DealInTile> createState() => _DealInTileState();
}

class _DealInTileState extends State<_DealInTile> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(Duration(milliseconds: widget.delayMs), () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        child: AnimatedSlide(
          offset: _visible ? Offset.zero : const Offset(0, -0.55),
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutBack,
          child: widget.child,
        ),
      );
}

class _RoundResultDialog extends StatefulWidget {
  final String title;
  final String finishTag;
  final List<Map<String, dynamic>> rows;
  final bool matchFinished;
  final int roundIndex;
  final int maxRounds;
  final bool turbo;
  final int multiplier;
  final int stake;
  final String variant;
  final int viewerSeat;
  final int viewerCommission;
  final int? viewerBalance;

  const _RoundResultDialog({
    required this.title,
    required this.finishTag,
    required this.rows,
    required this.matchFinished,
    required this.roundIndex,
    required this.maxRounds,
    required this.turbo,
    required this.multiplier,
    required this.stake,
    required this.variant,
    required this.viewerSeat,
    required this.viewerCommission,
    required this.viewerBalance,
  });

  @override
  State<_RoundResultDialog> createState() => _RoundResultDialogState();
}

class _RoundResultDialogState extends State<_RoundResultDialog> {
  late int _left = 10;
  Timer? _timer;
  final GlobalKey _shareCardKey=GlobalKey();
  bool _sharing=false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if(_sharing)return;
      if (_left <= 1) {
        _timer?.cancel();
        Navigator.of(context).pop(widget.matchFinished ? 'menu' : 'next');
      } else {
        setState(() => _left--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  static int _i(dynamic value) => value is num ? value.toInt() : int.tryParse('$value') ?? 0;
  static String _fmt(int value) {
    final negative=value<0;final abs=value.abs();
    String scaled(num d,String s){var t=(abs/d).toStringAsFixed(2);while(t.contains('.') && t.endsWith('0')){t=t.substring(0,t.length-1);}if(t.endsWith('.')){t=t.substring(0,t.length-1);}return '${negative?'-':''}$t$s';}
    if(abs>=1000000000)return scaled(1000000000,'B');
    if(abs>=1000000)return scaled(1000000,'M');
    if(abs>=1000)return scaled(1000,'K');
    return '$value';
  }
  static String _delta(int value) => '${value >= 0 ? '+' : '-'}${_fmt(value.abs())}';

  Future<void> _shareResult() async {
    if(_sharing)return;
    setState(()=>_sharing=true);
    try{
      await Future<void>.delayed(const Duration(milliseconds:40));
      final boundary=_shareCardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if(boundary==null)return;
      final image=await boundary.toImage(pixelRatio:2.4);
      final data=await image.toByteData(format:ui.ImageByteFormat.png);
      if(data==null)return;
      final bytes=data.buffer.asUint8List();
      final shareText='${widget.title} • ${widget.finishTag} • OkeyX 101';
      if(Platform.isAndroid){
        final file=File('${Directory.systemTemp.path}${Platform.pathSeparator}okeyx-mac-sonucu-${DateTime.now().millisecondsSinceEpoch}.png');
        await file.writeAsBytes(bytes, flush:true);
        const channel=MethodChannel('com.senshilabs.okeyx_mobile/share');
        await channel.invokeMethod<void>('shareImage', <String,dynamic>{
          'path':file.path,
          'text':shareText,
          'chooserTitle':'OkeyX maç sonucunu paylaş',
        });
      }else{
        // Android dışındaki yerel testlerde paylaşım özelliği build'i bloklamasın.
        // Platforma özel paylaşım kanalı eklendiğinde aynı kart kullanılabilir.
        debugPrint('OkeyX share card hazır: $shareText (${bytes.length} bytes)');
      }
    }finally{if(mounted)setState(()=>_sharing=false);}
  }

  @override
  Widget build(BuildContext context) {
    final mine = widget.rows.firstWhere(
      (r) => _i(r['seat']) == widget.viewerSeat,
      orElse: () => const <String, dynamic>{},
    );
    final viewerDelta = _i(mine['delta']);
    final myRank = _i(mine['rank']);
    final top = widget.rows.firstWhere((r) => _i(r['rank']) == 1, orElse: () => const <String, dynamic>{});
    // Eşli oyunda birinci gelen eşinse yine "Kazandın"; tekli oyunda yalnızca birinci kazanır.
    final teamWon = mine['team'] != null && top['team'] != null && '${mine['team']}' == '${top['team']}';
    final firstPlace = myRank <= 1 || teamWon;
    final won = widget.title.contains('KAZANDIN') && (!widget.matchFinished || firstPlace);
    final placed = !won && widget.matchFinished && myRank > 1 && viewerDelta > 0;
    final lost = !won && !placed && (widget.title.contains('KAYBETTİN') || (widget.matchFinished && viewerDelta < 0));
    final heroName = '${(won ? mine['name'] : (widget.rows.isNotEmpty ? widget.rows.first['name'] : mine['name'])) ?? 'Oyuncu'}';
    final balance = widget.viewerBalance;
    final showCoins = widget.matchFinished && viewerDelta > 0 && balance != null;
    final titleText = won
        ? 'Kazandın!'
        : placed
            ? '$myRank. oldun'
            : lost
            ? 'Bu sefer olmadı'
            : _titleCase(widget.title);
    return Dialog.fullscreen(
      backgroundColor: Colors.transparent,
      child: OkxRoom(
        child: SafeArea(
          child: LayoutBuilder(builder: (context, c) {
            final compact = c.maxHeight < 430;
            final wide = c.maxWidth > c.maxHeight * 1.12;
            return Stack(children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: Align(
                    alignment: const Alignment(0, -1.1),
                    child: CustomPaint(size: Size(c.maxWidth, c.maxHeight * .9), painter: _RaysPainter(alpha: won ? .16 : .07)),
                  ),
                ),
              ),
              Positioned.fill(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(16, compact ? 6 : 16, 16, 12),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 980),
                      child: RepaintBoundary(
                        key: _shareCardKey,
                        child: wide
                            ? _landscapeResult(won: won, lost: lost, compact: compact, heroName: heroName, titleText: titleText, viewerDelta: viewerDelta, mine: mine)
                            : Column(mainAxisSize: MainAxisSize.min, children: [
                          Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: OkxAvatar(name: heroName, size: compact ? 54 : 70, highlight: won),
                            ),
                            if (won) const Positioned(top: -6, child: Icon(Icons.workspace_premium_rounded, size: 26, color: OkeyXColors.gold)),
                          ]),
                          SizedBox(height: compact ? 8 : 12),
                          ShaderMask(
                            shaderCallback: (r) => LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: lost ? const [Color(0xFFF4EAD2), Color(0xFF9E9AC7)] : const [Color(0xFFFFF0B8), Color(0xFFE3A740), Color(0xFFA8661C)],
                            ).createShader(r),
                            child: Text(titleText, textAlign: TextAlign.center, style: TextStyle(fontFamily: OkeyXFonts.serif, fontWeight: FontWeight.w700, fontSize: compact ? 30 : 40, height: 1.1, color: Colors.white)),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${widget.finishTag} • ${widget.matchFinished ? 'MAÇ SONU' : 'EL'} ${widget.roundIndex}/${widget.maxRounds}${widget.turbo ? ' • TURBO ×${widget.multiplier}' : ''}'.toUpperCase(),
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.8, color: OkeyXColors.cream),
                          ),
                          if (widget.matchFinished && mine.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              OkxCoin(size: compact ? 22 : 28),
                              const SizedBox(width: 8),
                              TweenAnimationBuilder<double>(
                                tween: Tween(begin: 0, end: viewerDelta.toDouble()),
                                duration: const Duration(milliseconds: 1100),
                                curve: Curves.easeOutCubic,
                                builder: (context, v, _) => Text(
                                  '${v >= 0 ? '+' : '-'}${okxFormat(v.round().abs())}',
                                  style: TextStyle(fontFamily: OkeyXFonts.number, fontSize: compact ? 24 : 30, color: viewerDelta >= 0 ? const Color(0xFFFFE3A0) : OkeyXColors.danger),
                                ),
                              ),
                            ]),
                          ],
                          SizedBox(height: compact ? 10 : 16),
                          OkxLeather(
                            radius: 18,
                            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                            child: Column(children: [for (final row in widget.rows) _resultRow(row, compact)]),
                          ),
                          if (widget.matchFinished && widget.viewerCommission > 0) ...[
                            const SizedBox(height: 6),
                            Text('Masa ${_fmt(widget.stake)} • komisyon ${_fmt(widget.viewerCommission)}', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: OkeyXColors.muted)),
                          ],
                          SizedBox(height: compact ? 10 : 16),
                          Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
                            OkxButton.ghost(label: 'MENÜ', icon: Icons.home_rounded, height: 42, onTap: () => Navigator.of(context).pop('menu')),
                            OkxButton.ghost(label: 'PAYLAŞ', icon: _sharing ? Icons.hourglass_top_rounded : Icons.ios_share_rounded, height: 42, onTap: _sharing ? null : () => unawaited(_shareResult())),
                            OkxButton(
                              label: widget.matchFinished ? 'TEKRAR OYNA ($_left)' : 'SONRAKİ EL ($_left)',
                              icon: Icons.replay_rounded,
                              height: 42,
                              style: widget.matchFinished ? OkxButtonStyle.green : OkxButtonStyle.brass,
                              onTap: () => Navigator.of(context).pop(widget.matchFinished ? 'rematch' : 'next'),
                            ),
                          ]),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
              if (balance != null && widget.matchFinished)
                Positioned(
                  // Yatay ekranda sağ üstte skor tablosunun üstüne biniyordu;
                  // sol sütunun boş üst köşesine alındı.
                  right: wide ? null : 14,
                  left: wide ? 14 : null,
                  top: 10,
                  child: OkxLeather(
                    radius: 999,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    borderColor: OkeyXColors.gold.withValues(alpha: .6),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const OkxCoin(size: 18),
                      const SizedBox(width: 8),
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: (balance - (showCoins ? viewerDelta : 0)).toDouble(), end: balance.toDouble()),
                        duration: const Duration(milliseconds: 1300),
                        curve: const Interval(.45, 1, curve: Curves.easeOutCubic),
                        builder: (context, v, _) => Text(okxFormat(v.round()), style: const TextStyle(fontFamily: OkeyXFonts.number, fontSize: 15, color: OkeyXColors.cream)),
                      ),
                    ]),
                  ),
                ),
              if (won)
                for (var i = 0; i < 42; i++)
                  TweenAnimationBuilder<double>(
                    key: ValueKey('result-confetti-${widget.roundIndex}-$i'),
                    tween: Tween(begin: 0, end: 1),
                    duration: Duration(milliseconds: 1900 + (i % 7) * 260),
                    curve: Interval((i % 6) * .05, 1, curve: Curves.easeIn),
                    builder: (context, v, child) => Positioned(
                      left: (c.maxWidth * ((i * 37 % 97) / 100) + math.sin(v * math.pi * 3 + i) * 22).clamp(0.0, c.maxWidth - 12).toDouble(),
                      top: -24 + (c.maxHeight + 48) * v,
                      child: IgnorePointer(child: Opacity(opacity: v > .85 ? ((1 - v) / .15).clamp(0.0, 1.0).toDouble() : 1, child: Transform.rotate(angle: v * (i.isEven ? 9 : -9), child: child))),
                    ),
                    child: Container(
                      width: 6 + (i % 3) * 2.0,
                      height: 10 + (i % 4) * 2.0,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(1.5),
                        color: const [Color(0xFFFFD15C), Color(0xFF3CCF8E), Color(0xFFFFE36B), Color(0xFFE85A4F), Color(0xFF5BC0EB), Color(0xFFFFFFFF)][i % 6],
                      ),
                    ),
                  ),
              if (showCoins)
                for (var i = 0; i < 9; i++)
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: Duration(milliseconds: 900 + i * 70),
                    curve: Interval((i * .05).clamp(0.0, .5), 1, curve: Curves.easeInOutCubic),
                    builder: (context, v, child) {
                      final from = Offset(c.maxWidth / 2 - 30 + (i % 3) * 18, compact ? 150 : 200);
                      final to = wide ? const Offset(60, 24) : Offset(c.maxWidth - 120, 24);
                      final p = Offset.lerp(from, to, v)!;
                      final lift = math.sin(v * math.pi) * (60 + i * 6);
                      return Positioned(
                        left: p.dx,
                        top: p.dy - lift,
                        child: Opacity(opacity: v < .05 || v > .97 ? 0 : 1, child: child),
                      );
                    },
                    child: const IgnorePointer(child: OkxCoin(size: 22)),
                  ),
            ]);
          }),
        ),
      ),
    );
  }

  Widget _landscapeResult({required bool won, required bool lost, required bool compact, required String heroName, required String titleText, required int viewerDelta, required Map<String, dynamic> mine}) {
    final finishLine = '${widget.finishTag} • ${widget.matchFinished ? 'MAÇ SONU' : 'EL'} ${widget.roundIndex}/${widget.maxRounds}${widget.turbo ? ' • TURBO ×${widget.multiplier}' : ''}'.toUpperCase();
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Expanded(flex: 4, child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 18, 8),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
            OkxAvatar(name: heroName, size: compact ? 54 : 76, highlight: won),
            if (won) const Positioned(top: -8, child: Icon(Icons.workspace_premium_rounded, size: 28, color: OkeyXColors.gold)),
          ]),
          const SizedBox(height: 10),
          ShaderMask(shaderCallback: (r) => LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: lost ? const [Color(0xFFF4EAD2), Color(0xFF9E9AC7)] : const [Color(0xFFFFF0B8), Color(0xFFE3A740), Color(0xFFA8661C)]).createShader(r), child: Text(titleText, textAlign: TextAlign.center, style: TextStyle(fontFamily: OkeyXFonts.serif, fontWeight: FontWeight.w700, fontSize: compact ? 27 : 38, height: 1.05, color: Colors.white))),
          const SizedBox(height: 7),
          Text(finishLine, textAlign: TextAlign.center, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.1, color: OkeyXColors.cream)),
          if (widget.matchFinished && mine.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(mainAxisSize: MainAxisSize.min, children: [
              OkxCoin(size: 24), const SizedBox(width: 8),
              TweenAnimationBuilder<double>(tween: Tween(begin: 0, end: viewerDelta.toDouble()), duration: const Duration(milliseconds: 1400), curve: Curves.easeOutCubic, builder: (context, v, _) => Text('${v >= 0 ? '+' : '-'}${okxFormat(v.round().abs())}', style: TextStyle(fontFamily: OkeyXFonts.number, fontSize: 25, color: viewerDelta >= 0 ? const Color(0xFFFFE3A0) : OkeyXColors.danger))),
            ]),
          ],
        ]),
      )),
      Container(width: 1, height: 250, color: OkeyXColors.gold.withValues(alpha: .22)),
      const SizedBox(width: 14),
      Expanded(flex: 6, child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 8, 10, 8),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          OkxLeather(radius: 16, padding: const EdgeInsets.fromLTRB(8, 6, 8, 6), child: Column(children: [for (final row in widget.rows) _resultRow(row, compact)])),
          if (widget.matchFinished && widget.viewerCommission > 0) ...[
            const SizedBox(height: 7),
            Text('Masa ${_fmt(widget.stake)} • komisyon ${_fmt(widget.viewerCommission)}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: OkeyXColors.muted)),
          ],
          const SizedBox(height: 14),
          Row(children: [
            Expanded(flex: 3, child: OkxButton.ghost(label: 'MENÜ', icon: Icons.home_rounded, height: 44, onTap: () => Navigator.of(context).pop('menu'))),
            const SizedBox(width: 7),
            Expanded(flex: 3, child: OkxButton.ghost(label: 'PAYLAŞ', icon: _sharing ? Icons.hourglass_top_rounded : Icons.ios_share_rounded, height: 44, onTap: _sharing ? null : () => unawaited(_shareResult()))),
            const SizedBox(width: 7),
            Expanded(flex: 4, child: OkxButton(label: widget.matchFinished ? 'TEKRAR OYNA ($_left)' : 'SONRAKİ EL ($_left)', icon: Icons.replay_rounded, height: 44, style: widget.matchFinished ? OkxButtonStyle.green : OkxButtonStyle.brass, onTap: () => Navigator.of(context).pop(widget.matchFinished ? 'rematch' : 'next'))),
          ]),
        ]),
      )),
    ]);
  }

  static String _titleCase(String s) {
    final lower = s.toLowerCase().replaceAll('i̇', 'i');
    return lower.isEmpty ? s : lower.substring(0, 1).toUpperCase() + lower.substring(1);
  }

  Widget _resultRow(Map<String, dynamic> row, bool compact) {
    final rank = _i(row['rank']);
    final delta = _i(row['delta']);
    final mine = _i(row['seat']) == widget.viewerSeat;
    final name = '${row['name'] ?? 'Oyuncu'}';
    final round = _i(row['round_score']);
    final total = _i(row['total']);
    final valueColor = widget.matchFinished
        ? (delta >= 0 ? OkeyXColors.mint : OkeyXColors.danger)
        : (round <= 0 ? OkeyXColors.mint : (round > 150 ? OkeyXColors.danger : OkeyXColors.cream));
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: compact ? 4 : 6),
      decoration: BoxDecoration(
        color: mine ? const Color(0x24FFD278) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border(bottom: BorderSide(color: mine ? Colors.transparent : const Color(0x14FFECBE))),
      ),
      child: Row(children: [
        SizedBox(width: 24, child: Text('$rank', style: TextStyle(fontFamily: OkeyXFonts.number, fontSize: 14, color: rank == 1 ? OkeyXColors.gold : OkeyXColors.muted))),
        Padding(padding: const EdgeInsets.all(4), child: OkxAvatar(name: name, size: compact ? 24 : 30)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$name${mine ? ' (sen)' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: OkeyXColors.cream)),
            Text(
              'Kalan ${_i(row['remaining_count'])} taş • ${_i(row['remaining'])} puan${_i(row['opening_value']) > 0 ? ' • ${row['opening_mode'] == 'pairs' ? 'Çift' : 'Seri'} ${_i(row['opening_value'])}' : ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: OkeyXColors.muted),
            ),
          ]),
        ),
        const SizedBox(width: 8),
        Text('El $round', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: OkeyXColors.muted)),
        const SizedBox(width: 14),
        SizedBox(
          width: 78,
          child: Text(
            widget.matchFinished ? _delta(delta) : '$total',
            textAlign: TextAlign.right,
            style: TextStyle(fontFamily: OkeyXFonts.number, fontSize: 14, color: valueColor),
          ),
        ),
      ]),
    );
  }
}

class _UsefulDiscardPulse extends StatefulWidget {
  final Widget child;
  const _UsefulDiscardPulse({required this.child});
  @override State<_UsefulDiscardPulse> createState()=>_UsefulDiscardPulseState();
}
class _UsefulDiscardPulseState extends State<_UsefulDiscardPulse> with SingleTickerProviderStateMixin{
  late final AnimationController c;
  @override void initState(){super.initState();c=AnimationController(vsync:this,duration:const Duration(milliseconds:850))..repeat(reverse:true);}
  @override void dispose(){c.dispose();super.dispose();}
  @override Widget build(BuildContext context)=>AnimatedBuilder(animation:c,builder:(_,child)=>Transform.scale(scale:1+(c.value*.035),child:Opacity(opacity:.92+(c.value*.08),child:child)),child:widget.child);
}

class _TableLoadingTiles extends StatefulWidget {
  const _TableLoadingTiles();
  @override State<_TableLoadingTiles> createState()=>_TableLoadingTilesState();
}
class _TableLoadingTilesState extends State<_TableLoadingTiles> with SingleTickerProviderStateMixin{
  late final AnimationController c;
  @override void initState(){super.initState();c=AnimationController(vsync:this,duration:const Duration(milliseconds:1150))..repeat();}
  @override void dispose(){c.dispose();super.dispose();}
  @override Widget build(BuildContext context)=>AnimatedBuilder(animation:c,builder:(_,__)=>Row(mainAxisSize:MainAxisSize.min,children:[for(var i=0;i<3;i++) Padding(padding:const EdgeInsets.symmetric(horizontal:4),child:Transform.translate(offset:Offset(0,-5*math.sin((c.value*math.pi*2)+(i*.9))),child:Container(width:34,height:48,alignment:Alignment.center,decoration:BoxDecoration(gradient:const LinearGradient(colors:[Color(0xFFFFFEF7),Color(0xFFE8DAC7)]),borderRadius:BorderRadius.circular(7),border:Border.all(color:OkeyXColors.gold.withValues(alpha:.65)),boxShadow:[BoxShadow(color:OkeyXColors.cyan.withValues(alpha:.15),blurRadius:9)]),child:Text('${i+1}',style:TextStyle(fontSize:17,fontWeight:FontWeight.w900,color:[const Color(0xFFD32929),const Color(0xFF236FCE),const Color(0xFFC99414)][i])))))]));
}

class _TableGrid extends StatelessWidget {
  const _TableGrid();

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _GridPainter());
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: .07)
      ..strokeWidth = 1;
    const step = 32.0;
    for (double x = step; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = step; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _GiftArt extends StatelessWidget {
  final String kind;
  final double size;
  final bool glow;
  const _GiftArt({required this.kind, required this.size, this.glow = false});

  @override
  Widget build(BuildContext context) {
    final emoji = _giftEmojiFor(kind);
    if (emoji != null) {
      return SizedBox.square(
        dimension: size,
        child: Center(
          child: Text(
            emoji,
            style: TextStyle(
              fontSize: size * .8,
              height: 1,
              shadows: [
                const Shadow(color: Color(0x80000000), blurRadius: 6, offset: Offset(0, 3)),
                if (glow) Shadow(color: OkeyXColors.gold.withValues(alpha: .55), blurRadius: size * .35),
              ],
            ),
          ),
        ),
      );
    }
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: glow
            ? BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: OkeyXColors.gold.withValues(alpha: .18), blurRadius: size * .34),
                  BoxShadow(color: OkeyXColors.mint.withValues(alpha: .12), blurRadius: size * .5),
                ],
              )
            : const BoxDecoration(),
        child: CustomPaint(painter: _GiftPainter(kind)),
      ),
    );
  }
}

class _GiftPainter extends CustomPainter {
  final String kind;
  const _GiftPainter(this.kind);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final c = Offset(w / 2, h / 2);
    final outline = Paint()
      ..color = const Color(0xFFF4E9D2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.2, w * .055).toDouble()
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final mint = Paint()..color = OkeyXColors.mint;
    final gold = Paint()..color = OkeyXColors.gold;
    final red = Paint()..color = const Color(0xFFE84D5B);
    final blue = Paint()..color = const Color(0xFF4DA3E8);
    final dark = Paint()..color = const Color(0xFF160E3D);

    void sparkle(Offset p, double r, Paint paint) {
      canvas.drawCircle(p, r, paint);
      canvas.drawLine(Offset(p.dx - r * 1.8, p.dy), Offset(p.dx + r * 1.8, p.dy), outline..strokeWidth = math.max(1, r * .55).toDouble());
      canvas.drawLine(Offset(p.dx, p.dy - r * 1.8), Offset(p.dx, p.dy + r * 1.8), outline);
    }

    final k = kind.toLowerCase();
    if (k.contains('çay') || k == 'tea') {
      final glass = Path()
        ..moveTo(w * .30, h * .30)
        ..lineTo(w * .70, h * .30)
        ..lineTo(w * .62, h * .76)
        ..lineTo(w * .38, h * .76)
        ..close();
      canvas.drawPath(glass, Paint()..color = const Color(0xFFB44425));
      canvas.drawPath(glass, outline);
      canvas.drawLine(Offset(w * .30, h * .82), Offset(w * .70, h * .82), outline);
      for (final x in [.42, .58]) {
        final steam = Path()
          ..moveTo(w * x, h * .26)
          ..cubicTo(w * (x - .05), h * .18, w * (x + .05), h * .13, w * x, h * .07);
        canvas.drawPath(steam, outline..color = Colors.white70);
      }
      return;
    }
    if (k.contains('kahve') || k == 'coffee') {
      final cup = RRect.fromRectAndRadius(Rect.fromLTWH(w * .22, h * .34, w * .48, h * .34), Radius.circular(w * .08));
      canvas.drawRRect(cup, Paint()..color = const Color(0xFFF5E6C8));
      canvas.drawRRect(cup, outline..color = const Color(0xFF7B4A2E));
      canvas.drawCircle(Offset(w * .73, h * .48), w * .11, outline);
      canvas.drawLine(Offset(w * .18, h * .76), Offset(w * .78, h * .76), outline);
      final steam = Path()
        ..moveTo(w * .40, h * .31)
        ..cubicTo(w * .31, h * .23, w * .49, h * .18, w * .40, h * .09)
        ..moveTo(w * .55, h * .31)
        ..cubicTo(w * .46, h * .23, w * .64, h * .18, w * .55, h * .09);
      canvas.drawPath(steam, outline..color = Colors.white70);
      return;
    }
    if (k.contains('nazar')) {
      canvas.drawCircle(c, w * .39, blue);
      canvas.drawCircle(c, w * .27, Paint()..color = Colors.white);
      canvas.drawCircle(c, w * .16, Paint()..color = const Color(0xFF184A9D));
      canvas.drawCircle(c, w * .075, dark);
      return;
    }
    if (k.contains('gül') || k == 'rose') {
      canvas.drawLine(Offset(w * .50, h * .46), Offset(w * .45, h * .90), Paint()..color = const Color(0xFF4FA668)..strokeWidth = w * .08..strokeCap = StrokeCap.round);
      canvas.drawOval(Rect.fromCenter(center: Offset(w * .35, h * .70), width: w * .25, height: h * .13), Paint()..color = const Color(0xFF4FA668));
      for (var i = 0; i < 6; i++) {
        final a = i * math.pi / 3;
        canvas.drawCircle(Offset(w * .50 + math.cos(a) * w * .13, h * .31 + math.sin(a) * h * .10), w * .14, red);
      }
      canvas.drawCircle(Offset(w * .50, h * .31), w * .12, Paint()..color = const Color(0xFFC82F46));
      return;
    }
    if (k.contains('simit')) {
      canvas.drawCircle(c, w * .34, Paint()..color = const Color(0xFFD5913A));
      canvas.drawCircle(c, w * .17, dark);
      for (var i = 0; i < 12; i++) {
        final a = i * math.pi * 2 / 12;
        canvas.drawCircle(Offset(c.dx + math.cos(a) * w * .27, c.dy + math.sin(a) * w * .27), w * .025, Paint()..color = const Color(0xFFF3DCA7));
      }
      return;
    }
    if (k.contains('pasta') || k == 'cake') {
      final body = RRect.fromRectAndRadius(Rect.fromLTWH(w * .18, h * .43, w * .64, h * .34), Radius.circular(w * .06));
      canvas.drawRRect(body, Paint()..color = const Color(0xFFFFD0D8));
      canvas.drawRRect(body, outline..color = const Color(0xFF7D4150));
      canvas.drawRect(Rect.fromLTWH(w * .24, h * .35, w * .52, h * .13), Paint()..color = const Color(0xFFF7F0E8));
      canvas.drawRect(Rect.fromLTWH(w * .47, h * .18, w * .06, h * .18), gold);
      final flame = Path()..moveTo(w*.50,h*.06)..quadraticBezierTo(w*.60,h*.16,w*.50,h*.19)..quadraticBezierTo(w*.40,h*.16,w*.50,h*.06)..close();
      canvas.drawPath(flame, red);
      return;
    }
    if (k.contains('kupa') || k == 'trophy') {
      final bowl = Path()
        ..moveTo(w * .28, h * .18)
        ..lineTo(w * .72, h * .18)
        ..quadraticBezierTo(w * .68, h * .55, w * .50, h * .57)
        ..quadraticBezierTo(w * .32, h * .55, w * .28, h * .18)
        ..close();
      canvas.drawPath(bowl, gold);
      canvas.drawLine(Offset(w * .50, h * .55), Offset(w * .50, h * .78), Paint()..color = OkeyXColors.gold..strokeWidth = w*.09);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(w*.31,h*.76,w*.38,h*.12), Radius.circular(w*.03)), gold);
      canvas.drawArc(Rect.fromLTWH(w*.12,h*.22,w*.26,h*.28), math.pi*.55, math.pi*1.05, false, outline..color=OkeyXColors.gold);
      canvas.drawArc(Rect.fromLTWH(w*.62,h*.22,w*.26,h*.28), -math.pi*.60, math.pi*1.05, false, outline);
      return;
    }
    if (k.contains('havai') || k.contains('firework')) {
      for (var j = 0; j < 3; j++) {
        final center = [Offset(w*.34,h*.42), Offset(w*.67,h*.34), Offset(w*.55,h*.69)][j];
        final paint = [gold,mint,red][j];
        for (var i = 0; i < 8; i++) {
          final a = i * math.pi / 4;
          final p1 = Offset(center.dx + math.cos(a) * w*.08, center.dy + math.sin(a) * w*.08);
          final p2 = Offset(center.dx + math.cos(a) * w*.24, center.dy + math.sin(a) * w*.24);
          canvas.drawLine(p1,p2,Paint()..color=paint.color..strokeWidth=math.max(1.1,w*.035).toDouble()..strokeCap=StrokeCap.round);
        }
        sparkle(center, w*.025, paint);
      }
      return;
    }
    if (k.contains('domates') || k == 'tomato') {
      canvas.drawCircle(Offset(w * .50, h * .58), w * .32, Paint()..color = const Color(0xFFE23B30));
      canvas.drawCircle(Offset(w * .39, h * .47), w * .08, Paint()..color = Colors.white.withValues(alpha: .38));
      final leaf = Paint()..color = const Color(0xFF3E9B4F);
      for (var i = 0; i < 5; i++) {
        final a = -math.pi / 2 + (i - 2) * .75;
        canvas.drawOval(Rect.fromCenter(center: Offset(w * .50 + math.cos(a) * w * .13, h * .31 + math.sin(a) * h * .06), width: w * .20, height: h * .08), leaf);
      }
      return;
    }
    if (k.contains('yumurta') || k == 'egg') {
      final eggRect = Rect.fromCenter(center: Offset(w * .50, h * .55), width: w * .50, height: h * .68);
      canvas.drawOval(eggRect, Paint()..color = const Color(0xFFFFF3D6));
      canvas.drawOval(eggRect, Paint()..color = const Color(0xFFD9BE86)..style = PaintingStyle.stroke..strokeWidth = math.max(1.0, w * .035).toDouble());
      canvas.drawOval(Rect.fromCenter(center: Offset(w * .40, h * .42), width: w * .10, height: h * .16), Paint()..color = Colors.white.withValues(alpha: .7));
      return;
    }
    if (k.contains('kalp') || k == 'heart') {
      final heart = Path()
        ..moveTo(w * .50, h * .84)
        ..cubicTo(w * .04, h * .52, w * .16, h * .14, w * .50, h * .38)
        ..cubicTo(w * .84, h * .14, w * .96, h * .52, w * .50, h * .84)
        ..close();
      canvas.drawPath(heart, Paint()..color = const Color(0xFFE63E62));
      canvas.drawCircle(Offset(w * .34, h * .40), w * .06, Paint()..color = Colors.white.withValues(alpha: .5));
      return;
    }
    if (k.contains('ateş') || k == 'fire') {
      final flame = Path()
        ..moveTo(w * .50, h * .08)
        ..cubicTo(w * .82, h * .38, w * .90, h * .62, w * .67, h * .85)
        ..cubicTo(w * .58, h * .94, w * .42, h * .94, w * .33, h * .85)
        ..cubicTo(w * .10, h * .62, w * .30, h * .40, w * .50, h * .08)
        ..close();
      canvas.drawPath(flame, Paint()..color = const Color(0xFFFF6A1F));
      final inner = Path()
        ..moveTo(w * .50, h * .40)
        ..cubicTo(w * .68, h * .58, w * .70, h * .72, w * .58, h * .84)
        ..cubicTo(w * .52, h * .89, w * .48, h * .89, w * .42, h * .84)
        ..cubicTo(w * .30, h * .72, w * .36, h * .58, w * .50, h * .40)
        ..close();
      canvas.drawPath(inner, Paint()..color = const Color(0xFFFFD54A));
      return;
    }
    // Generic premium parcel: still a drawn object, never an emoji glyph.
    final box = RRect.fromRectAndRadius(Rect.fromLTWH(w*.20,h*.32,w*.60,h*.48), Radius.circular(w*.06));
    canvas.drawRRect(box, mint);
    canvas.drawRRect(box, outline..color=Colors.white70);
    canvas.drawRect(Rect.fromLTWH(w*.46,h*.32,w*.08,h*.48), gold);
    canvas.drawRect(Rect.fromLTWH(w*.20,h*.48,w*.60,h*.08), gold);
    canvas.drawCircle(Offset(w*.43,h*.25),w*.10,gold);
    canvas.drawCircle(Offset(w*.57,h*.25),w*.10,gold);
  }

  @override
  bool shouldRepaint(covariant _GiftPainter oldDelegate) => oldDelegate.kind != kind;
}


class _WaitingTablePattern extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = Colors.white.withValues(alpha: .035)
      ..strokeWidth = 1;
    for (var i = 1; i < 9; i++) {
      final x = size.width * i / 9;
      canvas.drawLine(
        Offset(x, size.height * .12),
        Offset(x, size.height * .88),
        line,
      );
    }
    for (var i = 1; i < 5; i++) {
      final y = size.height * i / 5;
      canvas.drawLine(
        Offset(size.width * .08, y),
        Offset(size.width * .92, y),
        line,
      );
    }
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = OkeyXColors.gold.withValues(alpha: .10);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * .5, size.height * .5),
        width: size.width * .52,
        height: size.height * .40,
      ),
      ring,
    );
  }

  @override
  bool shouldRepaint(covariant _WaitingTablePattern oldDelegate) => false;
}

/// Onaylı taslağın 1000×450 çerçevesini gerçek ekran boyutuna ölçekler.
class _Frame {
  _Frame(this.w, this.h)
      : sx = w / 1000,
        sy = h / 450,
        k = math.min(w / 1000, h / 450);
  final double w, h, sx, sy, k;
  double x(double v) => v * sx;
  double y(double v) => v * sy;
  double s(double v) => v * k;
}

/// Masadaki hediye kataloğu (sunucudaki GIFT_CATALOG ile aynı kimlikler).
/// style: 'stick' avatara yapışır, 'big' tam ekran gösteri, 'float' süzülür.
class _GiftDef {
  final String id;
  final String name;
  final String emoji;
  final String style;
  const _GiftDef(this.id, this.name, this.emoji, this.style);
}

const _kGifts = <_GiftDef>[
  _GiftDef('slipper', 'Terlik', '🩴', 'stick'),
  _GiftDef('tomato', 'Domates', '🍅', 'stick'),
  _GiftDef('egg', 'Yumurta', '🥚', 'stick'),
  _GiftDef('fish', 'Balık Tokadı', '🐟', 'stick'),
  _GiftDef('rubber_chicken', 'Lastik Tavuk', '🐔', 'stick'),
  _GiftDef('tea', 'Çay', '🫖', 'float'),
  _GiftDef('coffee', 'Türk Kahvesi', '☕', 'float'),
  _GiftDef('rose', 'Gül', '🌹', 'float'),
  _GiftDef('nazar', 'Nazar Boncuğu', '🧿', 'float'),
  _GiftDef('simit', 'Simit', '🥨', 'float'),
  _GiftDef('heart', 'Kalp', '❤️', 'float'),
  _GiftDef('applause', 'Alkış', '👏', 'float'),
  _GiftDef('crown', 'Altın Taç', '👑', 'big'),
  _GiftDef('money_rain', 'Para Yağmuru', '💸', 'big'),
  _GiftDef('rocket', 'Roket', '🚀', 'big'),
  _GiftDef('sports_car', 'Spor Araba', '🏎️', 'big'),
  _GiftDef('dragon', 'Ejderha', '🐉', 'big'),
  _GiftDef('fireworks', 'Havai Fişek', '🎆', 'big'),
];

const _kExtraGiftEmoji = <String, String>{
  'Yumruk': '👊',
  'Ateş': '🔥',
  'Pompa': '🪠',
  'Sansürlü Muz': '🍌',
  'Pasta': '🎂',
  'Altın Kupa': '🏆',
};

_GiftDef? _giftByIdOrName(String? id, String? name) {
  for (final g in _kGifts) {
    if (id != null && id.isNotEmpty && g.id == id) return g;
  }
  for (final g in _kGifts) {
    if (name != null && g.name == name) return g;
  }
  return null;
}

String? _giftEmojiFor(String name) => _giftByIdOrName(null, name)?.emoji ?? _kExtraGiftEmoji[name];

class _StuckGift {
  final String emoji;
  final String key;
  const _StuckGift(this.emoji, this.key);
}

class _BigGift {
  final String emoji;
  final String name;
  final String from;
  final String to;
  final String key;
  const _BigGift(this.emoji, this.name, this.from, this.to, this.key);
}

/// Avatara "tak" diye yapışan hediye: büyük gelir, çarpar, hafif sallanır.
class _StuckGiftBadge extends StatefulWidget {
  final String emoji;
  final double size;
  final bool reduced;
  const _StuckGiftBadge({super.key, required this.emoji, required this.size, this.reduced = false});

  @override
  State<_StuckGiftBadge> createState() => _StuckGiftBadgeState();
}

class _StuckGiftBadgeState extends State<_StuckGiftBadge> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));

  @override
  void initState() {
    super.initState();
    if (widget.reduced) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          final t = _c.value;
          final slam = t < .35 ? 2.2 - 1.3 * Curves.easeIn.transform(t / .35) : .9 + .1 * Curves.elasticOut.transform(((t - .35) / .65).clamp(0.0, 1.0));
          final wobble = t < .35 ? 0.0 : math.sin((t - .35) * math.pi * 6) * (1 - t) * .5;
          return Transform.rotate(angle: -.35 + wobble, child: Transform.scale(scale: slam, child: child));
        },
        child: Text(
          widget.emoji,
          style: TextStyle(fontSize: widget.size, height: 1, shadows: const [Shadow(color: Color(0x99000000), blurRadius: 6, offset: Offset(0, 3))]),
        ),
      );
}

/// Duyurular ve büyük hediyelerin arkasındaki ışık huzmeleri.
class _RaysPainter extends CustomPainter {
  final double alpha;
  const _RaysPainter({required this.alpha});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.longestSide * .6;
    final paint = Paint()
      ..shader = RadialGradient(colors: [Color.fromRGBO(255, 214, 140, alpha), const Color(0x00FFD68C)]).createShader(Rect.fromCircle(center: c, radius: r));
    for (var i = 0; i < 14; i++) {
      final a = i / 14 * math.pi * 2;
      final path = Path()
        ..moveTo(c.dx, c.dy)
        ..lineTo(c.dx + math.cos(a - .07) * r, c.dy + math.sin(a - .07) * r)
        ..lineTo(c.dx + math.cos(a + .07) * r, c.dy + math.sin(a + .07) * r)
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RaysPainter oldDelegate) => oldDelegate.alpha != alpha;
}

/// Avatara dokununca açılan küçük profil kartı + hediye ızgarası.
class _PlayerCardBody extends StatefulWidget {
  final _TableScreenState state;
  final Map<String, dynamic> player;
  final bool giftMode;
  final List<Map<String, dynamic>> targets;
  final VoidCallback onClose;

  const _PlayerCardBody({
    required this.state,
    required this.player,
    required this.onClose,
    this.giftMode = false,
    this.targets = const [],
  });

  @override
  State<_PlayerCardBody> createState() => _PlayerCardBodyState();
}

class _PlayerCardBodyState extends State<_PlayerCardBody> {
  late bool _gifts = widget.giftMode;
  late Map<String, dynamic> _target = widget.player;
  String _selected = 'coffee';
  bool _sending = false;

  _TableScreenState get t => widget.state;

  static int _i(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
  static Map<String, dynamic> _m(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  Future<void> _send({bool everyone = false}) async {
    if (_sending) return;
    setState(() => _sending = true);
    final ok = await t._sendGift(_selected, everyone ? -1 : _i(_target['seat']));
    if (!mounted) return;
    setState(() => _sending = false);
    if (ok) widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final width = math.min(340.0, math.max(270.0, screen.width * .40));
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: width, maxHeight: screen.height - 24),
      child: OkxLeather(
        stitch: true,
        radius: 20,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        borderColor: OkeyXColors.line2,
        child: AnimatedSize(
          duration: const Duration(milliseconds: 180),
          child: SingleChildScrollView(child: _gifts ? _giftView() : _profileView()),
        ),
      ),
    );
  }

  Widget _closeButton() => GestureDetector(
        onTap: widget.onClose,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(color: const Color(0x66000000), shape: BoxShape.circle, border: Border.all(color: OkeyXColors.line)),
          child: const Icon(Icons.close_rounded, size: 17, color: OkeyXColors.muted),
        ),
      );

  Widget _chip(String text, {bool gold = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          gradient: gold ? brassGradient : null,
          color: gold ? null : const Color(0x40000000),
          borderRadius: BorderRadius.circular(999),
          border: gold ? null : Border.all(color: OkeyXColors.line2),
        ),
        child: Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: .6, color: gold ? okxTextDark : OkeyXColors.muted)),
      );

  Widget _stat(String label, String value) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(color: const Color(0x40000000), borderRadius: BorderRadius.circular(11), border: Border.all(color: OkeyXColors.line)),
          child: Column(children: [
            Text(value, maxLines: 1, style: const TextStyle(fontFamily: OkeyXFonts.number, fontSize: 14, color: OkeyXColors.cream)),
            const SizedBox(height: 2),
            Text(label, maxLines: 1, style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.w800, letterSpacing: .6, color: OkeyXColors.muted)),
          ]),
        ),
      );

  Widget _profileView() {
    final p = widget.player;
    final name = '${p['name'] ?? 'Oyuncu'}';
    final stats = _m(p['public_stats']);
    final games = _i(stats['games']);
    final wins = _i(stats['wins']);
    final rate = games > 0 ? ((wins * 100) / games).round() : 0;
    final gifts = (p['gifts_received'] is List) ? (p['gifts_received'] as List) : const [];
    final giftCount = _i(stats['gifts_received']) > 0 ? _i(stats['gifts_received']) : gifts.length;
    final targetId = '${p['player_id'] ?? ''}'.trim();
    final isBot = p['bot'] == true && targetId.isEmpty;
    final tier = '${stats['tier'] ?? ''}'.trim();
    final city = '${stats['city'] ?? ''}'.trim();
    final giftsOn = t._state['gifts_enabled'] != false;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        GestureDetector(
          onTap: () {
            widget.onClose();
            unawaited(t._showPlayerProfile(p));
          },
          child: Padding(padding: const EdgeInsets.all(6), child: OkxAvatar(name: name, imageUrl: t._avatarUrlOf(p), size: 54, online: p['connected'] != false && !isBot)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 4),
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: OkeyXFonts.serif, fontSize: 20, fontWeight: FontWeight.w700, color: OkeyXColors.cream)),
            const SizedBox(height: 5),
            Wrap(spacing: 5, runSpacing: 4, children: [
              _chip('LV ${_i(p['level'])}', gold: true),
              if (_i(p['vip_level']) > 0) _chip('VIP ${_i(p['vip_level'])}'),
              if (tier.isNotEmpty) _chip(tier.toUpperCase()),
              if (city.isNotEmpty) _chip(city.toUpperCase()),
              if (isBot) _chip('BOT'),
            ]),
          ]),
        ),
        _closeButton(),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        _stat('GALİBİYET', okxFormat(wins)),
        const SizedBox(width: 6),
        _stat('OYUN', okxFormat(games)),
        const SizedBox(width: 6),
        _stat('ORAN', '%$rate'),
        const SizedBox(width: 6),
        _stat('HEDİYE', okxFormat(giftCount)),
      ]),
      if (gifts.isNotEmpty) ...[
        const SizedBox(height: 8),
        SizedBox(
          height: 26,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (final raw in gifts.take(12))
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(_giftEmojiFor('${_m(raw)['name'] ?? ''}') ?? '🎁', style: const TextStyle(fontSize: 18)),
              ),
          ]),
        ),
      ],
      const SizedBox(height: 10),
      OkxButton(
        label: 'HEDİYE GÖNDER',
        icon: Icons.card_giftcard_rounded,
        height: 38,
        expand: true,
        onTap: giftsOn ? () => setState(() => _gifts = true) : null,
      ),
      const SizedBox(height: 7),
      Row(children: [
        Expanded(
          child: OkxButton.ghost(
            label: 'ARKADAŞ EKLE',
            icon: Icons.person_add_alt_1_rounded,
            height: 34,
            fontSize: 11,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            expand: true,
            onTap: targetId.isEmpty
                ? null
                : () {
                    widget.onClose();
                    unawaited(t._addTableFriend(targetId, name));
                  },
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: OkxButton.ghost(
            label: 'SESSİZE AL',
            icon: Icons.volume_off_rounded,
            height: 34,
            fontSize: 11,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            expand: true,
            onTap: targetId.isEmpty
                ? null
                : () {
                    widget.onClose();
                    unawaited(t._setTableSafety(targetId, 'mute'));
                  },
          ),
        ),
      ]),
      if (targetId.isNotEmpty) ...[
        const SizedBox(height: 4),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          TextButton.icon(
            onPressed: () {
              widget.onClose();
              unawaited(t._sendCoinsAtTable(targetId, name));
            },
            icon: const Icon(Icons.paid_rounded, size: 15, color: OkeyXColors.gold),
            label: const Text('ALTIN GÖNDER', style: TextStyle(fontSize: 11, color: OkeyXColors.gold)),
          ),
          TextButton.icon(
            onPressed: () {
              widget.onClose();
              unawaited(t._reportTablePlayer(targetId));
            },
            icon: const Icon(Icons.flag_rounded, size: 15, color: OkeyXColors.danger),
            label: const Text('ŞİKÂYET ET', style: TextStyle(fontSize: 11, color: OkeyXColors.danger)),
          ),
        ]),
      ],
    ]);
  }

  Widget _giftView() {
    final name = '${_target['name'] ?? 'Oyuncu'}';
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        OkxAvatar(name: name, imageUrl: t._avatarUrlOf(_target), size: 34),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: OkeyXFonts.serif, fontSize: 17, fontWeight: FontWeight.w700, color: OkeyXColors.cream)),
            const Text('Hediyeler ücretsiz • her hediye 10 sn’de bir', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: OkeyXColors.muted)),
          ]),
        ),
        _closeButton(),
      ]),
      if (widget.targets.length > 1) ...[
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final p in widget.targets)
            OkxChip(
              label: '${p['name'] ?? 'Oyuncu'}',
              selected: _i(p['seat']) == _i(_target['seat']),
              onTap: () => setState(() => _target = p),
            ),
        ]),
      ],
      const SizedBox(height: 10),
      ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 196),
        child: ValueListenableBuilder<int>(
          valueListenable: t._nowMsNotifier,
          builder: (context, now, _) => GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            mainAxisSpacing: 7,
            crossAxisSpacing: 7,
            childAspectRatio: 1.25,
            padding: EdgeInsets.zero,
            children: [for (final g in _kGifts) _giftCell(g, t._giftCooldownLeft(g.id, DateTime.now().millisecondsSinceEpoch))],
          ),
        ),
      ),
      const SizedBox(height: 10),
      Row(children: [
        if (!widget.giftMode) ...[
          GestureDetector(
            onTap: () => setState(() => _gifts = false),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: const Color(0xA60B0721), borderRadius: BorderRadius.circular(12), border: Border.all(color: OkeyXColors.line2, width: 1.3)),
              child: const Icon(Icons.arrow_back_rounded, size: 18, color: OkeyXColors.cream),
            ),
          ),
          const SizedBox(width: 7),
        ],
        Expanded(
          child: OkxButton.ghost(
            label: 'HERKESE',
            icon: Icons.groups_rounded,
            height: 38,
            fontSize: 11.5,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            expand: true,
            onTap: _sending ? null : () => unawaited(_send(everyone: true)),
          ),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: OkxButton(
            label: 'GÖNDER',
            icon: Icons.send_rounded,
            height: 38,
            fontSize: 12,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            expand: true,
            onTap: _sending ? null : () => unawaited(_send()),
          ),
        ),
      ]),
    ]);
  }

  Widget _giftCell(_GiftDef g, int cooldown) {
    final selected = _selected == g.id;
    return GestureDetector(
      onTap: cooldown > 0 ? null : () => setState(() => _selected = g.id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        decoration: BoxDecoration(
          color: const Color(0x4D000000),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: selected ? OkeyXColors.gold : OkeyXColors.line, width: selected ? 2 : 1.2),
          boxShadow: selected ? const [BoxShadow(color: Color(0x40FFC864), blurRadius: 12)] : const [],
        ),
        child: Stack(children: [
          Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(g.emoji, style: const TextStyle(fontSize: 24, height: 1.1)),
              const SizedBox(height: 3),
              Text(g.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: OkeyXColors.cream)),
            ]),
          ),
          if (g.style == 'big')
            const Positioned(right: 5, top: 4, child: Icon(Icons.auto_awesome_rounded, size: 11, color: OkeyXColors.gold)),
          if (cooldown > 0)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(color: const Color(0xB3000000), borderRadius: BorderRadius.circular(12)),
                child: Center(
                  child: Text('0:${cooldown.toString().padLeft(2, '0')}', style: const TextStyle(fontFamily: OkeyXFonts.number, fontSize: 15, color: OkeyXColors.cream)),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}





/// Hediye çarpma efekti. [t] 0→1 çarpma anından itibaren ilerler.
/// Domates/yumurta profilde patlar ve akar, terlik vurup sekerek düşer,
/// çay/kahve bardağından buhar tüter, gül yaprakları dökülür, nazar halkası yayılır.
class _GiftFxPainter extends CustomPainter {
  _GiftFxPainter({required this.kind, required this.emoji, required this.t, required this.unit});

  final String kind;
  final String emoji;
  final double t;
  final double unit;

  static final _rand = math.Random(7);
  static final List<double> _lobes = List.generate(14, (_) => .72 + _rand.nextDouble() * .5);
  static final List<Offset> _bits = List.generate(16, (_) => Offset(_rand.nextDouble() * 2 - 1, _rand.nextDouble() * 2 - 1));

  double get _fade => t < .78 ? 1.0 : (1 - (t - .78) / .22).clamp(0.0, 1.0);

  void _emoji(Canvas canvas, Offset c, double size, {double angle = 0, double opacity = 1}) {
    final tp = TextPainter(
      text: TextSpan(text: emoji, style: TextStyle(fontSize: size, color: Colors.white.withValues(alpha: opacity))),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(angle);
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
  }

  Path _blob(Offset c, double r) {
    final path = Path();
    final n = _lobes.length;
    for (var i = 0; i <= n; i++) {
      final a = i / n * math.pi * 2;
      final rr = r * _lobes[i % n];
      final p = c + Offset(math.cos(a) * rr, math.sin(a) * rr * .86);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        final pa = (i - .5) / n * math.pi * 2;
        final ctrl = c + Offset(math.cos(pa) * r * 1.18, math.sin(pa) * r * 1.0);
        path.quadraticBezierTo(ctrl.dx, ctrl.dy, p.dx, p.dy);
      }
    }
    return path..close();
  }

  void _splat(Canvas canvas, Offset c, {required Color main, required Color dark, Color? yolk}) {
    final pop = Curves.easeOutBack.transform((t / .16).clamp(0.0, 1.0));
    final r = unit * .62 * pop;
    final a = _fade;
    // Fırlayan parçalar
    if (t < .45) {
      final q = t / .45;
      final paint = Paint()..color = main.withValues(alpha: (1 - q) * a);
      for (final b in _bits) {
        final p = c + Offset(b.dx * unit * 1.5 * q, b.dy * unit * 1.2 * q + q * q * unit * .6);
        canvas.drawCircle(p, unit * .07 * (1 - q * .5), paint);
      }
    }
    // Akan damlalar
    final drip = Paint()..color = main.withValues(alpha: a);
    for (var i = 0; i < 4; i++) {
      final x = c.dx + (i - 1.5) * r * .42;
      final len = unit * (.35 + i % 2 * .25) * Curves.easeIn.transform(((t - .12) / .7).clamp(0.0, 1.0));
      final w = unit * (.10 - i % 2 * .03);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x - w / 2, c.dy, w, r * .5 + len), Radius.circular(w / 2)), drip);
      canvas.drawCircle(Offset(x, c.dy + r * .5 + len), w * .62, drip);
    }
    canvas.drawPath(_blob(c + Offset(0, unit * .04), r * 1.04), Paint()..color = dark.withValues(alpha: .55 * a));
    canvas.drawPath(_blob(c, r), Paint()..color = main.withValues(alpha: a));
    if (yolk != null) {
      canvas.drawCircle(c + Offset(r * .08, r * .04), r * .42, Paint()..color = yolk.withValues(alpha: a));
      canvas.drawCircle(c + Offset(-r * .06, -r * .1), r * .12, Paint()..color = Colors.white.withValues(alpha: .7 * a));
    } else {
      // domates çekirdekleri
      final seed = Paint()..color = const Color(0xFFFFE08A).withValues(alpha: .9 * a);
      for (var i = 0; i < 7; i++) {
        final b = _bits[i];
        canvas.drawOval(Rect.fromCenter(center: c + Offset(b.dx * r * .55, b.dy * r * .45), width: unit * .07, height: unit * .045), seed);
      }
    }
    canvas.drawCircle(c + Offset(-r * .35, -r * .35), r * .16, Paint()..color = Colors.white.withValues(alpha: .35 * a));
  }

  void _steam(Canvas canvas, Offset base) {
    final a = _fade;
    for (var k = 0; k < 3; k++) {
      final phase = (t * 1.6 + k / 3) % 1.0;
      final path = Path();
      for (var j = 0; j <= 18; j++) {
        final y = -j / 18 * unit * 1.25;
        final x = math.sin(j / 18 * math.pi * 2 + t * 8 + k) * unit * .10 + (k - 1) * unit * .16;
        final p = base + Offset(x, y - phase * unit * .35);
        j == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = unit * .07
          ..strokeCap = StrokeCap.round
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, unit * .05)
          ..color = Colors.white.withValues(alpha: .55 * (1 - phase) * a),
      );
    }
  }

  void _teaGlass(Canvas canvas, Offset c) {
    final a = _fade;
    final w = unit * .46, h = unit * .62;
    final glass = Path()
      ..moveTo(c.dx - w * .5, c.dy - h * .5)
      ..quadraticBezierTo(c.dx - w * .22, c.dy, c.dx - w * .42, c.dy + h * .5)
      ..lineTo(c.dx + w * .42, c.dy + h * .5)
      ..quadraticBezierTo(c.dx + w * .22, c.dy, c.dx + w * .5, c.dy - h * .5)
      ..close();
    canvas.drawPath(glass, Paint()..color = const Color(0xFFB5390F).withValues(alpha: .92 * a));
    canvas.drawPath(glass, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = unit * .03
      ..color = Colors.white.withValues(alpha: .75 * a));
    canvas.drawOval(Rect.fromCenter(center: c + Offset(0, h * .56), width: w * 1.5, height: unit * .12), Paint()..color = const Color(0xFFE8C478).withValues(alpha: a));
    canvas.drawLine(c + Offset(-w * .3, -h * .35), c + Offset(-w * .2, h * .3), Paint()
      ..strokeWidth = unit * .04
      ..color = Colors.white.withValues(alpha: .4 * a));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final a = _fade;
    switch (kind) {
      case 'tomato':
      case 'domates':
        _splat(canvas, c, main: const Color(0xFFD7261C), dark: const Color(0xFF7A0E08));
      case 'egg':
      case 'yumurta':
        // kabuk parçaları
        if (t < .3) {
          final q = t / .3;
          final shell = Paint()..color = const Color(0xFFF4EBDD).withValues(alpha: 1 - q);
          for (var i = 0; i < 6; i++) {
            final b = _bits[i];
            final p = c + Offset(b.dx * unit * 1.1 * q, b.dy * unit * .9 * q - unit * .3 * q);
            canvas.drawPath(Path()..addPolygon([p, p + Offset(unit * .12, unit * .02), p + Offset(unit * .04, unit * .11)], true), shell);
          }
        }
        _splat(canvas, c, main: const Color(0xFFFBF6EA), dark: const Color(0xFF8D8AA8), yolk: const Color(0xFFFFB81F));
      case 'slipper':
      case 'terlik':
      case 'fish':
      case 'rubber_chicken':
        // PAT! yıldızı + terlik geri seker
        if (t < .4) {
          final q = Curves.easeOut.transform(t / .4);
          final star = Path();
          for (var i = 0; i < 16; i++) {
            final ang = i / 16 * math.pi * 2;
            final rr = (i.isEven ? 1.0 : .55) * unit * (.5 + .55 * q);
            final p = c + Offset(math.cos(ang) * rr, math.sin(ang) * rr);
            i == 0 ? star.moveTo(p.dx, p.dy) : star.lineTo(p.dx, p.dy);
          }
          star.close();
          canvas.drawPath(star, Paint()..color = const Color(0xFFFFD34D).withValues(alpha: 1 - q));
          final tp = TextPainter(
            text: TextSpan(text: 'PAT!', style: TextStyle(fontFamily: OkeyXFonts.number, fontSize: unit * .42 * (.8 + .4 * q), color: const Color(0xFF7A1408).withValues(alpha: 1 - q * .6))),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
        }
        final bounce = Curves.easeOut.transform(t);
        final pos = c + Offset(unit * 1.0 * bounce, -unit * 1.1 * math.sin(bounce * math.pi * .9) + unit * .9 * bounce * bounce);
        _emoji(canvas, pos, unit * .8, angle: -bounce * math.pi * 1.6, opacity: a);
        // baş dönmesi yıldızları
        for (var i = 0; i < 3; i++) {
          final ang = t * math.pi * 4 + i * math.pi * 2 / 3;
          _drawSpark(canvas, c + Offset(math.cos(ang) * unit * .55, -unit * .55 + math.sin(ang) * unit * .16), unit * .1, a);
        }
      case 'tea':
      case 'coffee':
      case 'çay':
      case 'türk kahvesi':
        final land = Curves.easeOutBack.transform((t / .2).clamp(0.0, 1.0));
        final cup = c + Offset(unit * .7, unit * .15 + (1 - land) * -unit * .4);
        if (kind == 'tea' || kind == 'çay') {
          _teaGlass(canvas, cup);
        } else {
          _emoji(canvas, cup, unit * .75, opacity: a);
        }
        _steam(canvas, cup - Offset(0, unit * .38));
      case 'rose':
      case 'gül':
        _emoji(canvas, c + Offset(unit * .75, unit * .1), unit * .7 * Curves.easeOutBack.transform((t / .2).clamp(0.0, 1.0)), opacity: a);
        for (var i = 0; i < 12; i++) {
          final b = _bits[i];
          final fall = (t * 1.2 + i / 12) % 1.0;
          final p = c + Offset(b.dx * unit * 1.2 + math.sin(fall * 6 + i) * unit * .15, -unit * 1.3 + fall * unit * 2.4);
          canvas.save();
          canvas.translate(p.dx, p.dy);
          canvas.rotate(fall * 6 + i);
          canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: unit * .16, height: unit * .1), Paint()..color = const Color(0xFFE23B5C).withValues(alpha: .85 * a * (1 - fall * .4)));
          canvas.restore();
        }
      case 'nazar':
      case 'nazar boncuğu':
        for (var k = 0; k < 3; k++) {
          final q = ((t * 1.4) - k * .18).clamp(0.0, 1.0);
          canvas.drawCircle(c, unit * (.4 + q * 1.3), Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = unit * .07 * (1 - q)
            ..color = const Color(0xFF3FA9F5).withValues(alpha: (1 - q) * a));
        }
        _emoji(canvas, c + Offset(unit * .7, -unit * .3), unit * .6, opacity: a);
      default:
        _emoji(canvas, c + Offset(0, -unit * .7 - t * unit * .4), unit * .75 * Curves.easeOutBack.transform((t / .25).clamp(0.0, 1.0)), opacity: a);
        for (var i = 0; i < 10; i++) {
          final b = _bits[i];
          _drawSpark(canvas, c + Offset(b.dx, b.dy) * unit * (0.4 + t * 1.1), unit * .09 * (1 - t), a);
        }
    }
  }

  void _drawSpark(Canvas canvas, Offset p, double r, double a) {
    final path = Path();
    for (var i = 0; i < 8; i++) {
      final ang = i / 8 * math.pi * 2;
      final rr = i.isEven ? r : r * .38;
      final q = p + Offset(math.cos(ang) * rr, math.sin(ang) * rr);
      i == 0 ? path.moveTo(q.dx, q.dy) : path.lineTo(q.dx, q.dy);
    }
    canvas.drawPath(path..close(), Paint()..color = const Color(0xFFFFE08A).withValues(alpha: a));
  }

  @override
  bool shouldRepaint(_GiftFxPainter old) => old.t != t || old.kind != kind || old.unit != unit;
}


/// Istakada per taşıma için hızlı (280 ms) basılı tutma algılayıcı.
/// Varsayılan 500 ms çok uzun geldiği için perler zor yakalanıyordu.
class _QuickLongPress extends StatelessWidget {
  const _QuickLongPress({required this.child, required this.onTap, required this.onLongPressStart, required this.onLongPressMoveUpdate, required this.onLongPressEnd});

  final Widget child;
  final VoidCallback onTap;
  final GestureLongPressStartCallback onLongPressStart;
  final GestureLongPressMoveUpdateCallback onLongPressMoveUpdate;
  final GestureLongPressEndCallback onLongPressEnd;

  @override
  Widget build(BuildContext context) => RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: <Type, GestureRecognizerFactory>{
          TapGestureRecognizer: GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
            () => TapGestureRecognizer(),
            (r) => r.onTap = onTap,
          ),
          LongPressGestureRecognizer: GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
            () => LongPressGestureRecognizer(duration: const Duration(milliseconds: 280)),
            (r) => r
              ..onLongPressStart = onLongPressStart
              ..onLongPressMoveUpdate = onLongPressMoveUpdate
              ..onLongPressEnd = onLongPressEnd,
          ),
        },
        child: child,
      );
}
