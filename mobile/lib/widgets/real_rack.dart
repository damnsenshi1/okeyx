import 'package:flutter/material.dart';

/// Blender ile işlenmiş iki katlı gerçek ıstaka. Üç katman halinde çizilir:
/// arka pano → üst sıra taşları → orta dudak → alt sıra taşları → ön dudak.
/// Böylece taşların alt kenarı ahşap dudakların arkasında kalır ve taşlar
/// ıstakaya gerçekten oturmuş görünür.
///
/// Konumlar `rack_geo.json` çıktısından alınmıştır (görüntü oranları).
class RealRackGeometry {
  // Düz (önden) ıstaka: her sıranın altında bir raf. Taşın alt %6'sı rafın
  // arkasında kalır, böylece taş rafa oturmuş görünür.
  static const double row0Top = .055, row0Bottom = .455;
  static const double row1Top = .525, row1Bottom = .925;
  static const double left = .018, right = .982;
  static const double aspect = 5.4;
  static const double ledgeH = .085;
}

/// Istaka kaplaması: tahta dokusu rengi ve raf renkleri.
class _RackSkin {
  const _RackSkin(this.filter, this.ledgeTop, this.ledgeBottom, this.edge, {this.texture = true, this.flat});
  final ColorFilter? filter;
  final Color ledgeTop, ledgeBottom, edge;
  final bool texture;
  final Color? flat;
}

ColorFilter _mul(double r, double g, double b, {double add = 0, double sat = 1}) {
  final s = sat, i = 1 - s;
  const lr = .2126, lg = .7152, lb = .0722;
  return ColorFilter.matrix(<double>[
    (lr * i + s) * r, lg * i * r, lb * i * r, 0, add,
    lr * i * g, (lg * i + s) * g, lb * i * g, 0, add,
    lr * i * b, lg * i * b, (lb * i + s) * b, 0, add,
    0, 0, 0, 1, 0,
  ]);
}

_RackSkin _skinFor(String style) => switch (style) {
      'walnut' => _RackSkin(_mul(.78, .62, .5), const Color(0xFF8A5530), const Color(0xFF3E200E), const Color(0xFF2A1408)),
      'velvet' => const _RackSkin(null, Color(0xFFB9BCC2), Color(0xFF6F737B), Color(0xFF2E3036), texture: false, flat: Color(0xFF9A9DA5)),
      'sakura' => _RackSkin(_mul(1.15, .78, .85, add: 18, sat: .7), const Color(0xFFF2B8C6), const Color(0xFFB0647A), const Color(0xFF7A3A4C)),
      'bosphorus' => _RackSkin(_mul(.45, .95, 1.0, sat: .55), const Color(0xFF4FC9C4), const Color(0xFF136B6E), const Color(0xFF0B3F42)),
      'obsidian' => _RackSkin(_mul(.32, .32, .36, sat: .2), const Color(0xFF55555E), const Color(0xFF1A1A1F), const Color(0xFF0A0A0D)),
      'neon' => _RackSkin(_mul(.35, .3, .75, sat: .4), const Color(0xFF7B5CFF), const Color(0xFF2A1A6E), const Color(0xFF00E5FF)),
      'royal' => _RackSkin(_mul(.95, .45, .35, sat: .9), const Color(0xFFF4CB6A), const Color(0xFFA0661E), const Color(0xFF5A0E12)),
      'ice' => _RackSkin(_mul(.85, 1.05, 1.2, add: 30, sat: .25), const Color(0xFFE8F6FF), const Color(0xFF8FB8D6), const Color(0xFF5E86A6)),
      'ember' => _RackSkin(_mul(1.1, .45, .25, sat: .9), const Color(0xFFFF9A4A), const Color(0xFF8A2A0E), const Color(0xFF3E0E04)),
      'marble' => const _RackSkin(null, Color(0xFFF4F2EE), Color(0xFFB9B5AD), Color(0xFF8C887F), texture: false, flat: Color(0xFFE2DED6)),
      'classic' => _RackSkin(_mul(1.05, .82, .58, add: 10), const Color(0xFFF2B866), const Color(0xFFB0661F), const Color(0xFF6A3A12)),
      // Varsayılan: açık bal rengi ahşap (klasik kahvehane ıstakası)
      _ => _RackSkin(_mul(1.25, .92, .6, add: 24, sat: 1.05), const Color(0xFFFFCF7A), const Color(0xFFC07420), const Color(0xFF7A4412)),
    };

/// Kozmetik ya da yerel tercih kimliğini işlenmiş ıstaka stiline çevirir.
/// Sunucu `loadout['rack']` değerini yalnızca sahip olunan eşyalar için
/// gönderir; varsayılan (rack_classic) ise yerel Ayarlar tercihi kullanılır.
String realRackStyle({String? equipped, String local = 'walnut'}) {
  const cosmetic = {
    'rack_walnut': 'walnut',
    'rack_sakura': 'sakura',
    'rack_bosphorus': 'bosphorus',
    'rack_obsidian': 'obsidian',
    'rack_neon': 'neon',
    'rack_royal': 'royal',
    'rack_ice': 'ice',
    'rack_ember': 'ember',
    'rack_marble': 'marble',
    'rack_velvet': 'velvet',
  };
  final e = (equipped ?? '').trim();
  if (cosmetic.containsKey(e)) return cosmetic[e]!;
  return switch (local) {
    'oak' => 'classic',
    'ebony' => 'obsidian',
    'walnut_wood' => 'walnut',
    'velvet' => 'velvet',
    // Varsayılan: açık bal rengi ahşap.
    _ => 'honey',
  };
}

class RealRack extends StatelessWidget {
  const RealRack({
    super.key,
    required this.style,
    required this.row0,
    required this.row1,
    this.active = false,
  });

  final String style;
  final Widget row0;
  final Widget row1;

  /// Sıra bende: ıstakanın arkasında yumuşak altın ışık.
  final bool active;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth, h = c.maxHeight;
        final skin = _skinFor(style);
        Rect row(double top, double bottom) => Rect.fromLTRB(w * RealRackGeometry.left, h * top, w * RealRackGeometry.right, h * bottom);
        final r0 = row(RealRackGeometry.row0Top, RealRackGeometry.row0Bottom);
        final r1 = row(RealRackGeometry.row1Top, RealRackGeometry.row1Bottom);
        final lh = h * RealRackGeometry.ledgeH;
        Widget ledge(double bottom) => Positioned(
              left: 0,
              right: 0,
              top: h * bottom - lh * .55,
              height: lh,
              child: IgnorePointer(child: _Ledge(skin: skin)),
            );
        return Stack(clipBehavior: Clip.none, children: [
          // Gölge + sıra bende ışığı
          Positioned.fill(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  const BoxShadow(color: Color(0xAA000000), blurRadius: 20, offset: Offset(0, 10)),
                  if (active) const BoxShadow(color: Color(0x90FFC24A), blurRadius: 26, spreadRadius: 2),
                ],
              ),
            ),
          ),
          // Pano
          Positioned.fill(child: IgnorePointer(child: _Board(skin: skin))),
          Positioned.fromRect(rect: r0, child: row0),
          ledge(RealRackGeometry.row0Bottom),
          Positioned.fromRect(rect: r1, child: row1),
          ledge(RealRackGeometry.row1Bottom),
        ]);
      });
}

class _Board extends StatelessWidget {
  const _Board({required this.skin});
  final _RackSkin skin;

  @override
  Widget build(BuildContext context) {
    Widget base = skin.texture
        ? Image.asset('assets/textures/walnut.jpg', fit: BoxFit.cover, repeat: ImageRepeat.repeatX, filterQuality: FilterQuality.medium, gaplessPlayback: true,
            errorBuilder: (_, __, ___) => ColoredBox(color: skin.ledgeBottom))
        : DecoratedBox(
            decoration: BoxDecoration(
              color: skin.flat,
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color.lerp(skin.flat, Colors.white, .08)!, skin.flat!, Color.lerp(skin.flat, Colors.black, .12)!]),
            ),
          );
    if (skin.filter != null) base = ColorFiltered(colorFilter: skin.filter!, child: base);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(fit: StackFit.expand, children: [
        base,
        // Üstten ışık, alta doğru hafif gölge (pano hafif içe eğik)
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x33FFFFFF), Color(0x00FFFFFF), Color(0x26000000)], stops: [0, .45, 1]),
          ),
        ),
        // Kenar çerçevesi
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: skin.edge.withValues(alpha: .9), width: 2),
          ),
        ),
        // Uç kapakları (sol/sağ)
        Align(alignment: Alignment.centerLeft, child: FractionallySizedBox(widthFactor: .012, heightFactor: 1, child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(colors: [skin.edge, skin.ledgeBottom]))))),
        Align(alignment: Alignment.centerRight, child: FractionallySizedBox(widthFactor: .012, heightFactor: 1, child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(colors: [skin.ledgeBottom, skin.edge]))))),
        // Pano üzerinde silik logo
        const Align(
          alignment: Alignment(0, -.62),
          child: Opacity(
            opacity: .10,
            child: Text('OKEYX', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: 8, color: Colors.black)),
          ),
        ),
      ]),
    );
  }
}

/// Taşların oturduğu raf: üst yüzü aydınlık, ön yüzü koyu, altına gölge düşer.
class _Ledge extends StatelessWidget {
  const _Ledge({required this.skin});
  final _RackSkin skin;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color.lerp(skin.ledgeTop, Colors.white, .25)!, skin.ledgeTop, skin.ledgeBottom, Color.lerp(skin.ledgeBottom, Colors.black, .35)!],
            stops: const [0, .22, .7, 1],
          ),
          boxShadow: const [BoxShadow(color: Color(0x88000000), blurRadius: 6, offset: Offset(0, 4))],
        ),
      );
}
