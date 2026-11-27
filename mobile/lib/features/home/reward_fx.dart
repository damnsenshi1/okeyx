import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_theme.dart';
import '../../core/game_audio.dart';

String _fmt(int v) => v.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');

/// Günlük çark: eğik (3D) altın çerçeveli, yanıp sönen ampullü çark.
/// Dilimler sunucudaki (yönetici panelinde ayarlanan) ödüllerdir; çark
/// sunucunun seçtiği dilimde durur, geçtiği her dilimde tık sesi çıkar.
class PrizeWheelDialog extends StatefulWidget {
  const PrizeWheelDialog({super.key, required this.reward, required this.segments, this.reducedMotion = false, this.sound = true});
  final int reward;
  final List<int> segments;
  final bool reducedMotion;
  final bool sound;

  @override
  State<PrizeWheelDialog> createState() => _PrizeWheelDialogState();
}

class _PrizeWheelDialogState extends State<PrizeWheelDialog> with TickerProviderStateMixin {
  static const _fallback = [500, 1000, 1500, 2500, 5000, 10000, 25000];
  late final List<int> rewards = widget.segments.where((x) => x >= 0).isNotEmpty ? widget.segments : _fallback;
  late final AnimationController _spin;
  late final Animation<double> _turns;
  late final AnimationController _bulbs = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..repeat();
  late final AnimationController _win = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  int _lastTickSeg = -1;
  bool _done = false;
  late final int _index;

  @override
  void initState() {
    super.initState();
    final idx = rewards.indexOf(widget.reward);
    _index = idx < 0 ? 0 : idx;
    final segment = 1 / rewards.length;
    // Dilimin ortasında değil, hafif rastgele bir yerinde dursun (daha gerçekçi).
    final jitter = (math.Random().nextDouble() - .5) * segment * .6;
    final target = 6.0 - ((_index + .5) * segment) + jitter;
    _spin = AnimationController(vsync: this, duration: widget.reducedMotion ? const Duration(milliseconds: 400) : const Duration(milliseconds: 4200));
    _turns = CurvedAnimation(parent: _spin, curve: const Cubic(.12, .78, .18, 1)).drive(Tween(begin: 0.0, end: target));
    _turns.addListener(_tick);
    _spin.forward().whenComplete(() async {
      if (!mounted) return;
      setState(() => _done = true);
      HapticFeedback.heavyImpact();
      GameAudio.sfx('reward', enabled: widget.sound, volume: .9);
      _win.forward();
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      if (mounted) Navigator.of(context).pop();
    });
  }

  void _tick() {
    final seg = ((_turns.value % 1) * rewards.length).floor();
    if (seg != _lastTickSeg) {
      _lastTickSeg = seg;
      if (_spin.value < .97) {
        GameAudio.sfx('ui_tap', enabled: widget.sound, volume: .35);
        if (_spin.value > .7) HapticFeedback.selectionClick();
      }
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    _bulbs.dispose();
    _win.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final d = math.min(300.0, math.min(size.width, size.height) * .72);
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ShaderMask(
            shaderCallback: (r) => const LinearGradient(colors: [Color(0xFFFFF1A8), Color(0xFFFFC845), Color(0xFFFF9A2E)]).createShader(r),
            child: const Text('ŞANS ÇARKI', style: TextStyle(fontFamily: OkeyXFonts.number, fontSize: 26, color: Colors.white, letterSpacing: 2)),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: d + 24,
            height: d * .86 + 34,
            child: Stack(alignment: Alignment.topCenter, children: [
              // Gölge (masaya düşen)
              Positioned(
                bottom: 0,
                child: Container(width: d * .8, height: 22, decoration: BoxDecoration(borderRadius: BorderRadius.circular(60), boxShadow: const [BoxShadow(color: Color(0xAA000000), blurRadius: 24, spreadRadius: 4)])),
              ),
              Positioned(
                top: 14,
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, .0016)
                    ..rotateX(.42),
                  child: SizedBox(
                    width: d,
                    height: d,
                    child: Stack(alignment: Alignment.center, children: [
                      // Altın dış çerçeve + ampuller
                      AnimatedBuilder(animation: _bulbs, builder: (context, _) => CustomPaint(size: Size.square(d), painter: _RimPainter(_bulbs.value, _done))),
                      AnimatedBuilder(
                        animation: _turns,
                        builder: (_, child) => Transform.rotate(angle: _turns.value * 2 * math.pi, child: child),
                        child: AnimatedBuilder(
                          animation: _win,
                          builder: (context, _) => CustomPaint(size: Size.square(d * .84), painter: WheelFacePainter(rewards, highlight: _done ? _index : -1, glow: _win.value)),
                        ),
                      ),
                      // Orta göbek
                      Container(
                        width: d * .2,
                        height: d * .2,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(colors: [Color(0xFFFFF1A8), Color(0xFFE0A63A), Color(0xFF8A5A14)], stops: [0, .55, 1]),
                          boxShadow: [BoxShadow(color: Color(0x99000000), blurRadius: 10, offset: Offset(0, 4))],
                        ),
                        child: const Icon(Icons.star_rounded, color: Color(0xFF6B3E0B)),
                      ),
                    ]),
                  ),
                ),
              ),
              // İbre
              const Positioned(top: 0, child: _Pointer()),
            ]),
          ),
          const SizedBox(height: 10),
          AnimatedBuilder(
            animation: _win,
            builder: (context, _) => Opacity(
              opacity: _win.value.clamp(0, 1),
              child: Transform.scale(
                scale: .6 + .4 * Curves.elasticOut.transform(_win.value),
                child: Text('+${_fmt(widget.reward)} ALTIN', style: const TextStyle(fontFamily: OkeyXFonts.number, fontSize: 28, color: Color(0xFFFFD45A), shadows: [Shadow(color: Color(0xFFFF9A2E), blurRadius: 18)])),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Pointer extends StatelessWidget {
  const _Pointer();
  @override
  Widget build(BuildContext context) => CustomPaint(size: const Size(34, 44), painter: _PointerPainter());
}

class _PointerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final path = Path()
      ..moveTo(s.width / 2, s.height)
      ..lineTo(0, s.height * .28)
      ..quadraticBezierTo(s.width / 2, -s.height * .12, s.width, s.height * .28)
      ..close();
    canvas.drawShadow(path, Colors.black, 6, false);
    canvas.drawPath(path, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFF4C4), Color(0xFFE2A93C), Color(0xFF9A6216)]).createShader(Offset.zero & s));
    canvas.drawCircle(Offset(s.width / 2, s.height * .3), 4, Paint()..color = const Color(0xFFB8122E));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _RimPainter extends CustomPainter {
  _RimPainter(this.t, this.done);
  final double t;
  final bool done;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final rect = Rect.fromCircle(center: c, radius: r);
    // Kalın metalik altın halka (3D his için iki tonlu).
    canvas.drawCircle(c, r, Paint()..shader = const SweepGradient(colors: [Color(0xFFFFE9A0), Color(0xFFB47A1E), Color(0xFFFFF4C4), Color(0xFF8A5A14), Color(0xFFFFE9A0)]).createShader(rect));
    canvas.drawCircle(c, r * .93, Paint()..color = const Color(0xFF2A1450));
    // Ampuller
    const n = 20;
    for (var i = 0; i < n; i++) {
      final a = i / n * 2 * math.pi;
      final p = c + Offset(math.cos(a), math.sin(a)) * r * .965;
      final on = done ? ((t * 6).floor() % 2 == 0) : (((t * n).floor() + i) % 3 == 0);
      canvas.drawCircle(p, r * .03, Paint()..color = on ? const Color(0xFFFFF7D0) : const Color(0xFF8A6A2A));
      if (on) canvas.drawCircle(p, r * .055, Paint()..color = const Color(0x55FFE58A)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    }
  }

  @override
  bool shouldRepaint(covariant _RimPainter old) => old.t != t || old.done != done;
}

/// Çark yüzü: gradyanlı dilimler, altın ayraçlar, kazanan dilim parlar.
class WheelFacePainter extends CustomPainter {
  WheelFacePainter(this.rewards, {this.highlight = -1, this.glow = 0});
  final List<int> rewards;
  final int highlight;
  final double glow;

  static const colors = [
    [Color(0xFFE0476A), Color(0xFF8E1B3A)],
    [Color(0xFF3A8EE0), Color(0xFF1B4A8E)],
    [Color(0xFFF0B53A), Color(0xFFA36A10)],
    [Color(0xFF35C49A), Color(0xFF147258)],
    [Color(0xFF9A63E0), Color(0xFF52238E)],
    [Color(0xFFF07A3A), Color(0xFFA33E10)],
    [Color(0xFF35B4D6), Color(0xFF14637A)],
    [Color(0xFFE05ACB), Color(0xFF8A1B78)],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final rect = Rect.fromCircle(center: c, radius: r);
    final sweep = 2 * math.pi / rewards.length;
    for (var i = 0; i < rewards.length; i++) {
      final start = -math.pi / 2 + i * sweep;
      final pair = colors[i % colors.length];
      final paint = Paint()..shader = RadialGradient(colors: [pair[0], pair[1]], stops: const [.25, 1]).createShader(rect);
      canvas.drawArc(rect, start, sweep, true, paint);
      if (i == highlight && glow > 0) {
        canvas.drawArc(rect, start, sweep, true, Paint()..color = Colors.white.withValues(alpha: .35 * glow));
      }
      // Altın ayraç
      final edge = c + Offset(math.cos(start), math.sin(start)) * r;
      canvas.drawLine(c, edge, Paint()..color = const Color(0xFFFFD979)..strokeWidth = 2.2);
      // Yazı
      final angle = start + sweep / 2;
      canvas.save();
      canvas.translate(c.dx + math.cos(angle) * r * .64, c.dy + math.sin(angle) * r * .64);
      canvas.rotate(angle + math.pi / 2);
      final v = rewards[i];
      final text = v >= 1000000 ? '${(v / 1000000).toStringAsFixed(v % 1000000 == 0 ? 0 : 1)}M' : v >= 1000 ? '${v ~/ 1000}K' : '$v';
      final tp = TextPainter(
        text: TextSpan(text: text, style: TextStyle(color: Colors.white, fontSize: r * .15, fontWeight: FontWeight.w900, shadows: const [Shadow(color: Colors.black87, blurRadius: 4, offset: Offset(0, 1))])),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }
    // İçe doğru gölge (derinlik)
    canvas.drawCircle(c, r, Paint()..shader = const RadialGradient(colors: [Color(0x00000000), Color(0x00000000), Color(0x66000000)], stops: [0, .8, 1]).createShader(rect));
  }

  @override
  bool shouldRepaint(covariant WheelFacePainter old) => old.highlight != highlight || old.glow != glow || old.rewards != rewards;
}

/// Şans sandığı: sandık sallanır, kapak 3D açılır, içinden ışık ve altınlar fışkırır.
class ChestOpenDialog extends StatefulWidget {
  const ChestOpenDialog({super.key, required this.reward, this.reducedMotion = false, this.sound = true});
  final int reward;
  final bool reducedMotion;
  final bool sound;

  @override
  State<ChestOpenDialog> createState() => _ChestOpenDialogState();
}

class _ChestOpenDialogState extends State<ChestOpenDialog> with TickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.reducedMotion ? const Duration(milliseconds: 500) : const Duration(milliseconds: 2600));

  @override
  void initState() {
    super.initState();
    _c.addListener(() {
      if (_c.value > .42 && !_popped) {
        _popped = true;
        HapticFeedback.heavyImpact();
        GameAudio.sfx('coin_shower', enabled: widget.sound, volume: .8);
      }
    });
    _c.forward().whenComplete(() async {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (mounted) Navigator.of(context).pop();
    });
  }

  bool _popped = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Center(
        child: Material(
          color: Colors.transparent,
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final t = _c.value;
              final shake = t < .38 ? math.sin(t * 90) * 5 * (t / .38) : 0.0;
              final open = Curves.easeOutBack.transform(((t - .38) / .2).clamp(0.0, 1.0));
              final burst = ((t - .42) / .5).clamp(0.0, 1.0);
              return Column(mainAxisSize: MainAxisSize.min, children: [
                ShaderMask(
                  shaderCallback: (r) => const LinearGradient(colors: [Color(0xFFFFF1A8), Color(0xFFFFC845), Color(0xFFFF9A2E)]).createShader(r),
                  child: const Text('ŞANS SANDIĞI', style: TextStyle(fontFamily: OkeyXFonts.number, fontSize: 26, color: Colors.white, letterSpacing: 2)),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: 260,
                  height: 230,
                  child: CustomPaint(painter: _ChestPainter(open: open, burst: burst, shake: shake)),
                ),
                Opacity(
                  opacity: burst,
                  child: Transform.scale(
                    scale: .6 + .4 * Curves.elasticOut.transform(burst),
                    child: Text('+${_fmt(widget.reward)} ALTIN', style: const TextStyle(fontFamily: OkeyXFonts.number, fontSize: 28, color: Color(0xFFFFD45A), shadows: [Shadow(color: Color(0xFFFF9A2E), blurRadius: 18)])),
                  ),
                ),
              ]);
            },
          ),
        ),
      );
}

class _ChestPainter extends CustomPainter {
  _ChestPainter({required this.open, required this.burst, required this.shake});
  final double open, burst, shake;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2 + shake;
    final baseTop = size.height * .55;
    final w = size.width * .62, h = size.height * .32;
    final body = RRect.fromRectAndRadius(Rect.fromLTWH(cx - w / 2, baseTop, w, h), const Radius.circular(10));
    // Işık huzmeleri
    if (burst > 0) {
      final center = Offset(cx, baseTop);
      for (var i = 0; i < 12; i++) {
        final a = -math.pi + (i + .5) * math.pi / 12;
        final len = size.height * .55 * burst;
        final p1 = center + Offset(math.cos(a - .06), math.sin(a - .06)) * len;
        final p2 = center + Offset(math.cos(a + .06), math.sin(a + .06)) * len;
        canvas.drawPath(Path()..moveTo(center.dx, center.dy)..lineTo(p1.dx, p1.dy)..lineTo(p2.dx, p2.dy)..close(), Paint()..color = const Color(0xFFFFE58A).withValues(alpha: .22 * (1 - burst * .5)));
      }
      canvas.drawCircle(center, 40 + 30 * burst, Paint()..color = const Color(0x66FFE58A)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24));
      // Fışkıran altınlar
      final rnd = math.Random(5);
      for (var i = 0; i < 26; i++) {
        final a = -math.pi / 2 + (rnd.nextDouble() - .5) * 2.2;
        final speed = 90 + rnd.nextDouble() * 90;
        final tt = burst;
        final pos = center + Offset(math.cos(a) * speed * tt, math.sin(a) * speed * tt + 160 * tt * tt);
        final rr = 5 + rnd.nextDouble() * 4;
        final squash = (math.cos((tt * 10 + i) * math.pi)).abs() * .8 + .2;
        final rect = Rect.fromCenter(center: pos, width: rr * 2 * squash, height: rr * 2);
        canvas.drawOval(rect, Paint()..shader = const LinearGradient(colors: [Color(0xFFFFF1A8), Color(0xFFFFB834), Color(0xFFC77A12)]).createShader(rect));
      }
    }
    // Gölge
    canvas.drawOval(Rect.fromCenter(center: Offset(cx, baseTop + h + 6), width: w * 1.1, height: 16), Paint()..color = const Color(0x88000000)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    // Gövde (ahşap + altın bantlar)
    canvas.drawRRect(body, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF9A4E1E), Color(0xFF5E2A0C)]).createShader(body.outerRect));
    for (final fx in [.12, .5, .88]) {
      final x = cx - w / 2 + w * fx;
      canvas.drawRect(Rect.fromLTWH(x - 7, baseTop, 14, h), Paint()..shader = const LinearGradient(colors: [Color(0xFFFFE9A0), Color(0xFFB47A1E), Color(0xFFFFE9A0)]).createShader(Rect.fromLTWH(x - 7, baseTop, 14, h)));
    }
    // Kilit
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(cx, baseTop + 10), width: 26, height: 30), const Radius.circular(5)), Paint()..color = const Color(0xFFFFD45A));
    // Kapak (alt kenarından açılır; 3D için dikey basıklık)
    final lidH = h * .62;
    final lidAngle = open * 1.9; // radyan
    final squeeze = math.cos(lidAngle);
    canvas.save();
    canvas.translate(cx, baseTop);
    canvas.scale(1, squeeze.abs() < .05 ? .05 : squeeze);
    final lid = RRect.fromRectAndCorners(Rect.fromLTWH(-w / 2 - 4, -lidH, w + 8, lidH), topLeft: const Radius.circular(26), topRight: const Radius.circular(26));
    canvas.drawRRect(lid, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: squeeze >= 0 ? const [Color(0xFFB8602A), Color(0xFF6E3210)] : const [Color(0xFF3A1A08), Color(0xFF5E2A0C)]).createShader(lid.outerRect));
    for (final fx in [.12, .5, .88]) {
      final x = -w / 2 + w * fx;
      canvas.drawRect(Rect.fromLTWH(x - 7, -lidH + 6, 14, lidH - 6), Paint()..color = const Color(0xFFE2A93C));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ChestPainter old) => old.open != open || old.burst != burst || old.shake != shake;
}
