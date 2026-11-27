import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_theme.dart';
import '../lobby/lobby_api.dart';

/// Yönetici paneli • Sistem testi: sunucuda botlarla yüzlerce maç oynatır,
/// her hamlede kuralları denetler; veritabanı, masa kaydı ve anlık bildirimi
/// dener. Hata çıkarsa "KOPYALA" ile rapor alınıp geliştiriciye iletilir.
class StaffSelfTestTab extends StatefulWidget {
  const StaffSelfTestTab({super.key, required this.api});
  final LobbyApiClient api;

  @override
  State<StaffSelfTestTab> createState() => _StaffSelfTestTabState();
}

class _StaffSelfTestTabState extends State<StaffSelfTestTab> {
  int _games = 200;
  bool _push = true;
  bool _running = false;
  int _progress = 0;
  int _total = 0;
  Map<String, dynamic>? _result;
  String _error = '';
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Map<String, dynamic> _m(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
  List<dynamic> _l(Object? v) => v is List ? v : const [];

  Future<void> _refresh() async {
    try {
      final d = await widget.api.staffSelfTestStatus();
      if (!mounted) return;
      setState(() {
        _running = d['running'] == true;
        _progress = (d['progress'] as num?)?.toInt() ?? 0;
        _total = (d['total'] as num?)?.toInt() ?? 0;
        final r = d['result'];
        _result = r is Map ? Map<String, dynamic>.from(r) : _result;
        _error = '';
      });
      if (_running) {
        _poll ??= Timer.periodic(const Duration(seconds: 2), (_) => unawaited(_refresh()));
      } else {
        _poll?.cancel();
        _poll = null;
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Durum alınamadı: $e');
    }
  }

  Future<void> _start() async {
    setState(() {
      _running = true;
      _result = null;
      _progress = 0;
      _total = _games;
      _error = '';
    });
    try {
      await widget.api.staffSelfTestStart(games: _games, push: _push);
      _poll?.cancel();
      _poll = null;
      await _refresh();
    } catch (e) {
      if (mounted) setState(() {
        _running = false;
        _error = 'Test başlatılamadı: $e';
      });
    }
  }

  String _report() {
    final r = _result;
    if (r == null) return '';
    final b = StringBuffer('OKEYX SİSTEM TESTİ • ${r['ok'] == true ? 'HEPSİ GEÇTİ' : 'HATA VAR'} • ${r['seconds']} sn\n');
    for (final c in _l(r['checks']).map(_m)) {
      b.writeln('${c['ok'] == true ? '✓' : '✗'} ${c['name']}: ${c['detail']}');
      for (final f in _l(c['failures']).map(_m)) {
        b.writeln('   - ${f['mode']} • tohum ${f['seed']} • ${f['error']}');
      }
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    return ListView(padding: const EdgeInsets.all(4), children: [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: const Color(0x14FFFFFF), borderRadius: BorderRadius.circular(14), border: Border.all(color: OkeyXColors.gold.withValues(alpha: .25))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('SİSTEM TESTİ', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 1)),
          const SizedBox(height: 4),
          const Text('Sunucuda botlarla maçlar oynatılır; her hamleden sonra 106 taş, kopya taş ve yerdeki perlerin kurala uygunluğu denetlenir. Canlı masalara dokunmaz. Ayrıca veritabanı, masa kaydı ve sana bir test bildirimi denenir.', style: TextStyle(fontSize: 10, color: Colors.white70, height: 1.35)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            const Text('Maç sayısı:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
            for (final n in const [50, 100, 200, 300, 500])
              ChoiceChip(label: Text('$n'), selected: _games == n, onSelected: _running ? null : (_) => setState(() => _games = n)),
            FilterChip(label: const Text('Test bildirimi gönder'), selected: _push, onSelected: _running ? null : (v) => setState(() => _push = v)),
          ]),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _running ? null : _start,
              icon: Icon(_running ? Icons.hourglass_top_rounded : Icons.play_arrow_rounded),
              label: Text(_running ? 'TEST SÜRÜYOR… $_progress / $_total MAÇ' : 'TESTİ BAŞLAT'),
            ),
          ),
          if (_running) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(value: _total > 0 ? (_progress / _total).clamp(0.0, 1.0) : null, minHeight: 6, borderRadius: BorderRadius.circular(6)),
          ],
          if (_error.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error, style: const TextStyle(color: OkeyXColors.danger, fontSize: 11))),
        ]),
      ),
      if (r != null) ...[
        const SizedBox(height: 10),
        Row(children: [
          Icon(r['ok'] == true ? Icons.verified_rounded : Icons.error_rounded, color: r['ok'] == true ? OkeyXColors.mint : OkeyXColors.danger),
          const SizedBox(width: 6),
          Expanded(child: Text(r['ok'] == true ? 'Hepsi geçti • ${r['seconds']} sn' : 'Hata bulundu • ${r['seconds']} sn', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12))),
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _report()));
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('Rapor kopyalandı; geliştiriciye yapıştırabilirsin.')));
            },
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text('KOPYALA'),
          ),
        ]),
        for (final c in _l(r['checks']).map(_m))
          Container(
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: (c['ok'] == true ? OkeyXColors.mint : OkeyXColors.danger).withValues(alpha: .08), borderRadius: BorderRadius.circular(12), border: Border.all(color: (c['ok'] == true ? OkeyXColors.mint : OkeyXColors.danger).withValues(alpha: .35))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(c['ok'] == true ? Icons.check_circle_rounded : Icons.cancel_rounded, size: 16, color: c['ok'] == true ? OkeyXColors.mint : OkeyXColors.danger),
                const SizedBox(width: 6),
                Expanded(child: Text('${c['name']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
              ]),
              const SizedBox(height: 3),
              Text('${c['detail']}', style: const TextStyle(fontSize: 11, color: Colors.white70)),
              if (_m(c['end_reasons']).isNotEmpty)
                Text('Bitişler: ${_m(c['end_reasons']).entries.map((e) => '${e.key == 'finish' ? 'elini bitiren' : e.key == 'stock_empty' ? 'deste bitti' : e.key} ${e.value}').join(' • ')}', style: const TextStyle(fontSize: 10, color: Colors.white54)),
              for (final f in _l(c['failures']).map(_m))
                Padding(padding: const EdgeInsets.only(top: 3), child: Text('• ${f['mode']} • tohum ${f['seed']} • ${f['error']}', style: const TextStyle(fontSize: 10, color: OkeyXColors.danger))),
            ]),
          ),
      ],
    ]);
  }
}
