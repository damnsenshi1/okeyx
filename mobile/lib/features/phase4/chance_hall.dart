import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_theme.dart';
import '../../core/game_audio.dart';
import '../lobby/lobby_api.dart';

class ChanceHall extends StatelessWidget {
  final LobbyApiClient api;
  final Map<String, dynamic> hub;
  final Future<void> Function() onRefresh;
  final ValueChanged<String> onMessage;
  final VoidCallback? onOpenStore;
  final ValueChanged<Map<String,dynamic>>? onWalletChanged;
  final bool soundEnabled;
  final bool vibrationEnabled;

  const ChanceHall({
    super.key,
    required this.api,
    required this.hub,
    required this.onRefresh,
    required this.onMessage,
    this.onOpenStore,
    this.onWalletChanged,
    this.soundEnabled = true,
    this.vibrationEnabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final games = _map(hub['side_games']);
    final wallet = _salonWallet(_map(hub['wallet']));
    final vouchers = _map(wallet['slot_vouchers']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF3E3023), Color(0xFF281E16), Color(0xFF18130E)],
            ),
            border: Border.all(color: OkeyXColors.gold.withValues(alpha: .28)),
            boxShadow: const [BoxShadow(color: Color(0x44000000), blurRadius: 22, offset: Offset(0, 10))],
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: const LinearGradient(colors: [Color(0xFFB98A34), Color(0xFF56411E)]),
                  boxShadow: const [BoxShadow(color: Color(0x55F4C542), blurRadius: 16)],
                ),
                child: const Icon(Icons.grid_view_rounded, color: Colors.white, size: 30),
              ),
              const SizedBox(width: 11),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('OKEYX ŞANS SALONU', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: .4)),
                    SizedBox(height: 3),
                    Text('Şanslı Taşlar • Hipodrom • Sirk • Okey Drop • Kasa Kulesi', style: TextStyle(fontSize: 8, color: Colors.white60, fontWeight: FontWeight.w700)),
                    Text('Yalnız oynayarak kazandığın SALON JETONU ile oynanır • satın alınamaz • nakit ödül yoktur.', style: TextStyle(fontSize: 7, color: Colors.white38)),
                  ],
                ),
              ),
              TextButton(
                onPressed: () async {
                  try {
                    final r = await api.claimSalonDaily();
                    onMessage(r['ok'] == true ? 'Günlük Salon hakkı: +${_compact(_int(r['granted']))} jeton' : 'Bugünkü Salon hakkını zaten aldın.');
                    await onRefresh();
                  } catch (_) {
                    onMessage('Salon hakkı şu an alınamadı.');
                  }
                },
                child: const Text('GÜNLÜK HAK', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900)),
              ),
              _walletPill(Icons.casino_rounded, _compact(_int(wallet['coins'])), OkeyXColors.gold),
              const SizedBox(width: 6),
              _walletPill(Icons.diamond_rounded, _compact(_int(wallet['diamonds'])), const Color(0xFF78E4FF)),
            ],
          ),
        ),
        if (vouchers.values.any((x) => _int(x) > 0)) ...[
          const SizedBox(height: 8),
          _voucherBar(vouchers),
        ],
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, c) {
            final wide = c.maxWidth >= 780;
            final cards = [
              _gameTile(
                context,
                title: 'ŞANSLI TAŞLAR',
                subtitle: 'Okey taşlarını eşleştir • farklı ödül desenleri',
                description: 'Okey temalı taş desenlerini yakala. Ödül kuralları ve olasılıklar şeffaf tabloda gösterilir.',
                icon: Icons.grid_view_rounded,
                accent: const Color(0xFFFFB332),
                badge: 'x5000',
                onTap: () => _open(context, SlotDialog(api: api, config: _map(games['slot']), wallet: wallet, onRefresh: onRefresh, onMessage: onMessage, onOpenStore: onOpenStore, onWalletChanged:onWalletChanged, soundEnabled: soundEnabled, vibrationEnabled: vibrationEnabled)),
              ),
              _gameTile(
                context,
                title: 'OKEYX HİPODROM',
                subtitle: '4 at • farklı risk ve çarpan',
                description: 'Favoriden sürprize atını seç. Yarış sonucu sunucuda belirlenir, sahnede canlı izlenir.',
                icon: Icons.sports_score_rounded,
                accent: const Color(0xFF4FD0A1),
                badge: 'CANLI YARIŞ',
                onTap: () => _open(context, HorseDialog(api: api, config: _map(games['horse']), wallet: wallet, onRefresh: onRefresh, onMessage: onMessage, onOpenStore: onOpenStore, onWalletChanged:onWalletChanged, soundEnabled: soundEnabled, vibrationEnabled: vibrationEnabled)),
              ),
              _gameTile(
                context,
                title: 'SİRK IŞIKLARI',
                subtitle: 'Refleks • seri • tam isabet',
                description: 'Hedef ışığı yakala. Şans yerine zamanlamanı konuştur ve seri isabet peşinde koş.',
                icon: Icons.flare_rounded,
                accent: const Color(0xFFFF6E78),
                badge: 'BECERİ',
                onTap: () => _open(context, CircusDialog(api: api, config: _map(games['circus']), wallet: wallet, onRefresh: onRefresh, onMessage: onMessage, onOpenStore: onOpenStore, onWalletChanged:onWalletChanged, soundEnabled: soundEnabled, vibrationEnabled: vibrationEnabled)),
              ),
              _gameTile(
                context,
                title: 'OKEY DROP',
                subtitle: 'Taşı bırak • x50 cebe indir',
                description: 'Okey taşı pimlerden sekerek ödül haznesine düşer. Kenarlar nadir ama büyük çarpan verir.',
                icon: Icons.south_rounded,
                accent: const Color(0xFF5DD7FF),
                badge: 'x50',
                onTap: () => _open(context, DropDialog(api: api, config: _map(games['drop']), wallet: wallet, onRefresh: onRefresh, onOpenStore: onOpenStore, onWalletChanged:onWalletChanged, soundEnabled: soundEnabled, vibrationEnabled: vibrationEnabled)),
              ),
              _gameTile(
                context,
                title: 'KASA KULESİ',
                subtitle: 'Kat çık • riski al • çekil',
                description: 'Her katta üç kapıdan birini seç. Tuzaktan kaç, çarpanı büyüt veya kazancını alıp çık.',
                icon: Icons.account_balance_rounded,
                accent: const Color(0xFFEAC45B),
                badge: '6 KAT',
                onTap: () => _open(context, TowerDialog(api: api, config: _map(games['tower']), wallet: wallet, onRefresh: onRefresh, onOpenStore: onOpenStore, onWalletChanged:onWalletChanged, soundEnabled: soundEnabled, vibrationEnabled: vibrationEnabled)),
              ),
            ];
            if (wide) {
              final width = (c.maxWidth - 18) / 3;
              return Wrap(spacing: 9, runSpacing: 9, children: [for (final card in cards) SizedBox(width: width, child: card)]);
            }
            return Column(children: [for (final card in cards) Padding(padding: const EdgeInsets.only(bottom: 8), child: card)]);
          },
        ),
      ],
    );
  }

  Future<void> _open(BuildContext context, Widget page) async {
    await GameAudio.sfx('ui_tap', enabled: soundEnabled, volume: .7);
    if (!context.mounted) return;
    await showDialog<void>(context: context, barrierDismissible: false, builder: (_) => page);
    await onRefresh();
  }
}

class SlotDialog extends StatefulWidget {
  final LobbyApiClient api;
  final Map<String, dynamic> config;
  final Map<String, dynamic> wallet;
  final Future<void> Function() onRefresh;
  final ValueChanged<String> onMessage;
  final VoidCallback? onOpenStore;
  final ValueChanged<Map<String,dynamic>>? onWalletChanged;
  final bool soundEnabled;
  final bool vibrationEnabled;

  const SlotDialog({
    super.key,
    required this.api,
    required this.config,
    required this.wallet,
    required this.onRefresh,
    required this.onMessage,
    this.onOpenStore,
    this.onWalletChanged,
    this.soundEnabled = true,
    this.vibrationEnabled = true,
  });

  @override
  State<SlotDialog> createState() => _SlotDialogState();
}

class _SlotDialogState extends State<SlotDialog> {
  Timer? _winCountTimer;
  Timer? _reelMotionTimer;
  final math.Random _reelRandom = math.Random();
  static const List<String> _spinSymbols = <String>['cherry','bar','star','crown','okey','diamond','seven'];
  int _lockedReels = 0;
  int _spinTick = 0;
  late List<int> _bets;
  late List<int> _availableLines;
  late int _bet;
  final Set<int> _activeLines = <int>{1, 2, 3, 4, 5};
  late Map<String, dynamic> _wallet;
  late Map<String, dynamic> _vouchers;
  List<List<String>> _grid = List.generate(3, (_) => List.filled(5, 'bar'));
  List<Map<String, dynamic>> _wins = [];
  bool _spinning = false;
  bool _useVoucher = false;
  String _message = 'Oyun miktarını seç ve taşları çevir.';
  int _lastPayout = 0;
  int _countedWin = 0;
  bool _showWinOverlay = false;
  String _winTitle = '';

  void _startWinCount(int payout, String resultClass) {
    _winCountTimer?.cancel();
    final title = switch (resultClass) {
      'jackpot' => 'NADİR TAŞ ÖDÜLÜ!',
      'mega' => 'BÜYÜK TAŞ ÖDÜLÜ!',
      'big' => 'GÜÇLÜ DESEN!',
      _ => 'KAZANÇ!',
    };
    if (!mounted) return;
    setState(() {
      _showWinOverlay = true;
      _countedWin = 0;
      _winTitle = title;
    });
    const steps = 28;
    var step = 0;
    _winCountTimer = Timer.periodic(const Duration(milliseconds: 34), (timer) {
      step++;
      if (!mounted) {
        timer.cancel();
        return;
      }
      final eased = 1 - math.pow(1 - (step / steps).clamp(0.0, 1.0), 3).toDouble();
      setState(() => _countedWin = (payout * eased).round());
      if (step >= steps) {
        timer.cancel();
        Future<void>.delayed(const Duration(milliseconds: 950), () {
          if (mounted) setState(() => _showWinOverlay = false);
        });
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _bets = _list(widget.config['bet_options']).map(_int).toList();
    if (_bets.isEmpty) _bets = [100, 500, 1000, 2500, 5000, 10000, 25000, 50000, 100000, 250000];
    _availableLines = _list(widget.config['line_options']).map(_int).where((x) => x >= 1 && x <= 9).toList();
    if (_availableLines.isEmpty) _availableLines = List<int>.generate(9, (i) => i + 1);
    _activeLines.removeWhere((x) => !_availableLines.contains(x));
    if (_activeLines.isEmpty) _activeLines.add(_availableLines.first);
    _bet = _bets.contains(1000) ? 1000 : (_bets.contains(5000) ? 5000 : _bets.first);
    _wallet = _salonWallet(widget.wallet);
    _vouchers = _map(_wallet['slot_vouchers']);
  }

  @override
  void dispose() {
    _winCountTimer?.cancel();
    _reelMotionTimer?.cancel();
    super.dispose();
  }

  void _startReelMotion() {
    _reelMotionTimer?.cancel();
    _lockedReels = 0;
    _spinTick = 0;
    _reelMotionTimer = Timer.periodic(const Duration(milliseconds: 52), (_) {
      if (!mounted || !_spinning) return;
      setState(() {
        _spinTick++;
        for (var col = _lockedReels; col < 5; col++) {
          for (var row = 0; row < 3; row++) {
            // Offset every row/reel so the symbols visually stream instead of
            // flashing as one static board.
            final index = (_reelRandom.nextInt(_spinSymbols.length) + row + col + _spinTick) % _spinSymbols.length;
            _grid[row][col] = _spinSymbols[index];
          }
        }
      });
    });
  }

  Future<void> _landReels(List<List<String>> target) async {
    for (var col = 0; col < 5; col++) {
      if (!mounted) return;
      await Future<void>.delayed(Duration(milliseconds: col == 0 ? 45 : 78));
      if (!mounted) return;
      setState(() {
        for (var row = 0; row < 3; row++) {
          if (row < target.length && col < target[row].length) _grid[row][col] = target[row][col];
        }
        _lockedReels = col + 1;
      });
      unawaited(GameAudio.sfx('reel_stop', enabled: widget.soundEnabled, volume: .72));
      if (widget.vibrationEnabled && col == 4) unawaited(HapticFeedback.selectionClick());
    }
    _reelMotionTimer?.cancel();
  }

  int get _totalBet => _bet * _activeLines.length;
  int get _voucherCount => _int(_vouchers['$_totalBet']);

  Future<void> _spin() async {
    if (_spinning) return;
    if (!_useVoucher && _int(_wallet['coins']) < _totalBet) {
      await _offerCoins(context, needed: _totalBet, current: _int(_wallet['coins']), onOpenStore: widget.onOpenStore, closeParent: true);
      return;
    }
    if (_useVoucher && _voucherCount <= 0) {
      widget.onMessage('Bu tutarda oyun biletin yok.');
      return;
    }
    unawaited(GameAudio.sfx('slot_spin', enabled: widget.soundEnabled, volume: .72));
    if (widget.vibrationEnabled) HapticFeedback.selectionClick();
    setState(() {
      _spinning = true;
      _wins = [];
      _lastPayout = 0;
      _countedWin = 0;
      _showWinOverlay = false;
      _winTitle = '';
      _message = 'Makaralar dönüyor…';
    });
    _startReelMotion();
    try {
      final out = await widget.api.playSideGame('slot', wager: _bet, useVoucher: _useVoucher, activeLines: _activeLines.toList()..sort());
      if (!mounted) return;
      if (out['ok'] != true) {
        _reelMotionTimer?.cancel();
        setState(() {
          _spinning = false;
          _message = _errorText('${out['code']}');
        });
        return;
      }

      final targetGrid = _list(out['grid']).map((r) => _list(r).map((x) => '$x').toList()).toList();
      await _landReels(targetGrid);
      if (!mounted) return;

      final payout = _int(out['payout_coins']);
      final net = _int(out['net_coins']);
      final diamonds = _int(out['premium_diamonds']);
      final resultClass = '${out['result_class'] ?? 'loss'}';
      final jackpotTier = '${out['jackpot_tier'] ?? ''}';
      final mult = (out['multiplier'] as num?)?.toDouble() ?? 0;
      setState(() {
        _grid = targetGrid;
        _wins = _list(out['wins']).map(_map).toList();
        _wallet = _salonWallet(_map(out['wallet']));
        _vouchers = _map(_wallet['slot_vouchers']);
        _spinning = false;
        _lastPayout = payout;
        final tierPrefix = jackpotTier.isEmpty ? '' : '$jackpotTier • ';
        _message = switch (resultClass) {
          'jackpot' => '${tierPrefix}NADİR TAŞ ÖDÜLÜ!  ×${_decimal(mult)}  •  +${_compact(payout)} ALTIN',
          'mega' => '${tierPrefix}BÜYÜK TAŞ ÖDÜLÜ!  ×${_decimal(mult)}  •  +${_compact(payout)} ALTIN',
          'big' => '${tierPrefix}GÜÇLÜ DESEN!  ×${_decimal(mult)}  •  +${_compact(payout)} ALTIN',
          'win' => '${tierPrefix}KAZANDIN  ×${_decimal(mult)}  •  +${_compact(net)} NET',
          'push' => 'Oyun miktarın geri geldi.',
          'partial' => '${_compact(payout)} altın geri döndü.',
          _ => 'Bu tur ödül çıkmadı.',
        } + (diamonds > 0 ? '  •  +$diamonds ELMAS' : '');
      });
      if (mult >= 2 && payout > 0) _startWinCount(payout, resultClass);
      if (resultClass == 'win' || resultClass == 'big' || resultClass == 'mega' || resultClass == 'jackpot') {
        if (widget.vibrationEnabled) HapticFeedback.mediumImpact();
        unawaited(GameAudio.sfx('coin_count', enabled: widget.soundEnabled, volume: .76));
        Future<void>.delayed(const Duration(milliseconds: 110), () {
          unawaited(GameAudio.sfx(resultClass == 'jackpot' ? 'win' : 'reward', enabled: widget.soundEnabled, volume: resultClass == 'jackpot' ? .92 : .72));
        });
      }
      widget.onWalletChanged?.call(_realWallet(_wallet));
    unawaited(widget.onRefresh());
    } catch (_) {
      _reelMotionTimer?.cancel();
      if (mounted) setState(() { _spinning = false; _message = 'Bağlantı yenileniyor…'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _premiumDialog(
      context,
      title: 'OKEYX ŞANSLI TAŞLAR',
      subtitle: '5 SÜTUN • 3 SIRA • 9 TAŞ DESENİ',
      icon: Icons.grid_view_rounded,
      accent: const Color(0xFFE5B95B),
      child: Column(
        children: [
          Row(children: [
            Expanded(child: _metricCard('BAKİYE', '${_compact(_int(_wallet['coins']))} ALTIN', Icons.monetization_on_rounded, OkeyXColors.gold)),
            const SizedBox(width: 7),
            Expanded(child: _metricCard('DESEN BAŞI', _compact(_bet), Icons.tune_rounded, const Color(0xFF81DDE8))),
            const SizedBox(width: 7),
            Expanded(child: _metricCard('TOPLAM OYUN', _compact(_totalBet), Icons.linear_scale_rounded, OkeyXColors.mint)),
            const SizedBox(width: 7),
            Expanded(child: _metricCard('NADİR ÖDÜL TAVANI', _compact(_totalBet * _int(widget.config['max_multiplier']).clamp(1, 5000).toInt()), Icons.local_fire_department_rounded, const Color(0xFFFF765C))),
          ]),
          const SizedBox(height: 6),
          _jackpotStrip(),
          const SizedBox(height: 7),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final controlsWidth = (constraints.maxWidth * .28).clamp(190.0, 245.0).toDouble();
                return Row(
                  children: [
                    Expanded(child: RepaintBoundary(child: _slotMachine())),
                    const SizedBox(width: 7),
                    SizedBox(width: controlsWidth, child: RepaintBoundary(child: _slotControls())),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }


  Widget _jackpotStrip() {
    final rows = _list(widget.config['jackpots']).map(_map).toList();
    final jackpots = rows.isEmpty
        ? const <Map<String, dynamic>>[
            {'name':'MINI','multiplier':20}, {'name':'MAJOR','multiplier':50}, {'name':'MEGA','multiplier':150}, {'name':'GRAND','multiplier':5000},
          ]
        : rows;
    return Row(
      children: [
        for (var i = 0; i < jackpots.length; i++) ...[
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                gradient: LinearGradient(colors: i == jackpots.length - 1 ? const [Color(0xFF5A2819), Color(0xFF26120E)] : const [Color(0xFF3D2F22), Color(0xFF251C15)]),
                border: Border.all(color: i == jackpots.length - 1 ? const Color(0x88FF9B43) : const Color(0x335BDCC6)),
              ),
              child: Column(children: [
                Text('${jackpots[i]['name']}', style: TextStyle(fontSize: 6.1, fontWeight: FontWeight.w900, color: i == jackpots.length - 1 ? const Color(0xFFFFB35B) : Colors.white54, letterSpacing: .8)),
                Text(_compact(_totalBet * _int(jackpots[i]['multiplier'])), style: const TextStyle(fontSize: 8.3, fontWeight: FontWeight.w900, color: OkeyXColors.gold)),
              ]),
            ),
          ),
          if (i < jackpots.length - 1) const SizedBox(width: 5),
        ],
      ],
    );
  }

  Widget _slotMachine() {
    final winCells = <String>{};
    final winLines = <int>{};
    for (final win in _wins) {
      final rows = _list(win['rows']).map(_int).toList();
      final count = _int(win['count']);
      winLines.add(_int(win['line']));
      for (var reel = 0; reel < math.min(count, rows.length); reel++) {
        winCells.add('${rows[reel]}:$reel');
      }
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(colors: [Color(0xFF3A2A13), Color(0xFF231B14), Color(0xFF120E0A)]),
        border: Border.all(color: const Color(0xFFB98B3B), width: 1.2),
        boxShadow: const [BoxShadow(color: Color(0x44000000), blurRadius: 18, offset: Offset(0, 8)), BoxShadow(color: Color(0x33E7B84C), blurRadius: 18)],
      ),
      child: Column(
        children: [
          Row(children: [
            const Icon(Icons.auto_awesome_rounded, size: 13, color: OkeyXColors.gold),
            const SizedBox(width: 5),
            const Text('OKEYX ŞANSLI TAŞLAR', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: OkeyXColors.gold, letterSpacing: .8)),
            const Spacer(),
            Text(winLines.isEmpty ? '${_activeLines.length}/9 ÇİZGİ AKTİF' : 'KAZANAN ÇİZGİ: ${winLines.join(', ')}', style: TextStyle(fontSize: 6.5, color: winLines.isEmpty ? Colors.white38 : OkeyXColors.mint, fontWeight: FontWeight.w900)),
          ]),
          const SizedBox(height: 6),
          Expanded(
            child: Stack(
              children: [
                Row(children: [
                  for (var col = 0; col < 5; col++) ...[
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(13),
                          gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF30251B), Color(0xFF16110C), Color(0xFF30251B)]),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Column(children: [
                          for (var row = 0; row < 3; row++)
                            Expanded(
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 80),
                                margin: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  gradient: winCells.contains('$row:$col') ? const LinearGradient(colors: [Color(0xFF65451D), Color(0xFF24190F)]) : const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF392C20), Color(0xFF18120D), Color(0xFF2F241B)]),
                                  border: Border.all(color: winCells.contains('$row:$col') ? OkeyXColors.gold : const Color(0x335FE0D0), width: winCells.contains('$row:$col') ? 1.7 : 1),
                                  boxShadow: winCells.contains('$row:$col') ? const [BoxShadow(color: Color(0x99F4C542), blurRadius: 12)] : const [],
                                ),
                                child: Center(child: _reelCell(row, col, winCells.contains('$row:$col'))),
                              ),
                            ),
                        ]),
                      ),
                    ),
                    if (col < 4) const SizedBox(width: 2),
                  ],
                ]),
                IgnorePointer(child: CustomPaint(size: Size.infinite, painter: _PaylinePainter(selectedLines: Set<int>.from(_activeLines), winningLines: Set<int>.from(winLines)))),
                if (_spinning)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x22000000), Color(0x9917B7B0), Color(0x22000000)], stops: [.0, .5, 1]),
                        ),
                        child: Center(child: Text('▾  ▾  ▾  ▾  ▾', style: TextStyle(fontSize: 21, letterSpacing: 13, color: Colors.white.withValues(alpha: .18), fontWeight: FontWeight.w900))),
                      ),
                    ),
                  ),
                AnimatedOpacity(
                  opacity: _showWinOverlay ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: IgnorePointer(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
                        decoration: BoxDecoration(
                          color: const Color(0xED11140D),
                          borderRadius: BorderRadius.circular(19),
                          border: Border.all(color: OkeyXColors.gold, width: 1.4),
                          boxShadow: const [BoxShadow(color: Color(0x99F4C542), blurRadius: 24)],
                        ),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Text(_winTitle, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: OkeyXColors.gold, letterSpacing: .7)),
                          const SizedBox(height: 4),
                          Text('+${_compact(_countedWin)}', style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900, color: Colors.white)),
                          const Text('ALTIN', style: TextStyle(fontSize: 7, color: Colors.white54, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                        ]),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          AnimatedContainer(
            duration: const Duration(milliseconds: 110),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: _wins.isEmpty ? Colors.black26 : OkeyXColors.gold.withValues(alpha: .10), borderRadius: BorderRadius.circular(11), border: Border.all(color: _wins.isEmpty ? Colors.white10 : OkeyXColors.gold.withValues(alpha: .35))),
            child: Text(_message, textAlign: TextAlign.center, style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: _wins.isEmpty ? Colors.white60 : OkeyXColors.gold)),
          ),
        ],
      ),
    );
  }

  Widget _reelCell(int row, int col, bool win) {
    final symbol = _grid[row][col];
    final key = _spinning
        ? ValueKey<String>('spin-$row-$col-$symbol-$_spinTick')
        : ValueKey<String>('land-$row-$col-$symbol');
    final cell = SizedBox(
      key: key,
      width: double.infinity,
      height: double.infinity,
      child: Center(child: RepaintBoundary(child: _slotSymbol(symbol, win, _spinning))),
    );
    if (_spinning) return ClipRect(child: cell);
    return ClipRect(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 90),
        reverseDuration: const Duration(milliseconds: 60),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: cell,
      ),
    );
  }

  void _setLineCount(int count) {
    if (_spinning) return;
    final target = count.clamp(1, _availableLines.length).toInt();
    setState(() {
      _activeLines
        ..clear()
        ..addAll(_availableLines.take(target));
      _useVoucher = _int(_vouchers['$_totalBet']) > 0;
    });
  }

  Widget _linePreset(int count, String label) {
    final target = count.clamp(1, _availableLines.length).toInt();
    final selected = _activeLines.length == target &&
        _availableLines.take(target).every(_activeLines.contains);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.only(right: 4),
        child: OutlinedButton(
          onPressed: _spinning ? null : () => _setLineCount(target),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            backgroundColor: selected ? OkeyXColors.gold.withValues(alpha: .16) : Colors.white.withValues(alpha: .025),
            side: BorderSide(color: selected ? OkeyXColors.gold.withValues(alpha: .72) : Colors.white12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('$target', style: TextStyle(fontSize: 10, color: selected ? OkeyXColors.gold : Colors.white, fontWeight: FontWeight.w900)),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 5.3, color: Colors.white38, fontWeight: FontWeight.w800)),
          ]),
        ),
      ),
    );
  }

  void _showRewardTable() {
    final tiers = _list(widget.config['payout_tiers']).map(_map).toList();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.grid_view_rounded, color: OkeyXColors.gold),
          SizedBox(width: 8),
          Text('Şanslı Taşlar • Ödül Tablosu'),
        ]),
        content: SizedBox(
          width: 430,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Her sonuç sunucuda belirlenir. Aşağıdaki çarpanlar toplam oyun miktarına uygulanır. Oyun içi altının nakit değeri yoktur.',
                style: TextStyle(fontSize: 10, color: Colors.white60, height: 1.35),
              ),
              const SizedBox(height: 12),
              if (tiers.isEmpty)
                const Text('Ödül tablosu şu anda sunucudan alınamadı.')
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 310),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: tiers.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final row = tiers[i];
                      final mult = (row['multiplier'] as num?)?.toDouble() ?? 0;
                      final probability = (row['probability_percent'] as num?)?.toDouble() ?? 0;
                      final label = '${row['label'] ?? 'Taş deseni'}';
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Container(
                          width: 40,
                          height: 34,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: OkeyXColors.gold.withValues(alpha: .10),
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(color: OkeyXColors.gold.withValues(alpha: .28)),
                          ),
                          child: Text('×${_decimal(mult)}', style: const TextStyle(fontSize: 9, color: OkeyXColors.gold, fontWeight: FontWeight.w900)),
                        ),
                        title: Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800)),
                        subtitle: Text('Yaklaşık olasılık: %${probability.toStringAsFixed(probability < .01 ? 5 : 2)}', style: const TextStyle(fontSize: 7, color: Colors.white38)),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('KAPAT'))],
      ),
    );
  }

  Widget _slotControls() {
    final maxLines = _availableLines.length;
    final presets = <(int, String)>[
      (1, 'AZ'),
      (math.min(3, maxLines), 'ORTA'),
      (math.min(5, maxLines), 'STANDART'),
      (maxLines, 'TAM'),
    ];
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xED261D15), Color(0xED18120D)]),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(right: 2, bottom: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('DESEN BAŞI OYUN', style: TextStyle(fontSize: 7.8, fontWeight: FontWeight.w900, color: Colors.white70)),
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (final value in _bets)
                        ChoiceChip(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          label: Text(_compact(value), style: const TextStyle(fontSize: 6.5, fontWeight: FontWeight.w900)),
                          selected: _bet == value,
                          onSelected: _spinning
                              ? null
                              : (_) => setState(() {
                                    _bet = value;
                                    _useVoucher = _int(_vouchers['$_totalBet']) > 0;
                                  }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 9),
                  Row(children: [
                    const Expanded(child: Text('TAŞ DESENLERİ', style: TextStyle(fontSize: 7.4, fontWeight: FontWeight.w900, color: Colors.white70))),
                    Text('${_activeLines.length}/$maxLines AKTİF', style: const TextStyle(fontSize: 6.2, color: OkeyXColors.mint, fontWeight: FontWeight.w900)),
                  ]),
                  const SizedBox(height: 5),
                  Row(children: [for (final preset in presets) _linePreset(preset.$1, preset.$2)]),
                  const SizedBox(height: 7),
                  const Text('İNCE AYAR', style: TextStyle(fontSize: 5.8, color: Colors.white38, fontWeight: FontWeight.w900, letterSpacing: .5)),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 5,
                    runSpacing: 5,
                    children: [
                      for (final line in _availableLines)
                        SizedBox(
                          width: 38,
                          height: 31,
                          child: FilterChip(
                            showCheckmark: false,
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            labelPadding: EdgeInsets.zero,
                            label: Center(child: Text('$line', style: const TextStyle(fontSize: 7, fontWeight: FontWeight.w900))),
                            selected: _activeLines.contains(line),
                            onSelected: _spinning
                                ? null
                                : (on) {
                                    setState(() {
                                      if (on) {
                                        _activeLines.add(line);
                                      } else if (_activeLines.length > 1) {
                                        _activeLines.remove(line);
                                      }
                                      _useVoucher = _int(_vouchers['$_totalBet']) > 0;
                                    });
                                  },
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: .18), borderRadius: BorderRadius.circular(11), border: Border.all(color: Colors.white10)),
                    child: Row(children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('AKTİF', style: TextStyle(fontSize: 5.3, color: Colors.white38, fontWeight: FontWeight.w800)),
                        Text('${_activeLines.length} desen', style: const TextStyle(fontSize: 7.3, fontWeight: FontWeight.w900)),
                      ])),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
                        const Text('DESEN BAŞI', style: TextStyle(fontSize: 5.3, color: Colors.white38, fontWeight: FontWeight.w800)),
                        Text(_compact(_bet), style: const TextStyle(fontSize: 7.3, fontWeight: FontWeight.w900)),
                      ])),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        const Text('TOPLAM', style: TextStyle(fontSize: 5.3, color: Colors.white38, fontWeight: FontWeight.w800)),
                        Text(_compact(_totalBet), style: const TextStyle(fontSize: 8, color: OkeyXColors.gold, fontWeight: FontWeight.w900)),
                      ])),
                    ]),
                  ),
                  const SizedBox(height: 5),
                  Text('${_activeLines.length} desen × ${_compact(_bet)} = ${_compact(_totalBet)} altın', style: const TextStyle(fontSize: 6.2, color: Colors.white38, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 7),
                  SizedBox(
                    width: double.infinity,
                    height: 32,
                    child: OutlinedButton.icon(
                      onPressed: _showRewardTable,
                      icon: const Icon(Icons.info_outline_rounded, size: 13),
                      label: const Text('ÖDÜL TABLOSU', style: TextStyle(fontSize: 6.8, fontWeight: FontWeight.w900)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Material(
            color: _voucherCount > 0 ? OkeyXColors.mint.withValues(alpha: _useVoucher ? .16 : .07) : Colors.white.withValues(alpha: .025),
            borderRadius: BorderRadius.circular(11),
            child: InkWell(
              onTap: _voucherCount > 0 && !_spinning ? () => setState(() => _useVoucher = !_useVoucher) : null,
              borderRadius: BorderRadius.circular(11),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                child: Row(children: [
                  Icon(Icons.local_activity_rounded, size: 15, color: _voucherCount > 0 ? OkeyXColors.mint : Colors.white30),
                  const SizedBox(width: 5),
                  Expanded(child: Text(_voucherCount > 0 ? '${_compact(_totalBet)} KUPON ×$_voucherCount' : 'BU OYUNDA BİLET YOK', style: const TextStyle(fontSize: 6.5, fontWeight: FontWeight.w900))),
                  if (_voucherCount > 0) Icon(_useVoucher ? Icons.check_circle_rounded : Icons.circle_outlined, size: 14, color: OkeyXColors.mint),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 7),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: _spinning ? null : _spin,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFB98223),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                elevation: 3,
              ),
              child: _spinning
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Text('TAŞLARI ÇEVİR', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, letterSpacing: 1)),
                      Text(_useVoucher ? 'OYUN BİLETİ' : '${_compact(_totalBet)} ALTIN', style: const TextStyle(fontSize: 6.5, fontWeight: FontWeight.w800)),
                    ]),
            ),
          ),
        ],
      ),
    );
  }

}

class HorseDialog extends StatefulWidget {
  final LobbyApiClient api;
  final Map<String, dynamic> config;
  final Map<String, dynamic> wallet;
  final Future<void> Function() onRefresh;
  final ValueChanged<String> onMessage;
  final VoidCallback? onOpenStore;
  final ValueChanged<Map<String,dynamic>>? onWalletChanged;
  final bool soundEnabled;
  final bool vibrationEnabled;

  const HorseDialog({super.key, required this.api, required this.config, required this.wallet, required this.onRefresh, required this.onMessage, this.onOpenStore, this.onWalletChanged, this.soundEnabled = true, this.vibrationEnabled = true});
  @override
  State<HorseDialog> createState() => _HorseDialogState();
}

class _HorseDialogState extends State<HorseDialog> {
  Timer? _raceTimer;
  final math.Random _raceRandom = math.Random();
  final Map<int, double> _horseProgress = <int, double>{};
  int _raceEpoch = 0;
  late List<int> _bets;
  late int _bet;
  late Map<String, dynamic> _wallet;
  late List<Map<String, dynamic>> _horses;
  int _selectedHorse = 1;
  bool _running = false;
  List<int> _order = [];
  String _result = 'Atını seç ve yarışı başlat.';

  @override
  void initState() {
    super.initState();
    _bets = _list(widget.config['bet_options']).map(_int).toList();
    if (_bets.isEmpty) {
      _bets = [500, 1000, 2500, 5000, 10000, 25000, 50000, 100000, 250000];
    }
    _bet = _bets.contains(1000) ? 1000 : (_bets.contains(5000) ? 5000 : _bets.first);
    _wallet = _salonWallet(widget.wallet);
    _horses = _list(widget.config['horses']).map(_map).toList();
    if (_horses.isNotEmpty) {
      _selectedHorse = _int(_horses.first['id']);
    }
    for (final horse in _horses) {
      _horseProgress[_int(horse['id'])] = .035;
    }
  }

  @override
  void dispose() {
    _raceTimer?.cancel();
    super.dispose();
  }

  void _startRaceMotion(int epoch) {
    _raceTimer?.cancel();
    _raceTimer = Timer.periodic(const Duration(milliseconds: 92), (_) {
      if (!mounted || !_running || epoch != _raceEpoch) return;
      setState(() {
        for (final horse in _horses) {
          final id = _int(horse['id']);
          final now = _horseProgress[id] ?? .035;
          if (now >= .80) continue;
          final burst = .018 + (_raceRandom.nextDouble() * .030) + (id == _selectedHorse ? .002 : 0);
          _horseProgress[id] = math.min(.80, now + burst);
        }
      });
    });
  }

  Future<void> _race() async {
    if (_running) return;
    if (_int(_wallet['coins']) < _bet) {
      await _offerCoins(context, needed: _bet, current: _int(_wallet['coins']), onOpenStore: widget.onOpenStore, closeParent: true);
      return;
    }
    final epoch = ++_raceEpoch;
    setState(() {
      _running = true;
      _order = [];
      for (final horse in _horses) {
        _horseProgress[_int(horse['id'])] = .035;
      }
      _result = 'Kapılar açılıyor…';
    });
    _startRaceMotion(epoch);
    unawaited(GameAudio.sfx('game_start', enabled: widget.soundEnabled, volume: .58));
    try {
      final started = DateTime.now();
      final out = await widget.api.playSideGame('horse', wager: _bet, choice: _selectedHorse);
      final wait = const Duration(milliseconds: 2350) - DateTime.now().difference(started);
      if (!wait.isNegative) await Future<void>.delayed(wait);
      if (!mounted || epoch != _raceEpoch) return;
      if (out['ok'] != true) {
        _raceTimer?.cancel();
        setState(() { _running = false; _result = _errorText('${out['code']}'); });
        return;
      }
      final order = _list(out['order']).map(_int).toList();
      _raceTimer?.cancel();
      // Finish in real order rather than freezing every horse at the same spot.
      setState(() {
        _order = order;
        for (var i = 0; i < order.length; i++) {
          _horseProgress[order[i]] = (1.0 - (i * .055)).clamp(.78, 1.0).toDouble();
        }
        _wallet = _salonWallet(_map(out['wallet']));
      });
      await Future<void>.delayed(const Duration(milliseconds: 620));
      if (!mounted || epoch != _raceEpoch) return;
      final won = out['won'] == true;
      setState(() {
        _running = false;
        _result = won ? 'KAZANDIN! +${_compact(_int(out['payout_coins']))} ALTIN' : '${_horseName(_int(out['winner']))} yarışı kazandı.';
      });
      if (won) {
        unawaited(GameAudio.sfx('coin_count', enabled: widget.soundEnabled, volume: .68));
        Future<void>.delayed(const Duration(milliseconds: 100), () => unawaited(GameAudio.sfx('reward', enabled: widget.soundEnabled, volume: .70)));
      }
      widget.onWalletChanged?.call(_realWallet(_wallet));
    unawaited(widget.onRefresh());
      // Result stays readable, then horses visibly return to the gates. The
      // next race is also immediately allowed; pressing it cancels this reset.
      Future<void>.delayed(const Duration(milliseconds: 1650), () {
        if (!mounted || _running || epoch != _raceEpoch) return;
        setState(() {
          _order = [];
          for (final horse in _horses) {
            _horseProgress[_int(horse['id'])] = .035;
          }
          _result = 'Yeni yarış hazır. Atını seç.';
        });
      });
    } catch (_) {
      _raceTimer?.cancel();
      if (mounted && epoch == _raceEpoch) setState(() { _running = false; _result = 'Bağlantı yenileniyor…'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _premiumDialog(
      context,
      title: 'OKEYX HİPODROM',
      subtitle: 'ATINI SEÇ • BAHİS KOY • YARIŞI İZLE',
      icon: Icons.sports_score_rounded,
      accent: const Color(0xFF73D6A8),
      child: Column(children: [
        Row(children: [
          Expanded(child: _metricCard('BAKİYE', '${_compact(_int(_wallet['coins']))} ALTIN', Icons.monetization_on_rounded, OkeyXColors.gold)),
          const SizedBox(width: 7),
          Expanded(child: _metricCard('BAHİS', _compact(_bet), Icons.flag_rounded, const Color(0xFF73D6A8))),
          const SizedBox(width: 7),
          Expanded(child: _metricCard('SEÇİLEN', _horseName(_selectedHorse), Icons.pets_rounded, const Color(0xFF8DC8FF))),
        ]),
        const SizedBox(height: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), gradient: const LinearGradient(colors: [Color(0xFF392C20), Color(0xFF292017), Color(0xFF16110C)]), border: Border.all(color: const Color(0x3373D6A8))),
            child: Column(children: [
              for (final horse in _horses)
                Expanded(child: _horseLane(horse)),
              const SizedBox(height: 5),
              Text(_result, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: _result.startsWith('KAZANDIN') ? OkeyXColors.gold : Colors.white70)),
            ]),
          ),
        ),
        const SizedBox(height: 7),
        Row(children: [
          Expanded(child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [for (final value in _bets) Padding(padding: const EdgeInsets.only(right: 5), child: ChoiceChip(label: Text(_compact(value), style: const TextStyle(fontSize: 6.5)), selected: _bet == value, onSelected: _running ? null : (_) => setState(() => _bet = value)))]))),
          const SizedBox(width: 8),
          SizedBox(width: 170, height: 42, child: FilledButton.icon(onPressed: _running ? null : _race, icon: const Icon(Icons.flag_rounded), label: Text(_running ? 'YARIŞIYOR…' : 'YARIŞI BAŞLAT', style: const TextStyle(fontSize: 7.5, fontWeight: FontWeight.w900)))),
        ]),
      ]),
    );
  }

  Widget _horseLane(Map<String, dynamic> horse) {
    final id = _int(horse['id']);
    final selected = id == _selectedHorse;
    final rank = _order.indexOf(id);
    final finish = (_horseProgress[id] ?? .035).clamp(.0, 1.0).toDouble();
    return InkWell(
      onTap: _running ? null : () => setState(() => _selectedHorse = id),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: selected ? const Color(0x2273D6A8) : Colors.black12, borderRadius: BorderRadius.circular(12), border: Border.all(color: selected ? const Color(0x6673D6A8) : Colors.white10)),
        child: Row(children: [
          SizedBox(width: 72, child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [Text('${horse['name']}', style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.w900)), Text('${horse['tag']} • ×${_decimal(horse['base_multiplier'])}', style: const TextStyle(fontSize: 6.3, color: Color(0x75FFFFFF)))])),
          Expanded(child: LayoutBuilder(builder: (_, box) => Stack(alignment: Alignment.centerLeft, children: [
            Container(height: 3, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(99))),
            AnimatedContainer(duration: const Duration(milliseconds: 80), curve: Curves.easeOut, width: box.maxWidth * finish, alignment: Alignment.centerRight, child: Text('🐎', style: TextStyle(fontSize: selected ? 20 : 17))),
          ]))),
          const SizedBox(width: 7),
          SizedBox(width: 28, child: Text(rank >= 0 ? '#${rank + 1}' : '#$id', textAlign: TextAlign.right, style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: rank == 0 ? OkeyXColors.gold : Colors.white54))),
        ]),
      ),
    );
  }
}

class CircusDialog extends StatefulWidget {
  final LobbyApiClient api;
  final Map<String, dynamic> config;
  final Map<String, dynamic> wallet;
  final Future<void> Function() onRefresh;
  final ValueChanged<String> onMessage;
  final VoidCallback? onOpenStore;
  final ValueChanged<Map<String,dynamic>>? onWalletChanged;
  final bool soundEnabled;
  final bool vibrationEnabled;

  const CircusDialog({super.key, required this.api, required this.config, required this.wallet, required this.onRefresh, required this.onMessage, this.onOpenStore, this.onWalletChanged, this.soundEnabled = true, this.vibrationEnabled = true});
  @override
  State<CircusDialog> createState() => _CircusDialogState();
}

class _CircusDialogState extends State<CircusDialog> {
  late List<int> _bets;
  late int _bet;
  late Map<String, dynamic> _wallet;
  Timer? _timer;
  int _active = 0;
  int _target = -1;
  int _count = 12;
  int _speed = 185;
  String? _challengeId;
  bool _running = false;
  bool _busy = false;
  String _result = 'Altın ışığı mor hedefte durdur.';

  @override
  void initState() {
    super.initState();
    _bets = _list(widget.config['bet_options']).map(_int).toList();
    if (_bets.isEmpty) _bets = [500, 1000, 2500, 5000, 10000, 25000, 50000, 100000, 250000];
    _bet = _bets.contains(1000) ? 1000 : (_bets.contains(5000) ? 5000 : _bets.first);
    _wallet = _salonWallet(widget.wallet);
  }

  @override
  void dispose() { _timer?.cancel(); super.dispose(); }

  Future<void> _start() async {
    if (_busy || _running) return;
    if (_int(_wallet['coins']) < _bet) {
      await _offerCoins(context, needed: _bet, current: _int(_wallet['coins']), onOpenStore: widget.onOpenStore, closeParent: true);
      return;
    }
    setState(() => _busy = true);
    final out = await widget.api.playSideGame('circus', wager: _bet, action: 'start');
    if (!mounted) return;
    if (out['ok'] != true) { setState(() { _busy = false; _result = _errorText('${out['code']}'); }); return; }
    _target = _int(out['target_index']);
    _count = _int(out['lamp_count']);
    _speed = _int(out['speed_ms']);
    _challengeId = '${out['challenge_id']}';
    _wallet = _salonWallet(_map(out['wallet']));
    final started = DateTime.now().millisecondsSinceEpoch;
    setState(() { _busy = false; _running = true; _result = 'IŞIK AKIYOR • doğru anda DURDUR!'; });
    _timer = Timer.periodic(const Duration(milliseconds: 30), (_) {
      if (mounted && _running) setState(() => _active = ((DateTime.now().millisecondsSinceEpoch - started) ~/ math.max(1, _speed)) % _count);
    });
  }

  Future<void> _stop() async {
    if (!_running || _busy) return;
    _timer?.cancel();
    setState(() { _running = false; _busy = true; });
    final out = await widget.api.playSideGame('circus', action: 'finish', challengeId: _challengeId);
    if (!mounted) return;
    if (out['ok'] != true) { setState(() { _busy = false; _result = _errorText('${out['code']}'); }); return; }
    _active = _int(out['stop_index']);
    _target = _int(out['target_index']);
    _wallet = _salonWallet(_map(out['wallet']));
    final grade = '${out['grade']}';
    setState(() {
      _busy = false;
      _challengeId = null;
      _result = grade == 'perfect' ? 'TAM İSABET!  +${_compact(_int(out['payout_coins']))} ALTIN' : grade == 'near' ? 'ÇOK YAKIN!  +${_compact(_int(out['payout_coins']))} ALTIN' : 'Hedefi kaçırdın.';
    });
    if (grade != 'miss') unawaited(GameAudio.sfx('reward', enabled: widget.soundEnabled, volume: .65));
    widget.onWalletChanged?.call(_realWallet(_wallet));
    unawaited(widget.onRefresh());
  }

  @override
  Widget build(BuildContext context) {
    return _premiumDialog(
      context,
      title: 'SİRK IŞIKLARI',
      subtitle: 'OKEYX’E ÖZGÜ REFLEKS / ZAMANLAMA OYUNU',
      icon: Icons.flare_rounded,
      accent: const Color(0xFFD795DC),
      child: Column(children: [
        Row(children: [
          Expanded(child: _metricCard('BAKİYE', '${_compact(_int(_wallet['coins']))} ALTIN', Icons.monetization_on_rounded, OkeyXColors.gold)),
          const SizedBox(width: 7),
          Expanded(child: _metricCard('BAHİS', _compact(_bet), Icons.flare_rounded, const Color(0xFFD795DC))),
          const SizedBox(width: 7),
          Expanded(child: _metricCard('HEDEF', _target < 0 ? 'GİZLİ' : '${_target + 1}', Icons.adjust_rounded, const Color(0xFF8BE4D1))),
        ]),
        const SizedBox(height: 8),
        Expanded(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), gradient: const RadialGradient(colors: [Color(0xFF4B2350), Color(0xFF251C15), Color(0xFF140F0B)]), border: Border.all(color: const Color(0x44D795DC))),
            child: Column(children: [
              const Text('ALTIN IŞIĞI YAKALA', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1)),
              const Spacer(),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [for (var i = 0; i < _count; i++) AnimatedContainer(duration: const Duration(milliseconds: 65), width: 39, height: 39, decoration: BoxDecoration(shape: BoxShape.circle, color: i == _active ? OkeyXColors.gold : const Color(0xCC251D15), border: Border.all(color: i == _target ? const Color(0xFFD795DC) : Colors.white12, width: i == _target ? 2.2 : 1), boxShadow: i == _active ? const [BoxShadow(color: Color(0x99F4C542), blurRadius: 15)] : const []), child: Center(child: Text('${i + 1}', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: i == _active ? const Color(0xFF251A09) : Colors.white70))))],
              ),
              const Spacer(),
              Text(_result, style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.w900)),
            ]),
          ),
        ),
        const SizedBox(height: 7),
        Row(children: [
          Expanded(child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [for (final value in _bets) Padding(padding: const EdgeInsets.only(right: 5), child: ChoiceChip(label: Text(_compact(value), style: const TextStyle(fontSize: 6.5)), selected: _bet == value, onSelected: _running || _busy ? null : (_) => setState(() => _bet = value)))]))),
          const SizedBox(width: 8),
          SizedBox(width: 155, height: 42, child: FilledButton.icon(onPressed: _busy ? null : (_running ? _stop : _start), icon: Icon(_running ? Icons.stop_circle_rounded : Icons.play_arrow_rounded), label: Text(_running ? 'DURDUR!' : 'BAŞLAT', style: const TextStyle(fontWeight: FontWeight.w900)))),
        ]),
      ]),
    );
  }
}


class DropDialog extends StatefulWidget {
  final LobbyApiClient api;
  final Map<String, dynamic> config;
  final Map<String, dynamic> wallet;
  final Future<void> Function() onRefresh;
  final VoidCallback? onOpenStore;
  final ValueChanged<Map<String,dynamic>>? onWalletChanged;
  final bool soundEnabled;
  final bool vibrationEnabled;
  const DropDialog({super.key, required this.api, required this.config, required this.wallet, required this.onRefresh, this.onOpenStore, this.onWalletChanged, this.soundEnabled = true, this.vibrationEnabled = true});
  @override State<DropDialog> createState() => _DropDialogState();
}

class _DropDialogState extends State<DropDialog> {
  late List<int> _bets;
  late int _bet;
  late Map<String,dynamic> _wallet;
  int _landing=-1;
  int _dropRound=0;
  bool _animatingDrop=false;
  bool _busy=false;
  String _result='Taşı bırak. Kenardaki x50 hazneleri nadir ama büyük vurur.';
  @override void initState(){super.initState();_bets=_list(widget.config['bet_options']).map(_int).toList();if(_bets.isEmpty)_bets=[500,1000,2500,5000,10000,25000,50000,100000,250000];_bet=_bets.contains(5000)?5000:_bets.first;_wallet=_salonWallet(widget.wallet);}
  Future<void> _play() async {
    if(_busy)return;
    if(_int(_wallet['coins'])<_bet){await _offerCoins(context,needed:_bet,current:_int(_wallet['coins']),onOpenStore:widget.onOpenStore,closeParent:true);return;}
    setState((){_busy=true;_animatingDrop=false;_landing=-1;_result='Sonuç hazırlanıyor…';});
    unawaited(GameAudio.sfx('tile_drop',enabled:widget.soundEnabled,volume:.76));
    try{
      final out=await widget.api.playSideGame('drop',wager:_bet);
      if(!mounted)return;
      if(out['ok']!=true){setState((){_busy=false;_result=_errorText('${out['code']}');});return;}
      final landing=_int(out['landing_index']).clamp(0,10).toInt();
      final mult=(out['multiplier'] as num?)?.toDouble()??0;
      final payout=_int(out['payout_coins']);
      setState((){_landing=landing;_dropRound++;_animatingDrop=true;_result='Okey taşı pimlerden sekiyor…';});
      for (final delay in <int>[160, 360, 610, 900, 1140]) {
        Future<void>.delayed(Duration(milliseconds: delay), () => unawaited(GameAudio.sfx('drop_bounce', enabled: widget.soundEnabled, volume: .60)));
      }
      await Future<void>.delayed(const Duration(milliseconds:1350));
      if(!mounted)return;
      setState((){_busy=false;_animatingDrop=false;_wallet=_salonWallet(_map(out['wallet']));_result=mult>=2?'×${_decimal(mult)}!  +${_compact(payout)} ALTIN':mult>=1?'Bahsin geri geldi • ×${_decimal(mult)}':mult>0?'${_compact(payout)} altın geri döndü.':'Bu taş boş hazneye düştü.';});
      if(mult>=2){if(widget.vibrationEnabled)HapticFeedback.mediumImpact();unawaited(GameAudio.sfx('coin_count',enabled:widget.soundEnabled,volume:.78));Future<void>.delayed(const Duration(milliseconds:100),()=>unawaited(GameAudio.sfx('reward',enabled:widget.soundEnabled,volume:.78)));}
      widget.onWalletChanged?.call(_realWallet(_wallet));
    unawaited(widget.onRefresh());
    }catch(_){if(mounted)setState((){_busy=false;_animatingDrop=false;_result='Bağlantı yenileniyor…';});}
  }
  @override
  Widget build(BuildContext context) => _premiumDialog(
        context,
        title: 'OKEY DROP',
        subtitle: 'PİMLERDEN SEK • ÖDÜL HAZNESİNE DÜŞ',
        icon: Icons.south_rounded,
        accent: const Color(0xFF5DD7FF),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(child: _metricCard('BAKİYE', '${_compact(_int(_wallet['coins']))} ALTIN', Icons.monetization_on_rounded, OkeyXColors.gold)),
                const SizedBox(width: 7),
                Expanded(child: _metricCard('BAHİS', _compact(_bet), Icons.south_rounded, const Color(0xFF5DD7FF))),
                const SizedBox(width: 7),
                Expanded(child: _metricCard('TAVAN', '×50', Icons.trending_up_rounded, const Color(0xFFFFC44C))),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: const LinearGradient(colors: [Color(0xFF34281D), Color(0xFF221A13), Color(0xFF140F0B)]),
                  border: Border.all(color: const Color(0x335DD7FF)),
                ),
                child: _animatingDrop
                    ? TweenAnimationBuilder<double>(
                        key: ValueKey(_dropRound),
                        tween: Tween(begin: 0, end: 1),
                        duration: const Duration(milliseconds: 1280),
                        curve: Curves.easeInOutCubic,
                        builder: (_, progress, __) => CustomPaint(painter: _DropBoardPainter(active: _landing, progress: progress)),
                      )
                    : CustomPaint(painter: _DropBoardPainter(active: _busy ? -1 : _landing, progress: _busy ? .02 : 1)),
              ),
            ),
            const SizedBox(height: 6),
            Text(_result, style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.w900)),
            const SizedBox(height: 7),
            Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final v in _bets)
                          Padding(
                            padding: const EdgeInsets.only(right: 5),
                            child: ChoiceChip(
                              label: Text(_compact(v), style: const TextStyle(fontSize: 6.5)),
                              selected: _bet == v,
                              onSelected: _busy ? null : (_) => setState(() => _bet = v),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 160,
                  height: 42,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _play,
                    icon: const Icon(Icons.south_rounded),
                    label: Text(_busy ? 'DÜŞÜYOR…' : 'TAŞI BIRAK', style: const TextStyle(fontWeight: FontWeight.w900)),
                  ),
                ),
              ],
            ),
          ],
        ),
      );

}

class TowerDialog extends StatefulWidget {
  final LobbyApiClient api; final Map<String,dynamic> config; final Map<String,dynamic> wallet; final Future<void> Function() onRefresh; final VoidCallback? onOpenStore;
  final ValueChanged<Map<String,dynamic>>? onWalletChanged; final bool soundEnabled; final bool vibrationEnabled;
  const TowerDialog({super.key,required this.api,required this.config,required this.wallet,required this.onRefresh,this.onOpenStore,this.onWalletChanged,this.soundEnabled=true,this.vibrationEnabled=true});
  @override State<TowerDialog> createState()=>_TowerDialogState();
}
class _TowerDialogState extends State<TowerDialog>{
  late List<int> _bets;late int _bet;late Map<String,dynamic> _wallet;String? _cid;int _floor=0;bool _busy=false;bool _finished=false;String _result='Bahsi koy, kuleye gir. Güvendeyken istediğin an çekilebilirsin.';
  List<double> get _mults=>_list(widget.config['multipliers']).map((x)=>(x as num?)?.toDouble()??0).where((x)=>x>0).toList();
  @override void initState(){super.initState();_bets=_list(widget.config['bet_options']).map(_int).toList();if(_bets.isEmpty)_bets=[1000,2500,5000,10000,25000,50000,100000,250000];_bet=_bets.contains(5000)?5000:_bets.first;_wallet=_salonWallet(widget.wallet);}
  Future<void> _start()async{if(_busy)return;if(_int(_wallet['coins'])<_bet){await _offerCoins(context,needed:_bet,current:_int(_wallet['coins']),onOpenStore:widget.onOpenStore,closeParent:true);return;}setState((){_busy=true;_finished=false;_floor=0;_result='Kasa kapıları hazırlanıyor…';});final out=await widget.api.playSideGame('tower',wager:_bet);if(!mounted)return;if(out['ok']!=true){setState((){_busy=false;_result=_errorText('${out['code']}');});return;}setState((){_busy=false;_cid='${out['challenge_id']}';_wallet=_salonWallet(_map(out['wallet']));_result='1. kat • üç kapıdan birini seç.';});}
  Future<void> _choose(int door)async{if(_busy||_cid==null)return;setState(()=>_busy=true);unawaited(GameAudio.sfx('ui_tap',enabled:widget.soundEnabled,volume:.6));final out=await widget.api.playSideGame('tower',action:'choose',challengeId:_cid,choice:door);if(!mounted)return;if(out['ok']!=true){setState((){_busy=false;_result=_errorText('${out['code']}');});return;}final safe=out['safe']==true;final finished=out['finished']==true;setState((){_busy=false;_wallet=_salonWallet(_map(out['wallet']));_floor=_int(out['floor']);_finished=finished;if(!safe){_cid=null;_result='TUZAK! Bu turdaki bahis gitti.';}else if(finished){_cid=null;_result='KULE TAMAMLANDI! +${_compact(_int(out['payout_coins']))} ALTIN';}else{_result='GÜVENLİ! ${_floor+1}. kata çıktın. Devam mı, çekil mi?';}});widget.onWalletChanged?.call(_realWallet(_wallet));unawaited(GameAudio.sfx(safe?'tower_safe':'tower_fail',enabled:widget.soundEnabled,volume: safe ? .82 : .88));if(safe&&finished){Future<void>.delayed(const Duration(milliseconds:120),()=>unawaited(GameAudio.sfx('coin_count',enabled:widget.soundEnabled,volume:.86)));}await widget.onRefresh();}
  Future<void> _cashout()async{if(_busy||_cid==null||_floor<=0)return;setState(()=>_busy=true);final out=await widget.api.playSideGame('tower',action:'cashout',challengeId:_cid);if(!mounted)return;setState((){_busy=false;_cid=null;_finished=true;_wallet=_salonWallet(_map(out['wallet']));_result='KAZANCI ALDIN • +${_compact(_int(out['payout_coins']))} ALTIN';});widget.onWalletChanged?.call(_realWallet(_wallet));unawaited(GameAudio.sfx('coin_count',enabled:widget.soundEnabled,volume:.86));Future<void>.delayed(const Duration(milliseconds:100),()=>unawaited(GameAudio.sfx('reward',enabled:widget.soundEnabled,volume:.76)));await widget.onRefresh();}
  @override
  Widget build(BuildContext context) {
    final mults = _mults.isEmpty ? <double>[1.35, 1.9, 2.8, 4.4, 7.5, 13.0] : _mults;
    return _premiumDialog(
      context,
      title: 'KASA KULESİ',
      subtitle: 'KAPI SEÇ • KAT ÇIK • İSTEDİĞİN AN ÇEKİL',
      icon: Icons.account_balance_rounded,
      accent: const Color(0xFFEAC45B),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _metricCard('BAKİYE', '${_compact(_int(_wallet['coins']))} ALTIN', Icons.monetization_on_rounded, OkeyXColors.gold)),
              const SizedBox(width: 7),
              Expanded(child: _metricCard('BAHİS', _compact(_bet), Icons.lock_rounded, const Color(0xFFEAC45B))),
              const SizedBox(width: 7),
              Expanded(child: _metricCard('KAT', '${math.min(_floor + 1, 6)} / 6', Icons.stairs_rounded, const Color(0xFF6BE1BE))),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  flex: 5,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      gradient: const LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Color(0xFF251C15), Color(0xFF49351A), Color(0xFF201812)]),
                      border: Border.all(color: const Color(0x44EAC45B)),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        for (var i = mults.length - 1; i >= 0; i--)
                          Expanded(
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              margin: const EdgeInsets.only(bottom: 4),
                              decoration: BoxDecoration(
                                color: i < _floor ? const Color(0x333ED09B) : i == _floor ? const Color(0x33EAC45B) : Colors.black12,
                                borderRadius: BorderRadius.circular(9),
                                border: Border.all(color: i == _floor ? const Color(0x88EAC45B) : Colors.white10),
                              ),
                              child: Row(
                                children: [
                                  const SizedBox(width: 8),
                                  Icon(i < _floor ? Icons.lock_open_rounded : Icons.lock_rounded, size: 14, color: i < _floor ? OkeyXColors.mint : OkeyXColors.gold),
                                  const SizedBox(width: 7),
                                  Text('${i + 1}. KAT', style: const TextStyle(fontSize: 7, fontWeight: FontWeight.w900)),
                                  const Spacer(),
                                  Text('×${_decimal(mults[i])}', style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: OkeyXColors.gold)),
                                  const SizedBox(width: 8),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 4,
                  child: Column(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: const Color(0xB81A140E), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white10)),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(_result, textAlign: TextAlign.center, style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.w900)),
                              const SizedBox(height: 12),
                              if (_cid != null && !_finished)
                                Row(
                                  children: [
                                    for (var d = 0; d < 3; d++)
                                      Expanded(
                                        child: Padding(
                                          padding: EdgeInsets.only(right: d < 2 ? 5 : 0),
                                          child: FilledButton(
                                            onPressed: _busy ? null : () => _choose(d),
                                            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF76531F), padding: const EdgeInsets.symmetric(vertical: 14)),
                                            child: Text('${d + 1}', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900)),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              if (_cid != null && _floor > 0 && !_finished) ...[
                                const SizedBox(height: 7),
                                SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: _busy ? null : _cashout, icon: const Icon(Icons.savings_rounded), label: const Text('KAZANCI AL'))),
                              ],
                              if (_cid == null) ...[
                                const SizedBox(height: 8),
                                SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _busy ? null : _start, icon: const Icon(Icons.play_arrow_rounded), label: const Text('KULEYE GİR'))),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 7),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final v in _bets)
                              Padding(
                                padding: const EdgeInsets.only(right: 5),
                                child: ChoiceChip(
                                  label: Text(_compact(v), style: const TextStyle(fontSize: 6.5)),
                                  selected: _bet == v,
                                  onSelected: _cid != null || _busy ? null : (_) => setState(() => _bet = v),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

}

class _DropBoardPainter extends CustomPainter{
  final int active;
  final double progress;
  const _DropBoardPainter({required this.active,this.progress=1});
  @override void paint(Canvas canvas,Size size){
    final peg=Paint()..color=const Color(0xFF8CD7D2);
    final glow=Paint()..color=const Color(0x335DD7FF);
    const cols=11,rows=8;
    for(var r=0;r<rows;r++){
      final count=6+r;final gap=size.width/(count+1);
      for(var c=0;c<count;c++){
        final x=gap*(c+1)+(r.isOdd?gap*.15:0);final y=20+r*(size.height-72)/(rows-1);
        final o=Offset(x.clamp(8.0,size.width-8.0).toDouble(),y);
        canvas.drawCircle(o,4.8,glow);canvas.drawCircle(o,2.2,peg);
      }
    }
    const labels=['×50','×10','×5','×2','×0.5','×0','×0.5','×2','×5','×10','×50'];
    final w=size.width/cols;
    for(var i=0;i<cols;i++){
      final hit=progress>.93&&i==active;
      final rect=RRect.fromRectAndRadius(Rect.fromLTWH(i*w+2,size.height-38,w-4,31),const Radius.circular(6));
      canvas.drawRRect(rect,Paint()..color=hit?const Color(0xFFB87920):const Color(0xFF2F241B));
      final tp=TextPainter(text:TextSpan(text:labels[i],style:TextStyle(color:hit?Colors.white:const Color(0xFFB5D7D5),fontSize:7,fontWeight:FontWeight.w900)),textDirection:TextDirection.ltr)..layout();
      tp.paint(canvas,Offset(i*w+(w-tp.width)/2,size.height-28));
    }
    if(active>=0 && progress<1){
      final t=progress.clamp(0.0,1.0);
      final targetX=(active+.5)*w;
      final baseX=size.width*.5+(targetX-size.width*.5)*math.pow(t,1.35).toDouble();
      final wobble=math.sin(t*math.pi*9)*(1-t)*size.width*.065;
      final x=(baseX+wobble).clamp(9.0,size.width-9.0).toDouble();
      final y=10+(size.height-58)*t;
      canvas.drawCircle(Offset(x,y),9,Paint()..color=const Color(0x335DD7FF));
      canvas.drawCircle(Offset(x,y),6,Paint()..color=const Color(0xFFF4E7C7));
      canvas.drawCircle(Offset(x-1.5,y-1.5),2,Paint()..color=const Color(0xFF0B8C77));
    }
  }
  @override bool shouldRepaint(covariant _DropBoardPainter old)=>old.active!=active||old.progress!=progress;
}


Widget _gameTile(BuildContext context, {required String title, required String subtitle, required String description, required IconData icon, required Color accent, required String badge, required VoidCallback onTap}) {
  final kind = title.contains('REELS') ? 'slot' : title.contains('HİPODROM') ? 'horse' : title.contains('SİRK') ? 'circus' : title.contains('DROP') ? 'drop' : 'tower';
  return Material(
    color: Colors.transparent,
    borderRadius: BorderRadius.circular(20),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Ink(
        height: 142,
        decoration: BoxDecoration(
          color: const Color(0xFF1C1510),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: accent.withValues(alpha: .42), width: 1.1),
          boxShadow: [BoxShadow(color: accent.withValues(alpha: .08), blurRadius: 18, offset: const Offset(0, 8)), const BoxShadow(color: Color(0x55000000), blurRadius: 13, offset: Offset(0, 6))],
        ),
        child: Stack(children: [
          Positioned.fill(child: ClipRRect(borderRadius: BorderRadius.circular(19), child: CustomPaint(painter: _ChanceArtPainter(kind: kind, accent: accent)))),
          Positioned(left: 12, top: 10, child: Container(width: 36, height: 36, decoration: BoxDecoration(color: const Color(0xD9291F17), borderRadius: BorderRadius.circular(11), border: Border.all(color: accent.withValues(alpha: .42))), child: Icon(icon, color: accent, size: 21))),
          Positioned(right: 10, top: 10, child: Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4), decoration: BoxDecoration(color: const Color(0xD91C1510), borderRadius: BorderRadius.circular(9), border: Border.all(color: accent.withValues(alpha: .34))), child: Text(badge, style: TextStyle(fontSize: 6, color: accent, fontWeight: FontWeight.w900)))),
          Positioned(left: 12, right: 96, bottom: 11, child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900, letterSpacing: .2)),
            const SizedBox(height: 1),
            Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 7.1, color: accent, fontWeight: FontWeight.w900)),
            const SizedBox(height: 3),
            Text(description, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 6.5, height: 1.22, color: Colors.white60)),
          ])),
          Positioned(right: 12, bottom: 12, child: Container(width: 72, height: 29, alignment: Alignment.center, decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(10), boxShadow: [BoxShadow(color: accent.withValues(alpha: .25), blurRadius: 10)]), child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Text('OYNA', style: TextStyle(fontSize: 7.2, fontWeight: FontWeight.w900, color: Color(0xFF16110D))), SizedBox(width: 3), Icon(Icons.play_arrow_rounded, size: 13, color: Color(0xFF16110D))]))),
        ]),
      ),
    ),
  );
}

class _ChanceArtPainter extends CustomPainter {
  final String kind;
  final Color accent;
  const _ChanceArtPainter({required this.kind, required this.accent});
  @override
  void paint(Canvas canvas, Size size) {
    final fade = Paint()..color = accent.withValues(alpha: .055);
    canvas.drawCircle(Offset(size.width * .86, size.height * .42), size.height * .72, fade);
    final line = Paint()..color = accent.withValues(alpha: .22)..style = PaintingStyle.stroke..strokeWidth = 1.4;
    final fill = Paint()..color = accent.withValues(alpha: .12);
    final right = Rect.fromLTWH(size.width * .66, 34, size.width * .30, size.height - 66);
    if (kind == 'slot') {
      final w = right.width / 3.5;
      for (var i = 0; i < 3; i++) {
        final r = RRect.fromRectAndRadius(Rect.fromLTWH(right.left + i * (w + 5), right.top + 6, w, right.height - 12), const Radius.circular(7));
        canvas.drawRRect(r, fill); canvas.drawRRect(r, line);
        final tp = TextPainter(text: TextSpan(text: i == 0 ? '11' : (i == 1 ? '12' : '13'), style: TextStyle(color: accent.withValues(alpha: .70), fontSize: 18, fontWeight: FontWeight.w900)), textDirection: TextDirection.ltr)..layout();
        tp.paint(canvas, Offset(r.center.dx - tp.width / 2, r.center.dy - tp.height / 2));
      }
    } else if (kind == 'horse') {
      for (var i = 0; i < 3; i++) {
        final y = right.top + 13 + i * 20;
        canvas.drawLine(Offset(right.left, y + 7), Offset(right.right, y + 7), Paint()..color = Colors.white.withValues(alpha: .05)..strokeWidth = 1);
        canvas.drawCircle(Offset(right.left + 12 + i * 13, y), 5, fill);
        canvas.drawLine(Offset(right.left + 17 + i * 13, y), Offset(right.left + 38 + i * 10, y), line);
      }
      canvas.drawLine(Offset(right.right - 8, right.top), Offset(right.right - 8, right.bottom), Paint()..color = accent.withValues(alpha: .45)..strokeWidth = 2);
    } else if (kind == 'circus') {
      final c = right.center;
      for (var i = 0; i < 10; i++) {
        final a = (math.pi * 2 * i) / 10;
        canvas.drawCircle(Offset(c.dx + math.cos(a) * 31, c.dy + math.sin(a) * 31), 4.2, Paint()..color = accent.withValues(alpha: i == 2 ? .8 : .18));
      }
      canvas.drawCircle(c, 11, fill); canvas.drawCircle(c, 11, line);
    } else if (kind == 'drop') {
      for (var r = 0; r < 5; r++) {
        for (var c = 0; c < 6 + r; c++) {
          final x = right.left + 6 + c * (right.width - 12) / (5 + r);
          final y = right.top + 5 + r * 13;
          if (x <= right.right) canvas.drawCircle(Offset(x, y), 2.3, Paint()..color = accent.withValues(alpha: .38));
        }
      }
    } else {
      for (var i = 0; i < 5; i++) {
        final rect = RRect.fromRectAndRadius(Rect.fromLTWH(right.left + i * 3, right.bottom - 14 - i * 13, right.width - i * 6, 10), const Radius.circular(3));
        canvas.drawRRect(rect, i == 4 ? (Paint()..color = accent.withValues(alpha: .35)) : fill);
        canvas.drawRRect(rect, line);
      }
    }
  }
  @override bool shouldRepaint(covariant _ChanceArtPainter old) => old.kind != kind || old.accent != accent;
}

Widget _premiumDialog(BuildContext context, {required String title, required String subtitle, required IconData icon, required Color accent, required Widget child}) {
  return Dialog(
    backgroundColor: const Color(0xFF140F0B),
    insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: BorderSide(color: accent.withValues(alpha: .36))),
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 1040,
        maxHeight: (MediaQuery.sizeOf(context).height - 16).clamp(320.0, 620.0).toDouble(),
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 12),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF281F17), Color(0xFF18120E), Color(0xFF040D14)])),
        child: Column(children: [
          Row(children: [
            Container(width: 37, height: 37, decoration: BoxDecoration(color: accent.withValues(alpha: .12), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: accent, size: 22)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
                Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 6.2, color: accent, fontWeight: FontWeight.w800, letterSpacing: .4)),
              ]),
            ),
            const SizedBox(width: 6),
            const Flexible(child: Text('OYUN İÇİ ALTIN • NAKİT YOK', maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right, style: TextStyle(fontSize: 5.8, color: Colors.white30, fontWeight: FontWeight.w800))),
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, size: 19)),
          ]),
          const SizedBox(height: 4),
          Expanded(child: child),
        ]),
      ),
    ),
  );
}

Widget _metricCard(String label, String value, IconData icon, Color accent) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(color: accent.withValues(alpha: .055), borderRadius: BorderRadius.circular(12), border: Border.all(color: accent.withValues(alpha: .16))),
      child: Row(children: [Icon(icon, size: 15, color: accent), const SizedBox(width: 6), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(fontSize: 5.5, color: Colors.white38, fontWeight: FontWeight.w800)), Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w900))]))]),
    );

Widget _walletPill(IconData icon, String value, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(color: color.withValues(alpha: .08), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withValues(alpha: .15))),
      child: Row(children: [Icon(icon, size: 14, color: color), const SizedBox(width: 4), Text(value, style: TextStyle(fontSize: 8, color: color, fontWeight: FontWeight.w900))]),
    );

Widget _voucherBar(Map<String, dynamic> vouchers) {
  final rows = vouchers.entries.where((e) => _int(e.value) > 0).toList()..sort((a, b) => _int(a.key).compareTo(_int(b.key)));
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(color: const Color(0xFF2B2118), borderRadius: BorderRadius.circular(13), border: Border.all(color: OkeyXColors.gold.withValues(alpha: .20))),
    child: Row(children: [
      const Icon(Icons.local_activity_rounded, color: OkeyXColors.gold, size: 15),
      const SizedBox(width: 6),
      const Text('OYUN BİLETLERİ', style: TextStyle(fontSize: 7, color: OkeyXColors.gold, fontWeight: FontWeight.w900)),
      const SizedBox(width: 9),
      Expanded(child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [for (final e in rows) Container(margin: const EdgeInsets.only(right: 5), padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4), decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)), child: Text('${_compact(_int(e.key))} ×${_int(e.value)}', style: const TextStyle(fontSize: 6.8, fontWeight: FontWeight.w900)))]))),
    ]),
  );
}

Widget _slotSymbol(String id, bool win, bool spinning) {
  String value='?'; String tag=''; Color color=Colors.white54;
  switch(id){
    case 'cherry': value='7'; color=const Color(0xFFD32929); break;
    case 'bar': value='10'; color=const Color(0xFF121212); break;
    case 'seven': value='13'; color=const Color(0xFFC99414); break;
    case 'star': value='5'; tag='★'; color=const Color(0xFF236FCE); break;
    case 'crown': value='11'; tag='♛'; color=const Color(0xFFD32929); break;
    case 'okey': value='O'; tag='OKEY'; color=const Color(0xFF188A5B); break;
    case 'diamond': value='12'; tag='✦'; color=const Color(0xFF236FCE); break;
  }
  final child=Container(width:38,height:47,alignment:Alignment.center,decoration:BoxDecoration(gradient:const LinearGradient(colors:[Color(0xFFFFFFFF),Color(0xFFFFFAF0),Color(0xFFE6D9C8)]),borderRadius:BorderRadius.circular(8),border:Border.all(color:win?OkeyXColors.gold:const Color(0xFFB8AA99),width:win?2:1),boxShadow:win?const[BoxShadow(color:Color(0x99F4C542),blurRadius:13)]:const[BoxShadow(color:Color(0x55000000),blurRadius:3,offset:Offset(0,2))]),child:Column(mainAxisSize:MainAxisSize.min,children:[Text(value,style:TextStyle(fontSize:value=='O'?18:20,fontWeight:FontWeight.w900,color:color,height:.9)),if(tag.isNotEmpty)Text(tag,style:TextStyle(fontSize:5.2,fontWeight:FontWeight.w900,color:color,height:1))]));
  return AnimatedScale(scale: spinning ? .90 : 1,duration:const Duration(milliseconds:80),child:child);
}

class _PaylinePainter extends CustomPainter {
  final Set<int> selectedLines;
  final Set<int> winningLines;
  const _PaylinePainter({required this.selectedLines, required this.winningLines});
  static const lines = <List<int>>[
    [0, 0, 0, 0, 0], [1, 1, 1, 1, 1], [2, 2, 2, 2, 2], [0, 1, 2, 1, 0], [2, 1, 0, 1, 2], [0, 0, 1, 2, 2], [2, 2, 1, 0, 0], [1, 0, 1, 2, 1], [1, 2, 1, 0, 1],
  ];
  @override
  void paint(Canvas canvas, Size size) {
    if (selectedLines.isEmpty && winningLines.isEmpty) return;
    final w = size.width / 5;
    final h = size.height / 3;
    final all = <int>{...selectedLines, ...winningLines};
    for (final n in all) {
      if (n < 1 || n > lines.length) continue;
      final path = Path();
      final rows = lines[n - 1];
      for (var col = 0; col < 5; col++) {
        final point = Offset(w * col + w / 2, h * rows[col] + h / 2);
        if (col == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      final win = winningLines.contains(n);
      canvas.drawPath(path, Paint()..color = (win ? OkeyXColors.gold : OkeyXColors.mint).withValues(alpha: win ? .92 : .20)..strokeWidth = win ? 2.4 : .8..style = PaintingStyle.stroke);
    }
  }
  @override
  bool shouldRepaint(covariant _PaylinePainter oldDelegate) => true;
}

Future<void> _offerCoins(BuildContext context, {required int needed, required int current, VoidCallback? onOpenStore, bool closeParent = false}) async {
  final missing = math.max(0, needed - current);
  final go = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: const Color(0xFF1D1610),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: OkeyXColors.gold.withValues(alpha: .30))),
      title: const Row(children: [Icon(Icons.monetization_on_rounded, color: OkeyXColors.gold), SizedBox(width: 7), Text('ALTININ YETMİYOR')]),
      content: Text('Bu oyun için ${_compact(needed)} altın gerekiyor. Bakiyen ${_compact(current)} • ${_compact(missing)} eksik. Günlük fırsatlardan uygun paketi seçebilirsin.', style: const TextStyle(fontSize: 9, color: Colors.white70)),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('VAZGEÇ')), FilledButton.icon(onPressed: () => Navigator.pop(dialogContext, true), icon: const Icon(Icons.storefront_rounded), label: const Text('PAKETLERE BAK'))],
    ),
  );
  if (go == true && onOpenStore != null) {
    if (closeParent && context.mounted) {
      Navigator.of(context).pop();
    }
    onOpenStore();
  }
}

String _errorText(String code) => switch (code) {
      'invalid_wager' => 'Bu çizgi bahsi kullanılamıyor.',
      'invalid_paylines' => 'En az bir taş deseni seç.',
      'invalid_total_wager' => 'Toplam bahis sınırı aşıldı.',
      'insufficient_coins' => 'Yeterli altının yok.',
      'slot_voucher_unavailable' => 'Bu tutarda oyun biletin yok.',
      'circus_challenge_expired' => 'Turun süresi doldu.',
      _ => 'Oyun şu anda tamamlanamadı.',
    };

String _horseName(int id) => switch (id) {1 => 'Şimşek', 2 => 'Rüzgâr', 3 => 'Kuzgun', 4 => 'Yıldırım', _ => 'Rakip'};
String _decimal(dynamic value) { final n = value is num ? value.toDouble() : double.tryParse('$value') ?? 0; return n.toStringAsFixed(n % 1 == 0 ? 0 : 2); }
String _compact(int value) {
  final negative = value < 0, abs = value.abs();
  String scale(double n, String suffix) {
    var t = n.toStringAsFixed(2);
    while (t.contains('.') && t.endsWith('0')) {
      t = t.substring(0, t.length - 1);
    }
    if (t.endsWith('.')) {
      t = t.substring(0, t.length - 1);
    }
    return '${negative ? '-' : ''}$t$suffix';
  }
  if (abs >= 1000000000) return scale(abs / 1000000000, 'B');
  if (abs >= 1000000) return scale(abs / 1000000, 'M');
  if (abs >= 1000) return scale(abs / 1000, 'K');
  return '$value';
}
int _int(dynamic value) => value is num ? value.toInt() : int.tryParse('$value') ?? 0;
/// Şans Salonu yalnız KAZANILMIŞ bakiyeyle oynanır. Diyaloglar 'coins' alanını
/// salon bakiyesi olarak görür; gerçek (satın alınmış olabilen) altın 'real_coins'te saklanır.
Map<String, dynamic> _salonWallet(Map<String, dynamic> w) {
  final m = Map<String, dynamic>.from(w);
  if (m.containsKey('real_coins')) return m;
  m['real_coins'] = m['coins'];
  if (m['salon_chips'] != null) m['coins'] = m['salon_chips'];
  return m;
}

Map<String, dynamic> _realWallet(Map<String, dynamic> w) {
  final m = Map<String, dynamic>.from(w);
  if (m.containsKey('real_coins')) m['coins'] = m['real_coins'];
  return m;
}

Map<String, dynamic> _map(dynamic value) => value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
List<dynamic> _list(dynamic value) => value is List ? value : const <dynamic>[];
