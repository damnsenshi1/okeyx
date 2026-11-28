import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_theme.dart';
import '../../core/game_audio.dart';
import '../../core/app_updater.dart';
import '../onboarding/onboarding_overlay.dart';
import 'reward_fx.dart';
import '../../core/live_features.dart';
import '../../core/remote_config.dart';
import '../../core/telemetry.dart';
import '../../widgets/game_mode_picker.dart';
import '../../widgets/okx_kit.dart';
import '../../widgets/tile_widget.dart';
import '../../widgets/premium_radio_panel.dart';
import '../auth/auth_service.dart';
import '../auth/profile_repository.dart';
import '../lobby/lobby_api.dart';
import '../../core/crash_reporter.dart';
import '../../core/push_service.dart';
import '../tutorial/tutorial_screen.dart';
import '../tournament/tournament_screen.dart';
import '../phase4/phase4_screen.dart';
import '../phase4/chance_hall.dart';
import '../phase4/staff_console.dart';
import '../phase4/ad_service.dart';
import '../settings/settings_screen.dart';
import '../spectator/yanci_center_screen.dart';
import '../table/table_screen.dart';

class HomeShell extends StatefulWidget {
  final PlayerBundle bundle;
  final MobileRemoteConfig remoteConfig;
  final ProfileRepository repository;
  final AuthService auth;
  final ValueChanged<PlayerBundle> onBundleChanged;

  const HomeShell({
    super.key,
    required this.bundle,
    required this.remoteConfig,
    required this.repository,
    required this.auth,
    required this.onBundleChanged,
  });

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final AdService _interstitialAds = AdService();
  late PlayerProfile _profile = widget.bundle.profile;
  late UserPreferences _preferences = widget.bundle.preferences;
  late LobbyApiClient _api;
  Timer? _updateTimer;
  Timer? _roomTimer;
  Timer? _socialTimer;
  Timer? _alertTimer;
  bool _alertBusy = false;
  Timer? _activityTimer;
  final TextEditingController _playerSearchController = TextEditingController();

  int _selected = 0;
  bool _loading = false;
  bool _busy = false;
  bool _refreshingLiveHub = false;
  String _message = '';

  Map<String, dynamic> _account = const {};
  List<Map<String, dynamic>> _rooms = const [];
  String _roomFilter = 'all';
  Map<String, dynamic> _missions = const {};
  Map<String, dynamic> _social = const {};
  Map<String, dynamic> _notifications = const {};
  Map<String, dynamic> _referral = const {};
  Map<String, dynamic> _canak = const {};
  Map<String, dynamic> _season = const {};
  Map<String, dynamic> _clubs = const {};
  Map<String, dynamic> _leaderboard = const {};
  Map<String, dynamic> _rewardConfig = const {};
  Map<String, dynamic> _phase4Hub = const {};
  List<Map<String, dynamic>> _activity = const [];
  int _activityIndex = 0;
  OkeyXNowPlaying _nowPlaying = const OkeyXNowPlaying('', '');
  Timer? _nowPlayingTimer;
  List<Map<String, dynamic>> _searchResults = const [];
  GameSession? _resumeSession;
  OkeyXLiveFeatures _liveFeatures = const OkeyXLiveFeatures();
  bool _staffFallback = false;
  Map<String,dynamic> _staffFallbackData = const {};

  bool _turbo = false;
  String _variant = 'non_fold';
  String _lastRuleVariant = 'non_fold';
  String _teamMode = 'solo';
  bool _assisted = true;
  int _rounds = 1;
  int _entryFee = 5000;
  int _turnSeconds = 35;
  String _leagueScope = 'global';
  String _gameCategory = 'Tümü';

  List<(int, IconData, String)> get _visibleDestinations => [
    (0, Icons.sports_esports_rounded, 'Oyunlar'),
    (1, Icons.table_bar_rounded, 'Masalar'),
    (2, Icons.emoji_events_rounded, 'Etkinlikler'),
    (3, Icons.groups_rounded, 'Sosyal'),
    (4, Icons.shield_rounded, 'Kulüp'),
    if (_liveFeatures.chanceHallEnabled) (5, Icons.auto_awesome_rounded, 'Şans'),
    (6, Icons.storefront_rounded, 'Mağaza'),
    if (_isStaff) (7, Icons.admin_panel_settings_rounded, 'Operasyon'),
  ];

  bool get _isStaff => _map(_phase4Hub['staff'])['enabled'] == true || _staffFallback;
  List<Map<String, dynamic>> get _liveEvents => _list(_phase4Hub['live_events']).map(_map).toList();
  bool get _socialLocked => _social['requires_account_link'] == true;

  @override
  void initState() {
    super.initState();
    _api = LobbyApiClient(_profile);
    CrashReporter.playerId = _profile.userId;
    _account = <String,dynamic>{
      'id': _profile.userId,
      'name': _profile.displayName,
      'chips': _profile.coins,
      'diamonds': _profile.diamonds,
      'level': _profile.level,
      'xp': _profile.xp,
      'stats': <String,dynamic>{'games': _profile.gamesPlayed, 'wins': _profile.wins},
    };
    _phase4Hub = <String,dynamic>{
      'wallet': <String,dynamic>{'coins': _profile.coins, 'diamonds': _profile.diamonds, 'tickets': 3},
    };
    unawaited(GameAudio.setVolumes(music:_preferences.musicVolume,radio:_preferences.radioVolume,ambience:_preferences.ambienceVolume,sfx:_preferences.sfxVolume));
    unawaited(GameAudio.sfx('lobby_sting', enabled: _preferences.soundEnabled, volume: .72));
    unawaited(_loadLiveAudio());
    unawaited(_loadRewardState());
    unawaited(_loadStaffFallback());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 420), () {
        if (mounted) unawaited(_maybeOnboard());
      });
      Future<void>.delayed(const Duration(seconds: 3), () {
        if (mounted) unawaited(AppUpdater.checkAndPrompt(context));
      });
    });
    Future<void>.delayed(const Duration(milliseconds: 2400), () {
      if (mounted && _preferences.soundEnabled) unawaited(GameAudio.prewarm());
    });
    unawaited(_loadHub(first: true));
    Future<void>.delayed(const Duration(seconds: 9), () {
      if (mounted) unawaited(_setupPush());
    });
    _roomTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted && !_busy && _selected == 1) unawaited(_refreshRooms());
    });
    // Davet / arkadaşlık bildirimleri için hızlı ve hafif yoklama (3 sn).
    _alertTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) unawaited(_pollAlerts());
    });
    _updateTimer = Timer.periodic(const Duration(minutes: 30), (_) {
      if (mounted) unawaited(AppUpdater.checkAndPrompt(context));
    });
    _socialTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      if (mounted && !_busy) unawaited(_refreshLiveHub());
      if (mounted) unawaited(_api.presencePing());
    });
    _nowPlayingTimer = Timer.periodic(const Duration(seconds: 18), (_) { if (mounted && _preferences.radioEnabled) unawaited(_refreshNowPlaying()); });
    _activityTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted && _activity.isNotEmpty) setState(() => _activityIndex = (_activityIndex + 1) % _activity.length);
    });
  }

  @override
  void dispose() {
    _roomTimer?.cancel();
    _updateTimer?.cancel();
    _socialTimer?.cancel();
    _alertTimer?.cancel();
    _pushInSub?.cancel();
    _activityTimer?.cancel();
    _nowPlayingTimer?.cancel();
    _pushTapSub?.cancel();
    _inviteEntry?.remove();
    _inviteEntry = null;
    _playerSearchController.dispose();
    _api.dispose();
    unawaited(GameAudio.stopLobby());
    unawaited(GameAudio.stopRadio());
    unawaited(GameAudio.stopAmbience());
    super.dispose();
  }

  /// Sunucudan ilk cüzdan gelene kadar eski (telefonda kayıtlı) sayı gösterilmez.
  bool _walletSynced = false;
  int get _chips => _integer(_account['chips'], fallback: _profile.coins);
  int get _level => _integer(_account['level'], fallback: _profile.level);
  int get _xp => _integer(_account['xp'], fallback: _profile.xp);
  Map<String, dynamic> get _stats => _map(_account['stats']);
  List<Map<String, dynamic>> get _friends => _list(_social['friends']).map(_map).toList();
  List<Map<String, dynamic>> get _requests => _list(_social['requests']).map(_map).toList();
  List<Map<String, dynamic>> get _recent => _list(_social['recent_players']).map(_map).toList();
  Set<String> get _sentFriendRequests => _list(_social['sent_requests']).map((x) => '$x').toSet();
  List<Map<String, dynamic>> get _notificationRows => _list(_notifications['notifications']).map(_map).toList();


  Future<T> _safe<T>(Future<T> future, T fallback, String tag) async {
    try {
      return await future.timeout(const Duration(seconds: 4));
    } catch (e) {
      debugPrint('OKEYX_SOFT_FAIL[$tag] $e');
      return fallback;
    }
  }

  /// Yeni oyuncu karşılaması (bir kez). Hoş geldin hediyesi 1.000.000 altın
  /// sunucuda hesap açılırken yüklenir; burada kutlanır.
  Future<void> _maybeOnboard() async {
    // Karşılama yalnız gerçekten yeni oyuncuya: daha önce oynamış hesapta
    // (telefon değişse ya da uygulama yeniden kurulsa da) tekrar çıkmaz.
    final games = _integer(_map(_account['stats'])['games'], fallback: _profile.gamesPlayed);
    if (games > 0) {
      await OkxOnboarding.markDone(_profile.userId);
      return;
    }
    if (!await OkxOnboarding.shouldShow(_profile.userId) || !mounted) return;
    final next = await OkxOnboarding.show(context, userId: _profile.userId, name: _profile.displayName, sound: _preferences.soundEnabled);
    if (!mounted) return;
    if (next == 'practice') unawaited(_practicePlay());
    if (next == 'tutorial') _openTutorial();
  }

  // ignore: unused_element
  Future<void> _maybeShowWelcomeBonus() async {
    try {
      final raw = await Supabase.instance.client.rpc('okeyx_welcome_bonus_status');
      final status = _map(raw);
      if (!mounted || status['ok'] != true || status['available'] != true) return;
      final claimed = await showGeneralDialog<bool>(
        context: context,
        barrierDismissible: false,
        barrierLabel: 'Hoş geldin bonusu',
        barrierColor: const Color(0xE6000810),
        transitionDuration: (_preferences.reducedMotionEnabled || _preferences.dataSaverEnabled)
            ? Duration.zero
            : const Duration(milliseconds: 240),
        transitionBuilder: (_, animation, __, child) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: .94, end: 1).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        ),
        pageBuilder: (dialogContext, _, __) => Material(
          color: Colors.transparent,
          child: SafeArea(
            minimum: const EdgeInsets.all(8),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxHeight < 430 || constraints.maxWidth < 620;
                final dialogWidth = math.min(360.0, constraints.maxWidth - 16).clamp(250.0, 360.0).toDouble();
                final maxHeight = (constraints.maxHeight - 12).clamp(240.0, 560.0).toDouble();
                final heroSize = compact ? 50.0 : 66.0;
                return Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: dialogWidth, maxHeight: maxHeight),
                    child: Container(
                      width: dialogWidth,
                      padding: EdgeInsets.fromLTRB(compact ? 14 : 22, compact ? 11 : 18, compact ? 14 : 22, compact ? 11 : 18),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(compact ? 20 : 28),
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF2D1D7B), Color(0xFF191042), Color(0xFF0E0927)],
                        ),
                        border: Border.all(color: OkeyXColors.gold, width: 1.5),
                        boxShadow: const [BoxShadow(color: Color(0x66F4C542), blurRadius: 28)],
                      ),
                      child: SingleChildScrollView(
                        physics: const ClampingScrollPhysics(),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          SizedBox(
                            width: heroSize + 24,
                            height: heroSize + 12,
                            child: Stack(alignment: Alignment.center, children: [
                              Icon(Icons.auto_awesome_rounded, size: heroSize + 20, color: OkeyXColors.gold.withValues(alpha: .14)),
                              Container(
                                width: heroSize,
                                height: heroSize,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: OkeyXColors.gold.withValues(alpha: .13),
                                  border: Border.all(color: OkeyXColors.gold.withValues(alpha: .50), width: 1.3),
                                ),
                                child: Icon(Icons.monetization_on_rounded, color: OkeyXColors.gold, size: heroSize * .58),
                              ),
                            ]),
                          ),
                          Text(
                            'HOŞ GELDİN!',
                            maxLines: 1,
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: compact ? 16 : 21, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: .6),
                          ),
                          SizedBox(height: compact ? 2 : 4),
                          Text(
                            'OkeyX masalarına ilk adım hediyen hazır.',
                            maxLines: 2,
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: compact ? 7.5 : 9, color: Colors.white60, fontWeight: FontWeight.w600),
                          ),
                          SizedBox(height: compact ? 8 : 13),
                          Container(
                            width: double.infinity,
                            padding: EdgeInsets.symmetric(vertical: compact ? 7 : 11, horizontal: 8),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(15),
                              color: OkeyXColors.gold.withValues(alpha: .09),
                              border: Border.all(color: OkeyXColors.gold.withValues(alpha: .28)),
                            ),
                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                              Text('BAŞLANGIÇ BONUSU', maxLines: 1, style: TextStyle(fontSize: compact ? 6 : 7.5, color: Colors.white54, fontWeight: FontWeight.w900, letterSpacing: .8)),
                              const SizedBox(height: 2),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text('10.000 ALTIN', style: TextStyle(fontSize: compact ? 21 : 27, color: OkeyXColors.gold, fontWeight: FontWeight.w900)),
                              ),
                            ]),
                          ),
                          SizedBox(height: compact ? 9 : 14),
                          SizedBox(
                            width: double.infinity,
                            height: compact ? 40 : 46,
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: OkeyXColors.gold,
                                foregroundColor: const Color(0xFF140D36),
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                              onPressed: () => Navigator.pop(dialogContext, true),
                              icon: Icon(Icons.redeem_rounded, size: compact ? 18 : 21),
                              label: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text('BONUSU AL', style: TextStyle(fontSize: compact ? 10 : 12, fontWeight: FontWeight.w900, letterSpacing: .6)),
                              ),
                            ),
                          ),
                          SizedBox(height: compact ? 4 : 7),
                          const Text(
                            'Bu hediye her hesapta yalnızca 1 kez alınabilir.',
                            maxLines: 2,
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 6.2, color: Colors.white38),
                          ),
                        ]),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      if (claimed != true || !mounted) return;
      final claimRaw = await Supabase.instance.client.rpc('okeyx_claim_welcome_bonus');
      final out = _map(claimRaw);
      if (out['ok'] == true) {
        final coins = _integer(out['coins'], fallback: math.max(_chips, 10000));
        setState(() => _account = {..._account, 'chips': coins});
        if (_preferences.vibrationEnabled) unawaited(HapticFeedback.mediumImpact());
        unawaited(GameAudio.sfx('reward', enabled: _preferences.soundEnabled, volume: .9));
        await _showRewardBurst('HOŞ GELDİN BONUSU', 10000, Icons.redeem_rounded);
      }
    } catch (e) {
      debugPrint('OKEYX_WELCOME_BONUS $e');
    }
  }

  Future<void> _loadRewardState() async {
    try {
      final results = await Future.wait<dynamic>([
        _api.dailyRewardState().timeout(const Duration(seconds: 2)),
        _api.rewardConfig().timeout(const Duration(seconds: 2)),
      ]);
      final x = _map(results[0]);
      final cfg = _map(results[1]);
      if (!mounted || x['ok'] != true) return;
      if (cfg.isNotEmpty) _rewardConfig = cfg;
      final accountState = _map(x['account']);
      if (accountState.isNotEmpty) {
        setState(() => _account = {..._account, ...accountState});
        return;
      }
      final today = _todayKey;
      setState(() {
        _account = {..._account,
          'daily': {..._map(_account['daily']), if (x['daily_used']==true) 'last_claim_day': today},
          'wheel': {..._map(_account['wheel']), if (x['wheel_used']==true) 'last_spin_day': today},
          'chests': {..._map(_account['chests']), if (x['chest_used']==true) 'last_free_day': today},
        };
      });
    } catch (_) {}
  }

  Future<void> _refreshNowPlaying() async {
    if (!_preferences.radioEnabled || !_liveFeatures.radioEnabled || _liveFeatures.radioStations.isEmpty) return;
    final st = _liveFeatures.station(_preferences.radioStation);
    final np = await RadioNowPlayingService.fetch(st);
    if (mounted && np.available) setState(() => _nowPlaying = np);
  }

  Future<void> _loadStaffFallback() async {
    try {
      final row = await Supabase.instance.client
          .from('okeyx_staff_roles')
          .select('role,permissions,active')
          .eq('user_id', _profile.userId)
          .eq('active', true)
          .maybeSingle();
      if (!mounted || row == null) return;
      final data = <String,dynamic>{
        'enabled': true,
        'role': '${row['role'] ?? 'staff'}',
        'permissions': _list(row['permissions']),
        'source': 'supabase_fallback',
      };
      setState(() {
        _staffFallback = true;
        _staffFallbackData = data;
        final current = _map(_phase4Hub['staff']);
        if (current['enabled'] != true) _phase4Hub = {..._phase4Hub, 'staff': data};
      });
    } catch (e) {
      debugPrint('OKEYX_STAFF_FALLBACK $e');
    }
  }

  Map<String,dynamic> _mergeStaffFallback(Map<String,dynamic> hub) {
    if (!_staffFallback) return hub;
    final current = _map(hub['staff']);
    if (current['enabled'] == true) return hub;
    return {...hub, 'staff': _staffFallbackData};
  }

  Future<void> _loadLiveAudio() async {
    final f=await LiveFeatureService().load(); if(!mounted)return; setState(()=>_liveFeatures=f);
    await _applyAudio();
    unawaited(_refreshNowPlaying());
  }
  Future<void> _applyAudio() async {
    await GameAudio.setVolumes(
      music: _preferences.musicVolume,
      radio: _preferences.radioVolume,
      ambience: _preferences.ambienceVolume,
      sfx: _preferences.sfxVolume,
    );
    if (_preferences.radioEnabled && _liveFeatures.radioEnabled) {
      final st = _liveFeatures.station(_preferences.radioStation);
      try {
        await GameAudio.startRadio(source: st.source, remote: st.remote);
      } catch (_) {
        await GameAudio.startLobby(enabled: _preferences.musicEnabled);
      }
    } else {
      await GameAudio.stopRadio();
      if (_preferences.musicEnabled) {
        await GameAudio.startLobby();
      } else {
        await GameAudio.stopLobby();
      }
    }
  }

  Future<void> _setHomeRadio(String? stationId) async {
    final next = _preferences.copyWith(
      radioEnabled: stationId != null,
      radioStation: stationId ?? _preferences.radioStation,
    );
    if (mounted) setState(() => _preferences = next);
    try {
      await widget.repository.savePreferences(next);
      widget.onBundleChanged(PlayerBundle(_profile, next));
      await _applyAudio();
      unawaited(_refreshNowPlaying());
    } catch (_) {
      _flash('Radyo tercihi kaydedilemedi.');
    }
  }

  Future<void> _showRadioMenu() async {
    if (!_liveFeatures.radioEnabled || _liveFeatures.radioStations.isEmpty) {
      _flash('Radyo kanalları şu anda yüklenemedi.');
      return;
    }
    if (_preferences.radioEnabled) await _refreshNowPlaying();
    if (!mounted) return;
    final selected = await showDialog<String>(
      context: context,
      barrierColor: const Color(0xCC00070C),
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(8),
        backgroundColor: Colors.transparent,
        child: PremiumRadioPanel(
          stations: _liveFeatures.radioStations,
          activeStationId: _preferences.radioStation,
          playing: _preferences.radioEnabled,
          nowPlaying: _nowPlaying,
        ),
      ),
    );
    if (selected == null) return;
    if (selected == '__off__') { await _setHomeRadio(null); return; }
    if (selected == '__play__') { await _setHomeRadio(_preferences.radioStation); return; }
    await _setHomeRadio(selected);
  }

  void _openYanciCenter() {
    unawaited(Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => YanciCenterScreen(
        api: _api,
        soundEnabled: _preferences.soundEnabled,
        vibrationEnabled: _preferences.vibrationEnabled,
      ),
    )));
  }

  Future<void> _loadHub({bool first = false}) async {
    // Render the lobby immediately from the cached Supabase profile. Network
    // bootstrap is background work and must never hold the whole UI hostage.
    try {
      final account = await _api.bootstrap().timeout(const Duration(seconds: 12));
      final roomsFuture = _safe(_api.rooms(), <Map<String,dynamic>>[], 'rooms');
      final reconnectFuture = _safe<GameSession?>(_api.reconnect(), null, 'reconnect');
      final critical = await Future.wait<dynamic>([roomsFuture, reconnectFuture]);
      if (!mounted) return;
      setState(() {
        // Supabase profile wallet is durable; a fresh/restarted runtime must
        // not visually reset the player's balance to its in-memory defaults.
        final merged = Map<String,dynamic>.from(account);
        // Sunucu cüzdanı tek doğru kaynaktır: altın gönderince/kaybedince
        // eski (yüksek) Supabase değeri ekranda kalmasın.
        merged['chips'] = _integer(account['chips'], fallback: _profile.coins);
        // Altın, elmas, seviye ve XP'nin tek doğru kaynağı oyun sunucusudur.
        // Eskiden telefondaki profil ile "büyük olan" gösteriliyordu; eski
        // yüksek değer ekranda kalıp birkaç saniye sonra değişiyordu.
        merged['diamonds'] = _integer(account['diamonds'], fallback: _profile.diamonds);
        merged['level'] = _integer(account['level'], fallback: _profile.level);
        merged['xp'] = _integer(account['xp'], fallback: _profile.xp);
        _walletSynced = true;
        _account = {..._account, ...merged};
        _phase4Hub = {..._phase4Hub, 'wallet': <String,dynamic>{
          'coins': _integer(_account['chips'], fallback: _profile.coins),
          'diamonds': _integer(_account['diamonds'], fallback: _profile.diamonds),
          'tickets': _integer(_map(_phase4Hub['wallet'])['tickets'], fallback: 3),
        }};
        _rooms = List<Map<String, dynamic>>.from(critical[0] as List);
        _resumeSession = critical[1] as GameSession?;
        _loading = false;
        _message = '';
      });
      Future<void>.delayed(const Duration(milliseconds: 120), () {
        if (mounted) unawaited(_loadSecondaryHub());
      });
    } catch (error) {
      if (!mounted) return;
      debugPrint('OKEYX_BOOT_SOFT_FAIL $error');
      setState(() {
        _loading = false;
        _message = 'Oyun sunucusuna bağlanılamadı • tekrar dene';
      });
    }
  }

  Future<void> _loadSecondaryHub() async {
    try {
      final results = await Future.wait<dynamic>([
        _safe(_api.missions(), <String,dynamic>{}, 'missions'),
        _safe(_api.social(), <String,dynamic>{}, 'social'),
        _safe(_api.notifications(), <String,dynamic>{}, 'notifications'),
        _safe(_api.referralInfo(), <String,dynamic>{}, 'referral'),
        _safe(_api.canak(), <String,dynamic>{}, 'canak'),
        _safe(_api.season(), <String,dynamic>{}, 'season'),
        _safe(_api.clubs(), <String,dynamic>{}, 'clubs'),
        _safe(_api.leaderboard(_leagueScope), <String,dynamic>{}, 'leaderboard'),
        _safe(_api.history(), <String,dynamic>{}, 'history'),
        _safe(_api.phase4Hub(), <String,dynamic>{}, 'phase4'),
        _safe(_api.liveActivity(), <Map<String,dynamic>>[], 'activity'),
      ]);
      if (!mounted) return;
      setState(() {
        _missions = _map(results[0]);
        _social = _map(results[1]);
        _notifications = _map(results[2]);
        _referral = _map(results[3]);
        _canak = _map(results[4]);
        _season = _map(results[5]);
        _clubs = _map(results[6]);
        _leaderboard = _map(results[7]);
        _account = {..._account, 'history': _list(_map(results[8])['history'])};
        _phase4Hub = _mergeStaffFallback(_map(results[9]));
        _activity = List<Map<String, dynamic>>.from(results[10] as List);
        if (_activity.isEmpty) {
          _activityIndex = 0;
        } else {
          _activityIndex %= _activity.length;
        }
      });
      _checkInvites();
    } catch (_) {}
  }

  Future<void> _refreshRooms() async {
    try {
      final rooms = await _api.rooms();
      if (mounted) setState(() => _rooms = rooms);
    } catch (_) {}
  }

  Future<void> _refreshLiveHub() async {
    if (_refreshingLiveHub) return;
    _refreshingLiveHub = true;
    try {
      // Keep lightweight presence/wallet data fresh, but do not poll every
      // secondary subsystem while the player is sitting on an unrelated tab.
      final jobs = <String, Future<dynamic>>{
        'account': _api.account(),
        'notifications': _api.notifications(),
        'social': _api.social(),
      };
      if (_resumeSession != null) jobs['reconnect'] = _api.reconnect();
      if (_selected == 5 || _selected == 6 || _selected == 7) {
        jobs['phase4'] = _api.phase4Hub();
      }
      if (_selected == 0 || _selected == 2) jobs['activity'] = _api.liveActivity();
      final keys = jobs.keys.toList(growable: false);
      final values = await Future.wait<dynamic>(jobs.values);
      if (!mounted) return;
      final data = <String, dynamic>{for (var i = 0; i < keys.length; i++) keys[i]: values[i]};
      setState(() {
        _account = {..._account, ..._map(data['account'])};
        _notifications = _map(data['notifications']);
        _social = _map(data['social']);
        if (data.containsKey('reconnect')) _resumeSession = data['reconnect'] as GameSession?;
        if (data.containsKey('phase4')) _phase4Hub = _mergeStaffFallback(_map(data['phase4']));
        if (data.containsKey('activity')) {
          _activity = List<Map<String, dynamic>>.from(data['activity'] as List);
          if (_activity.isEmpty) {
            _activityIndex = 0;
          } else {
            _activityIndex %= _activity.length;
          }
        }
      });
    } catch (_) {
      // A secondary refresh must never block the playable lobby.
    } finally {
      _refreshingLiveHub = false;
    }
  }

  void _applyWalletImmediate(Map<String,dynamic> wallet){
    if(!mounted||wallet.isEmpty)return;
    setState((){
      _phase4Hub={..._phase4Hub,'wallet':wallet};
      _account={..._account,'chips':_integer(wallet['coins'],fallback:_chips),'diamonds':_integer(wallet['diamonds'],fallback:_integer(_account['diamonds']))};
    });
  }

  Future<void> _refreshEconomy() async {
    try {
      final results = await Future.wait<dynamic>([_api.account(), _api.phase4Hub(), _api.liveActivity()]);
      if (!mounted) return;
      setState(() {
        _account = {..._account, ..._map(results[0])};
        _phase4Hub = _mergeStaffFallback(_map(results[1]));
        _activity = List<Map<String, dynamic>>.from(results[2] as List);
      });
    } catch (_) {}
  }

  Future<void> _refreshAccountBits() async {
    try {
      final results = await Future.wait<dynamic>([
        _api.account(),
        _api.missions(),
        _api.social(),
        _api.notifications(),
        _api.referralInfo(),
        _api.canak(),
        _api.season(),
        _api.clubs(),
        _api.leaderboard(_leagueScope),
        _api.history(),
        _api.phase4Hub(),
        _api.liveActivity(),
      ]);
      if (!mounted) return;
      final newLevel = _integer(_map(results[0])['level']);
      final shouldCelebrate = _seenLevel > 0 && newLevel > _seenLevel;
      if (newLevel > 0) _seenLevel = newLevel;
      if (shouldCelebrate) unawaited(_showLevelUp(newLevel));
      setState(() {
        _account = {..._map(results[0]), 'history': _list(_map(results[9])['history'])};
        _missions = _map(results[1]);
        _social = _map(results[2]);
        _notifications = _map(results[3]);
        _referral = _map(results[4]);
        _canak = _map(results[5]);
        _season = _map(results[6]);
        _clubs = _map(results[7]);
        _leaderboard = _map(results[8]);
        _phase4Hub = _mergeStaffFallback(_map(results[10]));
        _activity = List<Map<String, dynamic>>.from(results[11] as List);
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: OkeyXColors.ink,
        body: OkxRoom(
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxHeight < 470 || constraints.maxWidth < 850;
                final railWidth = compact ? 70.0 : 86.0;
                return Column(
                  children: [
                    _topBar(compact),
                    Expanded(
                      child: Row(
                        children: [
                          _navigation(railWidth, compact),
                          Expanded(
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: AnimatedSwitcher(
                                    duration: (_preferences.reducedMotionEnabled || _preferences.dataSaverEnabled) ? Duration.zero : const Duration(milliseconds: 200),
                                    child: KeyedSubtree(key: ValueKey(_selected), child: _page(_selected, compact)),
                                  ),
                                ),
                                if (_loading)
                                  const Positioned.fill(
                                    child: ColoredBox(
                                      color: Color(0x99000000),
                                      child: Center(child: CircularProgressIndicator(color: OkeyXColors.gold)),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );

  Widget _navigation(double width, bool compact) => Container(
        width: width,
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [Color(0x59000000), Color(0x00000000)]),
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: _visibleDestinations.length,
                itemBuilder: (context, index) {
                  final item = _visibleDestinations[index];
                  final selected = _selected == item.$1;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    child: GestureDetector(
                      onTap: () {
                        unawaited(GameAudio.sfx('ui_tap', enabled: _preferences.soundEnabled, volume: .65));
                        setState(() => _selected = item.$1);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        height: compact ? 54 : 62,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          gradient: selected ? const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x2EFFD278), Color(0x0DFFD278)]) : null,
                          border: Border.all(color: selected ? const Color(0x80E8C478) : Colors.transparent, width: 1.4),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(item.$2, color: selected ? const Color(0xFFFFE3A0) : OkeyXColors.muted, size: compact ? 20 : 22),
                            const SizedBox(height: 4),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                item.$3.toUpperCase(),
                                maxLines: 1,
                                style: TextStyle(fontSize: compact ? 8.5 : 9.5, letterSpacing: .5, fontWeight: FontWeight.w800, color: selected ? const Color(0xFFFFE3A0) : OkeyXColors.muted),
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
          ],
        ),
      );

  Widget _topBar(bool compact) {
    final level = _level;
    final xp = _xp;
    final nextXp = _integer(_account['next_level_xp'], fallback: 0);
    final levelStart = _integer(_account['level_xp_start'], fallback: 0);
    final progress = nextXp > levelStart ? ((xp - levelStart) / (nextXp - levelStart)).clamp(0.0, 1.0) : ((xp % 1000) / 1000).clamp(0.0, 1.0);
    return Container(
      height: compact ? 58 : 66,
      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 18),
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x8C000000), Color(0x26000000)]),
        border: Border(bottom: BorderSide(color: OkeyXColors.line)),
      ),
      child: Row(
        children: [
          Image.asset('assets/brand/okeyx_logo_transparent.png', height: compact ? 30 : 36, fit: BoxFit.contain),
          SizedBox(width: compact ? 10 : 18),
          Flexible(
            child: GestureDetector(
              onTap: _openSettings,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OkxAvatar(name: _profile.displayName, imageUrl: _profile.avatarUrl, size: compact ? 34 : 40),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_profile.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: OkeyXColors.text)),
                        const SizedBox(height: 4),
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          Text('LV $level', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: OkeyXColors.muted)),
                          const SizedBox(width: 7),
                          SizedBox(
                            width: compact ? 60 : 96,
                            height: 6,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Stack(fit: StackFit.expand, children: [
                                const ColoredBox(color: Color(0x80000000)),
                                FractionallySizedBox(
                                  alignment: Alignment.centerLeft,
                                  widthFactor: progress,
                                  child: const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF3CCF8E), Color(0xFF9FF0C6)]))),
                                ),
                              ]),
                            ),
                          ),
                          if (!compact) ...[
                            const SizedBox(width: 7),
                            Text('${okxFormat(xp)} XP', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: OkeyXColors.dim)),
                          ],
                        ]),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => setState(() => _selected = 6),
            child: OkxMoneyPill(icon: const OkxCoin(size: 18), value: !_walletSynced ? '…' : compact ? okxShort(_chips) : okxFormat(_chips), onPlus: () => setState(() => _selected = 6)),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => setState(() => _selected = 6),
            child: OkxMoneyPill(icon: const OkxGem(size: 16), value: !_walletSynced ? '…' : okxShort(_integer(_account['diamonds'], fallback: _profile.diamonds)), onPlus: () => setState(() => _selected = 6)),
          ),
          const SizedBox(width: 8),
          _roundIcon(_preferences.radioEnabled ? Icons.graphic_eq_rounded : Icons.radio_rounded, _showRadioMenu, active: _preferences.radioEnabled),
          const SizedBox(width: 6),
          _roundIcon(Icons.notifications_rounded, _showNotifications, badge: _integer(_notifications['unread'])),
          const SizedBox(width: 6),
          _roundIcon(Icons.settings_rounded, _openSettings),
        ],
      ),
    );
  }

  Widget _roundIcon(IconData icon, VoidCallback onTap, {int badge = 0, bool active = false}) => GestureDetector(
        onTap: onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF0F0A28),
                image: const DecorationImage(image: AssetImage('assets/textures/leather.jpg'), repeat: ImageRepeat.repeat),
                border: Border.all(color: active ? OkeyXColors.cyan : OkeyXColors.line, width: active ? 1.6 : 1),
                boxShadow: const [BoxShadow(color: Color(0x59000000), blurRadius: 10, offset: Offset(0, 4))],
              ),
              child: Icon(icon, size: 19, color: active ? OkeyXColors.mint : const Color(0xFFFFE9B0)),
            ),
            if (badge > 0)
              Positioned(
                right: -3,
                top: -3,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 18),
                  height: 18,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: OkeyXColors.flame, borderRadius: BorderRadius.circular(9), border: Border.all(color: OkeyXColors.night, width: 2)),
                  child: Text('${math.min(badge, 99)}', style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: Colors.white)),
                ),
              ),
          ],
        ),
      );

  Widget _page(int index, bool compact) => switch (index) {
        0 => _home(compact),
        1 => _tables(compact),
        2 => _events(compact),
        3 => _socialPage(compact),
        4 => _clubPage(compact),
        5 => _chancePage(compact),
        6 => Phase4Screen(api: _api, compact: compact, soundEnabled: _preferences.soundEnabled, onWalletChanged: () => unawaited(_refreshEconomy())),
        7 => _operationsPage(compact),
        _ => _home(compact),
      };

  // ------------------------------------------------------------ ANA EKRAN
  Widget _home(bool compact) => RefreshIndicator(
        onRefresh: _loadHub,
        color: OkeyXColors.gold,
        child: ListView(
          padding: EdgeInsets.fromLTRB(compact ? 8 : 14, compact ? 10 : 14, compact ? 10 : 16, 18),
          children: [
            LayoutBuilder(builder: (context, c) {
              final wide = c.maxWidth >= 760;
              final left = Column(
                children: [
                  _heroCard(compact),
                  const SizedBox(height: 12),
                  _shortcutRow(compact),
                  const SizedBox(height: 12),
                  _tickerBar(),
                ],
              );
              final right = Column(
                children: [
                  _rewardsCard(),
                  const SizedBox(height: 12),
                  _friendsCard(),
                ],
              );
              if (!wide) return Column(children: [left, const SizedBox(height: 12), right]);
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 69, child: left),
                  const SizedBox(width: 14),
                  Expanded(flex: 31, child: right),
                ],
              );
            }),
            if (_liveEvents.isNotEmpty) ...[
              const SizedBox(height: 12),
              _liveEventsPanel(compact, compactMode: true),
            ],
            const SizedBox(height: 16),
            const OkxLabel('İstatistiklerin'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _statCard('Oyun', _integer(_stats['games'])),
                _statCard('Galibiyet', _integer(_stats['wins'])),
                _statCard('Seri açma', _integer(_stats['series_opens'])),
                _statCard('Çift açma', _integer(_stats['pair_opens'])),
                _statCard('Okey bitiş', _integer(_stats['okey_finishes'])),
                _statCard('En iyi seri', _integer(_stats['best_streak'])),
              ],
            ),
            const SizedBox(height: 16),
            const OkxLabel('Son maçlar'),
            const SizedBox(height: 8),
            ..._historyPreview(),
          ],
        ),
      );

  Widget _heroCard(bool compact) {
    final fees = const [1000, 5000, 10000, 25000, 100000];
    final heroH = compact ? 250.0 : 284.0;
    final classic = _variant == 'duz';
    // Her modun kendi canlı rengi: 101 Okey zümrüt-turkuaz, Klasik Okey mor-pembe.
    final colors = classic
        ? const [Color(0xFF7B2FF7), Color(0xFFC0269E), Color(0xFFFF5A6E)]
        : const [Color(0xFF0BA37F), Color(0xFF0E7FA8), Color(0xFF3B3BC4)];
    return AnimatedContainer(
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      height: heroH,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
        border: Border.all(color: const Color(0x66FFFFFF), width: 1.2),
        boxShadow: [
          BoxShadow(color: colors[1].withValues(alpha: .55), blurRadius: 34, spreadRadius: -6, offset: const Offset(0, 14)),
          const BoxShadow(color: Color(0x99050218), blurRadius: 24, offset: Offset(0, 12)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(29),
        child: Stack(children: [
          // Parlak üst ışık ve büyük filigran.
          Positioned.fill(child: IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.white.withValues(alpha: .18), Colors.white.withValues(alpha: 0), Colors.black.withValues(alpha: .18)], stops: const [0, .45, 1]))))),
          Positioned(right: compact ? 150 : 200, bottom: -30, child: IgnorePointer(child: Text(classic ? 'OKEY' : '101', style: TextStyle(fontFamily: OkeyXFonts.number, fontSize: compact ? 150 : 190, color: Colors.white.withValues(alpha: .07), height: 1)))),
          const Positioned.fill(child: IgnorePointer(child: _ShineSweep())),
          Padding(
          padding: EdgeInsets.fromLTRB(compact ? 16 : 26, compact ? 14 : 20, compact ? 16 : 24, compact ? 14 : 18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _heroTiles(compact),
                        SizedBox(width: compact ? 14 : 22),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(mainAxisSize: MainAxisSize.min, children: [
                                Container(width: 7, height: 7, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF3CCF8E), boxShadow: [BoxShadow(color: Color(0xFF3CCF8E), blurRadius: 8)])),
                                const SizedBox(width: 6),
                                Text('${_rooms.length} AÇIK MASA', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.3, color: Color(0xFFB6FFE4))),
                              ]),
                              const SizedBox(height: 6),
                              FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: OkxTitle(_variant == 'duz' ? 'Klasik Okey' : '101 Okey', size: compact ? 32 : 40, color: Colors.white)),
                              const SizedBox(height: 5),
                              Text('Gerçek rakipler • boş koltuklar 15 sn’de dolar', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: compact ? 11 : 12, color: Colors.white.withValues(alpha: .88), fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    SizedBox(
                      height: compact ? 32 : 36,
                      width: compact ? 250 : 300,
                      child: OkxModeTabs(
                        height: compact ? 32 : 36,
                        classic: _variant == 'duz',
                        onChanged: (classic) => setState(() {
                          if (classic) {
                            if (_variant != 'duz') _lastRuleVariant = _variant;
                            _variant = 'duz';
                            _turbo = false;
                          } else if (_variant == 'duz') {
                            _variant = _lastRuleVariant;
                          }
                        }),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: [
                        if (_variant != 'duz') ...[
                          OkxToggleChip(
                            height: compact ? 30 : 34,
                            label: _variant == 'fold' ? 'Katlamalı' : 'Katlamasız',
                            active: _variant == 'fold',
                            onTap: () => setState(() => _variant = _variant == 'fold' ? 'non_fold' : 'fold'),
                          ),
                          const SizedBox(width: 7),
                          OkxToggleChip(
                            height: compact ? 30 : 34,
                            label: _turbo ? 'Turbo' : 'Normal',
                            icon: _turbo ? Icons.bolt_rounded : null,
                            active: _turbo,
                            onTap: () => setState(() => _turbo = !_turbo),
                          ),
                          const SizedBox(width: 7),
                        ],
                        OkxToggleChip(
                          height: compact ? 30 : 34,
                          label: _assisted ? 'Yardımlı' : 'Yardımsız',
                          icon: _assisted ? Icons.auto_fix_high_rounded : null,
                          active: _assisted,
                          onTap: () => setState(() => _assisted = !_assisted),
                        ),
                        const SizedBox(width: 7),
                        OkxToggleChip(
                          height: compact ? 30 : 34,
                          label: '$_rounds El',
                          icon: Icons.layers_rounded,
                          active: true,
                          onTap: () => setState(() => _rounds = switch (_rounds) { 1 => 2, 2 => 3, _ => 1 }),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: [
                        const Text('GİRİŞ', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5, color: Colors.white)),
                        const SizedBox(width: 8),
                        for (final f in fees) ...[
                          OkxChip(
                            label: okxShort(f),
                            onFelt: true,
                            selected: _entryFee == f,
                            leading: _entryFee == f ? const OkxCoin(size: 13) : null,
                            onTap: () => setState(() => _entryFee = f),
                          ),
                          const SizedBox(width: 6),
                        ],
                      ]),
                    ),
                  ],
                ),
              ),
              SizedBox(width: compact ? 12 : 18),
              Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _playButton(compact),
                  const SizedBox(height: 8),
                  Text(
                    _turbo ? 'Turbo: giriş x10 • ödül x10 • $_rounds el' : '4 oyuncu • $_rounds el',
                    style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                ],
              ),
            ],
          ),
        ),
        ]),
      ),
    );
  }

  Widget _heroTiles(bool compact) {
    final w = compact ? 46.0 : 58.0;
    Widget tile(int n, int c, double angle, double dy) => Transform.translate(
          offset: Offset(0, dy),
          child: Transform.rotate(angle: angle, child: SizedBox(width: w, height: w * 1.42, child: TileWidget(tile: GameTile(id: 'h$n$c$angle', number: n, colorIndex: c)))),
        );
    return SizedBox(
      width: w * 2.75,
      height: w * 1.62,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(left: 0, child: tile(1, 0, -.16, 6)),
          Positioned(right: 0, child: tile(1, 0, .16, 6)),
          tile(0, 2, 0, -2),
        ],
      ),
    );
  }

  Widget _playButton(bool compact) => GestureDetector(
        onTap: _busy ? null : _quickPlay,
        child: Container(
          width: compact ? 150 : 196,
          height: compact ? 70 : 84,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: brassGradient,
            boxShadow: const [
              BoxShadow(color: Color(0xFFA8480A), offset: Offset(0, 5)),
              BoxShadow(color: Color(0x99000000), blurRadius: 22, offset: Offset(0, 12)),
              BoxShadow(color: Color(0x80FFC845), blurRadius: 34),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('OYNA', style: TextStyle(fontFamily: OkeyXFonts.number, fontSize: compact ? 26 : 32, letterSpacing: 1.5, color: okxTextDark, height: 1, shadows: const [Shadow(color: Color(0x99FFF0C8), offset: Offset(0, 1.5))])),
              const SizedBox(height: 4),
              Row(mainAxisSize: MainAxisSize.min, children: [
                const OkxCoin(size: 13),
                const SizedBox(width: 5),
                Text('${okxShort(_turbo ? _entryFee * 10 : _entryFee)} giriş', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: okxTextDark)),
              ]),
            ],
          ),
        ),
      );

  Widget _shortcutRow(bool compact) {
    Widget item(IconData icon, String title, String sub, VoidCallback onTap, Gradient grad) => Expanded(
          child: GestureDetector(
            onTap: _busy ? null : onTap,
            child: OkxLeather(
              radius: 18,
              padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14, vertical: compact ? 10 : 13),
              child: Row(
                children: [
                  Container(
                    width: compact ? 38 : 44,
                    height: compact ? 38 : 44,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(13), gradient: grad, boxShadow: [BoxShadow(color: grad.colors.last.withValues(alpha: .55), blurRadius: 12, offset: const Offset(0, 4))]),
                    child: Icon(icon, color: Colors.white, size: compact ? 21 : 23),
                  ),
                  SizedBox(width: compact ? 9 : 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: compact ? 13 : 14, fontWeight: FontWeight.w800, color: OkeyXColors.cream)),
                        const SizedBox(height: 2),
                        Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: compact ? 10 : 11, fontWeight: FontWeight.w600, color: OkeyXColors.muted)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
    return Row(
      children: [
        item(Icons.smart_toy_rounded, 'Antrenman', 'Botlarla • ücretsiz', () => unawaited(_practicePlay()), okxOrangeGradient),
        SizedBox(width: compact ? 8 : 12),
        item(Icons.add_rounded, 'Oda kur', 'Arkadaşlarını çağır', () => unawaited(_createRoomDialog()), okxPinkGradient),
        SizedBox(width: compact ? 8 : 12),
        item(Icons.search_rounded, 'Oda bul', '${_rooms.length} açık masa', () => setState(() => _selected = 1), okxCyanGradient),
        SizedBox(width: compact ? 8 : 12),
        item(Icons.school_rounded, 'Öğren', 'Kuralları adım adım', _openTutorial, okxVioletGradient),
      ],
    );
  }

  Widget _tickerBar() {
    final row = _activity.isEmpty ? const <String, dynamic>{} : _activity[_activityIndex % _activity.length];
    final text = row.isEmpty ? 'Canlı oyuncu hareketleri burada akacak.' : '${row['message'] ?? ''}';
    return OkxLeather(
      radius: 14,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(children: [
        Container(width: 7, height: 7, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF3CCF8E), boxShadow: [BoxShadow(color: Color(0xFF3CCF8E), blurRadius: 8)])),
        const SizedBox(width: 7),
        const Text('CANLI', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.4, color: OkeyXColors.mint)),
        const SizedBox(width: 12),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            transitionBuilder: (child, a) => FadeTransition(opacity: a, child: SlideTransition(position: Tween(begin: const Offset(0, .4), end: Offset.zero).animate(a), child: child)),
            child: Text(text, key: ValueKey('${row['id'] ?? text}'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: OkeyXColors.cream, fontWeight: FontWeight.w600)),
          ),
        ),
      ]),
    );
  }

  Widget _rewardsCard() {
    final daily = _map(_account['daily']);
    final dailyDone = '${daily['last_claim_day'] ?? ''}' == _todayKey;
    final wheel = _map(_account['wheel']);
    final wheelCfg = _map(_rewardConfig['wheel']);
    final wheelLimit = math.max(1, _integer(wheelCfg['daily_limit'], fallback: 1));
    final wheelUsed = '${wheel['day'] ?? ''}' == _todayKey ? _integer(wheel['spins_today']) : ('${wheel['last_spin_day'] ?? ''}' == _todayKey ? 1 : 0);
    final chests = _map(_account['chests']);
    final keys = _integer(chests['keys']);
    final chestFreeDone = '${chests['last_free_day'] ?? ''}' == _todayKey;
    final chestLimit = math.max(1, _integer(_map(_rewardConfig['chest'])['daily_limit'], fallback: 5));
    final chestOpened = '${chests['day'] ?? ''}' == _todayKey ? _integer(chests['opened_today']) : 0;
    final chestFull = chestOpened >= chestLimit;
    final chestReady = !chestFull && (keys > 0 || !chestFreeDone);
    final ready = (dailyDone ? 0 : 1) + (wheelUsed < wheelLimit ? 1 : 0) + (chestReady ? 1 : 0);
    Widget row(IconData icon, String title, String sub, String action, bool enabled, Future<void> Function() onTap, {bool green = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: const Color(0x1AFFD278), border: Border.all(color: const Color(0x4DE8C478))),
              child: Icon(icon, size: 20, color: const Color(0xFFFFD98A)),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: OkeyXColors.cream)),
                const SizedBox(height: 2),
                Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: OkeyXColors.muted)),
              ]),
            ),
            const SizedBox(width: 8),
            OkxButton(
              label: action,
              style: green ? OkxButtonStyle.green : OkxButtonStyle.brass,
              height: 32,
              fontSize: 11,
              padding: const EdgeInsets.symmetric(horizontal: 13),
              onTap: enabled && !_busy ? () => unawaited(onTap()) : null,
            ),
          ]),
        );
    return OkxLeather(
      radius: 20,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: OkxTitle('Bugünün ödülleri', size: 17, color: Color(0xFFFFE9B0))),
          OkxLabel('$ready hazır'),
        ]),
        const SizedBox(height: 6),
        row(Icons.calendar_month_rounded, 'Günlük ödül', dailyDone ? '$_dailyResetText sonra yenilenir' : '${_integer(daily['streak']) + 1}. gün hazır', dailyDone ? 'ALINDI' : 'AL', !dailyDone, _claimDaily, green: true),
        row(Icons.casino_rounded, 'Şans çarkı', wheelUsed < wheelLimit ? '${wheelLimit - wheelUsed} ücretsiz çevirme' : '$_dailyResetText sonra', 'ÇEVİR', wheelUsed < wheelLimit, _spinWheel),
        row(Icons.inventory_2_rounded, 'Sandık', chestFull ? '$chestOpened/$chestLimit bugün • $_dailyResetText sonra' : keys > 0 ? '$keys anahtar • $chestOpened/$chestLimit bugün' : (chestFreeDone ? '$_dailyResetText sonra ücretsiz' : 'Bugün ücretsiz'), chestFull ? 'BİTTİ' : 'AÇ', chestReady, _openChest),
      ]),
    );
  }

  Widget _friendsCard() {
    final online = _friends.where((p) => p['online'] == true || p['in_game'] == true).toList();
    final playing = online.where((p) => p['in_game'] == true).toList();
    return OkxLeather(
      radius: 20,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: OkxTitle('Arkadaşlar', size: 17, color: Color(0xFFFFE9B0))),
          OkxLabel('${online.length} çevrimiçi'),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          for (final p in online.take(4)) ...[
            OkxAvatar(name: '${p['name'] ?? 'O'}', imageUrl: '${p['avatar_url'] ?? ''}', size: 36, online: true),
            const SizedBox(width: 12),
          ],
          if (online.isEmpty)
            const Expanded(child: Text('Çevrimiçi arkadaşın yok.', style: TextStyle(fontSize: 11.5, color: OkeyXColors.muted, fontWeight: FontWeight.w600)))
          else
            const Spacer(),
          OkxButton.ghost(label: 'DAVET', icon: Icons.person_add_alt_1_rounded, height: 32, fontSize: 11, padding: const EdgeInsets.symmetric(horizontal: 12), onTap: () => setState(() => _selected = 3)),
        ]),
        if (playing.isNotEmpty) ...[
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () => unawaited(_joinFriendRoom(playing.first)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: const Color(0x123CCF8E), border: Border.all(color: const Color(0x403CCF8E))),
              child: Row(children: [
                OkxAvatar(name: '${playing.first['name'] ?? 'O'}', size: 26),
                const SizedBox(width: 10),
                Expanded(child: Text('${playing.first['name'] ?? 'Arkadaşın'} ${playing.first['room_name'] ?? 'masada'} oynuyor', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: OkeyXColors.cream))),
                Text(playing.first['joinable'] == true ? 'KATIL' : 'İZLE', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: OkeyXColors.mint)),
              ]),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _liveEventsPanel(bool compact, {bool compactMode = false}) {
    final rows = _liveEvents;
    if (rows.isEmpty) {
      if (compactMode) return const SizedBox.shrink();
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: const Color(0x7A100A2B), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
        child: const Row(children: [Icon(Icons.event_available_rounded, color: Colors.white30), SizedBox(width: 8), Expanded(child: Text('Şu anda yayınlanmış etkinlik yok. Yeni etkinlikler burada görünür.', style: TextStyle(fontSize: 8, color: Colors.white54)))]),
      );
    }
    final visible = rows.take(compactMode ? 2 : 8).toList();
    return Container(
      padding: EdgeInsets.all(compact ? 9 : 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(compactMode ? 16 : 20),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF1C1251), Color(0xFF1B114B), Color(0xFF0F0929)]),
        border: Border.all(color: OkeyXColors.gold.withValues(alpha: .32)),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 15, offset: Offset(0, 7))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.local_fire_department_rounded, size: 16, color: OkeyXColors.gold),
          const SizedBox(width: 6),
          const Text('CANLI ETKİNLİK', style: TextStyle(fontSize: 8.5, color: OkeyXColors.gold, fontWeight: FontWeight.w900, letterSpacing: .5)),
          const Spacer(),
          if (!compactMode) Text('${rows.length} yayın', style: const TextStyle(fontSize: 6.2, color: Colors.white38)),
        ]),
        const SizedBox(height: 7),
        for (var i = 0; i < visible.length; i++) ...[
          _liveEventRow(visible[i], compact),
          if (i != visible.length - 1) const SizedBox(height: 5),
        ],
      ]),
    );
  }

  Widget _liveEventRow(Map<String, dynamic> event, bool compact) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final starts = _integer(event['starts_at']);
    final ends = _integer(event['ends_at']);
    final active = starts <= now && ends > now;
    final cfg = _map(event['config']);
    final reward = _integer(cfg['reward_coins'], fallback: 25000);
    final bonus = _integer(cfg['side_game_bonus_percent'], fallback: 10);
    final xp = (cfg['xp_multiplier'] as num?)?.toDouble() ?? 1.25;
    final claimable = event['claimable'] == true;
    final claimed = event['claimed'] == true;
    final leftSeconds = (active ? (ends - now).clamp(0, 31536000) : (starts - now).clamp(0, 31536000)).toInt();
    final duration = Duration(seconds: leftSeconds);
    final timeText = active
        ? 'BİTİŞ • ${duration.inHours}sa ${(duration.inMinutes % 60).toString().padLeft(2, '0')}dk'
        : 'BAŞLAR • ${duration.inHours}sa ${(duration.inMinutes % 60).toString().padLeft(2, '0')}dk';
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 9 : 11, vertical: compact ? 7 : 9),
      decoration: BoxDecoration(color: const Color(0xA60F0929), borderRadius: BorderRadius.circular(12), border: Border.all(color: active ? OkeyXColors.mint.withValues(alpha: .28) : Colors.white10)),
      child: Row(children: [
        Container(width: compact ? 31 : 36, height: compact ? 31 : 36, alignment: Alignment.center, decoration: BoxDecoration(shape: BoxShape.circle, color: (active ? OkeyXColors.mint : OkeyXColors.gold).withValues(alpha: .11), border: Border.all(color: (active ? OkeyXColors.mint : OkeyXColors.gold).withValues(alpha: .30))), child: Icon(active ? Icons.bolt_rounded : Icons.schedule_rounded, size: compact ? 17 : 20, color: active ? OkeyXColors.mint : OkeyXColors.gold)),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${event['title'] ?? 'OkeyX Etkinliği'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: compact ? 8.5 : 10, fontWeight: FontWeight.w900)),
          if ('${event['subtitle'] ?? ''}'.trim().isNotEmpty) Text('${event['subtitle']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 6.5, color: Colors.white60)),
          if (active) Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text('+${_format(reward)} etkinlik ödülü • Şans Salonu +%$bonus • XP ×${xp.toStringAsFixed(xp.truncateToDouble() == xp ? 0 : 2)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 5.9, color: OkeyXColors.mint, fontWeight: FontWeight.w800)),
          ),
        ])),
        const SizedBox(width: 7),
        if (active && (claimable || claimed))
          SizedBox(
            height: 29,
            child: FilledButton.tonalIcon(
              onPressed: claimable && !_busy ? () => _claimLiveEvent('${event['id']}') : null,
              icon: Icon(claimed ? Icons.check_rounded : Icons.redeem_rounded, size: 13),
              label: Text(claimed ? 'ALINDI' : 'ÖDÜLÜ AL', style: const TextStyle(fontSize: 5.8, fontWeight: FontWeight.w900)),
            ),
          )
        else
          Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4), decoration: BoxDecoration(color: active ? OkeyXColors.mint.withValues(alpha: .11) : OkeyXColors.gold.withValues(alpha: .09), borderRadius: BorderRadius.circular(8)), child: Text(active ? 'CANLI • $timeText' : timeText, style: TextStyle(fontSize: 5.8, fontWeight: FontWeight.w900, color: active ? OkeyXColors.mint : OkeyXColors.gold))),
      ]),
    );
  }

  Future<void> _claimLiveEvent(String eventId) => _runBusy(() async {
        final out = await _api.claimLiveEvent(eventId);
        if (out['ok'] == true) {
          final wallet = _map(out['wallet']);
          if (mounted) {
            setState(() {
              if (wallet.isNotEmpty) {
                _account = {..._account, 'chips': _integer(wallet['coins'], fallback: _chips)};
                _phase4Hub = {..._phase4Hub, 'wallet': wallet};
              }
            });
          }
          await _showRewardBurst('ETKİNLİK ÖDÜLÜ', _integer(out['reward_coins']), Icons.local_fire_department_rounded);
        } else {
          _flash('${out['code']}' == 'event_already_claimed' ? 'Bu etkinlik ödülünü zaten aldın.' : 'Etkinlik ödülü şu anda alınamadı.');
        }
        await _refreshAccountBits();
        unawaited(_loadRewardState());
      });

  Widget _liveEventStrip(bool compact) {
    final rows = _activity.take(compact ? 3 : 5).toList();
    if (rows.isEmpty) {
      return Container(
        height: compact ? 38 : 42,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(color: const Color(0x990F0A2C), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white10)),
        child: const Row(children: [Icon(Icons.wifi_tethering_rounded, size: 15, color: OkeyXColors.mint), SizedBox(width: 7), Text('CANLI • Yeni masalar ve oyuncu hareketleri burada akacak.', style: TextStyle(fontSize: 7.5, color: Colors.white60, fontWeight: FontWeight.w800))]),
      );
    }
    return SizedBox(
      height: compact ? 40 : 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: rows.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final row = rows[index];
          final kind = '${row['kind'] ?? ''}';
          final color = kind == 'purchase' ? OkeyXColors.gold : kind == 'big_win' || kind == 'match_win' ? const Color(0xFFFFC95C) : OkeyXColors.mint;
          final icon = kind == 'purchase' ? Icons.shopping_bag_rounded : kind == 'big_win' || kind == 'match_win' ? Icons.emoji_events_rounded : Icons.sports_esports_rounded;
          return Container(
            constraints: BoxConstraints(minWidth: compact ? 165 : 190, maxWidth: compact ? 230 : 280),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: const Color(0xB8120C31), borderRadius: BorderRadius.circular(13), border: Border.all(color: color.withValues(alpha: .22))),
            child: Row(children: [Icon(icon, size: 15, color: color), const SizedBox(width: 6), Expanded(child: Text('${row['message'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 7.2, color: Colors.white70, fontWeight: FontWeight.w800)))]),
          );
        },
      ),
    );
  }

  Widget _lobbyStage(bool compact) => LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 980;
          final stageHeight = compact ? 304.0 : 366.0;
          final sideWidth = narrow ? (compact ? 88.0 : 108.0) : (compact ? 108.0 : 132.0);
          return SizedBox(
            height: stageHeight,
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0x669BD6C6)),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF160E3A), Color(0xFF1D1350), Color(0xFF170E40), Color(0xFF100A2E)],
                ),
                boxShadow: const [BoxShadow(color: Color(0x88000000), blurRadius: 26, offset: Offset(0, 12))],
              ),
              child: Stack(
                children: [
                  const Positioned(top: -105, left: 200, child: _LobbyGlow(size: 300, color: Color(0x335CE8BE))),
                  const Positioned(bottom: -145, right: 210, child: _LobbyGlow(size: 330, color: Color(0x33F7B23B))),
                  Positioned.fill(
                    child: Padding(
                      padding: EdgeInsets.all(compact ? 9 : 13),
                      child: Row(
                        children: [
                          SizedBox(
                            width: sideWidth,
                            child: Column(children: [Expanded(child: _rankCard(compact)), const SizedBox(height: 7), Expanded(child: _socialPulseCard(compact))]),
                          ),
                          SizedBox(width: compact ? 8 : 11),
                          Expanded(
                            child: Column(
                              children: [
                                _announcementBar(compact),
                                SizedBox(height: compact ? 7 : 9),
                                Expanded(
                                  child: Row(
                                    children: [
                                      Expanded(
                                        flex: 12,
                                        child: _premium101Hero(compact),
                                      ),
                                      SizedBox(width: compact ? 7 : 9),
                                      Expanded(
                                        flex: 8,
                                        child: _gameCenterGrid(compact),
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(height: compact ? 7 : 9),
                                _lobbyShortcuts(compact),
                              ],
                            ),
                          ),
                          SizedBox(width: compact ? 8 : 11),
                          SizedBox(width: sideWidth, child: _bonusRail(compact)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );

  Widget _gameCategoryStrip(bool compact) {
    const categories = <(String, IconData)>[
      ('Tümü', Icons.grid_view_rounded),
      ('Masalar', Icons.table_bar_rounded),
      ('Etkinlikler', Icons.local_fire_department_rounded),
      ('Ödüller', Icons.redeem_rounded),
      ('Sosyal', Icons.groups_rounded),
    ];
    return Container(
      height: compact ? 32 : 38,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xB80E0A26),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(children: [
        for (final item in categories) ...[
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => setState(() => _gameCategory = item.$1),
                borderRadius: BorderRadius.circular(11),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _gameCategory == item.$1 ? OkeyXColors.mint.withValues(alpha: .12) : Colors.transparent,
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: _gameCategory == item.$1 ? OkeyXColors.mint.withValues(alpha: .35) : Colors.transparent),
                  ),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(item.$2, size: compact ? 12 : 14, color: _gameCategory == item.$1 ? OkeyXColors.mint : Colors.white38),
                    const SizedBox(width: 4),
                    Text(item.$1.toUpperCase(), style: TextStyle(fontSize: compact ? 5.8 : 6.7, fontWeight: FontWeight.w900, letterSpacing: .3, color: _gameCategory == item.$1 ? OkeyXColors.mint : Colors.white54)),
                  ]),
                ),
              ),
            ),
          ),
          if (item != categories.last) const SizedBox(width: 3),
        ],
      ]),
    );
  }

  Widget _premium101Hero(bool compact) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF56527E), Color(0xFF261969), Color(0xFF160E3D), Color(0xFF0F0A28)]),
          border: Border.all(color: const Color(0x9977E9D0), width: 1.4),
          boxShadow: const [BoxShadow(color: Color(0x4400D8B4), blurRadius: 18, offset: Offset(0, 7))],
        ),
        child: Stack(children: [
          const Positioned(top: -70, right: -45, child: _LobbyGlow(size: 190, color: Color(0x4458E8D0))),
          Positioned(right: -18, bottom: -25, child: Icon(Icons.table_bar_rounded, size: compact ? 105 : 135, color: Colors.white.withValues(alpha: .035))),
          Padding(
            padding: EdgeInsets.all(compact ? 10 : 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                  decoration: BoxDecoration(color: OkeyXColors.gold.withValues(alpha: .14), borderRadius: BorderRadius.circular(9), border: Border.all(color: OkeyXColors.gold.withValues(alpha: .36))),
                  child: const Text('ANA OYUN', style: TextStyle(fontSize: 6.2, color: OkeyXColors.gold, fontWeight: FontWeight.w900, letterSpacing: .7)),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                  decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(9), border: Border.all(color: Colors.white12)),
                  child: Text('${_rooms.length} AÇIK MASA', style: const TextStyle(fontSize: 6, color: Colors.white70, fontWeight: FontWeight.w900)),
                ),
              ]),
              SizedBox(height: compact ? 6 : 9),
              Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                Row(mainAxisSize: MainAxisSize.min, children: const [
                  _LobbyTileFace('1', Color(0xFFDB574E)),
                  SizedBox(width: 3),
                  _LobbyTileFace('0', Color(0xFF2F6B9A)),
                  SizedBox(width: 3),
                  _LobbyTileFace('1', Color(0xFFB68A24)),
                ]),
                const SizedBox(width: 9),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('101 OKEY', style: TextStyle(fontSize: compact ? 19 : 24, height: .9, fontWeight: FontWeight.w900, letterSpacing: .3)),
                  const SizedBox(height: 3),
                  Text(_modeSummary, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 6.7, color: Colors.white70, fontWeight: FontWeight.w700)),
                ])),
              ]),
              SizedBox(height: compact ? 7 : 10),
              Wrap(spacing: 5, runSpacing: 5, children: [
                _heroModeChip('Standart', !_turbo, () => setState(() => _turbo = false), Icons.shield_outlined),
                _heroModeChip('Turbo', _turbo, () => setState(() => _turbo = true), Icons.bolt_rounded),
                _heroModeChip('Katlamasız', _variant == 'non_fold', () => setState(() => _variant = 'non_fold'), Icons.horizontal_rule_rounded),
                _heroModeChip('Katlamalı', _variant == 'fold', () => setState(() => _variant = 'fold'), Icons.trending_up_rounded),
                _heroModeChip('Klasik Okey', _variant == 'duz', () => setState(() => _variant = 'duz'), Icons.grid_view_rounded),
                _heroModeChip(_assisted ? 'Yardımlı' : 'Yardımsız', true, () => setState(() => _assisted = !_assisted), _assisted ? Icons.auto_fix_high_rounded : Icons.psychology_alt_rounded),
              ]),
              const Spacer(),
              Row(children: [
                Expanded(child: FilledButton.icon(
                  onPressed: _busy ? null : _quickPlay,
                  icon: const Icon(Icons.bolt_rounded, size: 15),
                  label: const Text('HEMEN OYNA', style: TextStyle(fontSize: 7, fontWeight: FontWeight.w900)),
                )),
                const SizedBox(width: 6),
                Expanded(child: OutlinedButton.icon(
                  onPressed: _busy ? null : _practicePlay,
                  icon: const Icon(Icons.smart_toy_rounded, size: 14),
                  label: const Text('ANTRENMAN', style: TextStyle(fontSize: 7, fontWeight: FontWeight.w900)),
                )),
                const SizedBox(width: 6),
                Expanded(child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => setState(() => _selected = 1),
                  icon: const Icon(Icons.search_rounded, size: 14),
                  label: const Text('ODA BUL', style: TextStyle(fontSize: 6.7, fontWeight: FontWeight.w900)),
                )),
                const SizedBox(width: 6),
                Expanded(child: OutlinedButton.icon(
                  onPressed: _busy ? null : _createRoomDialog,
                  icon: const Icon(Icons.add_rounded, size: 14),
                  label: const Text('ODA OLUŞTUR', style: TextStyle(fontSize: 6.2, fontWeight: FontWeight.w900)),
                )),
              ]),
            ]),
          ),
        ]),
      );

  Widget _heroModeChip(String label, bool selected, VoidCallback onTap, IconData icon) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
            decoration: BoxDecoration(
              color: selected ? OkeyXColors.gold.withValues(alpha: .15) : Colors.black26,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: selected ? OkeyXColors.gold.withValues(alpha: .55) : Colors.white12),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 10, color: selected ? OkeyXColors.gold : Colors.white38),
              const SizedBox(width: 3),
              Text(label, style: TextStyle(fontSize: 6, fontWeight: FontWeight.w900, color: selected ? Colors.white : Colors.white54)),
            ]),
          ),
        ),
      );

  Widget _gameCenterGrid(bool compact) {
    final daily = _map(_account['daily']);
    final wheel = _map(_account['wheel']);
    final chests = _map(_account['chests']);
    final dailyReady = '${daily['last_claim_day'] ?? ''}' != _todayKey;
    final wheelLimit = math.max(1, _integer(_map(_rewardConfig['wheel'])['daily_limit'], fallback: 1));
    final wheelUsed = '${wheel['day'] ?? ''}' == _todayKey ? _integer(wheel['spins_today']) : ('${wheel['last_spin_day'] ?? ''}' == _todayKey ? 1 : 0);
    final wheelReady = wheelUsed < wheelLimit;
    final chestLimit = math.max(1, _integer(_map(_rewardConfig['chest'])['daily_limit'], fallback: 5));
    final chestOpened = '${chests['day'] ?? ''}' == _todayKey ? _integer(chests['opened_today']) : 0;
    final chestKeys = _integer(chests['keys']);
    final chestFreeReady = '${chests['last_free_day'] ?? ''}' != _todayKey;
    final chestReady = chestOpened < chestLimit && (chestKeys > 0 || chestFreeReady);
    final entries = switch (_gameCategory) {
      'Masalar' => <(IconData, String, String, String, Color, VoidCallback)>[
          (Icons.bolt_rounded, 'Hemen Oyna', _modeSummary, 'HAZIR', const Color(0xFF1C8ED8), () => unawaited(_quickPlay())),
          (Icons.smart_toy_rounded, 'Botlarla Antrenman', 'Bahissiz • anında başlar', 'ÜCRETSİZ', const Color(0xFF5D5988), () => unawaited(_practicePlay())),
          (Icons.school_rounded, 'Öğretici Masa', 'Kuralları adım adım öğren', 'YENİ', const Color(0xFF3C6FD1), _openTutorial),
          (Icons.search_rounded, 'Oda Bul', '${_rooms.length} açık masa', 'CANLI', const Color(0xFF178C79), () => setState(() => _selected = 1)),
          (Icons.group_add_rounded, 'Arkadaş Masası', 'Özel oda ve davet', 'SOSYAL', const Color(0xFF7653C8), _createRoomDialog),
          (Icons.tune_rounded, 'Masa Ayarları', 'Mod ve giriş seç', 'ÖZEL', const Color(0xFFB56B31), () => setState(() => _selected = 1)),
        ],
      'Etkinlikler' => <(IconData, String, String, String, Color, VoidCallback)>[
          (Icons.local_fire_department_rounded, 'Günlük Etkinlik', _liveEvents.isEmpty ? 'Yeni etkinlikler yakında' : '${_liveEvents.length} etkinlik aktif', _liveEvents.isEmpty ? 'BUGÜN' : 'YENİ', const Color(0xFFC65174), () => setState(() => _selected = 2)),
          (Icons.task_alt_rounded, 'Mini Görevler', 'Günlük ve haftalık', 'ÖDÜL', const Color(0xFF388C77), () => setState(() => _selected = 2)),
          (Icons.emoji_events_rounded, 'Lig Arenası', '${_map(_account['league'])['tier'] ?? 'Bronz'} ligi', 'CANLI', const Color(0xFFB77C25), () => setState(() => _selected = 2)),
          (Icons.shield_rounded, 'Kulüp Etkinliği', 'Takımınla ilerle', 'SOSYAL', const Color(0xFF5768B8), () => setState(() => _selected = 4)),
        ],
      'Ödüller' => <(IconData, String, String, String, Color, VoidCallback)>[
          (Icons.card_giftcard_rounded, 'Günlük Ödül', dailyReady ? 'Ödülün hazır' : _dailyResetText, dailyReady ? 'HAZIR' : 'ALINDI', const Color(0xFFC7962F), () => unawaited(_claimDaily())),
          (Icons.donut_large_rounded, 'Günlük Çark', wheelReady ? '$wheelUsed/$wheelLimit • dönüş hazır' : _dailyResetText, wheelReady ? 'HAZIR' : 'KULLANILDI', const Color(0xFFE47837), () { if (wheelReady) unawaited(_spinWheel()); }),
          (Icons.inventory_2_rounded, 'Şans Sandığı', '$chestOpened/$chestLimit bugün • $chestKeys anahtar', chestReady ? 'HAZIR' : (chestOpened >= chestLimit ? 'TAMAM' : 'KAPALI'), const Color(0xFF31946B), () { if (chestReady) unawaited(_openChest()); }),
          (Icons.storefront_rounded, 'Kozmetik Mağazası', 'Taş • ıstaka • efekt', 'YENİ', const Color(0xFF8754C7), () => setState(() => _selected = 6)),
        ],
      'Sosyal' => <(IconData, String, String, String, Color, VoidCallback)>[
          (Icons.visibility_rounded, 'Yancı Koltuğu', 'Canlı masayı destekle', 'CANLI', const Color(0xFFA56A2D), _openYanciCenter),
          (Icons.groups_rounded, 'Arkadaşların', '${_friends.length} arkadaş', _requests.isNotEmpty ? '${_requests.length} İSTEK' : 'SOSYAL', const Color(0xFF6E58C8), () => setState(() => _selected = 3)),
          (Icons.shield_rounded, 'Kulüp', 'Takımını büyüt', 'BİRLİKTE', const Color(0xFF2D8075), () => setState(() => _selected = 4)),
          (Icons.emoji_events_rounded, 'Haftalık Turnuva', 'Sıralama • altın ödül', 'YENİ', const Color(0xFFC08A1E), () => unawaited(Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TournamentScreen(api: _api, onClaimed: () => unawaited(_loadHub())))))),
          (_preferences.radioEnabled ? Icons.graphic_eq_rounded : Icons.radio_rounded, 'OkeyX Radyo', _preferences.radioEnabled ? 'Canlı yayın çalıyor' : '6 canlı istasyon', _preferences.radioEnabled ? 'AÇIK' : 'CANLI', const Color(0xFF2D83AA), () => unawaited(_showRadioMenu())),
        ],
      _ => <(IconData, String, String, String, Color, VoidCallback)>[
          (Icons.visibility_rounded, 'Yancı Koltuğu', 'Canlı masaya katıl', 'CANLI', const Color(0xFF9A682F), _openYanciCenter),
          (Icons.auto_awesome_rounded, 'Oyun Merkezi', 'Hipodrom • Şanslı Taşlar', '5 OYUN', const Color(0xFF6D53B8), () => setState(() => _selected = 5)),
          (Icons.local_fire_department_rounded, 'Günlük Etkinlik', _liveEvents.isEmpty ? 'Bugünün görevleri' : '${_liveEvents.length} etkinlik aktif', _liveEvents.isEmpty ? 'BUGÜN' : 'YENİ', const Color(0xFFB94F6C), () => setState(() => _selected = 2)),
          (Icons.redeem_rounded, 'Çark & Sandık', wheelReady || chestReady ? 'Ödülün hazır' : _dailyResetText, wheelReady || chestReady ? 'HAZIR' : 'KAPALI', const Color(0xFF298A6B), () => setState(() => _gameCategory = 'Ödüller')),
        ],
    };
    return Column(children: [
      Expanded(child: Row(children: [
        Expanded(child: _gameCenterMiniCard(entries[0], compact)),
        SizedBox(width: compact ? 5 : 7),
        Expanded(child: _gameCenterMiniCard(entries[1], compact)),
      ])),
      SizedBox(height: compact ? 5 : 7),
      Expanded(child: Row(children: [
        Expanded(child: _gameCenterMiniCard(entries[2], compact)),
        SizedBox(width: compact ? 5 : 7),
        Expanded(child: _gameCenterMiniCard(entries[3], compact)),
      ])),
    ]);
  }

  Widget _gameCenterMiniCard((IconData, String, String, String, Color, VoidCallback) item, bool compact) => Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: _busy ? null : item.$6,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            padding: EdgeInsets.all(compact ? 7 : 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [item.$5.withValues(alpha: .80), item.$5.withValues(alpha: .31), const Color(0xE9100A2B)]),
              border: Border.all(color: item.$5.withValues(alpha: .55)),
              boxShadow: [BoxShadow(color: item.$5.withValues(alpha: .09), blurRadius: 10, offset: const Offset(0, 4))],
            ),
            child: Stack(children: [
              Positioned(right: -10, bottom: -12, child: Icon(item.$1, size: compact ? 44 : 58, color: Colors.white.withValues(alpha: .055))),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(item.$1, color: Colors.white, size: compact ? 16 : 19),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                    decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(7), border: Border.all(color: Colors.white12)),
                    child: Text(item.$4, style: const TextStyle(fontSize: 5, color: Colors.white70, fontWeight: FontWeight.w900, letterSpacing: .35)),
                  ),
                ]),
                const Spacer(),
                Text(item.$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: compact ? 8 : 9.3, fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text(item.$3, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 5.7, color: Colors.white60, fontWeight: FontWeight.w700)),
              ]),
            ]),
          ),
        ),
      );

  Widget _hubGameTile({
    required String title,
    required String subtitle,
    required String badge,
    required Color primary,
    required Color secondary,
    required IconData icon,
    required VoidCallback onTap,
    bool featured = false,
    Widget? art,
  }) => Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(featured ? 22 : 17),
        child: InkWell(
          onTap: _busy ? null : onTap,
          borderRadius: BorderRadius.circular(featured ? 22 : 17),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(featured ? 22 : 17),
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [primary, secondary, const Color(0xFF110C2C)]),
              border: Border.all(color: primary.withValues(alpha: .72), width: featured ? 1.5 : 1),
              boxShadow: [BoxShadow(color: primary.withValues(alpha: .16), blurRadius: featured ? 18 : 10, offset: const Offset(0, 5))],
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(featured ? 22 : 17),
                      child: CustomPaint(painter: _HubGameArtPainter(title, featured: featured)),
                    ),
                  ),
                ),
                Positioned(right: -14, bottom: -18, child: Icon(icon, size: featured ? 112 : 68, color: Colors.white.withValues(alpha: .045))),
                Positioned(top: 9, right: 9, child: Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3), decoration: BoxDecoration(color: const Color(0x7A0D0822), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white12)), child: Text(badge, style: const TextStyle(fontSize: 6.3, color: Colors.white70, fontWeight: FontWeight.w900, letterSpacing: .5)))),
                Positioned.fill(
                  child: Padding(
                    padding: EdgeInsets.all(featured ? 14 : 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (featured && art != null) ...[Align(alignment: Alignment.centerLeft, child: art), const Spacer()],
                        Icon(icon, color: featured ? OkeyXColors.gold : Colors.white, size: featured ? 27 : 19),
                        SizedBox(height: featured ? 6 : 4),
                        Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: featured ? 18 : 10.5, height: .95, fontWeight: FontWeight.w900, letterSpacing: featured ? .2 : 0)),
                        const SizedBox(height: 3),
                        Text(subtitle, maxLines: featured ? 2 : 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: featured ? 7.4 : 6.2, color: Colors.white70, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _rankCard(bool compact) {
    final league = _map(_account['league']);
    final tier = '${league['tier'] ?? 'Bronz'}';
    final points = _integer(league['points']);
    return Material(
      color: const Color(0xA6100B2D),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: () => setState(() => _selected = 2),
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: EdgeInsets.all(compact ? 8 : 11),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.workspace_premium_rounded, color: OkeyXColors.gold, size: compact ? 25 : 32),
              const SizedBox(height: 4),
              FittedBox(child: Text(tier.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11))),
              Text('$points puan', style: const TextStyle(fontSize: 7, color: Colors.white60)),
              const SizedBox(height: 5),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: (points % 450) / 450,
                  minHeight: 4,
                  backgroundColor: Colors.white10,
                  color: OkeyXColors.gold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _socialPulseCard(bool compact) {
    final friendCount = _friends.length;
    final requestCount = _requests.length;
    return Material(
      color: const Color(0xA6100B2D),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: () => setState(() => _selected = 3),
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: EdgeInsets.all(compact ? 8 : 11),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(Icons.groups_rounded, color: const Color(0xFF9FD9FF), size: compact ? 24 : 30),
                  if (requestCount > 0)
                    Positioned(
                      right: -7,
                      top: -6,
                      child: CircleAvatar(radius: 8, backgroundColor: const Color(0xFFFF657D), child: Text('$requestCount', style: const TextStyle(fontSize: 7, fontWeight: FontWeight.w900))),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              const FittedBox(child: Text('ARKADAŞLIK', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900))),
              Text('$friendCount arkadaş', style: const TextStyle(fontSize: 7, color: Colors.white60)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _announcementBar(bool compact) {
    final row = _activity.isEmpty ? const <String, dynamic>{} : _activity[_activityIndex % _activity.length];
    final text = row.isEmpty ? 'Canlı oyuncu hareketleri burada görünecek.' : '${row['message'] ?? ''}';
    return Container(
      height: compact ? 29 : 34,
      padding: EdgeInsets.symmetric(horizontal: compact ? 9 : 12),
      decoration: BoxDecoration(color: const Color(0xA40B071E), borderRadius: BorderRadius.circular(12), border: Border.all(color: OkeyXColors.mint.withValues(alpha: .16))),
      child: Row(children: [
        Container(padding: const EdgeInsets.symmetric(horizontal:6,vertical:3),decoration:BoxDecoration(color:OkeyXColors.mint.withValues(alpha:.12),borderRadius:BorderRadius.circular(8),border:Border.all(color:OkeyXColors.mint.withValues(alpha:.28))),child:const Row(children:[Icon(Icons.circle,size:5,color:OkeyXColors.mint),SizedBox(width:3),Text('CANLI',style:TextStyle(fontSize:6,fontWeight:FontWeight.w900,color:OkeyXColors.mint))])),
        const SizedBox(width: 8),
        const Icon(Icons.campaign_rounded, size: 14, color: OkeyXColors.gold),
        const SizedBox(width: 6),
        Expanded(child: AnimatedSwitcher(duration: const Duration(milliseconds: 220), child: Text(text, key: ValueKey('${row['id'] ?? text}'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 8, color: Colors.white70, fontWeight: FontWeight.w700)))),
      ]),
    );
  }

  Widget _mainGameCard(bool compact) => Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          onTap: _busy ? null : _quickPlay,
          borderRadius: BorderRadius.circular(22),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF21165B), Color(0xFF1B124A), Color(0xFF140D36)]),
              border: Border.all(color: const Color(0x667BEADD)),
              boxShadow: const [BoxShadow(color: Color(0x77000000), blurRadius: 22, offset: Offset(0, 10)), BoxShadow(color: Color(0x2212E4D0), blurRadius: 25)],
            ),
            child: Stack(
              children: [
                Positioned(top: -65, right: -45, child: Container(width: 190, height: 190, decoration: const BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [Color(0x335EE7F3), Color(0x005EE7F3)])))),
                Padding(
                  padding: EdgeInsets.all(compact ? 10 : 14),
                  child: Row(children: [
                    Expanded(
                      flex: 7,
                      child: Stack(alignment: Alignment.center, children: [
                        Container(
                          height: compact ? 132 : 170,
                          constraints: const BoxConstraints(maxWidth: 360),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(95),
                            gradient: const RadialGradient(colors: [Color(0xFF07917D), Color(0xFF2D1D7D), Color(0xFF1F1455)]),
                            border: Border.all(color: const Color(0xFFB9873A), width: 5),
                            boxShadow: const [BoxShadow(color: Color(0x5500D8C0), blurRadius: 30), BoxShadow(color: Color(0x88000000), blurRadius: 15, offset: Offset(0, 8))],
                          ),
                          child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                            const Text('OKEYX', style: TextStyle(fontSize: 8, color: Color(0x73FFFFFF), fontWeight: FontWeight.w900, letterSpacing: 2)),
                            Text('101', style: TextStyle(fontSize: compact ? 34 : 43, height: .88, fontWeight: FontWeight.w900, color: Colors.white)),
                            const Text('OKEY ARENA', style: TextStyle(fontSize: 9, color: OkeyXColors.gold, fontWeight: FontWeight.w900, letterSpacing: .8)),
                            const SizedBox(height: 6),
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              for (final n in const [3, 5, 8]) ...[
                                Container(width: compact ? 20 : 24, height: compact ? 28 : 32, alignment: Alignment.center, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4), border: Border.all(color: const Color(0xFF8CC0AF))), child: Text('$n', style: const TextStyle(color: Color(0xFF2E1E7C), fontSize: 10, fontWeight: FontWeight.w900))),
                                const SizedBox(width: 3),
                              ],
                            ]),
                          ])),
                        ),
                        Positioned(top: 0, child: _lobbyArenaSeat('RAKİP', Icons.person_rounded, false)),
                        Positioned(bottom: 0, child: _lobbyArenaSeat('SEN', Icons.person_rounded, true)),
                        Positioned(left: 2, child: _lobbyArenaSeat('RAKİP', Icons.person_rounded, false)),
                        Positioned(right: 2, child: _lobbyArenaSeat('RAKİP', Icons.person_rounded, false)),
                      ]),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 4,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                        Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3), decoration: BoxDecoration(color: OkeyXColors.gold.withValues(alpha: .12), borderRadius: BorderRadius.circular(8), border: Border.all(color: OkeyXColors.gold.withValues(alpha: .30))), child: const Text('ANA ARENA', style: TextStyle(fontSize: 6.3, color: OkeyXColors.gold, fontWeight: FontWeight.w900, letterSpacing: .7))),
                        const SizedBox(height: 7),
                        const Text('101 OKEY', style: TextStyle(fontSize: 19, height: .9, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 5),
                        Text(_modeSummary, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 7.2, height: 1.25, color: Colors.white60, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 7),
                        Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white10)), child: Row(children: [const Icon(Icons.account_balance_wallet_rounded, size: 13, color: OkeyXColors.gold), const SizedBox(width: 5), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('GEREKLİ BAKİYE', style: TextStyle(fontSize: 5.5, color: Colors.white38, fontWeight: FontWeight.w900)), Text('${_format(_requiredBalance(_entryFee, _turbo))} altın', style: TextStyle(fontSize: 8, color: _chips >= _requiredBalance(_entryFee, _turbo) ? Colors.white : OkeyXColors.gold, fontWeight: FontWeight.w900))]))])),
                        const SizedBox(height: 7),
                        SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _busy ? null : _quickPlay, icon: const Icon(Icons.play_arrow_rounded, size: 17), label: Text(_chips >= _requiredBalance(_entryFee, _turbo) ? 'HIZLI OYNA' : 'ALTIN TAMAMLA', style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w900)))),
                      ]),
                    ),
                  ]),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _lobbyArenaSeat(String label, IconData icon, bool mine) => Container(
        width: 61,
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
        decoration: BoxDecoration(color: const Color(0xE8100B2D), borderRadius: BorderRadius.circular(12), border: Border.all(color: mine ? OkeyXColors.mint : Colors.white12), boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 8, offset: Offset(0, 4))]),
        child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 11, color: mine ? OkeyXColors.mint : Color(0x73FFFFFF)), const SizedBox(width: 3), Expanded(child: Text(label, maxLines: 1, style: TextStyle(fontSize: 5.6, fontWeight: FontWeight.w900, color: mine ? OkeyXColors.mint : Colors.white54)))]),
      );

  Widget _modeGameCard({required IconData icon, required String title, required String detail, required Color color, required VoidCallback onTap}) => Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: _busy ? null : onTap,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(colors: [color.withValues(alpha: .78), color.withValues(alpha: .26)]),
              border: Border.all(color: color.withValues(alpha: .55)),
            ),
            child: Row(
              children: [
                Icon(icon, color: Colors.white, size: 25),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900))),
                      Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 7, color: Colors.white70)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _bonusRail(bool compact) {
    final daily = _map(_account['daily']);
    final wheel = _map(_account['wheel']);
    final chests = _map(_account['chests']);
    final dailyDone = '${daily['last_claim_day'] ?? ''}' == _todayKey;
    final wheelDone = '${wheel['last_spin_day'] ?? ''}' == _todayKey;
    final keys = _integer(chests['keys']);
    final chestFreeDone = '${chests['last_free_day'] ?? ''}' == _todayKey;
    final chestEnabled = keys > 0 || !chestFreeDone;
    return Column(
      children: [
        Expanded(child: _bonusTile(Icons.card_giftcard_rounded, 'GÜNLÜK', dailyDone ? _dailyResetText : '${_integer(daily['streak'])}/7 hazır', OkeyXColors.gold, _claimDaily, enabled: !dailyDone)),
        const SizedBox(height: 6),
        Expanded(child: _bonusTile(Icons.casino_rounded, 'ÇARK', wheelDone ? _dailyResetText : 'Ücretsiz', const Color(0xFF87B9FF), _spinWheel, enabled: !wheelDone)),
        const SizedBox(height: 6),
        Expanded(child: _bonusTile(Icons.inventory_2_rounded, 'SANDIK', keys > 0 ? '$keys anahtar' : (chestFreeDone ? _dailyResetText : 'Ücretsiz'), const Color(0xFFD58CFF), _openChest, enabled: chestEnabled)),
        const SizedBox(height: 6),
        Expanded(child: _bonusTile(Icons.savings_rounded, 'ÇANAK', _compactNumber(_integer(_canak['balance'])), OkeyXColors.mint, () async { setState(() => _selected = 2); })),
      ],
    );
  }

  Widget _bonusTile(IconData icon, String title, String detail, Color color, Future<void> Function() onTap, {bool enabled = true}) => Material(
        color: const Color(0xA6100B2D),
        borderRadius: BorderRadius.circular(15),
        child: InkWell(
          onTap: _busy || !enabled ? null : onTap,
          borderRadius: BorderRadius.circular(15),
          child: Opacity(
            opacity: enabled ? 1 : .55,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  Icon(icon, size: 18, color: color),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(title, style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w900))),
                        Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 6.5, color: Colors.white60)),
                      ],
                    ),
                  ),
                  if (!enabled) const Icon(Icons.check_circle_rounded, size: 12, color: Colors.white38),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _lobbyShortcuts(bool compact) {
    final entries = <_LobbyShortcutEntry>[
      _LobbyShortcutEntry(Icons.task_alt_rounded, 'Görevler', () => setState(() => _selected = 2)),
      _LobbyShortcutEntry(Icons.groups_rounded, 'Arkadaşlık', () => setState(() => _selected = 3)),
      _LobbyShortcutEntry(Icons.emoji_events_rounded, 'Lig', () => setState(() => _selected = 2)),
      _LobbyShortcutEntry(Icons.shield_rounded, 'Kulüp', () => setState(() => _selected = 4)),
      _LobbyShortcutEntry(Icons.auto_awesome_rounded, 'Şanslı Taşlar', () => setState(() => _selected = 5)),
      _LobbyShortcutEntry(
        _preferences.radioEnabled ? Icons.graphic_eq_rounded : Icons.radio_rounded,
        _preferences.radioEnabled ? 'Radyo • Açık' : 'OkeyX Radyo',
        () { unawaited(_showRadioMenu()); },
        active: _preferences.radioEnabled,
      ),
      _LobbyShortcutEntry(Icons.table_bar_rounded, 'Masalar', () => setState(() => _selected = 1)),
    ];
    return Container(
      height: compact ? 38 : 44,
      decoration: BoxDecoration(color: const Color(0x880B071E), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white12)),
      child: Row(
        children: [
          for (final entry in entries)
            Expanded(
              child: InkWell(
                onTap: entry.onTap,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds:180),
                  decoration: BoxDecoration(color: entry.active ? OkeyXColors.mint.withValues(alpha:.08) : Colors.transparent, borderRadius: BorderRadius.circular(11)),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(entry.icon, size: compact ? 14 : 17, color: entry.active ? OkeyXColors.mint : Colors.white70),
                      const SizedBox(height: 1),
                      FittedBox(child: Text(entry.label, style: TextStyle(fontSize: 6.3, color: entry.active ? OkeyXColors.mint : Colors.white60, fontWeight: FontWeight.w800))),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _tables(bool compact) => RefreshIndicator(
        onRefresh: _refreshRooms,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final rooms = _rooms.where((r) {
              final duz = r['variant'] == 'duz';
              return switch (_roomFilter) {
                'okey101' => !duz,
                'klasik' => duz,
                'turbo' => r['turbo'] == true || r['game_mode'] == 'turbo',
                'open' => _integer(r['players']) < 4 && r['locked'] != true,
                _ => true,
              };
            }).toList()
              ..sort((x, y) {
                final fx = _integer(x['players']) >= 4 ? 1 : 0, fy = _integer(y['players']) >= 4 ? 1 : 0;
                if (fx != fy) return fx - fy;
                return _integer(y['players']).compareTo(_integer(x['players']));
              });
            final cardH = compact ? 168.0 : 186.0;
            final pad = compact ? 12.0 : 18.0;
            return ListView(
              padding: EdgeInsets.fromLTRB(pad, pad, pad, compact ? 74 : 92),
              children: [
                Row(children: [
                  const Expanded(child: OkxTitle('Masalar', size: 24)),
                  OkxButton.green(label: 'HIZLI OYNA', icon: Icons.bolt_rounded, height: 40, fontSize: 12, onTap: _busy ? null : _quickPlay),
                  const SizedBox(width: 8),
                  OkxButton(label: 'MASA KUR', icon: Icons.add_rounded, height: 40, fontSize: 12, onTap: _busy ? null : _createRoomDialog),
                ]),
                const SizedBox(height: 10),
                SizedBox(
                  height: 34,
                  child: ListView(scrollDirection: Axis.horizontal, children: [
                    for (final f in const [('all', 'Tümü'), ('okey101', '101 Okey'), ('klasik', 'Klasik Okey'), ('turbo', '★ Turbo'), ('open', 'Boş koltuklu')])
                      Padding(
                        padding: const EdgeInsets.only(right: 7),
                        child: OkxChip(label: f.$2, selected: _roomFilter == f.$1, onTap: () => setState(() => _roomFilter = f.$1)),
                      ),
                  ]),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Container(width: 8, height: 8, decoration: const BoxDecoration(shape: BoxShape.circle, color: OkeyXColors.mint)),
                  const SizedBox(width: 6),
                  Text('${rooms.length} MASA • CANLI', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, letterSpacing: 1.2, color: OkeyXColors.mint)),
                  const Spacer(),
                  IconButton(visualDensity: VisualDensity.compact, onPressed: _refreshRooms, icon: const Icon(Icons.refresh_rounded, size: 19, color: OkeyXColors.muted)),
                ]),
                const SizedBox(height: 4),
                SizedBox(
                  height: cardH,
                  child: rooms.isEmpty
                      ? OkxLeather(
                          radius: 18,
                          padding: const EdgeInsets.all(16),
                          child: Row(children: [
                            const Icon(Icons.table_bar_rounded, size: 34, color: OkeyXColors.gold),
                            const SizedBox(width: 14),
                            const Expanded(child: Text('Şu an bekleyen masa yok.\nHızlı oyna ya da kendi masanı kur!', style: TextStyle(fontSize: 13, height: 1.4, fontWeight: FontWeight.w700, color: OkeyXColors.cream))),
                            OkxButton(label: 'MASA KUR', height: 40, fontSize: 12, onTap: _busy ? null : _createRoomDialog),
                          ]),
                        )
                      : ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: rooms.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 10),
                          itemBuilder: (_, i) => _roomCard(rooms[i], compact ? 232.0 : 252.0),
                        ),
                ),
              ],
            );
          },
        ),
      );

  /// Yatay masa kartı: ad, oyun türü, giriş, 4 koltuk doluluğu (gerçek zamanlı).
  Widget _roomCard(Map<String, dynamic> room, double width) {
    final locked = room['locked'] == true;
    final players = _integer(room['players']).clamp(0, 4).toInt();
    final humans = _integer(room['human_players'], fallback: players).clamp(0, 4).toInt();
    final bots = _integer(room['bot_players']).clamp(0, 4).toInt();
    final full = players >= 4;
    final duz = room['variant'] == 'duz';
    final turbo = room['turbo'] == true || room['game_mode'] == 'turbo';
    final fee = _integer(room['entry_fee']);
    final required = _integer(room['required_balance'], fallback: fee);
    final affordable = _chips >= required;
    final title = duz ? 'KLASİK OKEY' : '101 OKEY';
    final rule = duz ? 'Klasik' : room['variant'] == 'fold' ? 'Katlamalı' : 'Katlamasız';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: _busy || full ? null : () => _joinRoom(room),
        child: Ink(
          width: width,
          padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: turbo ? const [Color(0xFF1C1250), Color(0xFF0F092B)] : const [Color(0xFF173A2B), Color(0xFF0E2219)]),
            border: Border.all(color: turbo ? const Color(0x99E0B354) : const Color(0x6650C894), width: 1.2),
            boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 14, offset: Offset(0, 6))],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(title, maxLines: 1, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.3, color: turbo ? const Color(0xFFFFD98A) : OkeyXColors.mint))),
              if (turbo) const Icon(Icons.bolt_rounded, size: 15, color: Color(0xFFFFD98A)),
              if (locked) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.lock_rounded, size: 14, color: OkeyXColors.gold)),
            ]),
            const SizedBox(height: 3),
            Text('${room['name'] ?? 'OkeyX Masası'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: OkeyXFonts.serif, fontSize: 16, fontWeight: FontWeight.w700, color: OkeyXColors.cream)),
            const SizedBox(height: 2),
            Text('$rule • ${room['assisted'] == false ? 'Yardımsız' : 'Yardımlı'} • ${math.max(1, _integer(room['rounds']))} el • ${_integer(room['turn_seconds'], fallback: 35)} sn', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: OkeyXColors.muted)),
            const Spacer(),
            Row(children: [
              for (var i = 0; i < 4; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 5),
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < humans ? const Color(0xFF2E7D5B) : i < humans + bots ? const Color(0xFF231664) : const Color(0x22FFFFFF),
                      border: Border.all(color: i < players ? const Color(0xCCE8C478) : const Color(0x33FFFFFF)),
                    ),
                    child: Icon(i < humans ? Icons.person_rounded : i < humans + bots ? Icons.smart_toy_rounded : Icons.add_rounded, size: 13, color: i < players ? const Color(0xFFFFE9B0) : const Color(0x66FFFFFF)),
                  ),
                ),
              const Spacer(),
              Text('$players/4', style: TextStyle(fontFamily: OkeyXFonts.number, fontSize: 15, color: full ? OkeyXColors.muted : const Color(0xFFFFE9B0))),
            ]),
            const SizedBox(height: 9),
            Row(children: [
              const OkxCoin(size: 15),
              const SizedBox(width: 5),
              Text(_format(fee), style: const TextStyle(fontFamily: OkeyXFonts.number, fontSize: 14, color: Color(0xFFFFD98A))),
              if (turbo) const Text('  ×10 bakiye', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: OkeyXColors.muted)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: full ? null : LinearGradient(colors: affordable ? const [Color(0xFFFFE36B), Color(0xFFFFA928)] : const [Color(0xFF8A6A3A), Color(0xFF2C1C7D)]),
                  color: full ? const Color(0x22FFFFFF) : null,
                ),
                child: Text(full ? 'DOLU' : affordable ? 'OTUR' : 'ALTIN AL', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: .6, color: full ? OkeyXColors.muted : okxTextDark)),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _events(bool compact) => RefreshIndicator(
        onRefresh: _refreshAccountBits,
        child: ListView(
          padding: EdgeInsets.all(compact ? 11 : 18),
          children: [
            _liveEventsPanel(compact),
            const SizedBox(height: 10),
            Wrap(
              spacing: 9,
              runSpacing: 9,
              children: [
                _rewardPanel(),
                _wheelPanel(),
                _chestPanel(),
                _canakPanel(),
              ],
            ),
            const SizedBox(height: 10),
            _missionsPanel(),
            const SizedBox(height: 10),
            _achievementsPanel(),
            const SizedBox(height: 10),
            _seasonPanel(),
            const SizedBox(height: 10),
            _leaguePanel(),
          ],
        ),
      );

  String get _todayKey {
    // Ödül günü sunucuyla aynı takvimden gelir (Türkiye saati). Yerel saat
    // farklıysa "hazır" görünüp sunucu reddediyordu.
    final serverKey = '${_account['reward_day_key'] ?? ''}';
    if (serverKey.length == 10) return serverKey;
    final now = DateTime.now().toUtc().add(const Duration(hours: 3));
    String p(int v) => v.toString().padLeft(2, '0');
    return '${now.year}-${p(now.month)}-${p(now.day)}';
  }

  String get _dailyResetText {
    final now = DateTime.now().toUtc().add(const Duration(hours: 3));
    final next = DateTime.utc(now.year, now.month, now.day + 1);
    final left = next.difference(now);
    final hours = left.inHours.clamp(0, 23);
    final minutes = (left.inMinutes % 60).clamp(0, 59);
    return '${hours}sa ${minutes.toString().padLeft(2, '0')}dk';
  }

  Widget _rewardPanel() {
    final daily = _map(_account['daily']);
    final claimed = '${daily['last_claim_day'] ?? ''}' == _todayKey;
    return _smallPanel(
      '7 Günlük Ödül',
      Icons.calendar_month_rounded,
      claimed ? '$_dailyResetText sonra yenilenir' : '${_integer(daily['streak'])}/7 seri • bugün hazır',
      claimed
          ? const _CooldownPill(label: 'ALINDI', icon: Icons.check_rounded)
          : FilledButton(onPressed: _busy ? null : _claimDaily, child: const FittedBox(fit: BoxFit.scaleDown, child: Text('ÖDÜLÜ AL', maxLines: 1, softWrap: false))),
    );
  }

  Widget _wheelPanel() {
    final wheel = _map(_account['wheel']);
    final cfg = _map(_rewardConfig['wheel']);
    final limit = math.max(1, _integer(cfg['daily_limit'], fallback: 1));
    final dayMatches = '${wheel['day'] ?? ''}' == _todayKey;
    final usedToday = dayMatches ? _integer(wheel['spins_today']) : ('${wheel['last_spin_day'] ?? ''}' == _todayKey ? 1 : 0);
    final canSpin = usedToday < limit;
    return _smallPanel(
      'Günlük Çark',
      Icons.casino_rounded,
      canSpin ? '$usedToday/$limit bugün • ${limit-usedToday} dönüş hazır' : '$usedToday/$limit bugün • $_dailyResetText sonra yenilenir',
      canSpin
          ? FilledButton(onPressed: _busy ? null : _spinWheel, child: const Text('ÇEVİR'))
          : const FilledButton(onPressed: null, child: FittedBox(fit: BoxFit.scaleDown, child: Text('KULLANILDI', maxLines: 1, softWrap: false))),
    );
  }

  Widget _chestPanel() {
    final chests = _map(_account['chests']);
    final cfg = _map(_rewardConfig['chest']);
    final limit = math.max(1, _integer(cfg['daily_limit'], fallback: 5));
    final keys = _integer(chests['keys']);
    final dayMatches = '${chests['day'] ?? ''}' == _todayKey;
    final openedToday = dayMatches ? _integer(chests['opened_today']) : 0;
    final freeUsed = '${chests['last_free_day'] ?? ''}' == _todayKey;
    final completed = openedToday >= limit;
    final canOpen = !completed && (keys > 0 || !freeUsed);
    final detail = completed
        ? '$openedToday/$limit bugün • $_dailyResetText sonra yenilenir'
        : '$openedToday/$limit bugün • $keys anahtar${freeUsed && keys == 0 ? ' • $_dailyResetText sonra ücretsiz' : ''}';
    return _smallPanel(
      'Şans Sandığı',
      Icons.inventory_2_rounded,
      detail,
      canOpen
          ? FilledButton(onPressed: _busy ? null : _openChest, child: const Text('AÇ'))
          : FilledButton(onPressed: null, child: FittedBox(fit: BoxFit.scaleDown, child: Text(completed ? 'BİTTİ' : 'ANAHTAR YOK', maxLines: 1, softWrap: false))),
    );
  }

  Widget _canakPanel() => _smallPanel(
        'Çanak',
        Icons.savings_rounded,
        '${_format(_integer(_canak['balance']))} altın',
        const Text('%2 KOMİSYON', style: TextStyle(fontSize: 7.5, color: Colors.white54, fontWeight: FontWeight.w900)),
      );

  Widget _smallPanel(String title, IconData icon, String value, Widget action) => SizedBox(
        width: 286,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: const Color(0xFF130C37),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: OkeyXColors.mint.withValues(alpha: .16)),
            boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 10, offset: Offset(0, 4))],
          ),
          child: Row(children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), color: OkeyXColors.gold.withValues(alpha: .10), border: Border.all(color: Colors.white10)),
              child: Icon(icon, color: OkeyXColors.gold, size: 21),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 10.5)),
              const SizedBox(height: 2),
              Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 7.8, color: Colors.white60, fontWeight: FontWeight.w600)),
            ])),
            const SizedBox(width: 8),
            ConstrainedBox(constraints: const BoxConstraints(minWidth: 78, maxWidth: 92, minHeight: 34), child: action),
          ]),
        ),
      );

  Widget _missionsPanel() => _panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('GÖREVLER', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
            const SizedBox(height: 8),
            _missionGroup('Günlük', _list(_missions['daily']).map(_map).toList()),
            const SizedBox(height: 9),
            _missionGroup('Haftalık', _list(_missions['weekly']).map(_map).toList()),
          ],
        ),
      );

  Widget _missionGroup(String title, List<Map<String, dynamic>> rows) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 9, color: OkeyXColors.gold, fontWeight: FontWeight.w900)),
          for (final m in rows)
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${m['title']}', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        LinearProgressIndicator(value: (_integer(m['progress']) / (_integer(m['target']).clamp(1, 999))).clamp(0.0, 1.0), minHeight: 3),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('${_integer(m['progress'])}/${_integer(m['target'])}', style: const TextStyle(fontSize: 8, color: Colors.white54)),
                  const SizedBox(width: 8),
                  FilledButton.tonal(
                    onPressed: _busy || m['claimed'] == true
                        ? null
                        : (m['complete'] == true
                            ? () => _claimMission('${m['id']}')
                            : () => setState(() => _selected = 1)),
                    child: Text(m['claimed'] == true ? 'ALINDI' : m['complete'] == true ? 'AL' : 'OYNA', style: const TextStyle(fontSize: 8)),
                  ),
                ],
              ),
            ),
        ],
      );

  Widget _achievementsPanel() {
    final rows = _list(_account['achievements']).map(_map).toList();
    return _panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('BAŞARIMLAR', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
        const SizedBox(height: 7),
        if (rows.isEmpty) const Text('İlk başarım için bir masa tamamla.', style: TextStyle(fontSize: 9, color: Colors.white54)),
        Wrap(spacing: 7, runSpacing: 7, children: [for (final a in rows) Chip(avatar: const Icon(Icons.emoji_events_rounded, size: 15, color: OkeyXColors.gold), label: Text('${a['title']}', style: const TextStyle(fontSize: 8)))]),
      ]),
    );
  }

  Widget _seasonPanel() {
    final milestones = _list(_season['milestones']).map(_map).toList();
    final claimed = _list(_season['claimed']).map((e) => '$e').toSet();
    final points = _integer(_season['points']);
    return _panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [const Text('SEZONLUK ETKİNLİK', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13)), const Spacer(), Text('${_season['id'] ?? ''} • $points puan', style: const TextStyle(fontSize: 8, color: Colors.white54))]),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final m in milestones)
              SizedBox(
                width: 190,
                child: Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: .04), borderRadius: BorderRadius.circular(12), border: Border.all(color: points >= _integer(m['points']) ? OkeyXColors.mint.withValues(alpha: .5) : Colors.white12)),
                  child: Row(children: [Expanded(child: Text('${_integer(m['points'])} puan • ${_format(_integer(m['chips']))} 🟡', style: const TextStyle(fontSize: 8))), FilledButton.tonal(onPressed: points >= _integer(m['points']) && !claimed.contains('${m['id']}') ? () => _claimSeason('${m['id']}') : null, child: Text(claimed.contains('${m['id']}') ? '✓' : 'AL', style: const TextStyle(fontSize: 7)))]),
                ),
              ),
          ],
        ),
      ]),
    );
  }

  Widget _leaguePanel() {
    final rows = _list(_leaderboard['rows']).map(_map).toList();
    return _panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('HAFTALIK LİGLER', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
          const Spacer(),
          TextButton.icon(onPressed: _changeCity, icon: const Icon(Icons.location_city_rounded, size: 16), label: Text('${_map(_account['league'])['city'] ?? 'Denizli'}', style: const TextStyle(fontSize: 8))),
        ]),
        Wrap(spacing: 6, children: [
          ChoiceChip(label: const Text('Global'), selected: _leagueScope == 'global', onSelected: (_) => _switchLeague('global')),
          ChoiceChip(label: const Text('Şehir'), selected: _leagueScope == 'city', onSelected: (_) => _switchLeague('city')),
          ChoiceChip(label: const Text('Aylık'), selected: _leagueScope == 'monthly', onSelected: (_) => _switchLeague('monthly')),
          ChoiceChip(label: const Text('Arkadaş'), selected: _leagueScope == 'friends', onSelected: (_) => _switchLeague('friends')),
        ]),
        const SizedBox(height: 7),
        for (final row in rows.take(12))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [SizedBox(width: 28, child: Text('#${_integer(row['rank'])}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 9))), Expanded(child: Text('${row['name']} • ${row['tier']}', style: const TextStyle(fontSize: 9))), Text('${_integer(row['points'])} puan', style: const TextStyle(fontSize: 8, color: Colors.white54))]),
          ),
      ]),
    );
  }

  Widget _socialPage(bool compact) => RefreshIndicator(
        onRefresh: _refreshAccountBits,
        child: ListView(
          padding: EdgeInsets.all(compact ? 11 : 18),
          children: [
            if (_socialLocked) _accountLinkGate() else _playerSearchPanel(),
            if (!_socialLocked) ...[
              const SizedBox(height: 10), _friendsPanel(),
              const SizedBox(height: 10), _referralPanel(),
              const SizedBox(height: 10), _clubPanel(),
            ],
          ],
        ),
      );

  Widget _accountLinkGate() => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(colors: [Color(0xFF201556), Color(0xFF100A2B)]),
          border: Border.all(color: OkeyXColors.gold.withValues(alpha: .32)),
        ),
        child: Row(children: [
          Container(width: 58, height: 58, decoration: BoxDecoration(shape: BoxShape.circle, color: OkeyXColors.gold.withValues(alpha: .12)), child: const Icon(Icons.person_add_alt_1_rounded, color: OkeyXColors.gold, size: 30)),
          const SizedBox(width: 14),
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('SOSYAL PROFİLİNİ AÇ', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
            SizedBox(height: 4),
            Text('Arkadaşlarını Oyuncu ID ile bul, ekle ve aynı masaya davet et. Hesabını bağlamak yalnızca ilerlemeni kurtarmayı kolaylaştırır.', style: TextStyle(fontSize: 8.5, color: Colors.white60)),
          ])),
          FilledButton.icon(onPressed: _openSettings, icon: const Icon(Icons.link_rounded), label: const Text('HESABI BAĞLA')),
        ]),
      );

  Widget _chancePage(bool compact) => RefreshIndicator(
        onRefresh: _refreshEconomy,
        child: ListView(
          padding: EdgeInsets.all(compact ? 9 : 14),
          children: [
            ChanceHall(api: _api, hub: _phase4Hub, onRefresh: _refreshEconomy, onMessage: _flash, onWalletChanged:_applyWalletImmediate, onOpenStore: () => setState(() => _selected = 6), soundEnabled: _preferences.soundEnabled, vibrationEnabled: _preferences.vibrationEnabled),
          ],
        ),
      );

  Widget _operationsPage(bool compact) {
    if (!_isStaff) return const Center(child: Text('Bu alan yalnızca yetkili OkeyX ekibi içindir.', style: TextStyle(color: Colors.white54)));
    final staff = _map(_phase4Hub['staff']);
    return ListView(
      padding: EdgeInsets.all(compact ? 12 : 20),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(colors: [Color(0xFF1A104A), Color(0xFF140D38), Color(0xFF0E0927)]),
            border: Border.all(color: OkeyXColors.gold.withValues(alpha: .42)),
            boxShadow: const [BoxShadow(color: Color(0x44000000), blurRadius: 24, offset: Offset(0, 10))],
          ),
          child: Row(children: [
            Container(width: 64, height: 64, decoration: BoxDecoration(shape: BoxShape.circle, color: OkeyXColors.gold.withValues(alpha: .12), border: Border.all(color: OkeyXColors.gold.withValues(alpha: .45))), child: const Icon(Icons.admin_panel_settings_rounded, color: OkeyXColors.gold, size: 34)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('OKEYX OPERASYON MERKEZİ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              Text('${staff['role'] ?? 'staff'} • ${_list(staff['permissions']).length} aktif yetki', style: const TextStyle(fontSize: 8, color: OkeyXColors.gold, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              const Text('Moderasyon, cüzdan düzeltmeleri, RTP, etkinlik ve denetim kayıtları tek merkezde.', style: TextStyle(fontSize: 8.5, color: Colors.white60)),
            ])),
            FilledButton.icon(onPressed: _openStaffConsole, icon: const Icon(Icons.dashboard_customize_rounded), label: const Text('PANELİ AÇ')),
          ]),
        ),
      ],
    );
  }

  Future<void> _openStaffConsole() async {
    await showDialog<void>(context: context, barrierDismissible: false, builder: (_) => StaffConsoleDialog(api: _api));
    await _refreshEconomy();
  }

  Widget _playerSearchPanel() => _panel(
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [const Icon(Icons.person_search_rounded, color: OkeyXColors.mint, size: 18), const SizedBox(width: 6), const Text('OYUNCU BUL', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13)), const Spacer(), Text('${_friends.length} arkadaş • ${_requests.length} istek', style: const TextStyle(fontSize: 7, color: Colors.white38))]),
      const SizedBox(height: 7),
      Row(children: [Expanded(child: TextField(controller: _playerSearchController, decoration: const InputDecoration(hintText: 'Kullanıcı adı veya oyuncu ID', prefixIcon: Icon(Icons.search_rounded), isDense: true), onSubmitted: _searchPlayers)), const SizedBox(width: 7), FilledButton(onPressed: () => _searchPlayers(_playerSearchController.text), child: const Text('ARA'))]),
      if (_searchResults.isNotEmpty) ...[const SizedBox(height: 8), for (final p in _searchResults) _socialPersonRow(p, action: _searchFriendAction(p))],
    ]),
  );

  Widget _searchFriendAction(Map<String, dynamic> p) {
    final id = '${p['id']}';
    final rel = '${p['relationship'] ?? (_sentFriendRequests.contains(id) ? 'sent' : 'none')}';
    if (rel == 'friend') return const Chip(label: Text('ARKADAŞ', style: TextStyle(fontSize: 7)));
    if (rel == 'sent') return TextButton(onPressed: () => _cancelFriendRequest(id), child: const Text('İSTEK GİTTİ', style: TextStyle(fontSize: 7)));
    if (rel == 'incoming') return Row(mainAxisSize: MainAxisSize.min, children: [IconButton.filledTonal(onPressed: () => _acceptFriend(id), icon: const Icon(Icons.check_rounded, size: 16)), IconButton(onPressed: () => _declineFriend(id), icon: const Icon(Icons.close_rounded, size: 16))]);
    return FilledButton.tonalIcon(onPressed: () => _friendRequest(id), icon: const Icon(Icons.person_add_alt_1_rounded, size: 14), label: const Text('EKLE', style: TextStyle(fontSize: 7)));
  }

  Widget _friendsPanel() {
    final online = _friends.where((p) => p['online'] == true || p['in_game'] == true).length;
    Widget head(String t, {String? trailing}) => Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 4),
          child: Row(children: [OkxLabel(t, color: OkeyXColors.gold), const Spacer(), if (trailing != null) OkxLabel(trailing, color: OkeyXColors.mint)]),
        );
    return _panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [const Expanded(child: OkxTitle('Arkadaşlar', size: 20)), OkxLabel('$online çevrimiçi', color: OkeyXColors.mint)]),
        if (_requests.isNotEmpty) ...[
          head('Gelen istekler'),
          for (final p in _requests)
            _socialPersonRow(p, request: true, action: Row(mainAxisSize: MainAxisSize.min, children: [
              OkxButton.green(label: 'KABUL', height: 34, fontSize: 11, padding: const EdgeInsets.symmetric(horizontal: 14), onTap: () => _acceptFriend('${p['id']}')),
              const SizedBox(width: 6),
              OkxButton.ghost(label: '', icon: Icons.close_rounded, height: 34, padding: const EdgeInsets.symmetric(horizontal: 8), onTap: () => _declineFriend('${p['id']}')),
            ])),
        ],
        head('Arkadaş listesi', trailing: '${_friends.length}'),
        if (_friends.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Row(children: [
              Icon(Icons.group_off_rounded, color: OkeyXColors.dim),
              SizedBox(width: 9),
              Expanded(child: Text('Henüz arkadaşın yok. Oyuncu numarasıyla ara ya da son oynadıklarından ekle.', style: TextStyle(fontSize: 12, color: OkeyXColors.muted, fontWeight: FontWeight.w600))),
            ]),
          ),
        for (final p in _friends)
          _socialPersonRow(p, action: Row(mainAxisSize: MainAxisSize.min, children: [
            if (p['joinable'] == true)
              OkxButton.green(label: 'KATIL', icon: Icons.login_rounded, height: 34, fontSize: 11, padding: const EdgeInsets.symmetric(horizontal: 12), onTap: () => _joinFriendRoom(p))
            else if (p['in_game'] == true)
              OkxButton.ghost(label: 'İZLE', icon: Icons.visibility_rounded, height: 34, fontSize: 11, padding: const EdgeInsets.symmetric(horizontal: 12), onTap: () => setState(() => _selected = 2))
            else if (_resumeSession != null && p['online'] == true)
              OkxButton(label: 'DAVET', icon: Icons.send_rounded, height: 34, fontSize: 11, padding: const EdgeInsets.symmetric(horizontal: 12), onTap: () => _inviteFriend('${p['id']}')),
            const SizedBox(width: 4),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded, color: OkeyXColors.muted),
              onSelected: (v) => v == 'coins' ? _showCoinTransfer(p) : (v == 'remove' ? _removeFriend('${p['id']}') : _socialSafety('${p['id']}', v)),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'coins', child: Row(children: [Icon(Icons.paid_rounded, size: 18, color: OkeyXColors.gold), SizedBox(width: 8), Text('Altın gönder')])),
                PopupMenuItem(value: 'remove', child: Text('Arkadaştan çıkar')),
                PopupMenuItem(value: 'mute', child: Text('Sessize al')),
                PopupMenuItem(value: 'block', child: Text('Engelle')),
                PopupMenuItem(value: 'report', child: Text('Şikâyet et')),
              ],
            ),
          ])),
        head('Son oynadıkların'),
        if (_recent.isEmpty) const Padding(padding: EdgeInsets.only(top: 6), child: Text('Bir masa bitirdiğinde birlikte oynadığın kişiler burada görünür.', style: TextStyle(fontSize: 12, color: OkeyXColors.muted, fontWeight: FontWeight.w600))),
        for (final p in _recent.take(12))
          _socialPersonRow(p,
              action: _friends.any((x) => '${x['id']}' == '${p['id']}')
                  ? const OkxChip(label: 'ARKADAŞ', icon: Icons.check_rounded)
                  : (_sentFriendRequests.contains('${p['id']}')
                      ? OkxButton.ghost(label: 'BEKLİYOR', height: 34, fontSize: 11, padding: const EdgeInsets.symmetric(horizontal: 12), onTap: () => _cancelFriendRequest('${p['id']}'))
                      : OkxButton(label: 'EKLE', icon: Icons.person_add_alt_1_rounded, height: 34, fontSize: 11, padding: const EdgeInsets.symmetric(horizontal: 12), onTap: () => _friendRequest('${p['id']}')))),
      ]),
    );
  }

  Widget _socialPersonRow(Map<String, dynamic> p, {required Widget action, bool request = false}) {
    final online = p['online'] == true, inGame = p['in_game'] == true;
    final status = request
        ? 'Sana arkadaşlık isteği gönderdi'
        : inGame
            ? 'Oyunda • ${p['room_name'] ?? 'OkeyX masası'}'
            : '${p['status']}' == 'lobby'
                ? 'Lobide • Çevrimiçi'
                : (online ? 'Çevrimiçi' : 'Çevrimdışı');
    final color = request ? OkeyXColors.gold : inGame ? const Color(0xFFFFD98A) : (online ? OkeyXColors.mint : OkeyXColors.dim);
    final name = '${p['name'] ?? 'Oyuncu'}';
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: inGame ? const Color(0x14FFD278) : const Color(0x0DFFEBC8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: inGame ? const Color(0x59E8C478) : const Color(0x14E8C478)),
      ),
      child: Row(children: [
        OkxAvatar(name: name, imageUrl: '${p['avatar_url'] ?? ''}', size: 40, online: online || inGame),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: OkeyXColors.cream)),
            const SizedBox(height: 2),
            Text('$status • LV ${_integer(p['level'])}${'${p['public_id'] ?? ''}'.isEmpty ? '' : ' • ${p['public_id']}'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
          ]),
        ),
        const SizedBox(width: 8),
        action,
      ]),
    );
  }

  // ------------------------------------------------------------ GELEN DAVET
  final Set<String> _shownInvites = <String>{};
  OverlayEntry? _inviteEntry;

  Future<void> _pollAlerts() async {
    if (_alertBusy) return;
    _alertBusy = true;
    try {
      final data = await _api.notifications();
      if (!mounted) return;
      setState(() => _notifications = data);
      _checkInvites();
      await _checkWalletEvents();
    } catch (_) {
    } finally {
      _alertBusy = false;
    }
  }

  /// Biri altın gönderdiğinde ya da çanak kırıldığında bakiyeyi hemen tazele.
  Future<void> _checkWalletEvents() async {
    var changed = false;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    for (final n in _notificationRows) {
      final kind = '${n['kind']}';
      if (n['read'] == true || !const {'social_transfer', 'canak'}.contains(kind)) continue;
      final id = 'w-${n['id']}';
      if (_shownInvites.contains(id)) continue;
      _shownInvites.add(id);
      if (now - _integer(n['created_at']) > 300) continue;
      changed = true;
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF150E3D),
          content: Row(children: [
            const Icon(Icons.paid_rounded, color: OkeyXColors.gold),
            const SizedBox(width: 8),
            Expanded(child: Text('${n['message'] ?? n['title'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w800))),
          ]),
        ));
      }
    }
    if (!changed) return;
    try {
      final account = await _api.account();
      if (mounted) setState(() => _account = {..._account, 'chips': _integer(account['chips'], fallback: _chips)});
      unawaited(GameAudio.sfx('reward'));
    } catch (_) {}
  }

  void _checkInvites() {
    if (!mounted || _inviteEntry != null) return;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    for (final n in _notificationRows) {
      final kind = '${n['kind']}';
      if (n['read'] == true || !const {'invite', 'friend_request', 'friend'}.contains(kind)) continue;
      final id = '${n['id']}';
      if (_shownInvites.contains(id)) continue;
      _shownInvites.add(id);
      if (now - _integer(n['created_at']) > 120) continue;
      if (kind == 'invite') {
        _showInviteToast(n);
      } else {
        _showSocialToast(n);
      }
      break;
    }
  }

  /// Masa daveti: tam ekran duyuru (splash). Ses + titreşim + 30 sn süre.
  void _showInviteToast(Map<String, dynamic> n) {
    final data = _map(n['data']);
    final roomId = '${data['room_id'] ?? ''}';
    if (roomId.isEmpty) return;
    unawaited(GameAudio.sfx('reveal', enabled: _preferences.soundEnabled, volume: .9));
    if (_preferences.vibrationEnabled) {
      unawaited(HapticFeedback.heavyImpact());
      Future<void>.delayed(const Duration(milliseconds: 220), () => HapticFeedback.heavyImpact());
    }
    late OverlayEntry entry;
    void close() {
      if (_inviteEntry == entry) _inviteEntry = null;
      entry.remove();
    }
    final variant = '${data['variant'] ?? ''}';
    final details = data['room_name'] == null
        ? ''
        : '${data['room_name']} • ${okxRuleSummary(variant: variant.isEmpty ? 'non_fold' : variant, turbo: data['turbo'] == true, assisted: data['assisted'] != false)} • ${okxShort(_integer(data['entry_fee']))} giriş';
    entry = OverlayEntry(
      builder: (_) => _InviteSplash(
        from: '${data['from_name'] ?? ''}'.trim().isEmpty ? 'Bir arkadaşın' : '${data['from_name']}',
        avatarUrl: data['from_avatar'] == null ? null : '${data['from_avatar']}',
        details: details,
        onJoin: () {
          close();
          unawaited(_runBusy(() async {
            final session = await _api.joinRoom(roomId);
            _resumeSession = session;
            await _openTable(session);
          }));
        },
        onDecline: close,
        onTimeout: close,
      ),
    );
    _inviteEntry = entry;
    Overlay.of(context).insert(entry);
  }

  /// Arkadaşlık isteği / kabul: üstten kayan bildirim.
  void _showSocialToast(Map<String, dynamic> n) {
    final kind = '${n['kind']}';
    final data = _map(n['data']);
    final fromId = '${data['from_id'] ?? ''}';
    unawaited(GameAudio.sfx('chat', enabled: _preferences.soundEnabled, volume: .8));
    if (_preferences.vibrationEnabled) unawaited(HapticFeedback.mediumImpact());
    late OverlayEntry entry;
    void close() {
      if (_inviteEntry == entry) _inviteEntry = null;
      entry.remove();
    }
    entry = OverlayEntry(
      builder: (_) => _InviteToast(
        label: kind == 'friend_request' ? 'ARKADAŞLIK İSTEĞİ' : 'ARKADAŞ',
        icon: kind == 'friend_request' ? Icons.person_add_alt_1_rounded : Icons.handshake_rounded,
        title: '${n['message'] ?? n['title'] ?? ''}',
        acceptLabel: kind == 'friend_request' && fromId.isNotEmpty ? 'KABUL ET' : null,
        declineLabel: kind == 'friend_request' && fromId.isNotEmpty ? 'REDDET' : 'TAMAM',
        seconds: 12,
        onJoin: () {
          close();
          if (fromId.isNotEmpty) unawaited(_acceptFriend(fromId));
        },
        onDecline: () {
          close();
          if (kind == 'friend_request' && fromId.isNotEmpty) unawaited(_declineFriend(fromId));
        },
        onTimeout: close,
      ),
    );
    _inviteEntry = entry;
    Overlay.of(context).insert(entry);
  }

  Widget _referralPanel() => _panel(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 520;
            final info = Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.group_add_rounded, color: OkeyXColors.gold, size: 27),
              const SizedBox(width: 10),
              Flexible(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('DAVET / REFERRAL', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
                Text('Kodun: ${_referral['code'] ?? '-'} • ${_integer(_referral['referrals'])} davet', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 8, color: Colors.white54)),
              ])),
            ]);
            final button = OutlinedButton(onPressed: _redeemReferralDialog, child: const Text('KOD GİR'));
            if (narrow) {
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [info, const SizedBox(height: 8), button]);
            }
            return Row(children: [Expanded(child: info), const SizedBox(width: 10), button]);
          },
        ),
      );

  Widget _clubPanel() {
    final club = _map(_clubs['club']);
    final listing = _list(_clubs['clubs']).map(_map).toList();
    final tournament = _map(_clubs['tournament']);
    final tournamentRows = _list(tournament['rows']).map(_map).toList();
    if (club.isEmpty) {
      return _panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [const Expanded(child: Text('KULÜPLER', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13))), FilledButton.tonal(onPressed: _createClubDialog, child: const Text('KULÜP KUR'))]),
          const SizedBox(height: 7),
          if (listing.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Row(children: [Icon(Icons.shield_outlined, color: Colors.white38), SizedBox(width: 8), Expanded(child: Text('Henüz listelenecek kulüp yok. İlk kulübü sen kurabilir veya topluluğunu davet koduyla büyütebilirsin.', style: TextStyle(fontSize: 8.5, color: Colors.white54)))])),
          for (final c in listing.take(12))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [SizedBox(width: 28, child: Text('#${_integer(c['rank'])}', style: const TextStyle(fontSize: 8, color: OkeyXColors.gold, fontWeight: FontWeight.w900))), Expanded(child: Text('${c['name']} • ${_integer(c['members'])}/50', style: const TextStyle(fontSize: 9))), Text('${_integer(c['season_points'])} puan', style: const TextStyle(fontSize: 8, color: Colors.white54)), const SizedBox(width: 6), FilledButton.tonal(onPressed: () => _joinClub('${c['id']}'), child: const Text('KATIL', style: TextStyle(fontSize: 7)))]),
            ),
          if (tournamentRows.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('${tournament['title'] ?? 'Kulüpler Kupası'} • ${tournament['season_id'] ?? ''}', style: const TextStyle(fontSize: 8, color: Colors.white54, fontWeight: FontWeight.w800)),
          ],
        ]),
      );
    }
    final members = _list(club['member_profiles']).map(_map).toList();
    final tasks = _list(club['tasks']).map(_map).toList();
    final chat = _list(club['chat']).map(_map).toList();
    return _panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Expanded(child: Text('${club['name']}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14))), Text('${members.length}/50 üye', style: const TextStyle(fontSize: 8, color: Colors.white54)), const SizedBox(width: 6), TextButton(onPressed: _leaveClub, child: const Text('AYRIL'))]),
        const Text('Kulüp görevleri', style: TextStyle(fontSize: 9, color: OkeyXColors.gold, fontWeight: FontWeight.w900)),
        for (final t in tasks) Padding(padding: const EdgeInsets.only(top: 4), child: Text('${t['title']} • ${_integer(t['progress'])}/${_integer(t['target'])}${t['complete'] == true ? ' ✓' : ''}', style: const TextStyle(fontSize: 8))),
        const SizedBox(height: 8),
        const Text('Kulüp sohbeti', style: TextStyle(fontSize: 9, color: OkeyXColors.gold, fontWeight: FontWeight.w900)),
        for (final m in chat.reversed.take(8).toList().reversed) Text('${m['name']}: ${m['text']}', style: const TextStyle(fontSize: 8, color: Colors.white70)),
        const SizedBox(height: 5),
        Row(children: [Expanded(child: TextField(onSubmitted: _clubChat, decoration: const InputDecoration(hintText: 'Kulübe mesaj yaz…', isDense: true))), const SizedBox(width: 7), const Icon(Icons.send_rounded, color: Colors.white38)]),
        const SizedBox(height: 9),
        Row(children: [
          Expanded(child: Text('${tournament['title'] ?? 'KULÜPLER KUPASI'}', style: const TextStyle(fontSize: 9, color: OkeyXColors.gold, fontWeight: FontWeight.w900))),
          if (tournament['my_rank'] != null) Text('Sıra #${_integer(tournament['my_rank'])}', style: const TextStyle(fontSize: 7, color: Colors.white54)),
        ]),
        const SizedBox(height: 4),
        for (final row in tournamentRows.take(5))
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(children: [
              SizedBox(width: 28, child: Text('#${_integer(row['rank'])}', style: const TextStyle(fontSize: 7, color: OkeyXColors.gold, fontWeight: FontWeight.w900))),
              Expanded(child: Text('${row['name']}', style: const TextStyle(fontSize: 8))),
              Text('${_integer(row['season_points'])} puan', style: const TextStyle(fontSize: 7, color: Colors.white54)),
            ]),
          ),
      ]),
    );
  }

  Widget _clubPage(bool compact) => RefreshIndicator(
        onRefresh: _refreshAccountBits,
        child: ListView(
          padding: EdgeInsets.all(compact ? 11 : 18),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: const LinearGradient(colors: [Color(0xFF22165E), Color(0xFF312086)]),
                border: Border.all(color: const Color(0x556CE7D0)),
              ),
              child: Row(
                children: [
                  const CircleAvatar(radius: 24, backgroundColor: Color(0x3327E6AE), child: Icon(Icons.shield_rounded, color: OkeyXColors.mint, size: 28)),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('KULÜP MERKEZİ', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                        Text('Kulüp sohbeti, görevler ve sezonluk kulüp rekabeti.', style: TextStyle(fontSize: 8, color: Colors.white60)),
                      ],
                    ),
                  ),
                  Text('${_integer(_season['points'])} sezon puanı', style: const TextStyle(fontSize: 8, color: OkeyXColors.gold, fontWeight: FontWeight.w900)),
                ],
              ),
            ),
            const SizedBox(height: 10),
            _clubPanel(),
            const SizedBox(height: 10),
            _panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('DAVET & TOPLULUK', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 7),
                  Text('Davet kodun: ${_referral['code'] ?? '-'}', style: const TextStyle(fontSize: 9, color: OkeyXColors.gold, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text('${_friends.length} arkadaş • ${_recent.length} son oynanan oyuncu', style: const TextStyle(fontSize: 8, color: Colors.white60)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      FilledButton.tonal(onPressed: () => setState(() => _selected = 3), child: const Text('ARKADAŞLAR', style: TextStyle(fontSize: 8))),
                      const SizedBox(width: 7),
                      OutlinedButton(onPressed: _showReferral, child: const Text('DAVET KODU', style: TextStyle(fontSize: 8))),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _actionCard(IconData icon, String title, String detail, Color color, Future<void> Function() onTap, bool compact) => SizedBox(
        width: compact ? 185 : 235,
        child: Material(
          color: const Color(0xD9170E40),
          borderRadius: BorderRadius.circular(17),
          child: InkWell(
            onTap: _busy ? null : onTap,
            borderRadius: BorderRadius.circular(17),
            child: Padding(
              padding: const EdgeInsets.all(13),
              child: Row(children: [Container(width: 38, height: 38, decoration: BoxDecoration(color: color.withValues(alpha: .14), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: color, size: 20)), const SizedBox(width: 9), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 10)), Text(detail, style: const TextStyle(fontSize: 8, color: Colors.white54))]))]),
            ),
          ),
        ),
      );

  Widget _panel({required Widget child}) => OkxLeather(radius: 18, padding: const EdgeInsets.all(14), child: child);

  Widget _sectionTitle(String text) => Padding(padding: const EdgeInsets.only(bottom: 8), child: OkxLabel(text));

  Widget _statCard(String label, int value) => OkxLeather(width: 140, radius: 14, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [OkxLabel(label), const SizedBox(height: 5), Text(okxFormat(value), style: const TextStyle(fontFamily: OkeyXFonts.number, fontSize: 20, color: Color(0xFFFFE9B0)))]));

  List<Widget> _historyPreview() {
    final rows = _list(_account['history']).map(_map).toList();
    if (rows.isEmpty) return [const Text('Henüz maç geçmişi yok. İlk maçını oyna!', style: TextStyle(fontSize: 12, color: OkeyXColors.muted, fontWeight: FontWeight.w600))];
    return rows.take(5).map((m) {
      final won = m['won'] == true;
      final delta = _integer(m['chips_delta'], fallback: _integer(m['payout']));
      return Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: OkxLeather(
          radius: 14,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(children: [
            Icon(won ? Icons.emoji_events_rounded : Icons.sports_esports_rounded, size: 20, color: won ? OkeyXColors.gold : OkeyXColors.muted),
            const SizedBox(width: 10),
            Expanded(child: Text(won ? 'Galibiyet' : 'Maç tamamlandı', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: OkeyXColors.cream))),
            if (delta != 0) ...[
              Text('${delta > 0 ? '+' : ''}${okxShort(delta)}', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: delta > 0 ? OkeyXColors.mint : OkeyXColors.danger)),
              const SizedBox(width: 12),
            ],
            Text('${_integer(m['rounds'])} el', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: OkeyXColors.muted)),
          ]),
        ),
      );
    }).toList();
  }

  String get _modeSummary => '${_turbo ? '★ Turbo' : 'Standart'} • ${_variant == 'duz' ? 'Klasik Okey' : _variant == 'fold' ? 'Katlamalı' : 'Katlamasız'} • ${_teamMode == 'paired' ? 'Eşli' : 'Tek'} • ${_assisted ? 'Yardımlı' : 'Yardımsız'} • $_rounds El • ${_format(_entryFee)} altın';

  int _requiredBalance(int fee, bool turbo) => math.max(0, fee) * (turbo ? 10 : 1);

  Future<bool> _ensureBalance(int fee, bool turbo) async {
    final required = _requiredBalance(fee, turbo);
    if (_chips >= required) return true;
    await _showInsufficientFunds(required);
    return false;
  }

  Future<void> _showInsufficientFunds(int required) async {
    final missing = math.max(0, required - _chips);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF0F0A2C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: BorderSide(color: OkeyXColors.gold.withValues(alpha: .32))),
        title: const Row(children: [Icon(Icons.account_balance_wallet_rounded, color: OkeyXColors.gold), SizedBox(width: 8), Text('ALTIN GEREKİYOR')]),
        content: SizedBox(width: 430, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Bu oyun için en az ${_format(required)} altın gerekiyor.', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text('Bakiyen ${_format(_chips)} • ${_format(missing)} altın eksik.', style: const TextStyle(fontSize: 9, color: Colors.white60)),
          const SizedBox(height: 10),
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: OkeyXColors.gold.withValues(alpha: .07), borderRadius: BorderRadius.circular(13), border: Border.all(color: OkeyXColors.gold.withValues(alpha: .18))), child: const Row(children: [Icon(Icons.local_offer_rounded, color: OkeyXColors.gold, size: 18), SizedBox(width: 7), Expanded(child: Text('Günlük fırsatlar eksik bakiyeyi daha uygun paketlerle tamamlamana yardım eder.', style: TextStyle(fontSize: 8, color: Colors.white70)))])),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('VAZGEÇ')),
          FilledButton.icon(onPressed: () { Navigator.pop(dialogContext); setState(() => _selected = 6); }, icon: const Icon(Icons.storefront_rounded), label: const Text('PAKETLERE BAK')),
        ],
      ),
    );
  }

  void _openTutorial() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => TutorialScreen(onPractice: () => unawaited(_practicePlay())),
    ));
  }

  Future<void> _practicePlay() async {
    await _runBusy(() async {
      final session = await _api.practice(variant: _variant, assisted: _assisted);
      await _openTable(session);
    });
  }

  Future<void> _quickPlay() async {
    if (!await _ensureBalance(_entryFee, _turbo)) return;
    await _runBusy(() async {
        final session = await _api.quick(turbo: _turbo, variant: _variant, teamMode: _teamMode, entryFee: _entryFee, rounds: _rounds, assisted: _assisted);
        await _openTable(session);
      });
  }

  Future<void> _createRoomDialog() async {
    final name = TextEditingController(text: '${_profile.displayName} Masası');
    final password = TextEditingController();
    var turbo = _turbo;
    var variant = _variant;
    var teamMode = _teamMode;
    var assisted = _assisted;
    var rounds = _rounds;
    var entryFee = _entryFee;
    var turnSeconds = _turnSeconds;
    var usePassword = false;
    var advancedOpen = false;
    var setupStep = 0;
    try {
      final result = await showDialog<bool>(
        context: context,
        barrierColor: const Color(0x99000000),
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, localSet) {
            Widget seg<T>(List<(T, String)> options, T selected, ValueChanged<T> changed) => Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(color: const Color(0x66000000), borderRadius: BorderRadius.circular(12), border: Border.all(color: OkeyXColors.line)),
                  child: Row(children: [
                    for (final o in options)
                      Expanded(
                        child: GestureDetector(
                          onTap: () => localSet(() => changed(o.$1)),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            height: 34,
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(9),
                              gradient: selected == o.$1 ? const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFE36B), Color(0xFFFFA928)]) : null,
                              boxShadow: selected == o.$1 ? const [BoxShadow(color: Color(0xFF2C1C7D), offset: Offset(0, 2))] : null,
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                child: Text(o.$2, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: selected == o.$1 ? okxTextDark : OkeyXColors.muted)),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ]),
                );
            Widget toggle(String label, IconData icon, bool value, ValueChanged<bool> changed) => GestureDetector(
                  onTap: () => localSet(() => changed(!value)),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(color: const Color(0x40000000), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0x1FE8C478))),
                    child: Row(children: [
                      Icon(icon, size: 15, color: OkeyXColors.muted),
                      const SizedBox(width: 7),
                      Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: OkeyXColors.cream))),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        width: 40,
                        height: 22,
                        padding: const EdgeInsets.all(3),
                        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          gradient: value ? const LinearGradient(colors: [Color(0xFF1F8F5D), Color(0xFF3CCF8E)]) : null,
                          color: value ? null : const Color(0x1FFFFFFF),
                        ),
                        child: Container(width: 16, height: 16, decoration: BoxDecoration(shape: BoxShape.circle, color: value ? Colors.white : const Color(0xFFACA7DB))),
                      ),
                    ]),
                  ),
                );
            Widget label(String t) => Padding(padding: const EdgeInsets.only(bottom: 7, top: 2), child: OkxLabel(t));

            final requiredBalance = _requiredBalance(entryFee, turbo);
            final canAfford = _chips >= requiredBalance;
            final pool = (turbo ? entryFee * 10 : entryFee) * 4;
            final tableName = name.text.trim().isEmpty ? '${_profile.displayName} Masası' : name.text.trim();
            final modeText = '${okxRuleSummary(variant: variant, turbo: turbo, assisted: assisted).toUpperCase()} • ${okxShort(entryFee)} • $rounds EL';
            Widget seat(String title, String sub, {bool me = false}) => SizedBox(
                  width: 96,
                  height: 74,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: me ? null : const Color(0x8C090619),
                        border: Border.all(color: me ? const Color(0xFF7CF2B8) : const Color(0xB3E8C478), width: 2),
                        boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 8, offset: Offset(0, 3))],
                      ),
                      child: me
                          ? ClipOval(child: OkxAvatar(name: _profile.displayName, imageUrl: _profile.avatarUrl, size: 40))
                          : const Icon(Icons.add_rounded, color: Color(0xFFFFD98A), size: 20),
                    ),
                    const SizedBox(height: 4),
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: OkeyXColors.cream)),
                    Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w800, letterSpacing: .5, color: me ? OkeyXColors.mint : OkeyXColors.muted)),
                  ]),
                );
            return Dialog.fullscreen(
              backgroundColor: OkeyXColors.ink,
              child: OkxRoom(
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Expanded(
                        flex: 46,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            GestureDetector(
                              onTap: () => setupStep == 1 ? localSet(() => setupStep = 0) : Navigator.pop(dialogContext, false),
                              child: Container(width: 40, height: 40, decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF0F0A28), border: Border.all(color: OkeyXColors.line)), child: const Icon(Icons.arrow_back_rounded, size: 19, color: Color(0xFFFFE9B0))),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              OkxTitle('Masa kur', size: 24),
                              SizedBox(height: 3),
                              Text('Masaya girince koltuklara dokunup davet et ya da bot ekle', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: OkeyXColors.muted, fontWeight: FontWeight.w600)),
                            ])),
                          ]),
                          const SizedBox(height: 10),
                          Expanded(
                            child: LayoutBuilder(builder: (context, c) {
                              // Koltuklar masanın DIŞINDA durur; masa adı ve kurallar hiçbir şeyle çakışmaz.
                              const seatW = 96.0, seatH = 74.0, gap = 6.0;
                              final w = math.max(120.0, math.min(math.min(c.maxWidth - 2 * (seatW + gap), 380.0), (c.maxHeight - 2 * (seatH + gap)) / .58));
                              final h = w * .58;
                              final cx = c.maxWidth / 2, cy = c.maxHeight / 2;
                              return Stack(children: [
                                Positioned(
                                  left: cx - w / 2,
                                  top: cy - h / 2,
                                  width: w,
                                  height: h,
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: walnutDecoration(radius: BorderRadius.circular(h / 2)),
                                    child: OkxFelt(
                                      borderRadius: BorderRadius.circular(h / 2),
                                      child: Center(
                                        child: Padding(
                                          padding: EdgeInsets.symmetric(horizontal: w * .14),
                                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                                            FittedBox(fit: BoxFit.scaleDown, child: OkxTitle(tableName, size: 18)),
                                            const SizedBox(height: 4),
                                            FittedBox(fit: BoxFit.scaleDown, child: Text(modeText, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: .6, color: Color(0xFFCFE8D8)))),
                                            if (turbo) const Padding(padding: EdgeInsets.only(top: 6), child: FittedBox(fit: BoxFit.scaleDown, child: OkxChip(label: 'TURBO • GİRİŞ ×10', icon: Icons.bolt_rounded, selected: true))),
                                          ]),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(left: cx - seatW / 2, top: cy - h / 2 - seatH - gap, child: seat('Boş koltuk', 'DAVET / BOT')),
                                Positioned(left: cx - w / 2 - seatW - gap, top: cy - seatH / 2, child: seat('Boş koltuk', 'DAVET / BOT')),
                                Positioned(left: cx + w / 2 + gap, top: cy - seatH / 2, child: seat('Boş koltuk', 'DAVET / BOT')),
                                Positioned(left: cx - seatW / 2, top: cy + h / 2 + gap, child: seat(_profile.displayName, 'MASA SAHİBİ', me: true)),
                              ]);
                            }),
                          ),
                          const Text('Davet edilen arkadaşına bildirim gider. Boş koltuklar istersen botla dolar.', style: TextStyle(fontSize: 10.5, color: OkeyXColors.muted, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 54,
                        child: OkxLeather(
                          radius: 24,
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            Expanded(
                              child: SingleChildScrollView(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                                  if (setupStep == 0) ...[
                                  label('OYUN TÜRÜ'),
                                  Row(children: [
                                    for (final option in [('non_fold', '101 OKEY', 'Seri ve çift açmalı'), ('duz', 'KLASİK OKEY', '14 taşı diz, son taşla bitir')])
                                      Expanded(child: Padding(padding: const EdgeInsets.only(right: 6), child: GestureDetector(
                                        onTap: () => localSet(() { if (option.$1 == 'duz') { variant = 'duz'; turbo = false; } else if (variant == 'duz') { variant = 'non_fold'; } }),
                                        child: AnimatedContainer(duration: const Duration(milliseconds: 180), padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10), decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(14),
                                          gradient: (option.$1 == 'duz' ? variant == 'duz' : variant != 'duz') ? const LinearGradient(colors: [Color(0xFF285D49), Color(0xFF123B2D)]) : null,
                                          color: (option.$1 == 'duz' ? variant == 'duz' : variant != 'duz') ? null : const Color(0x44000000),
                                          border: Border.all(color: (option.$1 == 'duz' ? variant == 'duz' : variant != 'duz') ? OkeyXColors.mint : OkeyXColors.line),
                                        ), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(option.$2, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: OkeyXColors.cream)), const SizedBox(height: 3), Text(option.$3, style: const TextStyle(fontSize: 9, color: OkeyXColors.muted))])),
                                      ))),
                                  ]),
                                  const SizedBox(height: 10),
                                  const Text('Oyun türünü seçtikten sonra masa kurallarını ve giriş ayarlarını belirleyeceksin.', style: TextStyle(fontSize: 10, color: OkeyXColors.muted, fontWeight: FontWeight.w600)),
                                  ] else ...[
                                  // İki sütun: solda kurallar, sağda giriş/el/hamle. Kaydırmadan sığar.
                                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                                      label(variant == 'duz' ? 'KLASİK OKEY KURALLARI' : '101 OKEY KURALLARI'),
                                      OkxRuleSwitches(
                                        height: 36,
                                        gap: 6,
                                        vertical: true,
                                        variant: variant,
                                        turbo: turbo,
                                        assisted: assisted,
                                        onVariant: (v) => localSet(() => variant = v),
                                        onTurbo: (v) => localSet(() => turbo = v),
                                        onAssisted: (v) => localSet(() => assisted = v),
                                      ),
                                      const SizedBox(height: 8),
                                      label('OYUNCULAR'),
                                      OkxPairSwitch(
                                        left: 'Tekli',
                                        right: 'Eşli',
                                        rightIcon: Icons.groups_2_rounded,
                                        height: 36,
                                        rightSelected: teamMode == 'paired',
                                        onChanged: (r) => localSet(() => teamMode = r ? 'paired' : 'solo'),
                                      ),
                                    ])),
                                    const SizedBox(width: 14),
                                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                                      label('GİRİŞ'),
                                      seg<int>(const [(1000, '1K'), (5000, '5K'), (10000, '10K'), (25000, '25K'), (100000, '100K')], entryFee, (v) => entryFee = v),
                                      const SizedBox(height: 6),
                                      label('EL SAYISI'),
                                      seg<int>(const [(1, '1 El'), (2, '2 El'), (3, '3 El')], rounds, (v) => rounds = v),
                                      const SizedBox(height: 6),
                                      label('HAMLE SÜRESİ'),
                                      seg<int>(const [(20, '20 sn'), (35, '35 sn'), (45, '45 sn')], turnSeconds, (v) => turnSeconds = v),
                                    ])),
                                  ]),
                                  const SizedBox(height: 8),
                                  GestureDetector(onTap: () => localSet(() => advancedOpen = !advancedOpen), child: Row(children: [Icon(advancedOpen ? Icons.expand_less_rounded : Icons.tune_rounded, size: 16, color: OkeyXColors.gold), const SizedBox(width: 6), const Text('GELİŞMİŞ AYARLAR', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: .8, color: OkeyXColors.gold)), const Spacer(), Text(advancedOpen ? 'GİZLE' : 'MASA ADI • ŞİFRE', style: const TextStyle(fontSize: 9, color: OkeyXColors.muted))])),
                                  if (advancedOpen) ...[
                                    const SizedBox(height: 8),
                                    label('Masa adı'),
                                    TextField(controller: name, maxLength: 24, onChanged: (_) => localSet(() {}), decoration: const InputDecoration(counterText: '', isDense: true, prefixIcon: Icon(Icons.edit_rounded, size: 17))),
                                    const SizedBox(height: 8),
                                    toggle('Şifreli masa', Icons.lock_rounded, usePassword, (v) => usePassword = v),
                                    if (usePassword) ...[
                                      const SizedBox(height: 8),
                                      TextField(controller: password, obscureText: true, maxLength: 24, decoration: const InputDecoration(labelText: 'Masa şifresi', counterText: '', isDense: true, prefixIcon: Icon(Icons.key_rounded, size: 17))),
                                    ],
                                  ],
                                  ],
                                ]),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(children: [
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                                  Text(canAfford ? 'ÖDÜL HAVUZU' : 'BAKİYE YETERSİZ', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.4, color: canAfford ? OkeyXColors.muted : OkeyXColors.danger)),
                                  const SizedBox(height: 3),
                                  Row(children: [
                                    const OkxCoin(size: 18),
                                    const SizedBox(width: 6),
                                    Text(canAfford ? okxFormat(pool) : '${okxFormat(requiredBalance - _chips)} eksik', style: TextStyle(fontFamily: OkeyXFonts.number, fontSize: 17, color: canAfford ? const Color(0xFFFFD98A) : OkeyXColors.danger)),
                                  ]),
                                ]),
                              ),
                              OkxButton.ghost(label: setupStep == 1 ? 'GERİ' : 'VAZGEÇ', height: 46, onTap: () => setupStep == 1 ? localSet(() => setupStep = 0) : Navigator.pop(dialogContext, false)),
                              const SizedBox(width: 10),
                              OkxButton(label: setupStep == 0 ? 'DEVAM ET' : 'MASAYI KUR', icon: Icons.play_arrow_rounded, height: 46, fontSize: 15, padding: const EdgeInsets.symmetric(horizontal: 22), onTap: () => setupStep == 0 ? localSet(() => setupStep = 1) : Navigator.pop(dialogContext, true)),
                            ]),
                          ]),
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
            );
          },
        ),
      );
      if (result != true) return;
      if (!await _ensureBalance(entryFee, turbo)) return;
      setState(() {
        _turbo = turbo;
        _variant = variant;
        _teamMode = teamMode;
        _assisted = assisted;
        _rounds = rounds;
        _entryFee = entryFee;
        _turnSeconds = turnSeconds;
      });
      await _runBusy(() async {
        final session = await _api.createRoom(name: name.text, turbo: turbo, variant: variant, teamMode: teamMode, entryFee: entryFee, rounds: rounds, assisted: assisted, turnSeconds: turnSeconds, password: usePassword ? password.text : '');
        _resumeSession = session;
        await _showRoomLaunchSplash(name.text.trim().isEmpty ? '${_profile.displayName} Masası' : name.text.trim(), turbo: turbo);
        await _openTable(session);
      });
    } finally {
      name.dispose();
      password.dispose();
    }
  }

  Future<void> _showRoomLaunchSplash(String roomName, {required bool turbo}) async {
    if (!mounted) return;
    final navigator = Navigator.of(context, rootNavigator: true);
    unawaited(showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0xCC000000),
      transitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (_, __, ___) => Material(
        color: Colors.transparent,
        child: Center(
          child: Container(
            width: 360,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xF21B124A), Color(0xF20E0928)]), borderRadius: BorderRadius.circular(24), border: Border.all(color: (turbo ? OkeyXColors.gold : OkeyXColors.mint).withValues(alpha: .38)), boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 30)]),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TweenAnimationBuilder<double>(tween: Tween(begin: .78, end: 1), duration: const Duration(milliseconds: 420), curve: Curves.easeOutBack, builder: (_, v, child) => Transform.scale(scale: v, child: child), child: Container(width: 64, height: 64, decoration: BoxDecoration(shape: BoxShape.circle, color: (turbo ? OkeyXColors.gold : OkeyXColors.mint).withValues(alpha: .10), border: Border.all(color: (turbo ? OkeyXColors.gold : OkeyXColors.mint).withValues(alpha: .35))), child: Icon(turbo ? Icons.bolt_rounded : Icons.table_bar_rounded, size: 31, color: turbo ? OkeyXColors.gold : OkeyXColors.mint))),
              const SizedBox(height: 9),
              Text(roomName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
              const SizedBox(height: 3),
              Text(turbo ? 'Turbo masa hazırlanıyor…' : 'Masa hazırlanıyor…', style: const TextStyle(fontSize: 7, color: Colors.white54)),
              const SizedBox(height: 10),
              ClipRRect(borderRadius: BorderRadius.circular(99), child: const LinearProgressIndicator(minHeight: 5)),
            ]),
          ),
        ),
      ),
    ));
    await Future<void>.delayed(const Duration(milliseconds: 720));
    if (mounted && navigator.canPop()) navigator.pop();
  }

  Future<void> _joinRoom(Map<String, dynamic> room) async {
    final fee = _integer(room['entry_fee']);
    final turbo = room['turbo'] == true;
    if (!await _ensureBalance(fee, turbo)) return;
    if (!mounted) return;
    String? password;
    if (room['locked'] == true) {
      final controller = TextEditingController();
      try {
        password = await showDialog<String>(
          context: context,
          builder: (dialogContext) => AlertDialog(title: const Text('Şifreli Masa'), content: TextField(controller: controller, obscureText: true, decoration: const InputDecoration(labelText: 'Masa şifresi')), actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('VAZGEÇ')), FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text), child: const Text('GİR'))]),
        );
      } finally {
        controller.dispose();
      }
      if (password == null) return;
    }
    await _runBusy(() async {
      final session = await _api.joinRoom('${room['room_id']}', password: password);
      _resumeSession = session;
      await _openTable(session);
    });
  }

  Future<void> _openTable(GameSession? session) async {
    if (session == null) return;
    Telemetry.track('live_table_opened');
    await GameAudio.stopLobby();
    if (!mounted) return;
    final tableResult = await Navigator.of(context).push<String>(MaterialPageRoute<String>(builder: (_) => TableScreen(profile: _profile, preferences: _preferences, initialSession: session, onClose: () async {}, onPreferencesChanged: (next) { if (mounted) setState(() => _preferences = next); unawaited(widget.repository.savePreferences(next)); widget.onBundleChanged(PlayerBundle(_profile, next)); })));
    if (mounted) {
      if (tableResult == 'store') setState(() => _selected = 6);
      unawaited(GameAudio.startLobby(enabled: _preferences.musicEnabled));
    }
    try {
      final adGate = await _api.matchTransitionAd();
      if (adGate['show_interstitial'] == true) {
        await _interstitialAds.showInterstitial();
      }
    } catch (_) {}
    await _refreshAccountBits();
    await _refreshRooms();
    try {
      _resumeSession = await _api.reconnect();
    } catch (_) {
      _resumeSession = null;
    }
    if (mounted) setState(() {});
  }

  Future<void> _claimDaily() => _runBusy(() async {
        final out = await _api.daily();
        if (out['ok'] == true) {
          final accountState = _map(out['account']);
          final chips = _integer(accountState['chips'], fallback: _chips);
          final streak = _integer(out['streak'], fallback: 1);
          if (mounted) {
            setState(() => _account = {
              ..._account,
              ...accountState,
              'chips': chips,
              'daily': {..._map(accountState['daily']), 'last_claim_day': _todayKey, 'streak': streak},
            });
          }
          _flash('Günlük ödül alındı • +${_format(_integer(out['reward']))} altın');
          await _showRewardBurst('GÜNLÜK ÖDÜL', _integer(out['reward']), Icons.calendar_month_rounded);
        } else {
          _flash('${out['code']}' == 'already_claimed' ? 'Bugünkü ödül zaten alındı.' : 'Günlük ödül şu anda alınamıyor.');
          final accountState = _map(out['account']);
          if (mounted && accountState.isNotEmpty) setState(() => _account = {..._account, ...accountState});
        }
        unawaited(_refreshAccountBits());
      });

  Future<void> _spinWheel() => _runBusy(() async {
        final out = await _api.spinWheel();
        if (out['ok'] == true) {
          final reward = _integer(out['reward']);
          final chips = _integer(out['chips'], fallback: _chips);
          if (mounted) {
            setState(() => _account = {
              ..._account,
              'chips': chips,
              'wheel': {..._map(_account['wheel']), ..._map(out['wheel']), 'last_spin_day': _todayKey},
            });
          }
          await _showWheelSpin(reward, segments: _list(out['segments']).map((x) => _integer(_map(x)['reward'])).toList());
          await _showRewardBurst('ÇARK ÖDÜLÜ', reward, Icons.casino_rounded);
        } else {
          final code='${out['code'] ?? ''}';
          _flash(code=='already_spun' ? 'Bugünkü çark hakkını kullandın.' : 'Çark şu anda kullanılamıyor.');
        }
        unawaited(_refreshAccountBits());
      });

  Future<void> _openChest() => _runBusy(() async {
        final out = await _api.openChest();
        if (out['ok'] == true) {
          final reward = _integer(out['reward']);
          final chips = _integer(out['chips'], fallback: _chips);
          if (mounted) {
            setState(() => _account = {
              ..._account,
              'chips': chips,
              'chests': {..._map(_account['chests']), ..._map(out['chests']), if (out['free'] == true) 'last_free_day': _todayKey},
            });
          }
          await _showChestOpen(reward);
          await _showRewardBurst('ŞANS SANDIĞI', reward, Icons.inventory_2_rounded);
        } else {
          final code='${out['code'] ?? ''}';
          _flash(code=='no_chest_key' ? 'Bugünkü ücretsiz sandık kullanıldı ve anahtarın kalmadı.' : code=='daily_chest_limit' ? 'Bugünkü sandık hakkın doldu, yarın yenilenir.' : 'Sandık şu anda açılamıyor.');
        }
        unawaited(_refreshAccountBits());
      });

  Future<void> _claimMission(String id) => _runBusy(() async {
        final out = await _api.claimMission(id);
        if (out['ok'] == true) {
          await _showRewardBurst('GÖREV TAMAMLANDI', _integer(out['reward_chips']), Icons.task_alt_rounded);
        } else {
          _flash('Görev henüz hazır değil.');
        }
        await _refreshAccountBits();
      });

  Future<void> _claimSeason(String id) => _runBusy(() async {
        final out = await _api.claimSeason(id);
        if (out['ok'] == true) {
          await _showRewardBurst('SEZON ÖDÜLÜ', _integer(out['reward']), Icons.emoji_events_rounded);
        } else {
          _flash('Ödül alınamadı.');
        }
        await _refreshAccountBits();
      });

  Future<void> _showWheelSpin(int reward, {List<int> segments = const []}) async {
    if (!mounted) return;
    unawaited(GameAudio.sfx('wheel_spin', enabled: _preferences.soundEnabled, volume: .78));
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0xE6070420),
      builder: (_) => PrizeWheelDialog(reward: reward, segments: segments, sound: _preferences.soundEnabled, reducedMotion: _preferences.reducedMotionEnabled || _preferences.dataSaverEnabled),
    );
  }

  Future<void> _showChestOpen(int reward) async {
    if (!mounted) return;
    unawaited(GameAudio.sfx('chest_open', enabled: _preferences.soundEnabled, volume: .82));
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0xE6070420),
      builder: (_) => ChestOpenDialog(reward: reward, sound: _preferences.soundEnabled, reducedMotion: _preferences.reducedMotionEnabled || _preferences.dataSaverEnabled),
    );
  }

  StreamSubscription<Map<String, dynamic>>? _pushTapSub;
  StreamSubscription<Map<String, dynamic>>? _pushInSub;

  /// Push token'ını sunucuya kaydeder; bildirime dokunulunca ilgili sekmeyi açar.
  Future<void> _setupPush() async {
    if (!PushService.configured) return;
    final token = await PushService.token();
    if (token != null && token.isNotEmpty) {
      try {
        await _api.registerPush(token);
        // Arka plan yoklayıcısı, anlık bildirimle gelenleri ikinci kez göstermesin.
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('okx_push_ok', true);
        } catch (_) {}
      } catch (_) {}
    }
    _pushTapSub ??= PushService.taps.listen((data) {
      if (!mounted) return;
      unawaited(_refreshAccountBits());
      unawaited(_pollAlerts());
    });
    // Uygulama açıkken gelen anlık bildirim: daveti 3 sn yoklamayı beklemeden göster.
    _pushInSub ??= PushService.incoming.listen((_) {
      if (mounted) unawaited(_pollAlerts());
    });
  }

  int _seenLevel = 0;

  /// Seviye atlama kutlaması (maç sonrası hesap yenilenince tetiklenir).
  Future<void> _showLevelUp(int level) async {
    if (!mounted) return;
    unawaited(GameAudio.sfx('reward', enabled: _preferences.soundEnabled, volume: .9));
    if (_preferences.vibrationEnabled) unawaited(HapticFeedback.heavyImpact());
    final calm = _preferences.reducedMotionEnabled || _preferences.dataSaverEnabled;
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Kapat',
      barrierColor: Colors.black54,
      transitionDuration: calm ? Duration.zero : const Duration(milliseconds: 380),
      transitionBuilder: (context, animation, _, child) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(scale: CurvedAnimation(parent: animation, curve: Curves.elasticOut), child: child),
      ),
      pageBuilder: (dialogContext, _, __) => SafeArea(
        child: Center(
          child: GestureDetector(
            onTap: () => Navigator.pop(dialogContext),
            child: Container(
              width: 270,
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                gradient: const LinearGradient(colors: [Color(0xFF291B6E), Color(0xFF130C35)]),
                border: Border.all(color: OkeyXColors.gold, width: 1.8),
                boxShadow: const [BoxShadow(color: Color(0x99F4C542), blurRadius: 34, spreadRadius: 1)],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.workspace_premium_rounded, size: 54, color: OkeyXColors.gold),
                const SizedBox(height: 6),
                const Text('SEVİYE ATLADIN!', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1, color: Colors.white, decoration: TextDecoration.none)),
                const SizedBox(height: 4),
                Text('LV $level', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: OkeyXColors.gold, decoration: TextDecoration.none)),
                const SizedBox(height: 4),
                const Text('Devam etmek için dokun', style: TextStyle(fontSize: 9, color: Colors.white54, decoration: TextDecoration.none)),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showRewardBurst(String title, int reward, IconData icon) async {
    if (!mounted) return;
    unawaited(GameAudio.sfx('coin_shower', enabled: _preferences.soundEnabled, volume: .88));
    Future<void>.delayed(const Duration(milliseconds: 110), () => unawaited(GameAudio.sfx('reward', enabled: _preferences.soundEnabled, volume: .82)));
    if (_preferences.vibrationEnabled) unawaited(HapticFeedback.mediumImpact());
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Ödülü kapat',
      barrierColor: Colors.black54,
      transitionDuration: (_preferences.reducedMotionEnabled || _preferences.dataSaverEnabled) ? Duration.zero : const Duration(milliseconds: 320),
      transitionBuilder: (context, animation, _, child) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(scale: CurvedAnimation(parent: animation, curve: Curves.elasticOut), child: child),
      ),
      pageBuilder: (dialogContext, _, __) => SafeArea(
        minimum: const EdgeInsets.all(8),
        child: Center(
          child: GestureDetector(
            onTap: () => Navigator.pop(dialogContext),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 285, maxHeight: 330),
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: Container(
            width: 285,
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              gradient: const LinearGradient(colors: [Color(0xFF291B6E), Color(0xFF140D3A)]),
              border: Border.all(color: OkeyXColors.gold, width: 1.6),
              boxShadow: const [BoxShadow(color: Color(0x99F4C542), blurRadius: 34, spreadRadius: 1)],
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Stack(clipBehavior:Clip.none,alignment: Alignment.center, children: [
                const SizedBox(width: 100, height: 82),
                if(!(_preferences.reducedMotionEnabled||_preferences.dataSaverEnabled))
                  for(var i=0;i<9;i++)
                    TweenAnimationBuilder<double>(
                      key:ValueKey('reward-coin-$i-$reward'),
                      tween:Tween(begin:0,end:1),
                      duration:Duration(milliseconds:700+(i%4)*120),
                      curve:Curves.easeIn,
                      builder:(context,v,child)=>Transform.translate(offset:Offset((i-4)*15.0,(-58+(116*v))+math.sin(v*math.pi*2+i)*7),child:Transform.rotate(angle:v*math.pi*3,child:Opacity(opacity:(1-v*.65).clamp(0,1),child:child))),
                      child:const Icon(Icons.monetization_on_rounded,size:15,color:OkeyXColors.gold),
                    ),
                Positioned.fill(child: Icon(Icons.auto_awesome_rounded, size: 82, color: OkeyXColors.gold.withValues(alpha: .20))),
                CircleAvatar(radius: 30, backgroundColor: OkeyXColors.gold.withValues(alpha: .16), child: Icon(icon, size: 36, color: OkeyXColors.gold)),
              ]),
              Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, decoration: TextDecoration.none, color: Colors.white)),
              const SizedBox(height: 5),
              Text('+${_format(reward)} ALTIN', style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900, decoration: TextDecoration.none, color: OkeyXColors.gold)),
              const SizedBox(height: 7),
              const Text('ÖDÜL HESABINA EKLENDİ', style: TextStyle(fontSize: 7.5, fontWeight: FontWeight.w800, decoration: TextDecoration.none, color: Colors.white54)),
            ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _switchLeague(String scope) async {
    setState(() => _leagueScope = scope);
    try { final board = await _api.leaderboard(scope); if (mounted) setState(() => _leaderboard = board); } catch (_) {}
  }

  Future<void> _changeCity() async {
    final controller = TextEditingController(text: '${_map(_account['league'])['city'] ?? 'Denizli'}');
    try {
      final city = await showDialog<String>(context: context, builder: (dialogContext) => AlertDialog(title: const Text('Şehir Ligi'), content: TextField(controller: controller, maxLength: 40, decoration: const InputDecoration(labelText: 'Şehrin')), actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('VAZGEÇ')), FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('KAYDET'))]));
      if (city == null || city.isEmpty) return;
      await _api.setCity(city); await _refreshAccountBits(); await _switchLeague('city');
    } finally { controller.dispose(); }
  }

  Future<void> _searchPlayers(String query) async {
    if (query.trim().isEmpty) return;
    try { final rows = await _api.searchPlayers(query.trim()); if (mounted) setState(() => _searchResults = rows); } catch (e) { _flash(_friendly(e)); }
  }

  int _parseCoinTransferAmount(String raw) {
    var text=raw.trim().toLowerCase().replaceAll(' ', '').replaceAll('.', '');
    if(text.isEmpty)return 0;
    var multiplier=1;
    if(text.endsWith('k')){multiplier=1000;text=text.substring(0,text.length-1);}
    else if(text.endsWith('m')){multiplier=1000000;text=text.substring(0,text.length-1);}
    else if(text.endsWith('b')){multiplier=1000000000;text=text.substring(0,text.length-1);}
    final value=double.tryParse(text.replaceAll(',', '.'));
    if(value==null||value<=0)return 0;
    return (value*multiplier).round();
  }

  Future<void> _showCoinTransfer(Map<String,dynamic> friend) async {
    if(_busy)return;
    final targetId='${friend['id']??''}'.trim();
    if(targetId.isEmpty)return;
    final name='${friend['name']??'Arkadaş'}';
    final controller=TextEditingController(text:'100K');
    var selected=100000;
    final amount=await showDialog<int>(context:context,builder:(dialogContext)=>StatefulBuilder(builder:(dialogContext,setLocal){
      final parsed=_parseCoinTransferAmount(controller.text);
      final enough=parsed>=1000 && parsed<=2000000 && parsed<=_chips;
      return AlertDialog(
        title:Row(children:[const Icon(Icons.paid_rounded,color:OkeyXColors.gold),const SizedBox(width:7),Expanded(child:Text('$name • Altın Gönder',maxLines:1,overflow:TextOverflow.ellipsis))]),
        content:SizedBox(width:430,child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text('Bakiyen ${_format(_chips)} altın • Günlük arkadaş transferi sunucuda korunur.',style:const TextStyle(fontSize:8,color:Colors.white54)),
          const SizedBox(height:10),
          Wrap(spacing:6,runSpacing:6,children:[for(final q in const [10000,50000,100000,500000,1000000,2000000]) ChoiceChip(label:Text(_format(q)),selected:selected==q,onSelected:(_){selected=q;controller.text=q>=1000000?'${q~/1000000}M':'${q~/1000}K';setLocal((){});})]),
          const SizedBox(height:10),
          TextField(controller:controller,keyboardType:TextInputType.text,onChanged:(_)=>setLocal((){selected=0;}),decoration:const InputDecoration(labelText:'Miktar',hintText:'100K • 1M • 2000000',prefixIcon:Icon(Icons.monetization_on_rounded))),
          const SizedBox(height:7),
          Text(parsed<1000?'Minimum 1.000 altın.':parsed>2000000?'Tek seferde en fazla 2M.':parsed>_chips?'Bakiyen yetersiz.':'Gönderilecek: ${_format(parsed)} altın',style:TextStyle(fontSize:8,fontWeight:FontWeight.w800,color:enough?OkeyXColors.mint:OkeyXColors.danger)),
        ])),
        actions:[TextButton(onPressed:()=>Navigator.pop(dialogContext),child:const Text('VAZGEÇ')),FilledButton.icon(onPressed:enough?()=>Navigator.pop(dialogContext,parsed):null,icon:const Icon(Icons.send_rounded,size:16),label:const Text('GÖNDER'))],
      );
    }));
    controller.dispose();
    if(amount==null||amount<=0||!mounted)return;
    await _runBusy(() async {
      final out=await _api.transferCoins(targetId,amount);
      if(out['ok']==true){
        _applyWalletImmediate({'coins':_integer(out['sender_chips'],fallback:_chips),'diamonds':_integer(_account['diamonds'])});
        if(_preferences.vibrationEnabled)unawaited(HapticFeedback.mediumImpact());
        unawaited(GameAudio.sfx('reward',enabled:_preferences.soundEnabled,volume:.55));
        _flash('$name kullanıcısına ${_format(amount)} altın gönderildi.');
      }else{
        final code='${out['code']??'transfer_failed'}';
        final message=switch(code){
          'friends_only'=>'Altın yalnızca arkadaşlara gönderilebilir.',
          'insufficient_balance'=>'Bakiyen yetersiz.',
          'transfer_minimum'=>'Minimum 1.000 altın gönderebilirsin.',
          'transfer_too_large'=>'Tek seferde en fazla 2M gönderebilirsin.',
          'transfer_daily_limit'=>'Bugünkü arkadaş transfer hakkın doldu.',
          _=>'Altın gönderilemedi • $code',
        };
        _flash(message);
      }
      await _refreshAccountBits();
    });
  }

  Future<void> _friendRequest(String id) => _runBusy(() async {final out=await _api.friendRequest(id);final code='${out['code'] ?? ''}';_flash(out['ok']==true?(code=='accepted'?'Arkadaşlık karşılıklı kabul edildi.':code=='already_pending'?'İstek zaten bekliyor.':'Arkadaşlık isteği gönderildi.'):_friendly(code));await _refreshAccountBits();});
  Future<void> _acceptFriend(String id) => _runBusy(() async {await _api.acceptFriend(id); await _refreshAccountBits();});
  Future<void> _declineFriend(String id) => _runBusy(() async {await _api.declineFriend(id); await _refreshAccountBits();});
  Future<void> _cancelFriendRequest(String id) => _runBusy(() async {await _api.cancelFriendRequest(id); await _refreshAccountBits();});
  Future<void> _removeFriend(String id) => _runBusy(() async {await _api.removeFriend(id); await _refreshAccountBits();});
  Future<void> _joinFriendRoom(Map<String,dynamic> p) => _runBusy(() async {final room='${p['room_id']??''}';if(room.isEmpty){_flash('Masa bilgisi bulunamadı.');return;}final session=await _api.joinRoom(room);_resumeSession=session;await _openTable(session);});
  Future<void> _inviteFriend(String id) => _runBusy(() async {final room = _resumeSession?.roomId; if (room == null) { _flash('Önce bir masa oluştur veya masaya dön.'); return; } final out = await _api.inviteFriend(id, room); _flash(out['ok'] == true ? 'Masa daveti gönderildi.' : 'Davet gönderilemedi.');});

  Future<void> _socialSafety(String id, String action) async {
    if (action == 'mute') { await _api.setMute(id, true); _flash('Oyuncu susturuldu.'); }
    if (action == 'block') { await _api.setBlock(id, true); _flash('Oyuncu engellendi.'); }
    if (action == 'report') {
      final reason = await _reportReasonDialog();
      if (reason != null) { await _api.report(id, reason, roomId: _resumeSession?.roomId); _flash('Şikâyet gönderildi.'); }
    }
  }

  Future<String?> _reportReasonDialog() => showDialog<String>(context: context, builder: (dialogContext) => SimpleDialog(title: const Text('Şikâyet nedeni'), children: [for (final reason in const ['Hakaret / taciz', 'Spam', 'Hile şüphesi', 'Uygunsuz isim', 'Diğer']) SimpleDialogOption(onPressed: () => Navigator.pop(dialogContext, reason), child: Text(reason))]));

  Future<void> _redeemReferralDialog() async {
    final controller = TextEditingController();
    try {
      final code = await showDialog<String>(context: context, builder: (dialogContext) => AlertDialog(title: const Text('Davet kodu'), content: TextField(controller: controller, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'OKX...')), actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('VAZGEÇ')), FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('KULLAN'))]));
      if (code == null || code.isEmpty) return;
      final out = await _api.redeemReferral(code);
      _flash(out['ok'] == true ? 'Davet ödülü +5.000 altın!' : 'Kod kullanılamadı: ${out['code']}');
      await _refreshAccountBits();
    } finally { controller.dispose(); }
  }

  Future<void> _showReferral() async {
    final code = '${_referral['code'] ?? '-'}';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Davet Kodun'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Arkadaşın bu kodu kullandığında ikiniz de davet ödülü kazanırsınız.', style: TextStyle(fontSize: 10, color: Colors.white60)),
            const SizedBox(height: 12),
            SelectableText(code, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: OkeyXColors.gold)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('KAPAT')),
          FilledButton(onPressed: () { Navigator.pop(dialogContext); unawaited(_redeemReferralDialog()); }, child: const Text('KOD GİR')),
        ],
      ),
    );
  }

  Future<void> _createClubDialog() async {
    final controller = TextEditingController();
    try {
      final name = await showDialog<String>(context: context, builder: (dialogContext) => AlertDialog(title: const Text('Kulüp Kur'), content: TextField(controller: controller, maxLength: 28, decoration: const InputDecoration(labelText: 'Kulüp adı')), actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('VAZGEÇ')), FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('KUR'))]));
      if (name == null || name.length < 3) return;
      final out = await _api.createClub(name); _flash(out['ok'] == true ? 'Kulüp kuruldu.' : 'Kulüp kurulamadı: ${out['code']}'); await _refreshAccountBits();
    } finally { controller.dispose(); }
  }
  Future<void> _joinClub(String id) => _runBusy(() async {final out = await _api.joinClub(id); _flash(out['ok'] == true ? 'Kulübe katıldın.' : 'Katılamadın: ${out['code']}'); await _refreshAccountBits();});
  Future<void> _leaveClub() => _runBusy(() async {await _api.leaveClub(); await _refreshAccountBits();});
  Future<void> _clubChat(String text) async {if (text.trim().isEmpty) return; await _api.clubChat(text.trim()); await _refreshAccountBits();}

  Future<void> _showNotifications() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF120B32),
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * .72,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Text(
                      'BİLDİRİMLER',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () async {
                        await _api.markNotificationsRead();
                        await _refreshAccountBits();
                        if (sheetContext.mounted) Navigator.pop(sheetContext);
                      },
                      child: const Text('TÜMÜ OKUNDU'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    if (_notificationRows.isEmpty)
                      const Text(
                        'Henüz bildirim yok.',
                        style: TextStyle(color: Colors.white54),
                      ),
                    for (final n in _notificationRows)
                      ListTile(
                        dense: true,
                        leading: Icon(
                          n['read'] == true
                              ? Icons.notifications_none_rounded
                              : Icons.notifications_active_rounded,
                          color: n['read'] == true
                              ? Colors.white38
                              : OkeyXColors.gold,
                        ),
                        title: Text(
                          '${n['title']}',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        subtitle: Text(
                          '${n['message']}',
                          style: const TextStyle(fontSize: 8),
                        ),
                        trailing: n['kind'] == 'invite'
                            ? TextButton(
                                onPressed: () async {
                                  final roomId =
                                      '${_map(n['data'])['room_id'] ?? ''}';
                                  if (roomId.isEmpty) return;
                                  Navigator.pop(sheetContext);
                                  await _runBusy(() async {
                                    final session =
                                        await _api.joinRoom(roomId);
                                    await _openTable(session);
                                  });
                                },
                                child: const Text('GİT'),
                              )
                            : null,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _runBusy(Future<void> Function() task) async {
    if (_busy) return;
    _busy = true;
    var paintedBusy = false;
    final showBusy = Future<void>.delayed(const Duration(milliseconds: 140), () {
      if (!mounted || !_busy) return;
      paintedBusy = true;
      setState(() {});
    });
    try {
      await task();
    } catch (error) {
      _flash(_friendly(error));
    } finally {
      _busy = false;
      if (paintedBusy && mounted) setState(() {});
      unawaited(showBusy);
    }
  }

  void _flash(String text) {
    if (!mounted) return;
    setState(() => _message = text);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(
          onDeleteGameData: () async { await _api.deleteGameAccount(); },
          onNotificationPrefs: (prefs) async { await _api.setNotificationPrefs(prefs); },
          onSupportTicket: (topic, message, orderId) => _api.supportTicket(topic: topic, message: message, orderId: orderId),
          profile: _profile,
          preferences: _preferences,
          repository: widget.repository,
          auth: widget.auth,
          remoteConfig: widget.remoteConfig,
          publicId: '${_account['public_id'] ?? ''}',
          level: _level,
          xp: _xp,
          levelXpStart: _integer(_account['level_xp_start'], fallback: 0),
          nextLevelXp: _integer(_account['next_level_xp'], fallback: 0),
          gamesPlayed: _integer(_stats['games'], fallback: _profile.gamesPlayed),
          wins: _integer(_stats['wins'], fallback: _profile.wins),
          onProfileChanged: (profile) {
            setState(() => _profile = profile);
            _api.dispose();
            _api = LobbyApiClient(_profile);
            unawaited(_loadHub(first: true));
            widget.onBundleChanged(PlayerBundle(_profile, _preferences));
          },
          onPreferencesChanged: (preferences) {
            setState(() => _preferences = preferences);
            unawaited(_applyAudio());
            widget.onBundleChanged(PlayerBundle(_profile, _preferences));
          },
        ),
      ),
    );
  }

  Widget _avatar(double size) => Container(
        width: size,
        height: size,
        clipBehavior: Clip.antiAlias,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: _seedColor(_profile.avatarSeed), shape: BoxShape.circle, border: Border.all(color: const Color(0x88F4C542))),
        child: _profile.avatarUrl == null ? Text(_profile.displayName.isEmpty ? 'O' : _profile.displayName[0].toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900)) : Image.network(_profile.avatarUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Text(_profile.displayName[0].toUpperCase())),
      );

  Widget _currencyChip(IconData icon, String value, Color color, bool compact) => Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: () => setState(() => _selected = 6),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: compact ? 7 : 10, vertical: 7),
            decoration: BoxDecoration(
              color: color.withValues(alpha: .055),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withValues(alpha: .20)),
            ),
            child: Row(children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 4),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 10)),
              const SizedBox(width: 3),
              Icon(Icons.add_circle_outline_rounded, size: 11, color: color.withValues(alpha: .75)),
            ]),
          ),
        ),
      );

  Widget _miniPill(String text, Color color) => Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6), decoration: BoxDecoration(color: color.withValues(alpha: .08), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white12)), child: Text(text, style: TextStyle(fontSize: 8, color: color, fontWeight: FontWeight.w900)));

  String _compactNumber(int value) {
    final negative=value<0;final abs=value.abs();
    String scaled(num d,String suffix){var t=(abs/d).toStringAsFixed(2);while(t.contains('.') && t.endsWith('0')){t=t.substring(0,t.length-1);}if(t.endsWith('.')){t=t.substring(0,t.length-1);}return '${negative?'-':''}$t$suffix';}
    if(abs>=1000000000)return scaled(1000000000,'B');
    if(abs>=1000000)return scaled(1000000,'M');
    if(abs>=1000)return scaled(1000,'K');
    return '$value';
  }

  Color _seedColor(String? seed) => switch (seed) {
        'gold' => const Color(0xFF9C7108),
        'violet' => const Color(0xFF704F9D),
        'coral' => const Color(0xFFAD514E),
        'blue' => const Color(0xFF275E9C),
        'mint' => const Color(0xFF178265),
        _ => const Color(0xFF322187),
      };

  String _friendly(Object error) {
    final raw = '$error'.replaceFirst('LobbyApiException: ', '');
    const messages = {
      'room_password_required': 'Masa şifresi yanlış.',
      'room_not_found': 'Masa artık mevcut değil. Lobiden başka bir masa seçebilirsin.',
      'already_claimed': 'Bu ödülü bugün zaten aldın. Yarın tekrar gel!',
      'insufficient_coins': 'Bu işlem için yeterli altının yok.',
      'account_banned': 'Hesabın yönetim tarafından askıya alındı.',
      'invite_locked': 'Davet gönderme yetkin yönetim tarafından kapatıldı.',
      'gift_locked': 'Hediye gönderme yetkin yönetim tarafından kapatıldı.',
      'daily_wheel_limit': 'Bugünkü çark hakkını kullandın.',
      'daily_chest_limit': 'Bugünkü sandık hakkını kullandın.',
      'no_chest_key': 'Sandığı açmak için anahtarın yok.',
      'club_full': 'Kulüp dolu.',
      'club_name_taken': 'Bu kulüp adı alınmış.',
      'club_name_too_short': 'Kulüp adı çok kısa.',
      'transfer_daily_limit': 'Günlük transfer limitine ulaştın.',
      'transfer_minimum': 'Transfer tutarı minimumun altında.',
      'cannot_transfer_self': 'Kendine altın gönderemezsin.',
      'achievement_locked': 'Bu başarım henüz açılmadı.',
      'not_complete': 'Görev henüz tamamlanmadı.',
      'room_full': 'Masa dolu.',
      'room_already_started': 'Bu masa başlamış.',
      'not_enough_chips': 'Bu masa için yeterli altının yok.',
      'insufficient_balance': 'Bu masa için bakiyen yetersiz.',
      'account_link_required': 'Sosyal oturum doğrulanamadı. Girişi yenileyip tekrar dene.',
      'invalid_account_token': 'Oturum yenilenmeli.',
      'supabase_session_missing': 'Giriş oturumu bulunamadı.',
      'authentication_required': 'Arkadaşlık için oturumunu yenileyip tekrar dene.',
      'network_error': 'Bağlantı kurulamadı. İnternetini kontrol edip tekrar dene.',
      'timeout': 'Sunucu yanıtı gecikti. Birkaç saniye sonra tekrar dene.',
      'social_service_unavailable':'Arkadaş servisine ulaşılamadı. Bağlantıyı yenileyip tekrar dene.',
      'user_not_found':'Oyuncu bulunamadı.',
      'cannot_friend_self':'Kendini arkadaş olarak ekleyemezsin.',
      'already_friends':'Bu oyuncu zaten arkadaşın.',
      'already_pending':'Arkadaşlık isteğin zaten bekliyor.',
      'request_not_found':'Bekleyen arkadaşlık isteği bulunamadı.',
      'relationship_blocked':'Bu oyuncuyla sosyal etkileşim engellenmiş.',
    };
    final key = raw.split(':').first;
    final lower = key.toLowerCase();
    if (lower.contains('supabase_session_missing') || key.contains('authentication_required')) return 'Oturum doğrulanamadı. Lütfen tekrar giriş yap.';
    if (lower.contains('auth_not_configured') || lower.contains('supabase_not_configured')) return 'Test sunucusunun Supabase bağlantısı eksik.';
    if (lower.contains('socketexception') || lower.contains('connection refused') || lower.contains('connection_refused')) return 'Oyun sunucusuna ulaşılamadı. USB/backend bağlantısını kontrol et.';
    if (lower.contains('timeoutexception') || lower.contains('timeout')) return 'Oyun sunucusu hazırlanıyor. Birkaç saniye sonra tekrar dene.';
    return messages[key] ?? 'İşlem şu an tamamlanamadı. Lütfen tekrar dene.';
  }

  static int _integer(dynamic value, {int fallback = 0}) => value is num ? value.toInt() : int.tryParse('$value') ?? fallback;
  static Map<String, dynamic> _map(dynamic value) => value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
  static List<dynamic> _list(dynamic value) => value is List ? value : const [];
  static String _format(int value) {
    final negative=value<0;final abs=value.abs();
    String scaled(num d,String suffix){var t=(abs/d).toStringAsFixed(2);while(t.contains('.') && t.endsWith('0')){t=t.substring(0,t.length-1);}if(t.endsWith('.')){t=t.substring(0,t.length-1);}return '${negative?'-':''}$t$suffix';}
    if(abs>=1000000000)return scaled(1000000000,'B');
    if(abs>=1000000)return scaled(1000000,'M');
    if(abs>=1000)return scaled(1000,'K');
    return '$value';
  }
}


class _SpinRewardIcon extends StatefulWidget {
  const _SpinRewardIcon();

  @override
  State<_SpinRewardIcon> createState() => _SpinRewardIconState();
}

class _CooldownPill extends StatelessWidget {
  final String label;
  final IconData icon;
  const _CooldownPill({required this.label, required this.icon});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(color: Colors.white.withValues(alpha: .06), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white12)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 13, color: Colors.white54), const SizedBox(width: 4), Text(label, style: const TextStyle(fontSize: 7.5, color: Colors.white54, fontWeight: FontWeight.w900))]),
  );
}

class _SpinRewardIconState extends State<_SpinRewardIcon> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 420))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RotationTransition(
        turns: _controller,
        child: const Icon(Icons.casino_rounded, size: 58, color: OkeyXColors.gold),
      );
}


class _HubGameArtPainter extends CustomPainter {
  final String title;
  final bool featured;
  const _HubGameArtPainter(this.title, {this.featured = false});

  @override
  void paint(Canvas canvas, Size size) {
    final soft = Paint()..color = const Color(0x18FFFFFF);
    final glow = Paint()..color = const Color(0x20FFCA61);
    final mint = Paint()..color = const Color(0x242AE2B9);
    final line = Paint()
      ..color = const Color(0x28FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    // Atmospheric arcs keep the cards lively without adding expensive blur
    // filters or continuous animation to the lobby frame.
    canvas.drawCircle(Offset(size.width * .82, size.height * .18), size.shortestSide * .30, mint);
    canvas.drawCircle(Offset(size.width * .68, size.height * .82), size.shortestSide * .22, glow);

    if (title.contains('101')) {
      final table = Rect.fromCenter(
        center: Offset(size.width * .70, size.height * .47),
        width: size.width * (featured ? .42 : .44),
        height: size.height * (featured ? .34 : .40),
      );
      canvas.drawOval(table, Paint()..color = const Color(0x4A170F3F));
      canvas.drawOval(table.deflate(2), line);
      final tileW = featured ? 18.0 : 12.0;
      final tileH = featured ? 25.0 : 17.0;
      for (var i = 0; i < 4; i++) {
        final x = size.width * .57 + i * (tileW + 3);
        final y = size.height * .35 + (i.isOdd ? 4 : 0);
        final r = RRect.fromRectAndRadius(Rect.fromLTWH(x, y, tileW, tileH), const Radius.circular(3));
        canvas.drawRRect(r, Paint()..color = const Color(0xDFF4E9CE));
        canvas.drawCircle(Offset(x + tileW / 2, y + tileH * .34), featured ? 2.5 : 1.8, Paint()..color = i == 3 ? const Color(0xFFD34F42) : const Color(0xFF504D76));
      }
      if (title.contains('TURBO')) {
        final bolt = Path()
          ..moveTo(size.width * .82, size.height * .19)
          ..lineTo(size.width * .73, size.height * .50)
          ..lineTo(size.width * .80, size.height * .48)
          ..lineTo(size.width * .72, size.height * .78)
          ..lineTo(size.width * .91, size.height * .39)
          ..lineTo(size.width * .82, size.height * .41)
          ..close();
        canvas.drawPath(bolt, Paint()..color = const Color(0xBFFFF06B));
      }
      return;
    }

    if (title.contains('GOLD') || title.contains('REELS')) {
      final cabinet = RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * .51, size.height * .22, size.width * .42, size.height * .52),
        const Radius.circular(10),
      );
      canvas.drawRRect(cabinet, Paint()..color = const Color(0x5A0C081F));
      canvas.drawRRect(cabinet, line);
      for (var i = 0; i < 3; i++) {
        final rr = RRect.fromRectAndRadius(
          Rect.fromLTWH(size.width * (.55 + .115 * i), size.height * .31, size.width * .095, size.height * .26),
          const Radius.circular(5),
        );
        canvas.drawRRect(rr, Paint()..color = const Color(0xDCF7E6C5));
        final c = Offset(rr.center.dx, rr.center.dy);
        canvas.drawCircle(c, size.shortestSide * .035, Paint()..color = i == 1 ? const Color(0xFFD23F37) : const Color(0xFFE6A62D));
      }
      canvas.drawCircle(Offset(size.width * .79, size.height * .67), size.shortestSide * .055, Paint()..color = const Color(0xDFFFBD3E));
      return;
    }

    if (title.contains('HİPODROM')) {
      final track = Rect.fromLTWH(size.width * .47, size.height * .23, size.width * .48, size.height * .55);
      canvas.drawArc(track, .15, 5.7, false, Paint()..color = const Color(0x48C78A54)..style = PaintingStyle.stroke..strokeWidth = featured ? 9 : 6);
      for (var i = 0; i < 3; i++) {
        final y = size.height * (.38 + i * .11);
        canvas.drawLine(Offset(size.width * .57, y), Offset(size.width * (.78 + i * .035), y), Paint()..color = const Color(0x9AF4E0BA)..strokeWidth = featured ? 3.5 : 2.4..strokeCap = StrokeCap.round);
        canvas.drawCircle(Offset(size.width * (.80 + i * .035), y), featured ? 5 : 3.7, Paint()..color = i == 0 ? const Color(0xFFFFC64A) : const Color(0xFF79E0C2));
      }
      return;
    }

    if (title.contains('MASA')) {
      final cx = size.width * .73;
      final cy = size.height * .47;
      canvas.drawCircle(Offset(cx, cy), size.shortestSide * .14, Paint()..color = const Color(0x4208A786));
      canvas.drawCircle(Offset(cx, cy), size.shortestSide * .14, line);
      for (final d in const [Offset(0, -1), Offset(1, 0), Offset(0, 1), Offset(-1, 0)]) {
        canvas.drawCircle(Offset(cx + d.dx * size.shortestSide * .20, cy + d.dy * size.shortestSide * .20), featured ? 6 : 4.5, soft);
      }
      canvas.drawLine(Offset(cx - 8, cy), Offset(cx + 8, cy), Paint()..color = const Color(0xCCFFE1A1)..strokeWidth = 2.4..strokeCap = StrokeCap.round);
      canvas.drawLine(Offset(cx, cy - 8), Offset(cx, cy + 8), Paint()..color = const Color(0xCCFFE1A1)..strokeWidth = 2.4..strokeCap = StrokeCap.round);
    }
  }

  @override
  bool shouldRepaint(covariant _HubGameArtPainter oldDelegate) => oldDelegate.title != title || oldDelegate.featured != featured;
}

class _LobbyGlow extends StatelessWidget {
  final double size;
  final Color color;

  const _LobbyGlow({required this.size, required this.color});

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [color, color.withValues(alpha: 0)],
            ),
          ),
        ),
      );
}

class _LobbyTileFace extends StatelessWidget {
  final String text;
  final Color color;
  const _LobbyTileFace(this.text, this.color);
  @override
  Widget build(BuildContext context) => Transform.rotate(
        angle: -.045,
        child: Container(
          width: 34,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFFF7F0DF),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFFA9A6CC)),
            boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 6, offset: Offset(0, 4))],
          ),
          child: Text(text, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: color)),
        ),
      );
}


class _RoomCreatePreviewPainter extends CustomPainter {
  final bool turbo;
  final bool paired;
  const _RoomCreatePreviewPainter({required this.turbo, required this.paired});

  @override
  void paint(Canvas canvas, Size size) {
    final table = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(size.width * .5, size.height * .55), width: size.width * .66, height: size.height * .48),
      Radius.circular(size.height * .18),
    );
    final accent = turbo ? OkeyXColors.gold : OkeyXColors.mint;
    canvas.drawRRect(table, Paint()..color = const Color(0x8A231760));
    canvas.drawRRect(table, Paint()..style = PaintingStyle.stroke..strokeWidth = 4..color = accent.withValues(alpha: .58));
    final glow = Paint()..shader = RadialGradient(colors: [accent.withValues(alpha: .16), Colors.transparent]).createShader(Rect.fromCircle(center: table.center, radius: size.width * .36));
    canvas.drawCircle(table.center, size.width * .36, glow);
    final seats = <Offset>[
      Offset(table.center.dx, table.top - 5),
      Offset(table.right + 2, table.center.dy),
      Offset(table.center.dx, table.bottom + 5),
      Offset(table.left - 2, table.center.dy),
    ];
    for (var i = 0; i < seats.length; i++) {
      final teamColor = paired && i.isOdd ? OkeyXColors.cyan : accent;
      canvas.drawCircle(seats[i], 10, Paint()..color = teamColor.withValues(alpha: .18));
      canvas.drawCircle(seats[i], 10, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.4..color = teamColor.withValues(alpha: .55));
      canvas.drawCircle(seats[i], 3.2, Paint()..color = teamColor);
    }
    if (turbo) {
      final star = Path();
      for (var i = 0; i < 10; i++) {
        final a = -math.pi / 2 + i * math.pi / 5;
        final r = i.isEven ? 9.0 : 4.0;
        final p = Offset(table.center.dx + math.cos(a) * r, table.center.dy + math.sin(a) * r);
        if (i == 0) star.moveTo(p.dx, p.dy); else star.lineTo(p.dx, p.dy);
      }
      star.close();
      canvas.drawPath(star, Paint()..color = OkeyXColors.gold);
    }
  }

  @override
  bool shouldRepaint(covariant _RoomCreatePreviewPainter oldDelegate) => oldDelegate.turbo != turbo || oldDelegate.paired != paired;
}


class _LobbyShortcutEntry {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  const _LobbyShortcutEntry(this.icon, this.label, this.onTap, {this.active = false});
}


/// Üstten düşen "masaya davet" kartı: 60 sn süre çubuğu, KATIL / REDDET.
class _InviteToast extends StatefulWidget {
  final String title;
  final String label;
  final IconData icon;
  final String? acceptLabel;
  final String declineLabel;
  final int seconds;
  final VoidCallback onJoin;
  final VoidCallback onDecline;
  final VoidCallback onTimeout;
  const _InviteToast({required this.title, required this.onJoin, required this.onDecline, required this.onTimeout, this.label = 'MASA DAVETİ', this.icon = Icons.mail_rounded, this.acceptLabel = 'KATIL', this.declineLabel = 'REDDET', this.seconds = 60});

  @override
  State<_InviteToast> createState() => _InviteToastState();
}

class _InviteToastState extends State<_InviteToast> with TickerProviderStateMixin {
  late final AnimationController _life = AnimationController(vsync: this, duration: Duration(seconds: widget.seconds))..forward();
  late final AnimationController _drop = AnimationController(vsync: this, duration: const Duration(milliseconds: 420))..forward();

  @override
  void initState() {
    super.initState();
    _life.addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onTimeout();
    });
  }

  @override
  void dispose() {
    _life.dispose();
    _drop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final drop = CurvedAnimation(parent: _drop, curve: Curves.easeOutBack);
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Center(
          child: AnimatedBuilder(
            animation: drop,
            builder: (context, child) => Transform.translate(offset: Offset(0, -90 * (1 - drop.value)), child: Opacity(opacity: drop.value.clamp(0, 1), child: child)),
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 520,
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xF8140D3A), Color(0xF80C0823)]),
                  border: Border.all(color: const Color(0xA6FFD278), width: 1.5),
                  boxShadow: const [BoxShadow(color: Color(0xB3000000), blurRadius: 40, offset: Offset(0, 18))],
                ),
                child: Stack(clipBehavior: Clip.none, children: [
                  Row(children: [
                    OkxAvatar(name: 'D', size: 44, child: Icon(widget.icon, color: OkeyXColors.cream)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                        Text(widget.label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.4, color: OkeyXColors.gold)),
                        const SizedBox(height: 3),
                        Text(widget.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: OkeyXColors.cream)),
                      ]),
                    ),
                    const SizedBox(width: 8),
                    OkxButton.ghost(label: widget.declineLabel, height: 36, fontSize: 11, padding: const EdgeInsets.symmetric(horizontal: 12), onTap: widget.onDecline),
                    if (widget.acceptLabel != null) ...[
                      const SizedBox(width: 8),
                      OkxButton.green(label: widget.acceptLabel!, height: 40, fontSize: 13, padding: const EdgeInsets.symmetric(horizontal: 18), onTap: widget.onJoin),
                    ],
                  ]),
                  Positioned(
                    left: 2,
                    right: 2,
                    bottom: -9,
                    child: AnimatedBuilder(
                      animation: _life,
                      builder: (context, _) => ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(minHeight: 3, value: 1 - _life.value, backgroundColor: const Color(0x1FFFFFFF), color: const Color(0xFFFFD56B)),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}


/// Masa daveti tam ekran duyurusu: karartılmış arka plan, büyüyerek gelen
/// pirinç çerçeveli kart, davet edenin avatarı, büyük KATIL butonu ve 30 sn
/// geri sayım halkası.
class _InviteSplash extends StatefulWidget {
  const _InviteSplash({required this.from, required this.details, required this.onJoin, required this.onDecline, required this.onTimeout, this.avatarUrl});

  final String from;
  final String details;
  final String? avatarUrl;
  final VoidCallback onJoin;
  final VoidCallback onDecline;
  final VoidCallback onTimeout;

  @override
  State<_InviteSplash> createState() => _InviteSplashState();
}

class _InviteSplashState extends State<_InviteSplash> with TickerProviderStateMixin {
  late final AnimationController _life = AnimationController(vsync: this, duration: const Duration(seconds: 30))..forward();
  late final AnimationController _in = AnimationController(vsync: this, duration: const Duration(milliseconds: 520))..forward();
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    _life.addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onTimeout();
    });
  }

  @override
  void dispose() {
    _life.dispose();
    _in.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appear = CurvedAnimation(parent: _in, curve: Curves.easeOutBack);
    final left = (30 * (1 - _life.value)).ceil();
    final chips = widget.details.split('•').map((x) => x.trim()).where((x) => x.isNotEmpty).toList();
    const chipColors = [Color(0xFF3DF2D0), Color(0xFFFFCB45), Color(0xFFFF7AC6), Color(0xFF8FB3FF), Color(0xFFB36BFF)];
    return Positioned.fill(
      child: Material(
        color: Colors.transparent,
        child: AnimatedBuilder(
          animation: Listenable.merge([_in, _pulse, _life]),
          builder: (context, _) => Stack(alignment: Alignment.center, children: [
            // Renkli, kararan arka plan
            Positioned.fill(
              child: GestureDetector(
                onTap: () {},
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      radius: 1.1,
                      colors: [const Color(0xFF6A1B9A).withValues(alpha: .70 * _in.value), const Color(0xFF0B0726).withValues(alpha: .92 * _in.value)],
                    ),
                  ),
                ),
              ),
            ),
            // Dönen ışık hüzmeleri
            IgnorePointer(
              child: Transform.rotate(
                angle: _life.value * math.pi * 1.5,
                child: Opacity(opacity: .55 * _in.value, child: CustomPaint(size: const Size(760, 760), painter: _RaysPainter())),
              ),
            ),
            Transform.scale(
              scale: .55 + .45 * appear.value,
              child: Opacity(
                opacity: _in.value.clamp(0.0, 1.0),
                child: Container(
                  width: 500,
                  constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .92, maxHeight: MediaQuery.sizeOf(context).height * .94),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(30),
                    gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF3B1D8F), Color(0xFF1A1255), Color(0xFF0C3A5C)]),
                    border: Border.all(color: Color.lerp(const Color(0xFFFFD54A), const Color(0xFFFF7AC6), _pulse.value)!, width: 2),
                    boxShadow: [
                      const BoxShadow(color: Color(0xCC000000), blurRadius: 44, offset: Offset(0, 22)),
                      BoxShadow(color: const Color(0xFFFF7AC6).withValues(alpha: .25 + .25 * _pulse.value), blurRadius: 40, spreadRadius: 2),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: SingleChildScrollView(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        // Üst şerit
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFFFFD54A), Color(0xFFFF8A3D), Color(0xFFFF4D8D)])),
                          child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Text('🀄', style: TextStyle(fontSize: 16)),
                            SizedBox(width: 8),
                            Text('MASA DAVETİ', style: TextStyle(fontFamily: OkeyXFonts.number, fontSize: 16, letterSpacing: 2.5, color: Color(0xFF2A0E3D))),
                            SizedBox(width: 8),
                            Text('🀄', style: TextStyle(fontSize: 16)),
                          ]),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(22, 16, 22, 18),
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Row(children: [
                              // Geri sayım halkalı avatar
                              SizedBox(
                                width: 104,
                                height: 104,
                                child: Stack(alignment: Alignment.center, children: [
                                  Container(width: 104, height: 104, decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: const Color(0xFF3DF2D0).withValues(alpha: .35 + .3 * _pulse.value), blurRadius: 24)])),
                                  SizedBox.expand(child: CircularProgressIndicator(value: 1 - _life.value, strokeWidth: 5, backgroundColor: const Color(0x22FFFFFF), color: Color.lerp(const Color(0xFFFF5470), const Color(0xFF3DF2D0), 1 - _life.value))),
                                  OkxAvatar(name: widget.from, imageUrl: widget.avatarUrl, size: 78),
                                ]),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(widget.from, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: OkeyXFonts.number, fontSize: 24, color: Colors.white, height: 1.1)),
                                  const SizedBox(height: 4),
                                  const Text('seni masasına çağırıyor!', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFFFFD9F0))),
                                  const SizedBox(height: 8),
                                  Wrap(spacing: 6, runSpacing: 6, children: [
                                    for (var i = 0; i < chips.length; i++)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(99), color: chipColors[i % chipColors.length].withValues(alpha: .16), border: Border.all(color: chipColors[i % chipColors.length].withValues(alpha: .6))),
                                        child: Text(chips[i], style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: chipColors[i % chipColors.length])),
                                      ),
                                  ]),
                                ]),
                              ),
                            ]),
                            const SizedBox(height: 16),
                            Row(children: [
                              Expanded(child: OkxButton.ghost(label: 'REDDET', height: 50, expand: true, onTap: widget.onDecline)),
                              const SizedBox(width: 10),
                              Expanded(
                                flex: 2,
                                child: Transform.scale(
                                  scale: 1 + .04 * _pulse.value,
                                  child: OkxButton.green(label: 'MASAYA OTUR  ($left)', icon: Icons.event_seat_rounded, height: 54, fontSize: 16, expand: true, onTap: widget.onJoin),
                                ),
                              ),
                            ]),
                            const SizedBox(height: 8),
                            const Text('Masaya girince istediğin boş koltuğu seçebilirsin.', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xAAFFFFFF))),
                          ]),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _RaysPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    for (var i = 0; i < 16; i++) {
      final a0 = i * math.pi * 2 / 16;
      final path = Path()
        ..moveTo(c.dx, c.dy)
        ..lineTo(c.dx + r * math.cos(a0), c.dy + r * math.sin(a0))
        ..lineTo(c.dx + r * math.cos(a0 + .16), c.dy + r * math.sin(a0 + .16))
        ..close();
      canvas.drawPath(path, Paint()..shader = RadialGradient(colors: [i.isEven ? const Color(0x88FFD54A) : const Color(0x66FF7AC6), const Color(0x00000000)]).createShader(Rect.fromCircle(center: c, radius: r)));
    }
  }

  @override
  bool shouldRepaint(covariant _RaysPainter oldDelegate) => false;
}


/// Kartın üstünden belirli aralıklarla geçen ince ışık parıltısı.
class _ShineSweep extends StatefulWidget {
  const _ShineSweep();
  @override
  State<_ShineSweep> createState() => _ShineSweepState();
}

class _ShineSweepState extends State<_ShineSweep> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 4200))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Telefonda "animasyonları kaldır" açıksa süs animasyonlarını durdur.
    if (MediaQuery.of(context).disableAnimations) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: _c.duration!.inMilliseconds == 2600);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = (_c.value * 1.6 - .3);
          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment(-1 + t * 2.4, -1),
                end: Alignment(-.6 + t * 2.4, 1),
                colors: [Colors.white.withValues(alpha: 0), Colors.white.withValues(alpha: .16), Colors.white.withValues(alpha: 0)],
                stops: const [0, .5, 1],
              ),
            ),
          );
        },
      );
}
