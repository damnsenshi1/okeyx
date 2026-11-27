import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_theme.dart';

/// OKEYX "Kahvehane Premium" ortak parçaları.
/// Deri paneller, pirinç butonlar, çuha, ceviz, para/elmas, avatar halkası.

const _walnut = AssetImage('assets/textures/walnut.jpg');
const _felt = AssetImage('assets/textures/felt.jpg');

const brassGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0xFFFFF1A8), Color(0xFFFFD54A), Color(0xFFFFA928), Color(0xFFE0701A)],
  stops: [0, .28, .62, 1],
);

const greenGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0xFF7CFFD0), Color(0xFF16D9A0), Color(0xFF0A9C8A)],
  stops: [0, .5, 1],
);

const redGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0xFFFF8FB1), Color(0xFFFF4D7E), Color(0xFFC21E5C)],
  stops: [0, .55, 1],
);

/// Renkli bölüm vurguları (her mod/özellik kendi renginde).
const okxVioletGradient = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFB36BFF), Color(0xFF6A3DF0)]);
const okxCyanGradient = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF4DF2FF), Color(0xFF2F7BFF)]);
const okxPinkGradient = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFF7AC6), Color(0xFFFF3D6E)]);
const okxOrangeGradient = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFFC94A), Color(0xFFFF6B2C)]);
const okxEmeraldGradient = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF3DFFB0), Color(0xFF0FA3A3)]);

const okxTextDark = Color(0xFF150E3D);

/// Ekran arka planı: deri doku + üstten sıcak lamba ışığı + kenar gölgesi.
class OkxRoom extends StatelessWidget {
  final Widget child;
  final bool lamp;
  const OkxRoom({super.key, required this.child, this.lamp = true});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E1056), Color(0xFF0C0830), Color(0xFF07273D)],
          stops: [0, .55, 1],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Renkli ışık lekeleri: mor, turkuaz ve sıcak altın.
          const IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(gradient: RadialGradient(center: Alignment(-.9, -.9), radius: .9, colors: [Color(0x55B04DFF), Color(0x00B04DFF)])))),
          const IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(gradient: RadialGradient(center: Alignment(1.0, .9), radius: .9, colors: [Color(0x4419E3D0), Color(0x0019E3D0)])))),
          if (lamp) const IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(gradient: RadialGradient(center: Alignment(.1, -1.3), radius: 1.0, colors: [Color(0x40FFC845), Color(0x00FFC845)])))),
          const IgnorePointer(child: CustomPaint(painter: _SparklePainter())),
          child,
        ],
      ),
    );
  }
}

/// Arka planda hafif yıldız/parıltı noktaları (sabit, performans dostu).
class _SparklePainter extends CustomPainter {
  const _SparklePainter();
  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(7);
    final p = Paint();
    for (var i = 0; i < 70; i++) {
      final o = Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height);
      final r = .6 + rnd.nextDouble() * 1.6;
      p.color = [const Color(0x66FFFFFF), const Color(0x55FFD45A), const Color(0x5566F0FF), const Color(0x55E08BFF)][i % 4];
      canvas.drawCircle(o, r, p);
    }
  }

  @override
  bool shouldRepaint(covariant _SparklePainter oldDelegate) => false;
}

/// Çuha yüzey (masa). İsteğe bağlı renk tonu (bordo, gece mavisi...).
class OkxFelt extends StatelessWidget {
  final Widget? child;
  final BorderRadius borderRadius;
  final Color? tint;
  /// Ayarlardaki çuha teması: green | bordo | navy | anthracite
  final String theme;
  /// true: Blender ile işlenmiş, lamba ışıklı ve ahşap kenarlı tam masa
  /// görseli (oyun masası arka planı). Üstüne ince kumaş dokusu eklenir.
  final bool photo;
  const OkxFelt({super.key, this.child, this.borderRadius = BorderRadius.zero, this.tint, this.theme = 'green', this.photo = false});

  @override
  Widget build(BuildContext context) {
    Widget base = photo
        ? Stack(fit: StackFit.expand, children: [
            Image.asset('assets/table/felt.webp', fit: BoxFit.cover, filterQuality: FilterQuality.medium, gaplessPlayback: true,
                errorBuilder: (_, __, ___) => const ColoredBox(color: OkeyXColors.felt)),
            const Opacity(
              opacity: .22,
              child: DecoratedBox(decoration: BoxDecoration(image: DecorationImage(image: _felt, repeat: ImageRepeat.repeat, scale: 1.4, opacity: 1, colorFilter: ColorFilter.mode(Color(0xFF808080), BlendMode.overlay)))),
            ),
          ])
        : const DecoratedBox(
            decoration: BoxDecoration(
              color: OkeyXColors.felt,
              image: DecorationImage(image: _felt, repeat: ImageRepeat.repeat, scale: 1.4),
            ),
          );
    final filter = tint != null ? ColorFilter.mode(tint!, BlendMode.hue) : okxFeltFilter(theme);
    if (filter != null) {
      base = ColorFiltered(colorFilter: filter, child: base);
    }
    return ClipRRect(
      borderRadius: borderRadius,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          Positioned.fill(child: base),
          if (!photo) const Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0, -.45),
                    radius: .9,
                    colors: [Color(0x29FFD68C), Color(0x00FFD68C)],
                  ),
                ),
              ),
            ),
          ),
          if (!photo) const Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    radius: 1.05,
                    colors: [Color(0x00000000), Color(0x9E000000)],
                    stops: [.45, 1],
                  ),
                ),
              ),
            ),
          ),
          if (child != null) child!,
        ],
      ),
    );
  }
}

/// Çuha teması renk filtresi (yeşil = orijinal doku).
ColorFilter? okxFeltFilter(String theme) => switch (theme) {
      'bordo' => const ColorFilter.mode(Color(0xFF8A2A2A), BlendMode.color),
      'navy' => const ColorFilter.mode(Color(0xFF2B4F86), BlendMode.color),
      'anthracite' => const ColorFilter.mode(Color(0xFF808080), BlendMode.saturation),
      _ => null,
    };

/// Istaka ağacı filtresi (ceviz = orijinal doku).
ColorFilter? okxRackFilter(String style) => switch (style) {
      'oak' => const ColorFilter.matrix(<double>[
          1.45, .10, 0, 0, 18, //
          .05, 1.30, 0, 0, 14, //
          0, .05, 1.05, 0, 4, //
          0, 0, 0, 1, 0,
        ]),
      'ebony' => const ColorFilter.matrix(<double>[
          .42, 0, 0, 0, 0, //
          0, .40, 0, 0, 0, //
          0, 0, .42, 0, 2, //
          0, 0, 0, 1, 0,
        ]),
      _ => null,
    };

/// Tema adları (ayarlarda gösterilen).
const okxFeltThemes = <(String, String)>[
  ('green', 'Kahvehane yeşili'),
  ('bordo', 'Bordo'),
  ('navy', 'Gece mavisi'),
  ('anthracite', 'Antrasit'),
];
const okxRackStyles = <(String, String)>[
  ('walnut', 'Ceviz'),
  ('oak', 'Meşe'),
  ('ebony', 'Abanoz'),
];

/// Ceviz ahşap kasnak (masa kenarı, ıstaka). [rack] ile ağaç türü değişir.
BoxDecoration walnutDecoration({BorderRadius radius = const BorderRadius.all(Radius.circular(18)), bool deep = true, String rack = 'walnut'}) => BoxDecoration(
      borderRadius: radius,
      color: const Color(0xFF2A1A78),
      image: DecorationImage(image: _walnut, fit: BoxFit.cover, alignment: Alignment.centerLeft, colorFilter: okxRackFilter(rack)),
      boxShadow: deep
          ? const [
              BoxShadow(color: Color(0xA6000000), blurRadius: 30, offset: Offset(0, 18)),
              BoxShadow(color: Color(0x66000000), blurRadius: 0, offset: Offset(0, -2)),
            ]
          : const [BoxShadow(color: Color(0x80000000), blurRadius: 12, offset: Offset(0, 6))],
    );

/// Deri panel (kartlar, menüler, isim plakaları).
class OkxLeather extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool stitch;
  final Color? borderColor;
  final double? width;
  final double? height;
  final List<BoxShadow>? shadows;
  const OkxLeather({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.radius = 18,
    this.stitch = false,
    this.borderColor,
    this.width,
    this.height,
    this.shadows,
  });

  @override
  Widget build(BuildContext context) {
    // Cam panel: mor-lacivert geçiş, üstte ışık şeridi, ince renkli kenar.
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xF2302079), Color(0xF21A1250), Color(0xF2102A55)],
          stops: [0, .55, 1],
        ),
        border: Border.all(color: borderColor ?? OkeyXColors.line2, width: 1.1),
        boxShadow: shadows ?? const [BoxShadow(color: Color(0x80070320), blurRadius: 26, offset: Offset(0, 12)), BoxShadow(color: Color(0x226A3DF0), blurRadius: 30, spreadRadius: -4)],
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x1FFFFFFF), Color(0x00FFFFFF), Color(0x26000000)],
            stops: [0, .35, 1],
          ),
        ),
        child: stitch
            ? CustomPaint(
                foregroundPainter: _StitchPainter(radius: radius),
                child: Padding(padding: padding, child: child),
              )
            : Padding(padding: padding, child: child),
      ),
    );
  }
}

class _StitchPainter extends CustomPainter {
  final double radius;
  _StitchPainter({required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)).deflate(5);
    final path = Path()..addRRect(rect);
    final paint = Paint()
      ..shader = const LinearGradient(colors: [Color(0x99FFD45A), Color(0x66E08BFF), Color(0x9966F0FF)]).createShader(Offset.zero & size)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _StitchPainter oldDelegate) => oldDelegate.radius != radius;
}

enum OkxButtonStyle { brass, ghost, green, red }

/// Basınca hafif içe çöken, gölgeli oyun butonu.
class OkxButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final OkxButtonStyle style;
  final double height;
  final double fontSize;
  final EdgeInsetsGeometry padding;
  final bool expand;
  final Widget? trailing;
  final double radius;
  const OkxButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.style = OkxButtonStyle.brass,
    this.height = 44,
    this.fontSize = 13,
    this.padding = const EdgeInsets.symmetric(horizontal: 18),
    this.expand = false,
    this.trailing,
    this.radius = 12,
  });

  const OkxButton.ghost({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.height = 44,
    this.fontSize = 13,
    this.padding = const EdgeInsets.symmetric(horizontal: 18),
    this.expand = false,
    this.trailing,
    this.radius = 12,
  }) : style = OkxButtonStyle.ghost;

  const OkxButton.green({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.height = 44,
    this.fontSize = 13,
    this.padding = const EdgeInsets.symmetric(horizontal: 18),
    this.expand = false,
    this.trailing,
    this.radius = 12,
  }) : style = OkxButtonStyle.green;

  @override
  State<OkxButton> createState() => _OkxButtonState();
}

class _OkxButtonState extends State<OkxButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final (Gradient? grad, Color? bg, Color fg, Color lip, Color? border) = switch (widget.style) {
      OkxButtonStyle.brass => (brassGradient, null, okxTextDark, const Color(0xFFA8480A), null),
      OkxButtonStyle.green => (greenGradient, null, const Color(0xFF04241A), const Color(0xFF0B4A30), null),
      OkxButtonStyle.red => (redGradient, null, const Color(0xFFFFF3EC), const Color(0xFF561208), null),
      OkxButtonStyle.ghost => (null, const Color(0xA6311F7A), OkeyXColors.cream, const Color(0x00000000), OkeyXColors.line2),
    };
    final content = Row(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.icon != null) ...[Icon(widget.icon, size: widget.fontSize + 4, color: fg), const SizedBox(width: 7)],
        Flexible(
          child: Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: OkeyXFonts.sans,
              fontWeight: FontWeight.w800,
              fontSize: widget.fontSize,
              letterSpacing: .5,
              color: fg,
              shadows: widget.style == OkxButtonStyle.brass ? const [Shadow(color: Color(0x99FFF0C8), offset: Offset(0, 1))] : null,
            ),
          ),
        ),
        if (widget.trailing != null) ...[const SizedBox(width: 7), widget.trailing!],
      ],
    );
    return Opacity(
      opacity: enabled ? 1 : .45,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: enabled ? () => setState(() => _down = false) : null,
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          curve: Curves.easeOut,
          height: widget.height,
          padding: widget.padding,
          transform: Matrix4.translationValues(0, _down ? 2 : 0, 0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: grad,
            color: bg,
            border: border == null ? null : Border.all(color: border, width: 1.4),
            boxShadow: [
              if (widget.style != OkxButtonStyle.ghost) BoxShadow(color: lip, offset: Offset(0, _down ? 1 : 3)),
              BoxShadow(color: const Color(0x80000000), blurRadius: _down ? 6 : 16, offset: Offset(0, _down ? 3 : 8)),
            ],
          ),
          alignment: Alignment.center,
          child: content,
        ),
      ),
    );
  }
}

/// Kare/simgeli küçük buton (ıstaka yanı: SERİ, ÇİFT, HEDİYE...).
class OkxIconTile extends StatelessWidget {
  final IconData icon;
  final String? label;
  final VoidCallback? onTap;
  final double size;
  final bool active;
  final Widget? badge;
  const OkxIconTile({super.key, required this.icon, this.label, this.onTap, this.size = 50, this.active = false, this.badge});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(size * .28),
              color: active ? null : const Color(0xA60B0721),
              gradient: active ? brassGradient : null,
              border: Border.all(color: active ? Colors.transparent : OkeyXColors.line2, width: 1.3),
              boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 12, offset: Offset(0, 6))],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: size * .36, color: active ? okxTextDark : const Color(0xFFFFE9B0)),
                if (label != null) ...[
                  const SizedBox(height: 2),
                  FittedBox(
                    child: Text(
                      label!,
                      style: TextStyle(
                        fontSize: size * .17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .4,
                        color: active ? okxTextDark : OkeyXColors.cream,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (badge != null) Positioned(right: -8, top: -10, child: badge!),
        ],
      ),
    );
  }
}

/// Altın para.
class OkxCoin extends StatelessWidget {
  final double size;
  const OkxCoin({super.key, this.size = 16});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const RadialGradient(
            center: Alignment(-.3, -.4),
            colors: [Color(0xFFFFF6CC), Color(0xFFF3CF6A), Color(0xFFC88D27), Color(0xFF8A5A14)],
            stops: [0, .3, .7, 1],
          ),
          border: Border.all(color: const Color(0xB3784B0A), width: size * .09),
          boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 2, offset: Offset(0, 1))],
        ),
        child: Container(
          margin: EdgeInsets.all(size * .08),
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0x8CFFE696), width: size * .07)),
        ),
      );
}

/// Elmas.
class OkxGem extends StatelessWidget {
  final double size;
  const OkxGem({super.key, this.size = 16});

  @override
  Widget build(BuildContext context) => SizedBox(width: size, height: size, child: const CustomPaint(painter: _GemPainter()));
}

class _GemPainter extends CustomPainter {
  const _GemPainter();

  @override
  void paint(Canvas canvas, Size s) {
    final p = Path()
      ..moveTo(s.width * .5, s.height)
      ..lineTo(0, s.height * .35)
      ..lineTo(s.width * .22, 0)
      ..lineTo(s.width * .78, 0)
      ..lineTo(s.width, s.height * .35)
      ..close();
    canvas.drawPath(
      p,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFD9FBFF), Color(0xFF5FD3E8), Color(0xFF1D7FA3)],
        ).createShader(Offset.zero & s),
    );
    canvas.drawLine(Offset(0, s.height * .35), Offset(s.width, s.height * .35), Paint()..color = const Color(0x66FFFFFF)..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Pirinç halkalı avatar; isteğe bağlı süre halkası ve çevrimiçi nokta.
class OkxAvatar extends StatelessWidget {
  final String name;
  final String? imageUrl;
  final double size;
  final double? ring; // 0..1 kalan süre
  final bool online;
  final bool highlight;
  final Widget? child;
  const OkxAvatar({super.key, required this.name, this.imageUrl, this.size = 52, this.ring, this.online = false, this.highlight = false, this.child});

  static const _palette = [
    [Color(0xFF7A5A3C), Color(0xFF1C1251)],
    [Color(0xFF4F7BB6), Color(0xFF1E3558)],
    [Color(0xFFB6554A), Color(0xFF5A1F19)],
    [Color(0xFF5C9A6E), Color(0xFF1E4A2D)],
    [Color(0xFF8C6BB3), Color(0xFF3A2756)],
  ];

  @override
  Widget build(BuildContext context) {
    final seed = name.isEmpty ? 0 : name.codeUnits.fold<int>(0, (a, b) => a + b);
    final colors = _palette[seed % _palette.length];
    final letter = name.trim().isEmpty ? '?' : name.trim().substring(0, 1).toUpperCase();
    final url = imageUrl;
    final inner = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(center: const Alignment(-.3, -.4), colors: colors),
        image: url != null && url.isNotEmpty ? DecorationImage(image: NetworkImage(url), fit: BoxFit.cover) : null,
        boxShadow: [
          const BoxShadow(color: Color(0x99000000), blurRadius: 14, spreadRadius: 4, offset: Offset(0, 6)),
          if (highlight) const BoxShadow(color: OkeyXColors.cyan, blurRadius: 16, spreadRadius: 4),
        ],
      ),
      alignment: Alignment.center,
      child: child ??
          (url != null && url.isNotEmpty
              ? null
              : Text(letter, style: TextStyle(fontFamily: OkeyXFonts.serif, fontWeight: FontWeight.w700, fontSize: size * .42, color: OkeyXColors.cream))),
    );
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (ring != null)
            Positioned(
              left: -10,
              top: -10,
              right: -10,
              bottom: -10,
              child: CustomPaint(painter: _RingPainter(ring!.clamp(0, 1).toDouble())),
            ),
          inner,
          // Blender ile işlenmiş pirinç çerçeve (3B görünüm).
          Positioned(
            left: -size * .13,
            top: -size * .13,
            width: size * 1.26,
            height: size * 1.26,
            child: IgnorePointer(child: Image.asset('assets/ui/bezel.webp', fit: BoxFit.contain, filterQuality: FilterQuality.medium, gaplessPlayback: true, errorBuilder: (_, __, ___) => const SizedBox.shrink())),
          ),
          if (online)
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: size * .26,
                height: size * .26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF3CCF8E),
                  border: Border.all(color: OkeyXColors.night, width: 2.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double value;
  _RingPainter(this.value);

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTWH(2, 2, size.width - 4, size.height - 4);
    canvas.drawArc(r, 0, math.pi * 2, false, Paint()
      ..color = const Color(0x14FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4);
    final color = value > .5 ? const Color(0xFF7CF2B8) : value > .25 ? const Color(0xFFFFD56B) : const Color(0xFFFF6B57);
    canvas.drawArc(r, -math.pi / 2, math.pi * 2 * value, false, Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4);
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) => oldDelegate.value != value;
}

/// Seçilebilir hap (mod/giriş seçimi).
class OkxChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;
  final Widget? leading;
  final bool onFelt;
  const OkxChip({super.key, required this.label, this.selected = false, this.onTap, this.icon, this.leading, this.onFelt = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          gradient: selected ? const LinearGradient(colors: [Color(0xFFFFE36B), Color(0xFFFFA928)], begin: Alignment.topCenter, end: Alignment.bottomCenter) : null,
          color: selected ? null : (onFelt ? const Color(0x47000000) : const Color(0x10FFEBC8)),
          border: Border.all(color: selected ? Colors.transparent : (onFelt ? const Color(0x24FFFFFF) : OkeyXColors.line)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 5)],
            if (icon != null) ...[Icon(icon, size: 13, color: selected ? okxTextDark : OkeyXColors.muted), const SizedBox(width: 5)],
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: .5,
                color: selected ? okxTextDark : (onFelt ? const Color(0xFFD8ECDF) : OkeyXColors.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Para/elmas hapı (+ butonlu).
class OkxMoneyPill extends StatelessWidget {
  final Widget icon;
  final String value;
  final VoidCallback? onPlus;
  final GlobalKey? valueKey;
  const OkxMoneyPill({super.key, required this.icon, required this.value, this.onPlus, this.valueKey});

  @override
  Widget build(BuildContext context) {
    return OkxLeather(
      radius: 999,
      padding: EdgeInsets.fromLTRB(12, 5, onPlus == null ? 14 : 5, 5),
      shadows: const [BoxShadow(color: Color(0x59000000), blurRadius: 10, offset: Offset(0, 4))],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(key: valueKey, child: icon),
          const SizedBox(width: 7),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: OkeyXColors.text)),
          if (onPlus != null) ...[
            const SizedBox(width: 7),
            GestureDetector(
              onTap: onPlus,
              child: Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(shape: BoxShape.circle, gradient: brassGradient),
                child: const Icon(Icons.add_rounded, size: 17, color: okxTextDark),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Küçük büyük-harf etiket.
class OkxLabel extends StatelessWidget {
  final String text;
  final Color color;
  const OkxLabel(this.text, {super.key, this.color = OkeyXColors.muted});

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.6, color: color),
      );
}

/// Serif başlık.
class OkxTitle extends StatelessWidget {
  final String text;
  final double size;
  final Color color;
  const OkxTitle(this.text, {super.key, this.size = 20, this.color = OkeyXColors.cream});

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(fontFamily: OkeyXFonts.serif, fontWeight: FontWeight.w700, fontSize: size, color: color, height: 1.1),
      );
}

/// Sayı sayarak değişen metin (bakiye, puan).
class OkxCountText extends StatelessWidget {
  final int value;
  final TextStyle style;
  final String Function(int) format;
  final Duration duration;
  const OkxCountText({super.key, required this.value, required this.style, required this.format, this.duration = const Duration(milliseconds: 900)});

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(end: value.toDouble()),
        duration: duration,
        curve: Curves.easeOutCubic,
        builder: (context, v, _) => Text(format(v.round()), style: style),
      );
}

/// Türkçe binlik ayırıcılı sayı.
String okxFormat(int n) {
  final neg = n < 0;
  final s = n.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return neg ? '-$b' : b.toString();
}

/// Kısa gösterim: 1.12M, 48K.
String okxShort(int n) {
  final a = n.abs();
  if (a >= 1000000) return '${(n / 1000000).toStringAsFixed(a >= 10000000 ? 1 : 2).replaceAll(RegExp(r'\.?0+$'), '')}M';
  if (a >= 10000) return '${(n / 1000).round()}K';
  return okxFormat(n);
}
