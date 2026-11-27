import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyx_mobile/widgets/real_rack.dart';
import 'package:okeyx_mobile/widgets/tile_widget.dart';

/// Görsel kontrol: CI'da `--update-goldens` ile PNG üretir (ıstaka kaplamaları).
Future<void> _loadFonts() async {
  for (final f in const [
    ('ArchivoBlack', 'assets/fonts/ArchivoBlack-Regular.ttf'),
    ('Montserrat', 'assets/fonts/Montserrat-Black.ttf'),
  ]) {
    final loader = FontLoader(f.$1)..addFont(rootBundle.load(f.$2));
    await loader.load();
  }
}

Widget _row(List<(int, int)> tiles) => Row(children: [
      for (final t in tiles)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: .5),
          child: AspectRatio(aspectRatio: .68, child: TileWidget(tile: GameTile(id: 't${t.$1}-${t.$2}', number: t.$1, colorIndex: t.$2))),
        ),
    ]);

void main() {
  testWidgets('ıstaka kaplamaları görsel', (tester) async {
    if (!Platform.environment.containsKey('OKEYX_GOLDENS')) return;
    await _loadFonts();
    tester.view.physicalSize = const Size(1100, 900);
    tester.view.devicePixelRatio = 1;
    const styles = ['honey', 'walnut', 'velvet', 'neon'];
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF7A1F22),
        body: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            for (final s in styles)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: SizedBox(
                  width: 1000,
                  child: AspectRatio(
                    aspectRatio: RealRackGeometry.aspect,
                    child: RealRack(
                      style: s,
                      active: s == 'honey',
                      row0: _row(const [(11, 1), (12, 1), (13, 1), (7, 1), (8, 1), (9, 1)]),
                      row1: _row(const [(8, 3), (9, 0), (13, 0), (11, 2), (1, 1), (5, 1), (7, 1), (1, 0), (2, 0), (5, 0), (7, 0), (10, 0), (11, 0)]),
                    ),
                  ),
                ),
              ),
          ]),
        ),
      ),
    ));
    await tester.runAsync(() async {
      final ctx = tester.element(find.byType(Scaffold));
      for (final a in const ['assets/textures/walnut.jpg', 'assets/tiles/blank_ivory.webp']) {
        await precacheImage(AssetImage(a), ctx);
      }
    });
    await tester.pumpAndSettle();
    await expectLater(find.byType(Scaffold), matchesGoldenFile('goldens/racks.png'));
  });
}
