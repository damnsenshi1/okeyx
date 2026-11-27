import 'package:flutter/material.dart';

/// Blender ile işlenmiş iki katlı gerçek ıstaka. Üç katman halinde çizilir:
/// arka pano → üst sıra taşları → orta dudak → alt sıra taşları → ön dudak.
/// Böylece taşların alt kenarı ahşap dudakların arkasında kalır ve taşlar
/// ıstakaya gerçekten oturmuş görünür.
///
/// Konumlar `rack_geo.json` çıktısından alınmıştır (görüntü oranları).
class RealRackGeometry {
  static const double row0Top = .150, row0Bottom = .474;
  static const double row1Top = .540, row1Bottom = .864;
  static const double left = .024, right = .976;
  static const double aspect = 1600 / 420;
}

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
  };
  final e = (equipped ?? '').trim();
  if (cosmetic.containsKey(e)) return cosmetic[e]!;
  return switch (local) {
    'oak' => 'classic',
    'ebony' => 'obsidian',
    _ => 'walnut',
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

  String _a(String layer) => 'assets/rack/rack_${style}_$layer.webp';

  Widget _layer(String layer) => IgnorePointer(
        child: Image.asset(
          _a(layer),
          fit: BoxFit.fill,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, __, ___) => layer == 'back'
              ? DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFF6B3D1E), Color(0xFF3A1F0E)],
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      );

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth, h = c.maxHeight;
        Rect row(double top, double bottom) => Rect.fromLTRB(w * RealRackGeometry.left, h * top, w * RealRackGeometry.right, h * bottom);
        final r0 = row(RealRackGeometry.row0Top, RealRackGeometry.row0Bottom);
        final r1 = row(RealRackGeometry.row1Top, RealRackGeometry.row1Bottom);
        return Stack(clipBehavior: Clip.none, children: [
          Positioned.fill(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  const BoxShadow(color: Color(0x99000000), blurRadius: 22, offset: Offset(0, 12)),
                  if (active) const BoxShadow(color: Color(0x80FFC24A), blurRadius: 26, spreadRadius: 2),
                ],
              ),
            ),
          ),
          Positioned.fill(child: _layer('back')),
          Positioned.fromRect(rect: r0, child: row0),
          Positioned.fill(child: _layer('mid')),
          Positioned.fromRect(rect: r1, child: row1),
          Positioned.fill(child: _layer('front')),
        ]);
      });
}
