import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../lobby/lobby_api.dart';

/// Yönetici paneli • Market ve ekonomi:
/// mağaza ürün fiyatları/indirim/gizle, altın-elmas paketleri, masa
/// komisyonu, çanak oranı, hoş geldin altını, şans oyunları RTP (85–97 arası,
/// oyunculara gösterilen oran = gerçek oran) ve gerçekleşen RTP raporu,
/// hazır etkinlik şablonları. Her değişiklik kayıt defterine yazılır.
class StaffMarketTab extends StatefulWidget {
  const StaffMarketTab({super.key, required this.api});
  final LobbyApiClient api;

  @override
  State<StaffMarketTab> createState() => _StaffMarketTabState();
}

class _StaffMarketTabState extends State<StaffMarketTab> {
  Map<String, dynamic> _data = const {};
  bool _loading = true;
  String _section = 'store';
  String _category = 'rack';
  final Map<String, double> _rtp = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final d = await widget.api.staffMarket();
      if (!mounted) return;
      final games = _m(d['side_games']);
      setState(() {
        _data = d;
        _loading = false;
        for (final e in games.entries) {
          _rtp[e.key] = _d(_m(e.value)['rtp_percent'], 90);
        }
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      _toast('Market verisi alınamadı (yetki ya da bağlantı).');
    }
  }

  void _toast(String s) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(s)));
  }

  Future<void> _patch(String kind, String target, Map<String, dynamic> patch, String ok) async {
    try {
      final out = await widget.api.staffPatch(kind, target, patch);
      _toast(out['ok'] == true ? ok : 'Kaydedilemedi: ${out['code'] ?? 'hata'}');
      await _load();
    } catch (_) {
      _toast('Kaydedilemedi (yetki ya da bağlantı).');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _data.isEmpty) return const Center(child: CircularProgressIndicator());
    return Column(children: [
      Wrap(spacing: 6, runSpacing: 6, children: [
        _seg('store', Icons.storefront_rounded, 'MAĞAZA'),
        _seg('packs', Icons.paid_rounded, 'PAKETLER'),
        _seg('economy', Icons.account_balance_rounded, 'EKONOMİ'),
        _seg('rtp', Icons.casino_rounded, 'RTP'),
        _seg('events', Icons.celebration_rounded, 'ETKİNLİK ŞABLONU'),
        _seg('log', Icons.history_rounded, 'DEĞİŞİKLİK KAYDI'),
      ]),
      const SizedBox(height: 10),
      Expanded(
        child: switch (_section) {
          'store' => _store(),
          'packs' => _packs(),
          'economy' => _economy(),
          'rtp' => _rtpView(),
          'events' => _events(),
          _ => _log(),
        },
      ),
    ]);
  }

  Widget _seg(String id, IconData icon, String label) {
    final on = _section == id;
    return GestureDetector(
      onTap: () => setState(() => _section = id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          gradient: on ? const LinearGradient(colors: [Color(0xFFFFD54A), Color(0xFFFF8A3D)]) : null,
          color: on ? null : const Color(0x22FFFFFF),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: on ? const Color(0xFF1A0F3D) : Colors.white70),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: on ? const Color(0xFF1A0F3D) : Colors.white70)),
        ]),
      ),
    );
  }

  // ───────── Mağaza (kozmetik) ─────────
  Widget _store() {
    final items = _l(_data['cosmetics']).map(_m).toList();
    final cats = <String>{for (final i in items) '${i['category']}'}.toList();
    if (!cats.contains(_category) && cats.isNotEmpty) _category = cats.first;
    const names = {'rack': 'Istaka', 'tiles': 'Taş', 'cloth': 'Çuha', 'frame': 'Çerçeve', 'avatar': 'Avatar', 'emote': 'Emoji', 'title': 'Unvan'};
    final rows = items.where((i) => '${i['category']}' == _category).toList();
    return Column(children: [
      SizedBox(
        height: 34,
        child: ListView(scrollDirection: Axis.horizontal, children: [
          for (final c in cats)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(label: Text(names[c] ?? c), selected: _category == c, onSelected: (_) => setState(() => _category = c)),
            ),
        ]),
      ),
      const SizedBox(height: 8),
      Expanded(
        child: ListView(children: [
          for (final i in rows)
            _card(Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${i['name']}${i['store_hidden'] == true ? '  (gizli)' : ''}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(
                    '${_fmt(_i(i['price']))} ${i['currency'] == 'diamonds' ? 'elmas' : 'altın'}'
                    '${_i(i['discount_percent']) > 0 ? '  •  %${_i(i['discount_percent'])} indirim → ${_fmt((_i(i['price']) * (100 - _i(i['discount_percent'])) / 100).round())}' : ''}  •  ${i['rarity'] ?? ''}',
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                ]),
              ),
              FilledButton.tonal(onPressed: () => _editCosmetic(i), child: const Text('DÜZENLE')),
            ])),
        ]),
      ),
    ]);
  }

  Future<void> _editCosmetic(Map<String, dynamic> i) async {
    final price = TextEditingController(text: '${_i(i['price'])}');
    final discount = TextEditingController(text: '${_i(i['discount_percent'])}');
    var currency = '${i['currency'] ?? 'coins'}';
    var hidden = i['store_hidden'] == true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text('${i['name']}'),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Fiyat')),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [ButtonSegment(value: 'coins', label: Text('Altın')), ButtonSegment(value: 'diamonds', label: Text('Elmas'))],
                selected: {currency},
                onSelectionChanged: (v) => set(() => currency = v.first),
              ),
              const SizedBox(height: 8),
              TextField(controller: discount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'İndirim % (0–90)')),
              SwitchListTile(value: hidden, onChanged: (v) => set(() => hidden = v), title: const Text('Mağazada gizle')),
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Kaydet'))],
        ),
      ),
    );
    if (ok == true) {
      await _patch('cosmetic', '${i['id']}', {'price': int.tryParse(price.text.trim()) ?? _i(i['price']), 'currency': currency, 'discount_percent': int.tryParse(discount.text.trim()) ?? 0, 'store_hidden': hidden}, 'Ürün güncellendi.');
    }
    price.dispose();
    discount.dispose();
  }

  // ───────── Paketler (uygulama içi satın alma) ─────────
  Widget _packs() {
    final rows = _l(_data['products']).map(_m).toList();
    return ListView(children: [
      _note('Gerçek para fiyatı Google Play Console\'dan değişir. Buradan paketin içeriğini (altın/elmas), başlığını, rozetini, gösterilen fiyat yazısını ve satışta olup olmadığını değiştirirsin.'),
      for (final p in rows)
        _card(Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${p['title']}${p['enabled'] == false ? '  (satışta değil)' : ''}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
              Text('${_fmt(_i(p['coins']))} altın • ${_i(p['diamonds'])} elmas • ${p['price_hint'] ?? ''} • ${p['sku']}', style: const TextStyle(fontSize: 12, color: Colors.white70)),
            ]),
          ),
          FilledButton.tonal(onPressed: () => _editPack(p), child: const Text('DÜZENLE')),
        ])),
    ]);
  }

  Future<void> _editPack(Map<String, dynamic> p) async {
    final title = TextEditingController(text: '${p['title'] ?? ''}');
    final coins = TextEditingController(text: '${_i(p['coins'])}');
    final diamonds = TextEditingController(text: '${_i(p['diamonds'])}');
    final badge = TextEditingController(text: '${p['value_label'] ?? ''}');
    final hint = TextEditingController(text: '${p['price_hint'] ?? ''}');
    var enabled = p['enabled'] != false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text('${p['sku']}'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: title, decoration: const InputDecoration(labelText: 'Başlık')),
                TextField(controller: coins, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Altın')),
                TextField(controller: diamonds, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Elmas')),
                TextField(controller: badge, decoration: const InputDecoration(labelText: 'Rozet (ör. EN İYİ DEĞER)')),
                TextField(controller: hint, decoration: const InputDecoration(labelText: 'Gösterilen fiyat yazısı (ör. ₺49,90)')),
                SwitchListTile(value: enabled, onChanged: (v) => set(() => enabled = v), title: const Text('Satışta')),
              ]),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Kaydet'))],
        ),
      ),
    );
    if (ok == true) {
      await _patch('product', '${p['sku']}', {'title': title.text, 'coins': int.tryParse(coins.text.trim()) ?? _i(p['coins']), 'diamonds': int.tryParse(diamonds.text.trim()) ?? _i(p['diamonds']), 'value_label': badge.text, 'price_hint': hint.text, 'enabled': enabled}, 'Paket güncellendi.');
    }
    for (final c in [title, coins, diamonds, badge, hint]) {
      c.dispose();
    }
  }

  // ───────── Ekonomi ─────────
  Widget _economy() {
    final e = _m(_data['economy']);
    var commission = _d(e['commission_percent'], 15);
    var canak = _d(e['canak_percent'], 10);
    final welcome = TextEditingController(text: '${_i(e['welcome_chips'])}');
    return StatefulBuilder(
      builder: (context, set) => ListView(children: [
        _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Masa komisyonu: %${commission.round()}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          const Text('Kazananın net kazancından kesilen ev payı.', style: TextStyle(fontSize: 12, color: Colors.white60)),
          Slider(value: commission, min: 0, max: 30, divisions: 30, label: '%${commission.round()}', onChanged: (v) => set(() => commission = v)),
          const SizedBox(height: 8),
          Text('Çanak payı: giriş bedelinin %${canak.round()}\'i', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          const Text('Her el başında her gerçek oyuncunun çanağa koyduğu. 0 = çanak kapalı.', style: TextStyle(fontSize: 12, color: Colors.white60)),
          Slider(value: canak, min: 0, max: 50, divisions: 50, label: '%${canak.round()}', onChanged: (v) => set(() => canak = v)),
          const SizedBox(height: 8),
          TextField(controller: welcome, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Yeni oyuncu hoş geldin altını')),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              icon: const Icon(Icons.save_rounded),
              onPressed: () => _patch('economy', '', {'commission_percent': commission.round(), 'canak_percent': canak.round(), 'welcome_chips': int.tryParse(welcome.text.trim()) ?? _i(e['welcome_chips'])}, 'Ekonomi ayarları kaydedildi.'),
              label: const Text('KAYDET'),
            ),
          ),
        ])),
      ]),
    );
  }

  // ───────── RTP ─────────
  Widget _rtpView() {
    final games = _m(_data['side_games']);
    final real = _m(_data['realized_rtp']);
    final bounds = _l(_data['rtp_bounds']);
    final lo = bounds.length == 2 ? _d(bounds[0], 85) : 85.0;
    final hi = bounds.length == 2 ? _d(bounds[1], 97) : 97.0;
    return ListView(children: [
      _note('Oran %${lo.round()}–%${hi.round()} arasında ayarlanır. Oyunculara oyun ekranında gösterilen oran her zaman burada seçilen gerçek orandır. "Gerçekleşen" son 2000 oyunun sonucudur.'),
      for (final e in games.entries)
        _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('${_m(e.value)['title'] ?? e.key}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
            Text('%${(_rtp[e.key] ?? 90).toStringAsFixed(1)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: OkeyXColors.gold)),
          ]),
          Text(_realLine(_m(real[e.key])), style: const TextStyle(fontSize: 12, color: Colors.white60)),
          Slider(value: (_rtp[e.key] ?? 90).clamp(lo, hi), min: lo, max: hi, divisions: ((hi - lo) * 2).round(), onChanged: (v) => setState(() => _rtp[e.key] = v)),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonal(
              onPressed: () async {
                try {
                  final out = await widget.api.staffRtp(e.key, _rtp[e.key] ?? 90);
                  _toast(out['ok'] == true ? 'RTP güncellendi: %${out['rtp_percent']}' : 'Güncellenemedi: ${out['code']}');
                  await _load();
                } catch (_) {
                  _toast('Güncellenemedi.');
                }
              },
              child: const Text('UYGULA'),
            ),
          ),
        ])),
    ]);
  }

  String _realLine(Map<String, dynamic> r) {
    if (r.isEmpty || r['realized_percent'] == null) return 'Gerçekleşen: henüz veri yok';
    return 'Gerçekleşen: %${r['realized_percent']} • ${_i(r['rounds'])} oyun • ${_fmt(_i(r['wagered']))} yatırılan • ${_fmt(_i(r['paid']))} ödenen';
  }

  // ───────── Etkinlik şablonları ─────────
  Widget _events() {
    final templates = [
      ('Çift XP Hafta Sonu', 'Tüm maçlarda 2 kat XP', {'xp_multiplier': 2.0, 'reward_coins': 50000}, 48),
      ('Çanak 2 Katı', 'Kırılan çanak iki katı ödenir', {'canak_multiplier': 2.0, 'reward_coins': 25000}, 24),
      ('Şans Salonu Bonusu', 'Şans oyunu kazançlarına +%25', {'side_game_bonus_percent': 25, 'reward_coins': 25000}, 24),
      ('Hoş Geldin Festivali', 'Katılana 100.000 altın hediye', {'reward_coins': 100000, 'xp_multiplier': 1.5}, 72),
    ];
    return ListView(children: [
      _note('Şablona dokun, süre ve ödülü kontrol et, yayınla. Yayındaki etkinlikleri "RTP / ETKİNLİK" sekmesinden kaldırabilirsin.'),
      for (final t in templates)
        _card(Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.$1, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
              Text('${t.$2} • ${t.$4} saat', style: const TextStyle(fontSize: 12, color: Colors.white70)),
            ]),
          ),
          FilledButton(
            onPressed: () async {
              final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
              try {
                final out = await widget.api.staffUpsertEvent(title: t.$1, subtitle: t.$2, startsAt: now, endsAt: now + t.$4 * 3600, config: Map<String, dynamic>.from(t.$3));
                _toast(out['ok'] == true ? '"${t.$1}" yayında.' : 'Yayınlanamadı.');
              } catch (_) {
                _toast('Yayınlanamadı (yetki ya da bağlantı).');
              }
            },
            child: const Text('YAYINLA'),
          ),
        ])),
    ]);
  }

  // ───────── Kayıt ─────────
  Widget _log() {
    final rows = _l(_data['audit']).map(_m).toList();
    if (rows.isEmpty) return const Center(child: Text('Henüz değişiklik yok.'));
    return ListView(children: [
      for (final r in rows)
        _card(Row(children: [
          Expanded(child: Text('${r['action']}  •  ${r['item_id'] ?? r['sku'] ?? r['game'] ?? r['player_id'] ?? ''}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
          Text(_time(_i(r['created_at'])), style: const TextStyle(fontSize: 11.5, color: Colors.white54)),
        ])),
    ]);
  }

  Widget _card(Widget child) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: const LinearGradient(colors: [Color(0xCC2A1F6E), Color(0xCC15204F)]),
          border: Border.all(color: const Color(0x40B79CFF)),
        ),
        child: child,
      );

  Widget _note(String text) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: const Color(0x2233F2D0), border: Border.all(color: const Color(0x5533F2D0))),
        child: Text(text, style: const TextStyle(fontSize: 12, color: Color(0xFFBFFBF0))),
      );

  String _time(int sec) {
    if (sec <= 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(sec * 1000);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
  }
}

Map<String, dynamic> _m(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<dynamic> _l(dynamic v) => v is List ? v : const [];
int _i(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
double _d(dynamic v, double d) => v is num ? v.toDouble() : double.tryParse('$v') ?? d;
String _fmt(int v) => v.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
