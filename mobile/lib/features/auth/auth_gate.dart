import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_theme.dart';
import '../../core/api_endpoint.dart';
import '../../core/config.dart';
import '../../core/remote_config.dart';
import '../../core/telemetry.dart';
import '../home/home_shell.dart';
import '../splash/splash_screen.dart';
import 'auth_service.dart';
import 'login_screen.dart';
import 'profile_repository.dart';

enum _RootStage { loading, login, home, maintenance, update, recovery, error }

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final AuthService _auth = AuthService();
  StreamSubscription<AuthState>? _authSubscription;
  ProfileRepository? _repository;
  MobileRemoteConfig _remoteConfig = const MobileRemoteConfig();
  PlayerBundle? _bundle;
  _RootStage _stage = _RootStage.loading;
  double _progress = .03;
  String _status = 'Mobil oyun motoru başlatılıyor...';
  String _error = '';
  bool _booting = true;

  @override
  void initState() {
    super.initState();
    if (AppConfig.hasSupabase) {
      _repository = ProfileRepository(Supabase.instance.client);
      _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen(_onAuthChanged);
    }
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    if (mounted) {
      setState(() {
        _booting = true;
        _error = '';
        _bundle = null;
      });
    }
    _setLoading(.14, 'Profil hazırlanıyor...');
    try {
      _remoteConfig = await RemoteConfigService().load().timeout(const Duration(milliseconds: 900));
    } catch (_) {
      _remoteConfig = const MobileRemoteConfig();
    }
    // Keep the compiled production endpoint authoritative. Remote config may
    // only switch servers after a successful health probe, so a stale/dead URL
    // can never send multiplayer back to an old deployment.
    final remoteApi = _remoteConfig.apiBaseUrl.trim();
    if (remoteApi.isNotEmpty && remoteApi != ApiEndpoint.baseUrl) {
      unawaited(ApiEndpoint.probeAndSet(remoteApi));
    }
    if (!mounted) return;
    _setLoading(.46, 'Oturum açılıyor...');

    if (_remoteConfig.maintenance) {
      setState(() {
        _booting = false;
        _stage = _RootStage.maintenance;
      });
      return;
    }
    if (_remoteConfig.updateRequired) {
      setState(() {
        _booting = false;
        _stage = _RootStage.update;
      });
      return;
    }
    if (!AppConfig.hasSupabase) {
      setState(() {
        _booting = false;
        _stage = _RootStage.error;
        _error = 'Mobil sunucu yapılandırması paket içinde bulunamadı.';
      });
      return;
    }

    _setLoading(.68, 'Kayıtlı oturum geri yükleniyor...');
    final user = _auth.currentUser;
    if (user != null) {
      await _loadPlayer();
    } else {
      _setLoading(.94, 'Giriş ekranı hazırlanıyor...');
      if (!mounted) return;
      setState(() {
        _progress = 1;
        _booting = false;
        _stage = _RootStage.login;
      });
    }
  }

  Future<void> _onAuthChanged(AuthState event) async {
    if (!mounted || _booting) return;
    if (event.event == AuthChangeEvent.passwordRecovery) {
      setState(() => _stage = _RootStage.recovery);
      return;
    }
    if (event.session?.user == null) {
      setState(() {
        _bundle = null;
        _stage = _RootStage.login;
      });
      return;
    }
    await _loadPlayer();
  }

  Future<void> _loadPlayer() async {
    final repository = _repository;
    if (repository == null) return;
    if (mounted) {
      setState(() {
        _stage = _RootStage.loading;
        _progress = .78;
        _status = 'Profil ve cihaz tercihleri eşitleniyor...';
      });
    }
    try {
      final bundle = await repository.ensureCurrentBundle();
      if (!mounted) return;
      setState(() {
        _bundle = bundle;
        _progress = 1;
        _status = 'Hazır. Masadaki yerin ayrıldı.';
      });
      if (!mounted) return;
      setState(() {
        _booting = false;
        _stage = _RootStage.home;
      });
      Telemetry.track('app_ready', properties: {'guest': bundle.profile.isGuest});
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _booting = false;
        _error = '$error';
        _stage = _RootStage.error;
      });
    }
  }

  void _setLoading(double progress, String status) {
    if (!mounted) return;
    setState(() {
      _stage = _RootStage.loading;
      _progress = progress;
      _status = status;
    });
  }

  @override
  Widget build(BuildContext context) {
    switch (_stage) {
      case _RootStage.loading:
        final tips = _remoteConfig.loadingTips;
        final tipIndex = tips.isEmpty ? 0 : ((_progress * 10).floor() % tips.length);
        return SplashScreen(
          progress: _progress,
          status: _status,
          tip: tips.isEmpty ? 'OkeyX mobil için hazırlanıyor.' : tips[tipIndex],
        );
      case _RootStage.login:
        return LoginScreen(auth: _auth, remoteConfig: _remoteConfig);
      case _RootStage.home:
        final bundle = _bundle;
        final repository = _repository;
        if (bundle == null || repository == null) return _problemScreen('Profil verisi hazır değil.');
        return HomeShell(
          bundle: bundle,
          remoteConfig: _remoteConfig,
          repository: repository,
          auth: _auth,
          onBundleChanged: (value) => setState(() => _bundle = value),
        );
      case _RootStage.maintenance:
        return _statusScreen(
          icon: Icons.engineering_rounded,
          title: 'Kısa bir bakımdayız',
          detail: 'Masaları daha sağlam hale getiriyoruz. Biraz sonra tekrar dene.',
          action: 'YENİDEN DENE',
          onTap: _bootstrap,
        );
      case _RootStage.update:
        return _statusScreen(
          icon: Icons.system_update_rounded,
          title: 'Yeni sürüm gerekli',
          detail: 'Bu mobil paket artık desteklenmiyor. Güncel OkeyX paketini kurman gerekiyor.',
          action: 'KONTROL ET',
          onTap: _bootstrap,
        );
      case _RootStage.recovery:
        return _PasswordRecoveryScreen(
          auth: _auth,
          onDone: () => _loadPlayer(),
        );
      case _RootStage.error:
        return _problemScreen(_error);
    }
  }

  Widget _problemScreen(String detail) => _statusScreen(
        icon: Icons.cloud_off_rounded,
        title: 'Bağlantı kurulamadı',
        detail: detail.contains('permission') || detail.contains('42501')
            ? 'Mobil profil yetkisi doğrulanamadı. Oturumu yenileyip tekrar dene.'
            : 'Sunucuya ulaşılamadı veya profil hazırlanamadı.',
        action: 'TEKRAR DENE',
        onTap: _bootstrap,
        secondaryAction: _auth.currentUser == null ? null : _auth.signOut,
      );

  Widget _statusScreen({
    required IconData icon,
    required String title,
    required String detail,
    required String action,
    required Future<void> Function() onTap,
    Future<void> Function()? secondaryAction,
  }) => Scaffold(
        body: Container(
          decoration: okeyXBackdrop,
          alignment: Alignment.center,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 470),
              child: Container(
                padding: const EdgeInsets.all(26),
                decoration: BoxDecoration(color: OkeyXColors.panel, borderRadius: BorderRadius.circular(22), border: Border.all(color: Colors.white24)),
                child: Column(
                  children: [
                    Icon(icon, size: 48, color: OkeyXColors.gold),
                    const SizedBox(height: 12),
                    Text(title, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 7),
                    Text(detail, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60, height: 1.4)),
                    const SizedBox(height: 18),
                    FilledButton(onPressed: onTap, child: Text(action)),
                    if (secondaryAction != null)
                      TextButton(onPressed: secondaryAction, child: const Text('Oturumu kapat')),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

class _PasswordRecoveryScreen extends StatefulWidget {
  final AuthService auth;
  final VoidCallback onDone;

  const _PasswordRecoveryScreen({required this.auth, required this.onDone});

  @override
  State<_PasswordRecoveryScreen> createState() => _PasswordRecoveryScreenState();
}

class _PasswordRecoveryScreenState extends State<_PasswordRecoveryScreen> {
  final _password = TextEditingController();
  final _again = TextEditingController();
  bool _busy = false;
  String _error = '';

  @override
  void dispose() {
    _password.dispose();
    _again.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_password.text.length < 8 || _password.text != _again.text) {
      setState(() => _error = 'Parolalar aynı ve en az 8 karakter olmalı.');
      return;
    }
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      await widget.auth.setPassword(_password.text);
      widget.onDone();
    } catch (_) {
      if (mounted) setState(() => _error = 'Parola kaydedilemedi. Bağlantıyı yeniden aç.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Container(
          decoration: okeyXBackdrop,
          alignment: Alignment.center,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(color: OkeyXColors.panel, borderRadius: BorderRadius.circular(22), border: Border.all(color: Colors.white24)),
                child: Column(
                  children: [
                    const Icon(Icons.lock_reset_rounded, size: 46, color: OkeyXColors.gold),
                    const SizedBox(height: 10),
                    const Text('Yeni parola oluştur', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 14),
                    TextField(controller: _password, obscureText: true, decoration: const InputDecoration(labelText: 'Yeni parola')),
                    const SizedBox(height: 9),
                    TextField(controller: _again, obscureText: true, decoration: const InputDecoration(labelText: 'Parolayı tekrar yaz')),
                    if (_error.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 9), child: Text(_error, style: const TextStyle(color: OkeyXColors.danger, fontSize: 11))),
                    const SizedBox(height: 14),
                    SizedBox(width: double.infinity, child: FilledButton(onPressed: _busy ? null : _save, child: const Text('PAROLAYI KAYDET'))),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}
