// mobile/lib/features/table/table_felt.dart
// Masa çuhası: yumuşak ışık, kenar karartması ve ince kumaş dokusu.
// Statik çizilir (RepaintBoundary içinde), animasyon maliyeti yoktur.
import 'package:flutter/material.dart';

class TableFelt extends StatelessWidget {
  const TableFelt({super.key});

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(painter: _FeltPainter(), size: Size.infinite),
      ),
    );
  }
}

class _FeltPainter extends CustomPainter {
  const _FeltPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // 1) Masanın üstünden gelen yumuşak ışık.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0, -.35),
          radius: .95,
          colors: [Color(0x22FFFFFF), Color(0x00FFFFFF)],
        ).createShader(rect),
    );

    // 2) Çuha dokusu: çok ince çapraz ağ (düşük opaklık, keskin değil).
    final weave = Paint()
      ..color = const Color(0x0DFFFFFF)
      ..strokeWidth = 0.6;
    const step = 5.0;
    for (double x = -size.height; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x + size.height, size.height), weave);
    }
    final weave2 = Paint()
      ..color = const Color(0x0A000000)
      ..strokeWidth = 0.6;
    for (double x = 0; x < size.width + size.height; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x - size.height, size.height), weave2);
    }

    // 3) Kenar karartması (vinyet) ile derinlik.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0, -.05),
          radius: 1.08,
          colors: [Color(0x00000000), Color(0x00000000), Color(0x66000000)],
          stops: [0, .62, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _FeltPainter oldDelegate) => false;
}
