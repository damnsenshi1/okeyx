import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyx_mobile/widgets/real_rack.dart';
import 'package:okeyx_mobile/widgets/tile_widget.dart';

void main() {
  test('kozmetik ve yerel tercih doğru ıstaka stiline eşlenir', () {
    expect(realRackStyle(equipped: 'rack_neon'), 'neon');
    expect(realRackStyle(equipped: 'rack_classic', local: 'oak'), 'classic');
    expect(realRackStyle(equipped: '', local: 'ebony'), 'obsidian');
    expect(realRackStyle(equipped: 'rack_bilinmeyen'), 'walnut');
  });

  test('taş gövdesi varlık yolu bilinen kaplamalara eşlenir', () {
    expect(TileWidget.bodyAsset('tiles_marble'), 'assets/tiles/blank_marble.webp');
    expect(TileWidget.bodyAsset('tiles_classic'), 'assets/tiles/blank_ivory.webp');
  });

  testWidgets('ıstaka iki sırayı katmanlar arasında çizer, taşma yok', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 480,
            height: 126,
            child: RealRack(
              style: 'walnut',
              active: true,
              row0: ColoredBox(key: ValueKey('r0'), color: Colors.red),
              row1: ColoredBox(key: ValueKey('r1'), color: Colors.blue),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    final r0 = tester.getRect(find.byKey(const ValueKey('r0')));
    final r1 = tester.getRect(find.byKey(const ValueKey('r1')));
    expect(r0.bottom, lessThan(r1.top));
    expect(tester.takeException(), isNull);
  });

  testWidgets('işlenebilir taş ve turbo yıldızı rakamı kapatmadan çizilir', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 40,
            height: 60,
            child: TileWidget(tile: GameTile(id: 's', number: 11, colorIndex: 1, useful: true, turboStar: true)),
          ),
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('11'), findsOneWidget);
    expect(find.byIcon(Icons.star_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
