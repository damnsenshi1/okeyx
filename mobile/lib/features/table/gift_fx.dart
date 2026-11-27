import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Büyük hediyelerin tam ekran gösterileri. Her hediyenin kendi koreografisi
/// vardır; hepsi tek bir AnimationController ile çizilir (hafif ve akıcı).
///
/// t: 0..1 ilerleme. Emojiler TextPainter ile önbellekten çizilir.
class GiftShowPainter extends CustomPainter {
  GiftShowPainter({required this.id, required this.emoji, required this.t});
  final String id;
  final String emoji;
  final double t;

  static final Map<String, TextPainter> _cache = {};

  static TextPainter _tp(String e, double size) {
    final key = '$e@${size.round()}';
    return _cache.putIfAbsent(key, () => TextPainter(text: TextSpan(text: e, style: TextStyle(fontSize: size)), textDirection: TextDirection.ltr)..layout());
  }

  void _emoji(Canvas c, String e, Offset center, double size, {double angle = 0, double alpha = 1, bool flipX = false}) {
    final tp = _tp(e, size);
    c.save();
    c.translate(center.dx, center.dy);
    if (angle != 0) c.rotate(angle);
    if (flipX) c.scale(-1, 1);
    if (alpha < 1) {
      c.saveLayer(Rect.fromCenter(center: Offset.zero, width: tp.width * 1.4, height: tp.height * 1.4), Paint()..color = Color.fromRGBO(0, 0, 0, alpha.clamp(0, 1)));
    }
    tp.paint(c, Offset(-tp.width / 2, -tp.height / 2));
    if (alpha < 1) c.restore();
    c.restore();
  }

  double _ease(double x) => Curves.easeInOutCubic.transform(x.clamp(0.0, 1.0));

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final rnd = math.Random(id.hashCode);
    switch (id) {
      case 'sports_car': {
        // Soldan sağa hızla geçer: hız çizgileri + egzoz dumanı.
        final x = -0.25 * w + _ease(t) * 1.5 * w;
        final y = h * .62;
        for (var i = 0; i < 9; i++) {
          final ly = y - 30 + i * 9.0;
          final len = 60 + rnd.nextDouble() * 120;
          canvas.drawLine(Offset(x - 90 - len, ly), Offset(x - 90, ly), Paint()..color = Colors.white.withValues(alpha: .35)..strokeWidth = 2);
        }
        for (var i = 0; i < 6; i++) {
          final age = i / 6;
          _emoji(canvas, '💨', Offset(x - 120 - i * 46, y + 18), 34 + i * 4, alpha: (1 - age) * .8, flipX: true);
        }
        _emoji(canvas, emoji, Offset(x, y + math.sin(t * 60) * 2), 130, flipX: true);
      }
      case 'rocket': {
        // Alttan fırlar, alev izi bırakır, tepede patlar.
        final up = _ease(t / .7);
        final p = Offset(w * .5 + math.sin(up * 6) * 16, h * 1.1 - up * h * 1.0);
        for (var i = 0; i < 14; i++) {
          final k = i / 14;
          canvas.drawCircle(p + Offset((rnd.nextDouble() - .5) * 20, 50 + k * 140), 16 * (1 - k), Paint()..color = Color.lerp(const Color(0xFFFFE08A), const Color(0xFFFF4D1A), k)!.withValues(alpha: (1 - k) * .85));
        }
        _emoji(canvas, emoji, p, 110, angle: -math.pi / 4);
        if (t > .7) _burst(canvas, Offset(w * .5, h * .12), (t - .7) / .3, 26, [const Color(0xFFFFD45A), const Color(0xFFFF5A7A), const Color(0xFF6CE5FF)]);
      }
      case 'dragon': {
        // Sinüs yolunda uçar, ağzından alev saçar.
        final x = w * 1.15 - _ease(t) * w * 1.35;
        final y = h * .38 + math.sin(t * math.pi * 3) * h * .08;
        for (var i = 0; i < 10; i++) {
          final k = i / 10;
          _emoji(canvas, '🔥', Offset(x - 110 - k * 160, y + 20 + math.sin(t * 30 + i) * 10), 46 * (1 - k * .5), alpha: 1 - k);
        }
        _emoji(canvas, emoji, Offset(x, y), 150, flipX: true);
      }
      case 'money_rain':
      case 'gold_rain': {
        // Ekranın her yerinden para yağar.
        final pool = id == 'gold_rain' ? const ['🪙', '💰', '🪙'] : const ['💸', '💵', '💶'];
        for (var i = 0; i < 46; i++) {
          final x0 = rnd.nextDouble() * w;
          final delay = rnd.nextDouble() * .5;
          final speed = .7 + rnd.nextDouble() * .6;
          final p = ((t - delay) * speed / .6).clamp(0.0, 1.2);
          if (p <= 0) continue;
          final y = -40 + p * (h + 80);
          _emoji(canvas, pool[i % pool.length], Offset(x0 + math.sin(p * 8 + i) * 18, y), 30 + rnd.nextDouble() * 22, angle: math.sin(p * 6 + i) * .6);
        }
        _emoji(canvas, emoji, Offset(w / 2, h * .42), 120 * (.6 + .4 * _ease(t / .25)));
      }
      case 'fireworks':
      case 'confetti': {
        final colorsA = [const Color(0xFFFFD45A), const Color(0xFFFF5A7A), const Color(0xFF6CE5FF), const Color(0xFF8CFF7A), const Color(0xFFC08BFF)];
        if (id == 'confetti') {
          for (var i = 0; i < 90; i++) {
            final x0 = rnd.nextDouble() * w;
            final delay = rnd.nextDouble() * .35;
            final p = ((t - delay) / .65).clamp(0.0, 1.0);
            if (p <= 0) continue;
            final y = -20 + p * (h + 40);
            canvas.save();
            canvas.translate(x0 + math.sin(p * 10 + i) * 30, y);
            canvas.rotate(p * 12 + i);
            canvas.drawRect(const Rect.fromLTWH(-5, -3, 10, 6), Paint()..color = colorsA[i % colorsA.length]);
            canvas.restore();
          }
          _emoji(canvas, emoji, Offset(w / 2, h * .45), 120 * (.6 + .4 * _ease(t / .25)));
        } else {
          for (var b = 0; b < 5; b++) {
            final start = b * .14;
            final local = ((t - start) / .45).clamp(0.0, 1.0);
            if (local <= 0) continue;
            final c = Offset(w * (.18 + .16 * b + (rnd.nextDouble() - .5) * .08), h * (.2 + rnd.nextDouble() * .3));
            _burst(canvas, c, local, 30, [colorsA[b % colorsA.length], colorsA[(b + 2) % colorsA.length]]);
          }
        }
      }
      case 'crown':
      case 'trophy':
      case 'diamond_ring': {
        // Yukarıdan iner, döner ışık halesiyle parlar.
        final down = Curves.easeOutBack.transform((t / .35).clamp(0.0, 1.0));
        final c = Offset(w / 2, -80 + down * (h * .45 + 80));
        final rays = Paint()..color = const Color(0x33FFE08A);
        for (var i = 0; i < 14; i++) {
          final a = t * 2 + i * math.pi / 7;
          canvas.drawPath(
            Path()
              ..moveTo(c.dx, c.dy)
              ..lineTo(c.dx + math.cos(a - .07) * 420, c.dy + math.sin(a - .07) * 420)
              ..lineTo(c.dx + math.cos(a + .07) * 420, c.dy + math.sin(a + .07) * 420)
              ..close(),
            rays,
          );
        }
        for (var i = 0; i < 18; i++) {
          final a = i / 18 * math.pi * 2 + t * 3;
          final r = 110 + math.sin(t * 10 + i) * 14;
          _emoji(canvas, '✨', c + Offset(math.cos(a) * r, math.sin(a) * r * .6), 22, alpha: .9);
        }
        _emoji(canvas, emoji, c, 140, angle: math.sin(t * 8) * .08);
      }
      case 'unicorn': {
        // Gökkuşağı izi bırakarak sıçrayarak geçer.
        final x = -0.2 * w + _ease(t) * 1.4 * w;
        final y = h * .55 - (math.sin(t * math.pi * 3).abs()) * h * .22;
        const rainbow = [Color(0xFFFF4D4D), Color(0xFFFFA64D), Color(0xFFFFE14D), Color(0xFF6CE57A), Color(0xFF4DB8FF), Color(0xFFA36CFF)];
        for (var k = 0; k < rainbow.length; k++) {
          final path = Path();
          for (var i = 0; i <= 30; i++) {
            final tt = (t - i * .012).clamp(0.0, 1.0);
            final px = -0.2 * w + _ease(tt) * 1.4 * w - 40;
            final py = h * .55 - (math.sin(tt * math.pi * 3).abs()) * h * .22 + 30 + k * 7.0;
            if (i == 0) {
              path.moveTo(px, py);
            } else {
              path.lineTo(px, py);
            }
          }
          canvas.drawPath(path, Paint()..color = rainbow[k].withValues(alpha: .85)..style = PaintingStyle.stroke..strokeWidth = 7..strokeCap = StrokeCap.round);
        }
        _emoji(canvas, emoji, Offset(x, y), 120, flipX: true);
      }
      case 'lightning': {
        // Ekran çakar, zikzak şimşek iner.
        final flash = (1 - ((t % .25) / .25)) * (t < .75 ? 1 : 0);
        canvas.drawRect(Offset.zero & s, Paint()..color = Colors.white.withValues(alpha: .35 * flash));
        final path = Path()..moveTo(w * .55, 0);
        var x = w * .55, y = 0.0;
        final r2 = math.Random((t * 8).floor());
        while (y < h * .7) {
          x += (r2.nextDouble() - .5) * 120;
          y += 40 + r2.nextDouble() * 50;
          path.lineTo(x, y);
        }
        canvas.drawPath(path, Paint()..color = const Color(0xFFFFF59A).withValues(alpha: flash)..style = PaintingStyle.stroke..strokeWidth = 6..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
        canvas.drawPath(path, Paint()..color = Colors.white.withValues(alpha: flash)..style = PaintingStyle.stroke..strokeWidth = 2);
        _emoji(canvas, emoji, Offset(w / 2, h * .45), 130 * (.6 + .4 * _ease(t / .2)));
      }
      default: {
        // Diğer büyük hediyeler: zıplayarak büyür, etrafında yıldızlar döner.
        final appear = Curves.elasticOut.transform((t / .4).clamp(0.0, 1.0));
        final c = Offset(w / 2, h * .45);
        for (var i = 0; i < 12; i++) {
          final a = i / 12 * math.pi * 2 + t * 4;
          _emoji(canvas, '⭐', c + Offset(math.cos(a) * 130, math.sin(a) * 90), 20);
        }
        _emoji(canvas, emoji, c, 130 * appear);
      }
    }
  }

  void _burst(Canvas canvas, Offset c, double p, int n, List<Color> colors) {
    final rnd = math.Random(c.dx.round() * 31 + c.dy.round());
    final fade = (1 - p).clamp(0.0, 1.0);
    for (var i = 0; i < n; i++) {
      final a = i / n * math.pi * 2 + rnd.nextDouble() * .2;
      final r = Curves.easeOut.transform(p) * (90 + rnd.nextDouble() * 60);
      final pos = c + Offset(math.cos(a) * r, math.sin(a) * r + p * p * 40);
      canvas.drawCircle(pos, 3.5 * fade + 1, Paint()..color = colors[i % colors.length].withValues(alpha: fade));
      canvas.drawLine(c + Offset(math.cos(a) * r * .7, math.sin(a) * r * .7), pos, Paint()..color = colors[i % colors.length].withValues(alpha: fade * .5)..strokeWidth = 1.5);
    }
  }

  @override
  bool shouldRepaint(covariant GiftShowPainter old) => old.t != t || old.id != id;
}

/// Hediye animasyonunu kendi zamanlayıcısıyla oynatan katman.
class GiftShow extends StatefulWidget {
  const GiftShow({super.key, required this.id, required this.emoji, this.duration = const Duration(milliseconds: 2600), this.reduced = false});
  final String id;
  final String emoji;
  final Duration duration;
  final bool reduced;

  @override
  State<GiftShow> createState() => _GiftShowState();
}

class _GiftShowState extends State<GiftShow> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.reduced ? const Duration(milliseconds: 1) : widget.duration)..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => CustomPaint(size: Size.infinite, painter: GiftShowPainter(id: widget.id, emoji: widget.emoji, t: _c.value)),
        ),
      );
}
