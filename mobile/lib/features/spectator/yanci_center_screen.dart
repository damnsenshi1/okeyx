import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_theme.dart';
import '../../core/game_audio.dart';
import '../../widgets/okx_kit.dart';
import '../lobby/lobby_api.dart';

class YanciCenterScreen extends StatefulWidget {
  final LobbyApiClient api;
  final bool soundEnabled;
  final bool vibrationEnabled;

  const YanciCenterScreen({
    super.key,
    required this.api,
    required this.soundEnabled,
    required this.vibrationEnabled,
  });

  @override
  State<YanciCenterScreen> createState() => _YanciCenterScreenState();
}

class _YanciCenterScreenState extends State<YanciCenterScreen> {
  List<Map<String, dynamic>> _tables = const [];
  bool _loading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _error = ''; });
    try {
      final rows = await widget.api.liveTables();
      if (mounted) setState(() => _tables = rows);
    } catch (_) {
      if (mounted) setState(() => _error = 'Canlı masalara şu anda ulaşılamadı.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(Map<String, dynamic> table) async {
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => YanciTableScreen(
        api: widget.api,
        roomId: '${table['room_id']}',
        soundEnabled: widget.soundEnabled,
        vibrationEnabled: widget.vibrationEnabled,
      ),
    ));
    if (mounted) unawaited(_load());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFF120E0A),
        body: OkxRoom(
          child: SafeArea(
            child: Column(children: [
              _header(),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error.isNotEmpty
                        ? _empty(Icons.wifi_off_rounded, _error, 'TEKRAR DENE', _load)
                        : _tables.isEmpty
                            ? _empty(Icons.visibility_off_rounded, 'Şu an izlenebilecek aktif masa yok.', 'YENİLE', _load)
                            : GridView.builder(
                                padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                                itemCount: _tables.length,
                                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 430, mainAxisExtent: 142, crossAxisSpacing: 10, mainAxisSpacing: 10),
                                itemBuilder: (_, index) => _tableCard(_tables[index]),
                              ),
              ),
            ]),
          ),
        ),
      );

  Widget _header() => Container(
        height: 66,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: const BoxDecoration(color: Color(0xCC120E0A), border: Border(bottom: BorderSide(color: OkeyXColors.line2))),
        child: Row(children: [
          IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_rounded)),
          const SizedBox(width: 5),
          Container(width: 40, height: 40, decoration: BoxDecoration(borderRadius: BorderRadius.circular(13), color: OkeyXColors.gold.withValues(alpha: .12), border: Border.all(color: OkeyXColors.gold.withValues(alpha: .35))), child: const Icon(Icons.visibility_rounded, color: OkeyXColors.gold)),
          const SizedBox(width: 9),
          const Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('YANCI KULÜBÜ', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: .7)),
            Text('Canlı masayı izle • tarafını seç • totemini gönder', style: TextStyle(fontSize: 7, color: Colors.white54, fontWeight: FontWeight.w700)),
          ])),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        ]),
      );

  Widget _empty(IconData icon, String text, String button, Future<void> Function() action) => Center(
        child: Container(
          width: 380,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(color: const Color(0xF21D1712), borderRadius: BorderRadius.circular(22), border: Border.all(color: OkeyXColors.line2)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: OkeyXColors.gold, size: 38),
            const SizedBox(height: 8),
            Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, color: Colors.white70, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            FilledButton.icon(onPressed: () => unawaited(action()), icon: const Icon(Icons.refresh_rounded), label: Text(button)),
          ]),
        ),
      );

  Widget _tableCard(Map<String, dynamic> table) {
    final players = _list(table['players']).map(_map).toList();
    final turbo = table['turbo'] == true;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _open(table),
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xF12B2118), Color(0xF21D1712), Color(0xFA0E0B08)]),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: turbo ? OkeyXColors.gold.withValues(alpha: .48) : OkeyXColors.ruby.withValues(alpha: .32)),
            boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 16, offset: Offset(0, 7))],
          ),
          child: Row(children: [
            Container(
              width: 116,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(65), gradient: const RadialGradient(colors: [Color(0xFF15927D), Color(0xFF503E2D), Color(0xFF30241B)]), border: Border.all(color: const Color(0xFFB98A41), width: 4)),
              child: Stack(alignment: Alignment.center, children: [
                const Text('101', style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900, color: Colors.white24)),
                for (var i = 0; i < math.min(4, players.length); i++)
                  Align(
                    alignment: const [Alignment(0, -.82), Alignment(.82, 0), Alignment(0, .82), Alignment(-.82, 0)][i],
                    child: CircleAvatar(radius: 10, backgroundColor: players[i]['bot'] == true ? Colors.white24 : OkeyXColors.mint, child: Text('${players[i]['name'] ?? 'O'}'.substring(0, 1).toUpperCase(), style: const TextStyle(fontSize: 6, fontWeight: FontWeight.w900, color: Color(0xFF221A13)))),
                  ),
              ]),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text('${table['name'] ?? 'OkeyX Masası'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900))),
                Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3), decoration: BoxDecoration(color: OkeyXColors.danger.withValues(alpha: .13), borderRadius: BorderRadius.circular(8)), child: const Text('● CANLI', style: TextStyle(fontSize: 5.8, color: OkeyXColors.danger, fontWeight: FontWeight.w900))),
              ]),
              const SizedBox(height: 5),
              Text('${turbo ? '★ Turbo' : 'Standart'} • ${table['variant'] == 'duz' ? 'Klasik Okey' : table['variant'] == 'fold' ? 'Katlamalı' : 'Katlamasız'} • ${table['team_mode'] == 'paired' ? 'Eşli' : 'Tek'}', style: const TextStyle(fontSize: 7, color: Colors.white60, fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text('${table['round_index']}/${table['max_rounds']} el • ${_money(_integer(table['entry_fee']))} altın masa', style: const TextStyle(fontSize: 7, color: OkeyXColors.gold, fontWeight: FontWeight.w800)),
              const Spacer(),
              Row(children: [
                const Icon(Icons.visibility_rounded, size: 13, color: Colors.white54),
                const SizedBox(width: 4),
                Text('${_integer(table['spectators'])} yancı', style: const TextStyle(fontSize: 7, color: Colors.white54)),
                const Spacer(),
                FilledButton.tonalIcon(onPressed: () => _open(table), icon: const Icon(Icons.chair_alt_rounded, size: 14), label: const Text('YANCI OL', style: TextStyle(fontSize: 7, fontWeight: FontWeight.w900))),
              ]),
            ])),
          ]),
        ),
      ),
    );
  }
}

class YanciTableScreen extends StatefulWidget {
  final LobbyApiClient api;
  final String roomId;
  final bool soundEnabled;
  final bool vibrationEnabled;

  const YanciTableScreen({
    super.key,
    required this.api,
    required this.roomId,
    required this.soundEnabled,
    required this.vibrationEnabled,
  });

  @override
  State<YanciTableScreen> createState() => _YanciTableScreenState();
}

class _YanciTableScreenState extends State<YanciTableScreen> {
  Map<String, dynamic> _state = const {};
  Timer? _poll;
  Timer? _clock;
  int _nowMs = DateTime.now().millisecondsSinceEpoch;
  int _targetSeat = 0;
  bool _loading = true;
  bool _busy = false;
  String _message = '';

  @override
  void initState() {
    super.initState();
    unawaited(_join());
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _nowMs = DateTime.now().millisecondsSinceEpoch);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _clock?.cancel();
    unawaited(widget.api.spectate(widget.roomId, action: 'leave'));
    super.dispose();
  }

  Future<void> _join() async {
    try {
      final out = await widget.api.spectate(widget.roomId, action: 'join');
      if (!mounted) return;
      setState(() { _state = _map(out['state']); _loading = false; });
      _poll = Timer.periodic(const Duration(seconds: 2), (_) => unawaited(_refresh()));
    } catch (_) {
      if (mounted) setState(() { _loading = false; _message = 'Bu masaya yancı olarak bağlanılamadı.'; });
    }
  }

  Future<void> _refresh() async {
    if (_busy) return;
    try {
      final out = await widget.api.spectate(widget.roomId, action: 'state');
      if (mounted && out['ok'] == true) setState(() => _state = _map(out['state']));
    } catch (_) {
      if (mounted) setState(() => _message = 'Canlı bağlantı yenileniyor…');
    }
  }

  Future<void> _react(String value) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final out = await widget.api.spectate(widget.roomId, action: 'react', value: value, toSeat: _targetSeat);
      if (!mounted) return;
      if (out['ok'] == true) {
        setState(() { _state = _map(out['state']); _message = 'Totemin masaya ulaştı!'; });
        unawaited(GameAudio.sfx(value == 'tea' || value == 'coffee' ? 'gift_coffee' : 'reaction', enabled: widget.soundEnabled, volume: .82));
        if (widget.vibrationEnabled) unawaited(HapticFeedback.mediumImpact());
      }
    } catch (error) {
      if (mounted) setState(() => _message = '$error'.contains('cooldown') ? 'Totem için bir an bekle.' : 'Totem gönderilemedi.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _predict(String value) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final out = await widget.api.spectate(widget.roomId, action: 'predict', value: value);
      if (!mounted) return;
      setState(() {
        _state = _map(out['state']);
        _message = out['ok'] == true ? 'Tahminin kilitlendi. Doğruysa Yancı Puanı kazanacaksın.' : 'Bu el için tahmin süresi kapandı.';
      });
      if (widget.vibrationEnabled && out['ok'] == true) unawaited(HapticFeedback.selectionClick());
    } catch (_) {
      if (mounted) setState(() => _message = 'Tahmin kaydedilemedi.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  int get _secondsLeft {
    final deadline = _integer(_state['turn_deadline_ms']);
    if (deadline <= _nowMs) return 0;
    return ((deadline - _nowMs) / 1000).ceil().clamp(0, 99).toInt();
  }

  Map<String, dynamic> _player(int seat) => _list(_state['players']).map(_map).firstWhere((p) => _integer(p['seat']) == seat, orElse: () => const <String, dynamic>{});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFF0E0B08),
        body: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _state.isEmpty
                  ? Center(child: Text(_message, style: const TextStyle(color: Colors.white70)))
                  : LayoutBuilder(builder: (context, constraints) {
                      final compact = constraints.maxHeight < 490;
                      return OkxRoom(
                        child: Stack(children: [
                          Positioned.fill(left: compact ? 142 : 175, right: compact ? 142 : 175, top: 46, bottom: 54, child: _spectatorBoard(compact)),
                          Positioned(left: 8, top: 8, child: Row(children: [
                            _roundButton(Icons.arrow_back_rounded, () => Navigator.pop(context)),
                            const SizedBox(width: 6),
                            _statusPill(Icons.visibility_rounded, '${_integer(_state['spectator_count'])} YANCI', OkeyXColors.gold),
                          ])),
                          Positioned(top: 7, left: 0, right: 0, child: Center(child: _timerPill())),
                          Positioned(right: 8, top: 8, child: _statusPill(Icons.stars_rounded, '${_integer(_state['spectator_points'])} PUAN', OkeyXColors.mint)),
                          Positioned(left: 8, top: 52, bottom: 8, width: compact ? 126 : 156, child: _predictionPanel(compact)),
                          Positioned(right: 8, top: 52, bottom: 8, width: compact ? 126 : 156, child: _totemPanel(compact)),
                          Positioned(left: compact ? 148 : 182, right: compact ? 148 : 182, bottom: 7, child: _yanciBar()),
                          if (_message.isNotEmpty) Positioned(left: 0, right: 0, bottom: 49, child: Center(child: _notice())),
                          if (_busy) const Positioned(top: 12, right: 155, child: SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2, color: OkeyXColors.ruby))),
                        ]),
                      );
                    }),
        ),
      );

  Widget _spectatorBoard(bool compact) => Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(120),
          gradient: const RadialGradient(colors: [Color(0xFF167A59), Color(0xFF155E43), Color(0xFF302318), Color(0xFF19130E)]),
          border: Border.all(color: const Color(0xFFC09149), width: compact ? 5 : 7),
          boxShadow: const [BoxShadow(color: Color(0x88000000), blurRadius: 25, offset: Offset(0, 12)), BoxShadow(color: Color(0x3300E2C0), blurRadius: 28)],
        ),
        child: Stack(alignment: Alignment.center, children: [
          Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${_state['room_name'] ?? 'OkeyX Masası'}', style: const TextStyle(fontSize: 10, color: Colors.white54, fontWeight: FontWeight.w900)),
            const SizedBox(height: 3),
            Text('${_integer(_state['stock_count'])}', style: const TextStyle(fontSize: 31, height: .9, fontWeight: FontWeight.w900)),
            const Text('KALAN TAŞ', style: TextStyle(fontSize: 6, color: OkeyXColors.gold, fontWeight: FontWeight.w900, letterSpacing: .7)),
            const SizedBox(height: 7),
            Text('${_list(_state['melds']).length} AÇIK PER • ${_state['turbo'] == true ? '★ TURBO ×${_integer(_state['multiplier'])}' : 'STANDART'}', style: const TextStyle(fontSize: 6.2, color: Colors.white60, fontWeight: FontWeight.w800)),
          ]),
          Positioned(top: 3, child: _spectatorPlayer(_player(2), Alignment.topCenter)),
          Positioned(right: 4, child: _spectatorPlayer(_player(1), Alignment.centerRight)),
          Positioned(bottom: 3, child: _spectatorPlayer(_player(0), Alignment.bottomCenter)),
          Positioned(left: 4, child: _spectatorPlayer(_player(3), Alignment.centerLeft)),
        ]),
      );

  Widget _spectatorPlayer(Map<String, dynamic> player, Alignment alignment) {
    final seat = _integer(player['seat']);
    final active = seat == _integer(_state['current_seat']);
    final selected = seat == _targetSeat;
    final name = '${player['name'] ?? 'Oyuncu'}';
    final oneTile = _integer(player['hand_count']) <= 1 && _state['started'] == true;
    final streak = _integer(_map(player['public_stats'])['current_streak']);
    return GestureDetector(
      onTap: () => setState(() => _targetSeat = seat),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 100,
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xF22B2118),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: selected ? OkeyXColors.gold : active ? OkeyXColors.ruby : Colors.white24, width: selected || active ? 2 : 1),
          boxShadow: streak >= 2 ? const [BoxShadow(color: Color(0x88FF723B), blurRadius: 14)] : active ? [BoxShadow(color: OkeyXColors.ruby.withValues(alpha: .23), blurRadius: 11)] : null,
        ),
        child: Row(children: [
          Stack(clipBehavior: Clip.none, children: [
            CircleAvatar(radius: 13, backgroundColor: active ? OkeyXColors.ruby : const Color(0xFF584432), child: Text(name.isEmpty ? 'O' : name.substring(0, 1).toUpperCase(), style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: Color(0xFF231B14)))),
            if (oneTile) const Positioned(right: -5, top: -6, child: Text('💧', style: TextStyle(fontSize: 10))),
            if (streak >= 2) const Positioned(left: -6, bottom: -7, child: Text('🔥', style: TextStyle(fontSize: 11))),
          ]),
          const SizedBox(width: 6),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 7.5, fontWeight: FontWeight.w900)),
            Text('${_integer(player['hand_count'])} taş${player['opened'] == true ? ' • AÇTI' : ''}', style: TextStyle(fontSize: 5.6, color: active ? OkeyXColors.mint : Colors.white.withValues(alpha: .45), fontWeight: FontWeight.w800)),
          ])),
        ]),
      ),
    );
  }

  Widget _predictionPanel(bool compact) {
    final prediction = _map(_state['spectator_prediction']);
    final settled = prediction['settled'] == true;
    final canPredict = _state['can_predict'] == true;
    return _sidePanel(
      title: 'TAHMİN',
      icon: Icons.psychology_alt_rounded,
      color: const Color(0xFF9F85FF),
      child: Column(children: [
        Text(settled ? (prediction['correct'] == true ? '+${_integer(prediction['reward'])} YANCI PUANI' : 'BU KEZ OLMADI') : canPredict ? 'Bu eli kim kazanır?' : 'Tahminler kilitlendi', textAlign: TextAlign.center, style: TextStyle(fontSize: 6.5, color: settled && prediction['correct'] == true ? OkeyXColors.mint : Colors.white54, fontWeight: FontWeight.w900)),
        SizedBox(height: compact ? 4 : 7),
        for (var seat = 0; seat < 4; seat++) ...[
          _predictionButton('${_player(seat)['name'] ?? 'Oyuncu'}', 'winner:$seat', prediction, canPredict),
          const SizedBox(height: 4),
        ],
        const Spacer(),
        _predictionButton('OKEYLE BİTER', 'joker_finish', prediction, canPredict, accent: OkeyXColors.gold),
        const SizedBox(height: 4),
        _predictionButton('ÇİFTTEN BİTER', 'pair_finish', prediction, canPredict, accent: OkeyXColors.mint),
        const SizedBox(height: 4),
        const Text('Gerçek para/altın yok • yalnızca Yancı Puanı', textAlign: TextAlign.center, style: TextStyle(fontSize: 5, color: Colors.white30)),
      ]),
    );
  }

  Widget _predictionButton(String label, String value, Map<String, dynamic> prediction, bool enabled, {Color accent = const Color(0xFF9F85FF)}) {
    final selected = '${prediction['value'] ?? ''}' == value;
    return SizedBox(
      width: double.infinity,
      height: 25,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 5), side: BorderSide(color: selected ? accent : Colors.white12), backgroundColor: selected ? accent.withValues(alpha: .13) : Colors.transparent),
        onPressed: enabled && !_busy ? () => _predict(value) : null,
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 5.8, color: selected ? accent : Colors.white60, fontWeight: FontWeight.w900)),
      ),
    );
  }

  Widget _totemPanel(bool compact) => _sidePanel(
        title: 'TOTEM & ÇAY',
        icon: Icons.auto_awesome_rounded,
        color: OkeyXColors.gold,
        child: Column(children: [
          Text('Desteklenen: ${_player(_targetSeat)['name'] ?? 'Oyuncu'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 6.4, color: OkeyXColors.gold, fontWeight: FontWeight.w900)),
          const SizedBox(height: 7),
          Expanded(child: Row(children: [
            Expanded(child: _totemButton('🧿', 'Nazar', 'nazar')),
            const SizedBox(width: 5),
            Expanded(child: _totemButton('🫖', 'Çay', 'tea')),
          ])),
          const SizedBox(height: 5),
          Expanded(child: Row(children: [
            Expanded(child: _totemButton('☕', 'Kahve', 'coffee')),
            const SizedBox(width: 5),
            Expanded(child: _totemButton('👏', 'Alkış', 'applause')),
          ])),
          const SizedBox(height: 7),
          const Divider(height: 1),
          const SizedBox(height: 6),
          const Text('Yancı elleri göremez. Totemler yalnızca görseldir ve oyuna avantaj sağlamaz.', textAlign: TextAlign.center, style: TextStyle(fontSize: 5.4, height: 1.25, color: Colors.white38)),
        ]),
      );

  Widget _totemButton(String emoji, String title, String value) => Material(
        color: Colors.white.withValues(alpha: .035),
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          onTap: _busy ? null : () => _react(value),
          borderRadius: BorderRadius.circular(13),
          child: Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(13), border: Border.all(color: Colors.white10)),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(emoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(height: 2),
              Text(title, style: const TextStyle(fontSize: 6, fontWeight: FontWeight.w900, color: Colors.white70)),
            ]),
          ),
        ),
      );

  Widget _sidePanel({required String title, required IconData icon, required Color color, required Widget child}) => Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: const Color(0xE8211912), borderRadius: BorderRadius.circular(18), border: Border.all(color: color.withValues(alpha: .32)), boxShadow: const [BoxShadow(color: Color(0x44000000), blurRadius: 12)]),
        child: Column(children: [
          Row(children: [Icon(icon, size: 14, color: color), const SizedBox(width: 5), Text(title, style: TextStyle(fontSize: 7, color: color, fontWeight: FontWeight.w900, letterSpacing: .4))]),
          const SizedBox(height: 6),
          Expanded(child: child),
        ]),
      );

  Widget _yanciBar() => Container(
        height: 39,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(color: const Color(0xF2281F16), borderRadius: BorderRadius.circular(15), border: Border.all(color: OkeyXColors.gold.withValues(alpha: .35))),
        child: Row(children: [
          const CircleAvatar(radius: 12, backgroundColor: Color(0xFF785A2B), child: Icon(Icons.chair_alt_rounded, size: 13, color: OkeyXColors.gold)),
          const SizedBox(width: 7),
          Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('YANCI • ${widget.api.profile.displayName}', style: const TextStyle(fontSize: 7.5, fontWeight: FontWeight.w900)),
            const Text('Eller gizli • adil izleyici modu', style: TextStyle(fontSize: 5.5, color: Colors.white38)),
          ])),
          Text('${_integer(_state['spectator_points'])} PUAN', style: const TextStyle(fontSize: 7, color: OkeyXColors.ruby, fontWeight: FontWeight.w900)),
        ]),
      );

  Widget _timerPill() {
    final left = _secondsLeft;
    final color = left <= 5 ? OkeyXColors.danger : left <= 12 ? OkeyXColors.gold : OkeyXColors.mint;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: const Color(0xEE251D15), borderRadius: BorderRadius.circular(18), border: Border.all(color: color, width: left <= 5 ? 2 : 1), boxShadow: left <= 5 ? [BoxShadow(color: color.withValues(alpha: .28), blurRadius: 13)] : null),
      child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.timer_rounded, size: 14, color: color), const SizedBox(width: 5), Text('$left', style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w900)), const SizedBox(width: 5), const Text('SANİYE', style: TextStyle(fontSize: 5.5, color: Colors.white38, fontWeight: FontWeight.w900))]),
    );
  }

  Widget _roundButton(IconData icon, VoidCallback onTap) => Material(color: const Color(0xDD281F16), shape: const CircleBorder(), child: IconButton(onPressed: onTap, icon: Icon(icon, size: 18)));

  Widget _statusPill(IconData icon, String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(color: const Color(0xDD281F16), borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withValues(alpha: .35))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 13, color: color), const SizedBox(width: 4), Text(text, style: TextStyle(fontSize: 6.5, color: color, fontWeight: FontWeight.w900))]),
      );

  Widget _notice() => Container(
        constraints: const BoxConstraints(maxWidth: 430),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(color: const Color(0xF22B2118), borderRadius: BorderRadius.circular(14), border: Border.all(color: OkeyXColors.ruby.withValues(alpha: .35)), boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 10)]),
        child: Text(_message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 7, color: Colors.white70, fontWeight: FontWeight.w800)),
      );
}

Map<String, dynamic> _map(dynamic value) => value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
List<dynamic> _list(dynamic value) => value is List ? value : const <dynamic>[];
int _integer(dynamic value) => value is num ? value.toInt() : int.tryParse('$value') ?? 0;
String _money(int value) => value.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
