import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../widgets/okx_kit.dart';
import '../lobby/lobby_api.dart';

/// Haftalık turnuva: puan ve ödül tamamen sunucuda hesaplanır, burası yalnızca gösterir.
class TournamentScreen extends StatefulWidget {
  final LobbyApiClient api;
  final VoidCallback? onClaimed;
  const TournamentScreen({super.key, required this.api, this.onClaimed});

  @override
  State<TournamentScreen> createState() => _TournamentScreenState();
}

class _TournamentScreenState extends State<TournamentScreen> {
  Map<String, dynamic>? _data;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  int _i(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

  Future<void> _load() async {
    try {
      final out = await widget.api.tournament();
      if (mounted) setState(() { _data = out; _error = null; });
    } catch (_) {
      if (mounted) setState(() => _error = 'Turnuva yüklenemedi. Bağlantını kontrol et.');
    }
  }

  Future<void> _claim() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final out = await widget.api.claimTournament();
      if (!mounted) return;
      final msg = out['ok'] == true
          ? 'Turnuva ödülü: +${_i(out['coins'])} altın (#${_i(out['rank'])})'
          : (out['code'] == 'not_enough_games' ? 'Ödül için en az ${_i(out['needed'])} maç gerekir.' : 'Ödül alınamadı.');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      widget.onClaimed?.call();
      await _load();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ödül alınamadı.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final rows = (d?['rows'] as List?)?.whereType<Map>().toList() ?? const <Map>[];
    final prev = (d?['previous'] as Map?) ?? const {};
    final me = d?['me'] as Map?;
    final claimable = _i(prev['claimable_coins']);

    return Scaffold(
      backgroundColor: OkeyXColors.ink,
      appBar: AppBar(
        title: const Text('HAFTALIK TURNUVA', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: .8)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: OkxRoom(
        child: _error != null
            ? Center(child: Text(_error!, style: const TextStyle(color: OkeyXColors.cream)))
            : d == null
                ? const Center(child: CircularProgressIndicator(color: OkeyXColors.ruby))
                : RefreshIndicator(
                    onRefresh: _load,
                    color: OkeyXColors.ruby,
                    backgroundColor: OkeyXColors.deep,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
                      children: [
                        OkxLeather(
                          stitch: true,
                          radius: 20,
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: const [
                                Icon(Icons.emoji_events_rounded, color: OkeyXColors.gold, size: 20),
                                SizedBox(width: 8),
                                Text('HAFTALIK LİG', style: TextStyle(fontSize: 11, color: OkeyXColors.gold, fontWeight: FontWeight.w900, letterSpacing: 1)),
                              ]),
                              const SizedBox(height: 8),
                              Text('Bu hafta: ${d['week']}', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: OkeyXColors.cream)),
                              const SizedBox(height: 5),
                              Text(
                                me == null
                                    ? 'Henüz maç oynamadın. Galibiyet +30, mağlubiyet +5 puan.'
                                    : 'Sıran #${_i(me['rank'])} • ${_i(me['points'])} puan • ${_i(me['games'])} maç',
                                style: const TextStyle(color: OkeyXColors.muted, fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 5),
                              Text('Ödül için en az ${_i(d['min_games_for_prize'])} maç • Hafta sonunda ödül hazır olur.',
                                  style: const TextStyle(color: OkeyXColors.dim, fontSize: 10, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                        if (claimable > 0) ...[
                          const SizedBox(height: 10),
                          SizedBox(
                            height: 48,
                            child: FilledButton.icon(
                              onPressed: _busy ? null : _claim,
                              icon: const Icon(Icons.card_giftcard_rounded),
                              label: Text('GEÇEN HAFTA ÖDÜLÜNÜ AL  +$claimable'),
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        Row(children: const [
                          Icon(Icons.leaderboard_rounded, color: OkeyXColors.gold, size: 17),
                          SizedBox(width: 7),
                          Text('SIRALAMA', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1, color: OkeyXColors.cream)),
                        ]),
                        const SizedBox(height: 8),
                        if (rows.isEmpty)
                          OkxLeather(
                            radius: 14,
                            padding: const EdgeInsets.all(16),
                            child: const Text('İlk maçı oynayan listeye girer.', style: TextStyle(color: OkeyXColors.muted, fontWeight: FontWeight.w700)),
                          ),
                        for (final r in rows)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: OkxLeather(
                              radius: 14,
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              child: ListTile(
                                dense: true,
                                visualDensity: VisualDensity.compact,
                                leading: CircleAvatar(
                                  radius: 15,
                                  backgroundColor: _i(r['rank']) <= 3 ? OkeyXColors.gold : OkeyXColors.panelSoft,
                                  child: Text('${_i(r['rank'])}', style: const TextStyle(color: OkeyXColors.ink, fontWeight: FontWeight.w900, fontSize: 12)),
                                ),
                                title: Text('${r['name']}', style: const TextStyle(fontWeight: FontWeight.w800, color: OkeyXColors.cream)),
                                subtitle: Text('${_i(r['wins'])} galibiyet / ${_i(r['games'])} maç', style: const TextStyle(color: OkeyXColors.muted)),
                                trailing: Text('${_i(r['points'])}', style: const TextStyle(color: OkeyXColors.gold, fontWeight: FontWeight.w900, fontSize: 16)),
                              ),
                            ),
                          ),
                        const SizedBox(height: 18),
                        Row(children: const [
                          Icon(Icons.redeem_rounded, color: OkeyXColors.gold, size: 17),
                          SizedBox(width: 7),
                          Text('ÖDÜLLER', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1, color: OkeyXColors.cream)),
                        ]),
                        const SizedBox(height: 8),
                        for (final prize in (d['prizes'] as List? ?? const []).whereType<Map>())
                          Padding(
                            padding: const EdgeInsets.only(bottom: 5),
                            child: OkxLeather(
                              radius: 12,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                              child: Row(children: [
                                const Icon(Icons.monetization_on_rounded, color: OkeyXColors.gold, size: 16),
                                const SizedBox(width: 8),
                                Expanded(child: Text(
                                  '#${prize['from']}${_i(prize['from']) == _i(prize['to']) ? '' : '–${prize['to']}'}',
                                  style: const TextStyle(color: OkeyXColors.cream, fontWeight: FontWeight.w800),
                                )),
                                Text('${_i(prize['coins'])} altın', style: const TextStyle(color: OkeyXColors.gold, fontWeight: FontWeight.w900)),
                              ]),
                            ),
                          ),
                      ],
                    ),
                  ),
      ),
    );
  }

}
