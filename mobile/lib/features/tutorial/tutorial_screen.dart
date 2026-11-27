import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../widgets/tile_widget.dart';
import '../../widgets/okx_kit.dart';

/// Yeni oyuncular için öğretici masa: kuralları taş görselleriyle anlatır,
/// her adımda küçük bir "geçerli mi?" sorusu sorar. Sonunda antrenman masasına
/// yönlendirir.
class TutorialScreen extends StatefulWidget {
  final VoidCallback? onPractice;
  const TutorialScreen({super.key, this.onPractice});

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

class _Step {
  final String title;
  final String body;
  final List<GameTile> tiles;
  final String? question;
  final bool? answer;
  final String explain;
  const _Step(this.title, this.body, this.tiles, {this.question, this.answer, this.explain = ''});
}

GameTile _t(int n, int c, {bool joker = false, bool fake = false}) =>
    GameTile(id: 'tut-$n-$c-$joker-$fake', number: n, colorIndex: c, isJoker: joker, isFakeJoker: fake);

const _red = 0, _blue = 1, _black = 2, _yellow = 3;

final _steps = <_Step>[
  _Step('106 taş, 4 renk',
      'Her renkte 1–13 arası ikişer taş ve 2 sahte okey vardır. Masada herkes taş çeker, bir taş atar.',
      [_t(1, _red), _t(5, _blue), _t(9, _black), _t(13, _yellow), _t(0, 0, fake: true)]),
  _Step('Gösterge ve okey',
      'Ortadaki gösterge taşının bir fazlası OKEY olur ve her taşın yerine geçer. Sahte okey, okeyin kendisi gibi sayılır.',
      [_t(6, _blue), _t(7, _blue, joker: true)],
      question: 'Gösterge mavi 6 ise okey mavi 7 midir?', answer: true,
      explain: 'Evet. Göstergenin aynı renkte bir fazlası okeydir (13 ise 1 olur).'),
  _Step('Seri (sıralı per)',
      'Aynı renkte ardışık en az 3 taş bir seri oluşturur.',
      [_t(4, _red), _t(5, _red), _t(6, _red), _t(7, _red)],
      question: 'Kırmızı 12-13-1 geçerli bir seri mi?', answer: false,
      explain: '13’ten sonra 1’e dönülemez. 12-13-1 geçersizdir.'),
  _Step('Grup (aynı sayı)',
      'Aynı sayıda, FARKLI renklerden 3 veya 4 taş bir grup olur.',
      [_t(8, _red), _t(8, _blue), _t(8, _black)],
      question: 'Kırmızı 8, kırmızı 8, mavi 8 geçerli bir grup mu?', answer: false,
      explain: 'Grupta aynı renk iki kez olamaz.'),
  _Step('101 ile açma',
      '101 Okey’de elini açmak için perlerinin toplamı en az 101 olmalı. Katlamalı modda her açılış bir öncekini geçmeli.',
      [_t(11, _yellow), _t(12, _yellow), _t(13, _yellow), _t(10, _red), _t(10, _blue), _t(10, _black)],
      question: '11+12+13 ve üç tane 10 = 66. Açabilir misin?', answer: false,
      explain: '66 < 101. Daha fazla per toplaman gerekir.'),
  _Step('Çift açma',
      'Alternatif olarak en az 5 çift (aynı renk, aynı sayı) ile açabilirsin. Çift açanın cezaları iki katıdır.',
      [_t(3, _red), _t(3, _red), _t(9, _blue), _t(9, _blue)]),
  _Step('İşleme ve cezalar',
      'Açtıktan sonra masadaki perlere taş işleyebilirsin. İşlenebilecek taşı ya da okeyi atarsan +101 ceza yazılır. Soldan aldığın taşı o tur kullanmalısın.',
      [_t(5, _black), _t(6, _black), _t(7, _black), _t(8, _black)],
      question: 'Masada siyah 5-6-7 varken elindeki siyah 8’i atmak ceza mı?', answer: true,
      explain: 'Evet. Siyah 8 o seriye işlenebilir; atarsan +101 ceza.'),
  _Step('Klasik Okey',
      'Klasik Okey’de 14 taşla oynanır ve masaya açma yoktur. 15. taşı ortaya kapatıp elindeki 14 taşın TAMAMINI per ya da 7 çift olarak dizersen BİTİR’e bas.',
      [_t(1, _blue), _t(2, _blue), _t(3, _blue), _t(7, _red), _t(7, _black), _t(7, _yellow)]),
  _Step('Bitiş ve puan',
      '101’de eli bitiren -101 yazar, diğerleri elinde kalan taşların toplamını. Okeyle ya da çiftle bitirmek puanları katlar. En düşük toplam kazanır.',
      [_t(0, 0, joker: true)]),
];

class _TutorialScreenState extends State<TutorialScreen> {
  int _index = 0;
  bool? _picked;
  int _correct = 0;

  _Step get _step => _steps[_index];
  bool get _last => _index == _steps.length - 1;

  void _answer(bool value) {
    if (_picked != null) return;
    setState(() {
      _picked = value;
      if (value == _step.answer) _correct++;
    });
  }

  void _next() {
    if (_last) {
      Navigator.of(context).pop();
      widget.onPractice?.call();
      return;
    }
    setState(() {
      _index++;
      _picked = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final step = _step;
    final quiz = step.question != null;
    final canContinue = !quiz || _picked != null;
    return Scaffold(
      backgroundColor: OkeyXColors.ink,
      body: OkxRoom(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: Column(
            children: [
              Row(children: [
                IconButton(
                  tooltip: 'Kapat',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                ),
                const SizedBox(width: 4),
                const Text('ÖĞRETİCİ MASA', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2, color: OkeyXColors.gold)),
                const Spacer(),
                Text('${_index + 1}/${_steps.length}', style: const TextStyle(color: Colors.white60, fontWeight: FontWeight.w800)),
              ]),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  height: 4,
                  child: LinearProgressIndicator(
                    value: (_index + 1) / _steps.length,
                    backgroundColor: Colors.white12,
                    color: OkeyXColors.ruby,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      flex: 5,
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(step.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)),
                            const SizedBox(height: 6),
                            Text(step.body, style: const TextStyle(fontSize: 13, height: 1.35, color: Colors.white70)),
                            if (quiz) ...[
                              const SizedBox(height: 10),
                              Text(step.question!, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: OkeyXColors.gold)),
                              const SizedBox(height: 6),
                              Row(children: [
                                _choice('EVET', true),
                                const SizedBox(width: 8),
                                _choice('HAYIR', false),
                              ]),
                              if (_picked != null) ...[
                                const SizedBox(height: 6),
                                Text(
                                  '${_picked == step.answer ? 'Doğru! ' : 'Yanlış. '}${step.explain}',
                                  style: TextStyle(fontSize: 12, color: _picked == step.answer ? const Color(0xFF7CF0B0) : const Color(0xFFFF9C8A)),
                                ),
                              ],
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 5,
                      child: Center(
                        child: OkxLeather(
                          radius: 16,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                          child: Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 5,
                            runSpacing: 6,
                            children: [
                              for (final tile in step.tiles)
                                SizedBox(width: 38, height: 54, child: TileWidget(tile: tile)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Row(children: [
                if (_index > 0)
                  TextButton(
                    onPressed: () => setState(() {
                      _index--;
                      _picked = null;
                    }),
                    child: const Text('GERİ'),
                  ),
                const Spacer(),
                if (_last)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Text('Doğru cevap: $_correct', style: const TextStyle(color: Colors.white60)),
                  ),
                FilledButton(
                  onPressed: canContinue ? _next : null,
                  style: FilledButton.styleFrom(backgroundColor: OkeyXColors.gold, foregroundColor: const Color(0xFF241500)),
                  child: Text(_last ? 'ANTRENMANA BAŞLA' : 'DEVAM', style: const TextStyle(fontWeight: FontWeight.w900)),
                ),
              ]),
            ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _choice(String label, bool value) {
    final picked = _picked == value;
    return OutlinedButton(
      onPressed: _picked == null ? () => _answer(value) : null,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: BorderSide(color: picked ? OkeyXColors.ruby : Colors.white30, width: picked ? 2 : 1),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
    );
  }
}
