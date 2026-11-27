import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyx_mobile/widgets/tile_widget.dart';

void main() {
  testWidgets('taş sayısı görünür ve taşma olmaz', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 40,
            height: 56,
            child: TileWidget(tile: GameTile(id: 't1', number: 7, colorIndex: 0)),
          ),
        ),
      ),
    ));
    expect(find.text('7'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('çok küçük alanda da hata vermez', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 18,
            height: 26,
            child: TileWidget(tile: GameTile(id: 't2', number: 13, colorIndex: 3)),
          ),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
  });

  test('copyWith yüzü değiştirir, kimliği korur', () {
    const tile = GameTile(id: 'x', number: 5, colorIndex: 1);
    final down = tile.copyWith(faceDown: true);
    expect(down.id, 'x');
    expect(down.faceDown, isTrue);
    expect(down.number, 5);
  });
}
