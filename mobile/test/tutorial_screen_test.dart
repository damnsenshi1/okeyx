import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyx_mobile/features/tutorial/tutorial_screen.dart';

void main() {
  testWidgets('öğretici adımlar ilerler ve soru cevaplanmadan geçilmez', (tester) async {
    tester.view.physicalSize = const Size(1600, 800);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    var practiced = false;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => TutorialScreen(onPractice: () => practiced = true),
              )),
              child: const Text('aç'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('aç'));
    await tester.pumpAndSettle();
    expect(find.text('ÖĞRETİCİ MASA'), findsOneWidget);
    expect(find.text('1/9'), findsOneWidget);

    // Adım 1 soru içermez -> DEVAM
    await tester.tap(find.text('DEVAM'));
    await tester.pumpAndSettle();
    expect(find.text('2/9'), findsOneWidget);

    // Adım 2 soru içerir: cevap verilmeden DEVAM pasif
    final devam = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'DEVAM'));
    expect(devam.onPressed, isNull);
    await tester.tap(find.text('EVET'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Doğru!'), findsOneWidget);

    // Son adıma kadar ilerle (sorularda HAYIR/EVET fark etmez)
    for (var i = 0; i < 7; i++) {
      final yes = find.text('EVET');
      if (yes.evaluate().isNotEmpty) {
        final btn = tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'EVET'));
        if (btn.onPressed != null) {
          await tester.tap(yes);
          await tester.pumpAndSettle();
        }
      }
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
    }
    expect(find.text('9/9'), findsOneWidget);
    await tester.tap(find.text('ANTRENMANA BAŞLA'));
    await tester.pumpAndSettle();
    expect(practiced, isTrue);
    expect(tester.takeException(), isNull);
  });
}
