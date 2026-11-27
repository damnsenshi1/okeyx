import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_theme.dart';

class GameTile {
  final String id;
  final int number;
  final int colorIndex;
  final bool isJoker;
  final bool isFakeJoker;
  final bool faceDown;
  final bool useful;
  final bool turboStar;

  const GameTile({
    required this.id,
    required this.number,
    required this.colorIndex,
    this.isJoker = false,
    this.isFakeJoker = false,
    this.faceDown = false,
    this.useful = false,
    this.turboStar = false,
  });

  GameTile copyWith({bool? faceDown, bool? useful, bool? turboStar}) => GameTile(
        id: id,
        number: number,
        colorIndex: colorIndex,
        isJoker: isJoker,
        isFakeJoker: isFakeJoker,
        faceDown: faceDown ?? this.faceDown,
        useful: useful ?? this.useful,
        turboStar: turboStar ?? this.turboStar,
      );
}

/// Gerçekçi okey taşı: fildişi gövde, görünen kalınlık, oyulmuş rakam ve
/// altında oyulmuş nokta. Okey taşı köşede altın taşla, sahte okey işlenmiş
/// yoncayla gösterilir. Boyut, verilen alandan (genişlik/yükseklik) hesaplanır.
class TileWidget extends StatelessWidget {
  final GameTile tile;
  final String skinId;
  final bool lifted;
  /// Kolay okuma: rakamlar ~%18 daha büyük (Ayarlar > Istaka ve taş).
  final bool bigNumber;

  const TileWidget({super.key, required this.tile, this.skinId = 'tiles_ivory', this.lifted = false, this.bigNumber = false});

  static const List<Color> numberColors = [
    OkeyXColors.tileRed,
    OkeyXColors.tileBlue,
    OkeyXColors.tileBlack,
    OkeyXColors.tileYellow,
  ];

  /// Blender ile işlenmiş gerçek taş gövdeleri (assets/tiles). Rakam, nokta,
  /// okey taşı ve sahte okey bu gövdenin ön yüzüne oyma gibi çizilir.
  static String bodyAsset(String skinId) {
    final key = skinId.startsWith('tiles_') ? skinId.substring(6) : skinId;
    const known = {'ivory', 'royal', 'marble', 'midnight', 'ember', 'carbon', 'neon', 'sakura', 'ice', 'bosphorus'};
    return 'assets/tiles/blank_${known.contains(key) ? key : 'ivory'}.webp';
  }

  // Render geometrisi (240x360 görüntü): ön yüz x 9..231, y 29..353.
  static const double _faceLeft = 9 / 240, _faceRight = 231 / 240, _faceTop = 29 / 360, _faceBottom = 353 / 360;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.maxHeight.isFinite ? constraints.maxHeight : 62.0;
        final w = constraints.maxWidth.isFinite ? constraints.maxWidth : h * .68;
        final color = numberColors[tile.colorIndex.clamp(0, numberColors.length - 1).toInt()];
        final fl = w * _faceLeft, fr = w * (1 - _faceRight), ft = h * _faceTop, fb = h * (1 - _faceBottom);
        final faceW = w - fl - fr, faceH = h - ft - fb;
        final body = Image.asset(
          tile.faceDown ? 'assets/tiles/back.webp' : bodyAsset(skinId),
          fit: BoxFit.fill,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, __, ___) => _fallbackBody(w, h, tile.faceDown),
        );
        final markSize = (w * .30).clamp(8.0, 16.0).toDouble();
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(w * .14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: lifted ? .48 : .30),
                      blurRadius: lifted ? h * .30 : h * .08,
                      offset: Offset(0, lifted ? h * .22 : h * .05),
                    ),
                  ],
                ),
                child: body,
              ),
            ),
            if (!tile.faceDown)
              Positioned(
                left: fl,
                top: ft,
                width: faceW,
                height: faceH,
                child: tile.isFakeJoker
                    ? Padding(
                        padding: EdgeInsets.fromLTRB(faceW * .10, faceH * .12, faceW * .10, faceH * .22),
                        child: const CustomPaint(painter: _CloverPainter()),
                      )
                    : Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
                        Positioned(
                          top: faceH * (bigNumber ? .07 : .10),
                          left: 0,
                          right: 0,
                          child: Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                '${tile.number}',
                                maxLines: 1,
                                style: TextStyle(
                                  fontFamily: OkeyXFonts.number,
                                  fontSize: math.min(faceH * (bigNumber ? .56 : .48), faceW * (tile.number >= 10 ? (bigNumber ? .66 : .58) : (bigNumber ? .92 : .80))),
                                  height: 1,
                                  letterSpacing: -.8,
                                  color: color,
                                  // Oyma: üst kenarda gölge, alt kenarda ışık.
                                  shadows: const [
                                    Shadow(color: Color(0xCCFFFFFF), offset: Offset(0, 1.0)),
                                    Shadow(color: Color(0x59000000), offset: Offset(0, -.8), blurRadius: .6),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          top: faceH * (bigNumber ? .70 : .66),
                          child: _EngravedDot(size: (faceW * (tile.useful ? .26 : .20)).clamp(3.5, 13.0).toDouble(), color: tile.useful ? const Color(0xFFFF2436) : color, glow: tile.useful),
                        ),
                      ]),
              ),
            if (!tile.faceDown && tile.isJoker && !tile.isFakeJoker)
              Positioned(right: fr + faceW * .02, top: ft + faceH * .02, child: _Gem(size: (w * .24).clamp(7.0, 13.0).toDouble())),
            // Turbo yıldızı sol alt köşede: rakamı ve noktayı asla örtmez.
            if (!tile.faceDown && tile.turboStar)
              Positioned(left: fl + faceW * .02, bottom: fb + faceH * .03, child: _TurboStar(size: markSize)),
          ],
        );
      },
    );
  }

  /// Görsel yüklenemezse (ör. testlerde) basit fildişi gövde.
  Widget _fallbackBody(double w, double h, bool faceDown) {
    final radius = (w * .14).clamp(3.5, 10.0).toDouble();
    if (faceDown) return _back(w, h, radius);
    final skin = _skin(skinId);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: RadialGradient(center: const Alignment(-.45, -.75), radius: 1.25, colors: skin.face, stops: const [0, .45, 1]),
        border: Border.all(color: skin.edge.withValues(alpha: .55), width: .6),
      ),
    );
  }

  Widget _back(double w, double faceH, double radius) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          gradient: const RadialGradient(
            center: Alignment(-.45, -.75),
            radius: 1.3,
            colors: [Color(0xFF2F8F67), Color(0xFF1D6B4B), Color(0xFF114A33)],
          ),
          border: Border.all(color: const Color(0x33000000), width: .6),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              left: w * .08,
              right: w * .08,
              top: faceH * .04,
              height: faceH * .28,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.white.withValues(alpha: .20), Colors.white.withValues(alpha: 0)],
                  ),
                ),
              ),
            ),
            Text(
              'X',
              style: TextStyle(
                fontFamily: OkeyXFonts.serif,
                fontWeight: FontWeight.w700,
                fontSize: (w * .34).clamp(7.0, 20.0).toDouble(),
                color: const Color(0x8CFFF0C8),
                height: 1,
              ),
            ),
          ],
        ),
      );
}

class _EngravedDot extends StatelessWidget {
  final double size;
  final Color color;
  /// İşlenebilir taş: oyuk parlak kırmızı yanar (yanıp sönmez).
  final bool glow;
  const _EngravedDot({required this.size, required this.color, this.glow = false});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            center: const Alignment(0, .35),
            colors: [color, Color.lerp(color, Colors.black, .45) ?? color],
          ),
          boxShadow: [
            const BoxShadow(color: Color(0xE6FFFFFF), offset: Offset(0, .9)),
            if (glow) const BoxShadow(color: Color(0xCCFF2436), blurRadius: 6, spreadRadius: .5),
          ],
        ),
      );
}

class _Gem extends StatelessWidget {
  final double size;
  const _Gem({required this.size});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const RadialGradient(center: Alignment(-.3, -.4), colors: [Color(0xFFFFF2B8), Color(0xFFE0A52F), Color(0xFF8A5A14)]),
          border: Border.all(color: const Color(0xFFFFF6DC), width: 1.2),
          boxShadow: const [BoxShadow(color: Color(0xE6FFC85A), blurRadius: 8)],
        ),
      );
}

class _TurboStar extends StatelessWidget {
  final double size;
  const _TurboStar({required this.size});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [Color(0xFFFFF5A8), Color(0xFFFFA51C), Color(0xFFE85B10)]),
          boxShadow: [BoxShadow(color: Color(0x88000000), blurRadius: 3, offset: Offset(0, 1))],
        ),
        child: Icon(Icons.star_rounded, size: size * .78, color: Colors.white),
      );
}

/// Sahte okey: taşa işlenmiş dört yapraklı yonca.
class _CloverPainter extends CustomPainter {
  const _CloverPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height);
    final c = Offset(size.width / 2, size.height / 2);
    final r = s * .22;
    final fill = Paint()..color = const Color(0xFF1F6B3F);
    final rim = Paint()
      ..color = const Color(0x40000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * .02;
    for (final d in const [Offset(0, -1), Offset(1, 0), Offset(0, 1), Offset(-1, 0)]) {
      final p = c + d * (r * 1.05);
      canvas.drawCircle(p.translate(0, s * .012), r, Paint()..color = const Color(0x99FFFFFF));
      canvas.drawCircle(p, r, fill);
      canvas.drawCircle(p, r, rim);
    }
    canvas.drawCircle(c, r * .42, Paint()..color = const Color(0xFFE9D9B0));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _TileSkinStyle {
  final List<Color> face;
  final List<Color> side;
  final Color edge;
  const _TileSkinStyle(this.face, this.side, this.edge);
}

_TileSkinStyle _skin(String id) => switch (id) {
      'tiles_royal' => const _TileSkinStyle([Color(0xFFFFFEF2), Color(0xFFFFF2C8), Color(0xFFE9CF8C)], [Color(0xFFD9B865), Color(0xFF8A6420)], Color(0xFFC9A042)),
      'tiles_marble' => const _TileSkinStyle([Color(0xFFFFFFFF), Color(0xFFF0F1F2), Color(0xFFCDD2D7)], [Color(0xFFB7BEC5), Color(0xFF6E7880)], Color(0xFF9CA6AF)),
      'tiles_midnight' => const _TileSkinStyle([Color(0xFFF7FAFF), Color(0xFFE5EAF4), Color(0xFFBBC5D8)], [Color(0xFF8E9BB8), Color(0xFF3B4A70)], Color(0xFF536A9A)),
      'tiles_ember' => const _TileSkinStyle([Color(0xFFFFFCF6), Color(0xFFFFE8CC), Color(0xFFE9B685)], [Color(0xFFD08E58), Color(0xFF8A4A1E)], Color(0xFFD96F32)),
      'tiles_carbon' => const _TileSkinStyle([Color(0xFFF8F8F7), Color(0xFFE5E5E1), Color(0xFFB9BAB6)], [Color(0xFF8D9093), Color(0xFF3E4245)], Color(0xFF575B5F)),
      _ => const _TileSkinStyle([Color(0xFFFFFEF8), Color(0xFFF8F0DC), Color(0xFFECDFBF)], [Color(0xFFD8C599), Color(0xFF7B6640)], Color(0xFFB8A07A)),
    };
