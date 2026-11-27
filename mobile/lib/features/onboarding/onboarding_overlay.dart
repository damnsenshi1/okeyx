import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/app_theme.dart';
import '../../core/game_audio.dart';
import '../../widgets/okx_kit.dart';

/// Yeni oyuncu karşılaması: 3 tanıtım kartı + 1.000.000 altın hoş geldin
/// hediyesi + "ilk maç / kuralları öğren" yönlendirmesi. Her hesap için bir
/// kez gösterilir (telefonda saklanır).
class OkxOnboarding {
  OkxOnboarding._();

  static String _key(String userId) => 'okeyx_onboarding_v1_$userId';

  static Future<bool> shouldShow(String userId) async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getBool(_key(userId)) != true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> markDone(String userId) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_key(userId), true);
    } catch (_) {}
  }

  /// Dönüş: 'practice' | 'tutorial' | 'home'
  static Future<String> show(BuildContext context, {required String userId, required String name, bool sound = true}) async {
    final result = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Hoş geldin',
      barrierColor: const Color(0xF0070420),
      transitionDuration: const Duration(milliseconds: 380),
      transitionBuilder: (context, a, _, child) => Opacity(opacity: a.value, child: Transform.scale(scale: .92 + .08 * Curves.easeOutBack.transform(a.value), child: child)),
      pageBuilder: (context, _, __) => PopScope(canPop: false, child: _OnboardingFlow(name: name, sound: sound)),
    );
    await markDone(userId);
    return result ?? 'home';
  }
}

class _Slide {
  const _Slide(this.emoji, this.title, this.text, this.gradient);
  final String emoji;
  final String title;
  final String text;
  final List<Color> gradient;
}

const _slides = [
  _Slide('🀄', '101 Okey ve Klasik Okey', 'Katlamalı, katlamasız, turbo, yardımlı ya da yardımsız: masanı istediğin kurallarla kur ya da tek dokunuşla hızlı maça gir.', [Color(0xFF0BA37F), Color(0xFF0E7FA8)]),
  _Slide('🎁', 'Ödüller her gün seni bekliyor', 'Günlük ödül, şans çarkı, sandıklar, etkinlikler ve masa çanağı. Okeyle ya da çiftten biten çanağı kırar!', [Color(0xFFFF8A3D), Color(0xFFFF3D6E)]),
  _Slide('👥', 'Arkadaşlarınla oyna', 'Arkadaşlarını masana davet et, sesli konuş, sohbet et, hediye at. Domates, terlik, çay… hepsi animasyonlu.', [Color(0xFF7B2FF7), Color(0xFFC0269E)]),
];

class _OnboardingFlow extends StatefulWidget {
  const _OnboardingFlow({required this.name, required this.sound});
  final String name;
  final bool sound;

  @override
  State<_OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<_OnboardingFlow> with TickerProviderStateMixin {
  final _page = PageController();
  int _index = 0;
  late final AnimationController _coins = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));

  @override
  void dispose() {
    _page.dispose();
    _coins.dispose();
    super.dispose();
  }

  void _next() {
    GameAudio.sfx('ui_tap', enabled: widget.sound);
    if (_index < _slides.length) {
      _page.nextPage(duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic);
    }
  }

  void _onPage(int i) {
    setState(() => _index = i);
    if (i == _slides.length) {
      _coins.forward(from: 0);
      GameAudio.sfx('coin_shower', enabled: widget.sound);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = math.min(size.width * .86, 720.0);
    final h = math.min(size.height * .86, 380.0);
    return Center(
      child: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: w,
          height: h,
          child: Column(children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: () => Navigator.of(context).pop('home'), child: const Text('ATLA', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2, color: Colors.white70))),
            ),
            Expanded(
              child: PageView(
                controller: _page,
                onPageChanged: _onPage,
                children: [
                  for (final s in _slides) _slideCard(s),
                  _bonusCard(),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 0; i <= _slides.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: i == _index ? 26 : 8,
                  height: 8,
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), color: i == _index ? OkeyXColors.gold : const Color(0x55FFFFFF)),
                ),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _slideCard(_Slide s) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 6),
        padding: const EdgeInsets.fromLTRB(28, 22, 28, 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: s.gradient),
          border: Border.all(color: const Color(0x66FFFFFF)),
          boxShadow: [BoxShadow(color: s.gradient.last.withValues(alpha: .5), blurRadius: 40, spreadRadius: -8)],
        ),
        child: Row(children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: .6, end: 1),
            duration: const Duration(milliseconds: 700),
            curve: Curves.elasticOut,
            builder: (context, v, child) => Transform.scale(scale: v, child: child),
            child: Container(
              width: 120,
              height: 120,
              alignment: Alignment.center,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: .16), border: Border.all(color: Colors.white.withValues(alpha: .35), width: 2)),
              child: Text(s.emoji, style: const TextStyle(fontSize: 60)),
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.title, style: const TextStyle(fontFamily: OkeyXFonts.number, fontSize: 24, color: Colors.white, height: 1.1)),
              const SizedBox(height: 10),
              Text(s.text, style: TextStyle(fontSize: 14, height: 1.4, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: .92))),
              const Spacer(),
              Align(
                alignment: Alignment.centerRight,
                child: OkxButton(label: 'DEVAM', icon: Icons.arrow_forward_rounded, height: 44, onTap: _next),
              ),
            ]),
          ),
        ]),
      );

  Widget _bonusCard() => Container(
        margin: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF2A1B6E), Color(0xFF6A1B9A), Color(0xFFB8336A)]),
          border: Border.all(color: const Color(0x88FFD45A), width: 1.5),
          boxShadow: const [BoxShadow(color: Color(0x88FFB834), blurRadius: 40, spreadRadius: -6)],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(27),
          child: Stack(children: [
            // Yağan altınlar
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _coins,
                  builder: (context, _) => CustomPaint(painter: _CoinRain(_coins.value)),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('Hoş geldin${widget.name.trim().isEmpty ? '' : ', ${widget.name.trim()}'}!', textAlign: TextAlign.center, style: const TextStyle(fontFamily: OkeyXFonts.number, fontSize: 22, color: Colors.white)),
                const SizedBox(height: 8),
                const Text('Hesabına hoş geldin hediyesi yüklendi', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFFFFE3F0))),
                const SizedBox(height: 10),
                AnimatedBuilder(
                  animation: _coins,
                  builder: (context, _) {
                    final v = Curves.easeOutCubic.transform((_coins.value / .7).clamp(0.0, 1.0));
                    return Row(mainAxisSize: MainAxisSize.min, children: [
                      const OkxCoin(size: 40),
                      const SizedBox(width: 10),
                      ShaderMask(
                        shaderCallback: (r) => const LinearGradient(colors: [Color(0xFFFFF1A8), Color(0xFFFFC845), Color(0xFFFF9A2E)]).createShader(r),
                        child: Text(okxFormat((1000000 * v).round()), style: const TextStyle(fontFamily: OkeyXFonts.number, fontSize: 46, color: Colors.white, height: 1)),
                      ),
                    ]);
                  },
                ),
                const SizedBox(height: 18),
                Wrap(alignment: WrapAlignment.center, spacing: 10, runSpacing: 10, children: [
                  OkxButton.ghost(label: 'KURALLARI ÖĞREN', icon: Icons.school_rounded, height: 46, onTap: () => Navigator.of(context).pop('tutorial')),
                  OkxButton(label: 'İLK MAÇA BAŞLA', icon: Icons.play_arrow_rounded, height: 46, fontSize: 15, onTap: () => Navigator.of(context).pop('practice')),
                  OkxButton.ghost(label: 'LOBİYE GİT', height: 46, onTap: () => Navigator.of(context).pop('home')),
                ]),
              ]),
            ),
          ]),
        ),
      );
}

class _CoinRain extends CustomPainter {
  _CoinRain(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0) return;
    final rnd = math.Random(3);
    for (var i = 0; i < 46; i++) {
      final x = rnd.nextDouble() * size.width;
      final delay = rnd.nextDouble() * .4;
      final speed = .8 + rnd.nextDouble() * .7;
      final p = ((t - delay) * speed).clamp(0.0, 1.0);
      if (p <= 0 || p >= 1) continue;
      final y = -20 + p * (size.height + 40);
      final r = 6 + rnd.nextDouble() * 6;
      final squash = (math.cos((p * 8 + i) * math.pi)).abs() * .8 + .2;
      final rect = Rect.fromCenter(center: Offset(x, y), width: r * 2 * squash, height: r * 2);
      canvas.drawOval(rect, Paint()..shader = const LinearGradient(colors: [Color(0xFFFFF1A8), Color(0xFFFFB834), Color(0xFFC77A12)]).createShader(rect));
    }
  }

  @override
  bool shouldRepaint(covariant _CoinRain old) => old.t != t;
}
