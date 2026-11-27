import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/config.dart';
import '../../core/remote_config.dart';
import '../../widgets/okx_kit.dart';
import '../../widgets/tile_widget.dart';
import 'auth_service.dart';

class LoginScreen extends StatefulWidget {
  final AuthService auth;
  final MobileRemoteConfig remoteConfig;

  const LoginScreen({
    super.key,
    required this.auth,
    required this.remoteConfig,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();

  bool _showEmail = false;
  bool _register = false;
  bool _busy = false;
  bool _obscure = true;
  String _busyLabel = '';
  String _message = '';
  bool _messageIsError = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action, {String? success, String working = 'Güvenli bağlantı kuruluyor…'}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = '';
      _messageIsError = false;
      _busyLabel = working;
    });
    try {
      await action();
      if (mounted && success != null) {
        setState(() {
          _message = success;
          _messageIsError = false;
        });
      }
    } catch (error) {
      if ('$error'.contains('google_cancelled')) return;
      if (mounted) {
        setState(() {
          _message = '$error'.contains('google_no_id_token') || '$error'.contains('ApiException: 10')
              ? 'Google girişi ayarı tamamlanmamış (OAuth istemcisi). Şimdilik misafir ya da e-posta ile girebilirsin.'
              : _friendlyError(error);
          _messageIsError = true;
        });
      }
    } finally {
      if (mounted) setState(() { _busy = false; _busyLabel = ''; });
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_register) {
      await _run(
        () => widget.auth.signUpWithEmail(_email.text, _password.text, _name.text),
        success: 'Doğrulama bağlantısı e-postana gönderildi.',
        working: 'Hesabın güvenli şekilde oluşturuluyor…',
      );
    } else {
      await _run(() => widget.auth.signInWithEmail(_email.text, _password.text),working:'Hesabına giriş yapılıyor…');
    }
  }

  Future<void> _resetPassword() async {
    final controller = TextEditingController(text: _email.text);
    final email = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Parolayı yenile'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          decoration: const InputDecoration(labelText: 'E-posta'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Gönder')),
        ],
      ),
    );
    controller.dispose();
    if (email == null || email.isEmpty) return;
    await _run(
      () => widget.auth.resetPassword(email),
      success: 'Parola yenileme bağlantısı gönderildi.',
      working: 'Parola yenileme bağlantısı hazırlanıyor…',
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: OkeyXColors.ink,
        body: OkxRoom(
          child: Stack(children: [
            const Positioned.fill(child: IgnorePointer(child: _FloatingTiles())),
            SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxHeight < 430;
                final wide = constraints.maxWidth >= 640;
                final hero = _hero(compact || !wide);
                final panel = TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeOutCubic,
                  builder: (context, v, child) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, 18 * (1 - v)), child: child)),
                  child: OkxLeather(
                    stitch: true,
                    radius: 24,
                    padding: EdgeInsets.fromLTRB(compact ? 16 : 22, compact ? 14 : 20, compact ? 16 : 22, compact ? 12 : 18),
                    child: AnimatedSwitcher(duration: const Duration(milliseconds: 220), child: _showEmail ? _emailPanel(compact) : _quickPanel(compact)),
                  ),
                );
                return SingleChildScrollView(
                  padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 22, vertical: compact ? 8 : 18),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight - (compact ? 16 : 36)),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1120),
                        child: wide
                            ? Row(crossAxisAlignment: CrossAxisAlignment.center, children: [Expanded(flex: 50, child: hero), const SizedBox(width: 28), Expanded(flex: 50, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 500), child: panel))])
                            : Column(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560), child: hero), SizedBox(height: compact ? 10 : 18), ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: panel)]),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          ]),
        ),
      );

  Widget _hero(bool compact) {
    final logoH = compact ? 170.0 : 250.0;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutBack,
      builder: (context, v, child) => Opacity(opacity: v.clamp(0, 1), child: Transform.scale(scale: .85 + .15 * v, child: child)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Logonun arkasında nefes alan renkli hale.
          _PulseHalo(
            size: logoH * 1.15,
            child: Hero(
              tag: 'okeyx-brand',
              child: Image.asset('assets/brand/okeyx_logo_3d.png', height: logoH, fit: BoxFit.contain, filterQuality: FilterQuality.medium),
            ),
          ),
          SizedBox(height: compact ? 6 : 10),
          ShaderMask(
            shaderCallback: (r) => const LinearGradient(colors: [Color(0xFFFFE36B), Color(0xFFFF8A3D), Color(0xFFFF4D8D)]).createShader(r),
            child: Text('Arkadaşlarınla okey keyfi', textAlign: TextAlign.center, style: TextStyle(fontFamily: OkeyXFonts.number, fontSize: compact ? 20 : 27, color: Colors.white, letterSpacing: .3)),
          ),
          const SizedBox(height: 6),
          Text('101 Okey • Klasik Okey • canlı rakipler • sohbet ve hediyeler', textAlign: TextAlign.center, style: TextStyle(color: OkeyXColors.muted, fontSize: compact ? 11 : 12.5, fontWeight: FontWeight.w700)),
          if (!compact) ...[
            const SizedBox(height: 14),
            const Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
              _GlowChip(label: 'SUNUCU DOĞRULAMALI', icon: Icons.verified_rounded, color: Color(0xFF3DF2D0)),
              _GlowChip(label: '4 KİŞİLİK CANLI MASA', icon: Icons.groups_rounded, color: Color(0xFFFF7AC6)),
              _GlowChip(label: 'SESLİ SOHBET', icon: Icons.graphic_eq_rounded, color: Color(0xFFFFCB45)),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _quickPanel(bool compact) => Column(
        key: const ValueKey('quick'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Expanded(child: OkxTitle('Hoş geldin', size: 22)),
            Text('v${AppConfig.versionName}', style: const TextStyle(color: OkeyXColors.dim, fontSize: 10, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 5),
          const Text('Yerini seç, masaya otur.', style: TextStyle(color: OkeyXColors.muted, fontSize: 12, fontWeight: FontWeight.w600)),
          if (_busy) ...[
            const SizedBox(height: 10),
            Row(children: [const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: OkeyXColors.gold)), const SizedBox(width: 9), Expanded(child: Text(_busyLabel, style: const TextStyle(fontSize: 11.5, color: OkeyXColors.gold, fontWeight: FontWeight.w700)))]),
          ],
          SizedBox(height: compact ? 14 : 18),
          if (widget.remoteConfig.googleEnabled)
            _entryButton(textIcon: 'G', label: 'GOOGLE İLE GİR', subtitle: 'Tek dokunuş • ilerlemen hesabında güvende', style: OkxButtonStyle.green, onTap: _busy ? null : () => _run(() => widget.auth.signInWithGoogle(), working: 'Google giriş ekranı açılıyor…')),
          if (widget.remoteConfig.googleEnabled) const SizedBox(height: 10),
          _entryButton(icon: Icons.person_rounded, label: 'MİSAFİR OYNA', subtitle: 'Hemen başla, sonra hesabını bağla', style: OkxButtonStyle.brass, onTap: _busy ? null : () => _run(widget.auth.signInAnonymously, working: 'Misafir oturumun hazırlanıyor…')),
          if (_message.isNotEmpty) ...[const SizedBox(height: 10), _messageView()],
          const SizedBox(height: 10),
          Center(child: TextButton(onPressed: _busy ? null : () => setState(() => _showEmail = true), child: const Text('E-posta ile giriş veya kayıt', style: TextStyle(fontSize: 11, color: OkeyXColors.muted, decoration: TextDecoration.underline)))),
        ],
      );

  Widget _emailPanel(bool compact) => Form(
        key: _formKey,
        child: Column(
          key: const ValueKey('email'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                GestureDetector(
                  onTap: _busy ? null : () => setState(() => _showEmail = false),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0x66000000), border: Border.all(color: OkeyXColors.line2)),
                    child: const Icon(Icons.arrow_back_rounded, size: 18, color: Color(0xFFFFE9B0)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: OkxTitle(_register ? 'Yeni hesap' : 'Hesabına giriş', size: 20)),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: const Color(0x66000000), borderRadius: BorderRadius.circular(12), border: Border.all(color: OkeyXColors.line)),
              child: Row(children: [
                Expanded(child: _modeButton('GİRİŞ', !_register, () => setState(() => _register = false))),
                const SizedBox(width: 4),
                Expanded(child: _modeButton('KAYIT', _register, () => setState(() => _register = true))),
              ]),
            ),
            const SizedBox(height: 10),
            if (_register) ...[
              TextFormField(
                controller: _name,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.person_rounded), labelText: 'Oyuncu adı', isDense: true),
                validator: (value) => (value?.trim().length ?? 0) < 2 ? 'En az 2 karakter yaz.' : null,
              ),
              const SizedBox(height: 9),
            ],
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autocorrect: false,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.mail_rounded), labelText: 'E-posta', isDense: true),
              validator: (value) => !(value?.contains('@') ?? false) ? 'Geçerli e-posta yaz.' : null,
            ),
            const SizedBox(height: 9),
            TextFormField(
              controller: _password,
              obscureText: _obscure,
              onFieldSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.lock_rounded),
                labelText: 'Parola',
                isDense: true,
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                ),
              ),
              validator: (value) => (value?.length ?? 0) < 8 ? 'En az 8 karakter yaz.' : null,
            ),
            if (!_register)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: _busy ? null : _resetPassword, child: const Text('Parolamı unuttum', style: TextStyle(fontSize: 11.5))),
              )
            else
              const SizedBox(height: 10),
            if (_message.isNotEmpty) ...[_messageView(), const SizedBox(height: 8)],
            OkxButton(
              label: _busy ? 'BEKLE…' : (_register ? 'HESAP OLUŞTUR' : 'GİRİŞ YAP'),
              icon: _register ? Icons.person_add_alt_1_rounded : Icons.login_rounded,
              height: compact ? 44 : 48,
              fontSize: 14,
              expand: true,
              onTap: _busy ? null : _submit,
            ),
            const SizedBox(height: 8),
            const Text(
              'Devam ederek Kullanım Koşulları ve Gizlilik Politikasını kabul edersin.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, color: OkeyXColors.dim),
            ),
          ],
        ),
      );

  Widget _entryButton({
    IconData? icon,
    String? textIcon,
    required String label,
    required String subtitle,
    required OkxButtonStyle style,
    required VoidCallback? onTap,
  }) {
    final dark = style == OkxButtonStyle.brass;
    final google = style == OkxButtonStyle.green;
    final fg = google ? const Color(0xFF1F1F3A) : (dark ? okxTextDark : OkeyXColors.cream);
    return Opacity(
      opacity: onTap == null ? .55 : 1,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 58,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: dark ? brassGradient : null,
            color: google ? Colors.white : (dark ? null : const Color(0xA6311F7A)),
            border: dark || google ? null : Border.all(color: OkeyXColors.line2, width: 1.3),
            boxShadow: [
              if (dark) const BoxShadow(color: Color(0xFFA8480A), offset: Offset(0, 3)),
              if (google) const BoxShadow(color: Color(0x664D7CFF), blurRadius: 18),
              const BoxShadow(color: Color(0x80000000), blurRadius: 14, offset: Offset(0, 7)),
            ],
          ),
          child: Row(
            children: [
              SizedBox(
                width: 30,
                child: textIcon != null
                    ? ShaderMask(
                        shaderCallback: (r) => const SweepGradient(colors: [Color(0xFF4285F4), Color(0xFF34A853), Color(0xFFFBBC05), Color(0xFFEA4335), Color(0xFF4285F4)]).createShader(r),
                        child: Text(textIcon, textAlign: TextAlign.center, style: const TextStyle(fontFamily: OkeyXFonts.number, fontSize: 22, color: Colors.white)),
                      )
                    : Icon(icon, color: fg, size: 23),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: TextStyle(color: fg, fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: .4)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(color: fg.withValues(alpha: .7), fontSize: 10.5, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_rounded, size: 18, color: fg.withValues(alpha: .8)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _messageView() => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: (_messageIsError ? OkeyXColors.danger : OkeyXColors.mint).withValues(alpha: .10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: (_messageIsError ? OkeyXColors.danger : OkeyXColors.mint).withValues(alpha: .4)),
        ),
        child: Text(
          _message,
          textAlign: TextAlign.center,
          style: TextStyle(color: _messageIsError ? OkeyXColors.danger : OkeyXColors.mint, fontSize: 12, fontWeight: FontWeight.w700),
        ),
      );

  Widget _modeButton(String label, bool selected, VoidCallback onTap) => GestureDetector(
        onTap: _busy ? null : onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            gradient: selected ? const LinearGradient(colors: [Color(0xFFFFE36B), Color(0xFFFFA928)], begin: Alignment.topCenter, end: Alignment.bottomCenter) : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(color: selected ? okxTextDark : OkeyXColors.muted, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: .5),
          ),
        ),
      );

  String _friendlyError(Object error) {
    final text = '$error'.toLowerCase();
    if (text.contains('invalid login')) return 'E-posta veya parola yanlış.';
    if (text.contains('email not confirmed')) return 'Önce e-postandaki doğrulama bağlantısına dokun.';
    if (text.contains('already registered')) return 'Bu e-posta zaten kayıtlı.';
    if (text.contains('anonymous') && text.contains('disabled')) return 'Misafir girişi Supabase panelinde henüz açılmamış.';
    if (text.contains('oauth_browser_not_opened')) return 'Google giriş ekranı açılamadı.';
    if (text.contains('network') || text.contains('socket')) return 'İnternet bağlantısı kurulamadı.';
    if (text.contains('supabase_not_configured')) return 'Sunucu yapılandırması eksik.';
    return 'İşlem tamamlanamadı. Biraz sonra tekrar dene.';
  }
}


class _GlowChip extends StatelessWidget {
  const _GlowChip({required this.label, required this.icon, required this.color});
  final String label;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: color.withValues(alpha: .12),
          border: Border.all(color: color.withValues(alpha: .55)),
          boxShadow: [BoxShadow(color: color.withValues(alpha: .25), blurRadius: 12)],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, letterSpacing: .8, color: color)),
        ]),
      );
}

/// Logonun arkasında yavaşça büyüyüp küçülen renkli ışık halesi.
class _PulseHalo extends StatefulWidget {
  const _PulseHalo({required this.child, required this.size});
  final Widget child;
  final double size;
  @override
  State<_PulseHalo> createState() => _PulseHaloState();
}

class _PulseHaloState extends State<_PulseHalo> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..repeat(reverse: true);
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
        child: widget.child,
        builder: (context, child) {
          final t = Curves.easeInOut.transform(_c.value);
          return Stack(alignment: Alignment.center, children: [
            Container(
              width: widget.size * (.78 + .12 * t),
              height: widget.size * (.78 + .12 * t),
              decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [const Color(0xFFFF4D8D).withValues(alpha: .38 + .12 * t), const Color(0xFF7B2FF7).withValues(alpha: .18), const Color(0x00000000)], stops: const [0, .55, 1])),
            ),
            Transform.translate(offset: Offset(0, -4 * t), child: child),
          ]);
        },
      );
}

/// Arka planda yavaşça süzülen okey taşları.
class _FloatingTiles extends StatefulWidget {
  const _FloatingTiles();
  @override
  State<_FloatingTiles> createState() => _FloatingTilesState();
}

class _FloatingTilesState extends State<_FloatingTiles> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 14))..repeat();
  static const _tiles = [
    (0.06, 0.18, 7, 0, -.3, 44.0),
    (0.90, 0.12, 13, 1, .25, 38.0),
    (0.14, 0.80, 1, 2, .35, 36.0),
    (0.84, 0.78, 9, 3, -.2, 46.0),
    (0.48, 0.06, 4, 1, .12, 30.0),
    (0.56, 0.92, 11, 0, -.15, 32.0),
  ];
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
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) => AnimatedBuilder(
          animation: _c,
          builder: (context, _) => Stack(children: [
            for (var i = 0; i < _tiles.length; i++)
              Builder(builder: (context) {
                final t = _tiles[i];
                final phase = _c.value * 2 * math.pi + i;
                return Positioned(
                  left: t.$1 * box.maxWidth - t.$6 / 2,
                  top: t.$2 * box.maxHeight + math.sin(phase) * 12,
                  child: Opacity(
                    opacity: .55,
                    child: Transform.rotate(
                      angle: t.$5 + math.sin(phase * .7) * .12,
                      child: SizedBox(width: t.$6, height: t.$6 * 1.42, child: TileWidget(tile: GameTile(id: 'f$i', number: t.$3, colorIndex: t.$4))),
                    ),
                  ),
                );
              }),
          ]),
        ),
      );
}
