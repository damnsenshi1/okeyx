import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_theme.dart';
import '../core/live_features.dart';

/// Fixed-height radio showcase used in both lobby and table.
///
/// The station catalogue is paged in groups of six. It deliberately contains
/// no vertical scroll view so even short landscape phones keep the player,
/// tabs, station grid and transport controls visible at the same time.
class PremiumRadioPanel extends StatefulWidget {
  final List<OkeyXRadioStation> stations;
  final String activeStationId;
  final bool playing;
  final OkeyXNowPlaying nowPlaying;
  final String title;
  final String subtitle;
  final bool compact;

  const PremiumRadioPanel({
    super.key,
    required this.stations,
    required this.activeStationId,
    required this.playing,
    required this.nowPlaying,
    this.title = 'OKEYX RADYO',
    this.subtitle = 'Canlı Türk radyoları • seç ve oyuna dön',
    this.compact = false,
  });

  @override
  State<PremiumRadioPanel> createState() => _PremiumRadioPanelState();
}

class _PremiumRadioPanelState extends State<PremiumRadioPanel> {
  static const _pageSize = 6;
  static const _favoriteKey = 'okeyx_radio_favorites_v1';
  static const _tabs = ['Popüler', 'Favoriler', 'Kategoriler'];
  static const _categories = ['Tümü', 'Pop', 'Arabesk', 'Yabancı'];

  String _tab = _tabs.first;
  String _category = _categories.first;
  int _page = 0;
  Set<String> _favorites = <String>{};

  @override
  void initState() {
    super.initState();
    unawaited(_loadFavorites());
  }

  Future<void> _loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_favoriteKey) ?? const <String>[];
    if (mounted) setState(() => _favorites = stored.toSet());
  }

  Future<void> _toggleFavorite(String id) async {
    setState(() {
      if (!_favorites.add(id)) _favorites.remove(id);
      _page = 0;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_favoriteKey, _favorites.toList()..sort());
  }

  String _stationCategory(OkeyXRadioStation station) {
    final id = station.id.toLowerCase();
    if (id == 'kral_fm') return 'Arabesk';
    if (id == 'power_fm' || id == 'metro_fm') return 'Yabancı';
    return 'Pop';
  }

  List<OkeyXRadioStation> get _visibleStations {
    Iterable<OkeyXRadioStation> rows = widget.stations;
    if (_tab == 'Favoriler') {
      rows = rows.where((station) => _favorites.contains(station.id));
    } else if (_tab == 'Kategoriler' && _category != 'Tümü') {
      rows = rows.where((station) => _stationCategory(station) == _category);
    }
    return rows.toList();
  }

  IconData _stationIcon(OkeyXRadioStation station) {
    final id = station.id.toLowerCase();
    if (id.contains('turk')) return Icons.music_note_rounded;
    if (id.contains('metro')) return Icons.bolt_rounded;
    if (id.contains('fenomen')) return Icons.local_fire_department_rounded;
    if (id.contains('kral')) return Icons.workspace_premium_rounded;
    if (id.contains('power')) return Icons.flash_on_rounded;
    return Icons.radio_rounded;
  }

  Color _stationColor(OkeyXRadioStation station) {
    final id = station.id.toLowerCase();
    if (id.contains('kral')) return const Color(0xFFFFB23E);
    if (id.contains('power')) return const Color(0xFF65C7FF);
    if (id.contains('metro')) return const Color(0xFF9A8CFF);
    if (id.contains('fenomen')) return const Color(0xFFFF6D78);
    return OkeyXColors.mint;
  }

  void _selectTab(String value) {
    setState(() {
      _tab = value;
      _page = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final short = size.height < 470 || widget.compact;
    final active = widget.stations.firstWhere(
      (station) => station.id == widget.activeStationId,
      orElse: () => widget.stations.first,
    );
    final rows = _visibleStations;
    final pages = math.max(1, (rows.length / _pageSize).ceil());
    final page = _page.clamp(0, pages - 1).toInt();
    final pageRows = rows.skip(page * _pageSize).take(_pageSize).toList();
    final accent = _stationColor(active);
    final nowPlaying = widget.nowPlaying.available
        ? widget.nowPlaying.label
        : '${active.title} • canlı yayın';

    return Container(
      width: math.min(size.width - 28, 820.0),
      height: math.min(size.height - 20, short ? 410.0 : 520.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF181044), Color(0xFF100A2E), Color(0xFF0D0822)],
        ),
        border: Border.all(color: accent.withValues(alpha: .42)),
        boxShadow: const [BoxShadow(color: Color(0xB3000000), blurRadius: 36, offset: Offset(0, 15))],
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(short ? 12 : 17, short ? 10 : 14, short ? 12 : 17, short ? 10 : 14),
        child: Column(children: [
          Row(children: [
            Container(
              width: short ? 34 : 42,
              height: short ? 34 : 42,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: accent.withValues(alpha: .13),
                border: Border.all(color: accent.withValues(alpha: .35)),
              ),
              child: Icon(Icons.radio_rounded, color: accent, size: short ? 18 : 22),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.title, style: TextStyle(fontSize: short ? 12 : 14, fontWeight: FontWeight.w900, letterSpacing: .7)),
              Text(widget.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 7, color: Colors.white54, fontWeight: FontWeight.w700)),
            ])),
            IconButton(
              tooltip: 'Kapat',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded, color: Colors.white70),
            ),
          ]),
          SizedBox(height: short ? 6 : 9),
          Container(
            width: double.infinity,
            height: short ? 66 : 82,
            padding: EdgeInsets.symmetric(horizontal: short ? 10 : 14, vertical: short ? 8 : 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(19),
              gradient: LinearGradient(colors: [accent.withValues(alpha: .22), const Color(0xEE150E37), const Color(0xF20E0927)]),
              border: Border.all(color: accent.withValues(alpha: .45)),
              boxShadow: [BoxShadow(color: accent.withValues(alpha: .11), blurRadius: 20)],
            ),
            child: Row(children: [
              Container(
                width: short ? 45 : 57,
                height: short ? 45 : 57,
                decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black26, border: Border.all(color: accent.withValues(alpha: .50), width: 2)),
                child: Icon(_stationIcon(active), color: accent, size: short ? 23 : 29),
              ),
              const SizedBox(width: 11),
              Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(widget.playing ? 'ŞU AN ÇALIYOR' : 'SEÇİLİ İSTASYON', style: TextStyle(fontSize: 6.4, color: widget.playing ? OkeyXColors.gold : Colors.white54, fontWeight: FontWeight.w900, letterSpacing: .8)),
                  const SizedBox(width: 6),
                  if (widget.playing) const _RadioLiveDot(),
                ]),
                const SizedBox(height: 2),
                Text(active.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: short ? 12 : 15, fontWeight: FontWeight.w900)),
                Text(nowPlaying, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 7.2, color: Colors.white60, fontWeight: FontWeight.w700)),
              ])),
              if (widget.playing) _RadioEqualizer(color: accent, compact: short),
              const SizedBox(width: 9),
              IconButton.filled(
                tooltip: widget.playing ? 'Durdur' : 'Oynat',
                style: IconButton.styleFrom(backgroundColor: widget.playing ? OkeyXColors.danger.withValues(alpha: .82) : accent, foregroundColor: Colors.white),
                onPressed: () => Navigator.pop(context, widget.playing ? '__off__' : '__play__'),
                icon: Icon(widget.playing ? Icons.stop_rounded : Icons.play_arrow_rounded),
              ),
            ]),
          ),
          SizedBox(height: short ? 6 : 9),
          Row(children: [
            for (final tab in _tabs) ...[
              Expanded(
                child: _RadioTab(
                  label: tab,
                  selected: _tab == tab,
                  onTap: () => _selectTab(tab),
                ),
              ),
              if (tab != _tabs.last) const SizedBox(width: 6),
            ],
          ]),
          if (_tab == 'Kategoriler') ...[
            const SizedBox(height: 5),
            Row(children: [
              for (final category in _categories) ...[
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() { _category = category; _page = 0; }),
                    borderRadius: BorderRadius.circular(10),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      height: 25,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _category == category ? OkeyXColors.gold.withValues(alpha: .15) : Colors.white.withValues(alpha: .025),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _category == category ? OkeyXColors.gold.withValues(alpha: .45) : Colors.white10),
                      ),
                      child: Text(category, style: TextStyle(fontSize: 6.5, fontWeight: FontWeight.w900, color: _category == category ? OkeyXColors.gold : Colors.white54)),
                    ),
                  ),
                ),
                if (category != _categories.last) const SizedBox(width: 5),
              ],
            ]),
          ],
          SizedBox(height: short ? 6 : 8),
          Expanded(
            child: pageRows.isEmpty
                ? _RadioEmptyFavorites(onShowPopular: () => _selectTab('Popüler'))
                : GridView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    padding: EdgeInsets.zero,
                    itemCount: pageRows.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: short ? 6 : 8,
                      mainAxisSpacing: short ? 5 : 7,
                      childAspectRatio: short ? 4.3 : 4.6,
                    ),
                    itemBuilder: (context, index) {
                      final station = pageRows[index];
                      final selected = station.id == widget.activeStationId && widget.playing;
                      return _RadioStationCard(
                        station: station,
                        selected: selected,
                        favorite: _favorites.contains(station.id),
                        color: _stationColor(station),
                        icon: _stationIcon(station),
                        category: _stationCategory(station),
                        onFavorite: () => _toggleFavorite(station.id),
                        onPlay: () => Navigator.pop(context, station.id),
                      );
                    },
                  ),
          ),
          if (pages > 1) ...[
            const SizedBox(height: 5),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton(onPressed: page > 0 ? () => setState(() => _page = page - 1) : null, icon: const Icon(Icons.chevron_left_rounded)),
              Text('${page + 1} / $pages', style: const TextStyle(fontSize: 7.5, color: Colors.white54, fontWeight: FontWeight.w900)),
              IconButton(onPressed: page + 1 < pages ? () => setState(() => _page = page + 1) : null, icon: const Icon(Icons.chevron_right_rounded)),
            ]),
          ],
        ]),
      ),
    );
  }
}

class _RadioTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _RadioTab({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 170),
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? OkeyXColors.mint.withValues(alpha: .11) : Colors.white.withValues(alpha: .025),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: selected ? OkeyXColors.mint.withValues(alpha: .42) : Colors.white10),
            ),
            child: Text(label.toUpperCase(), style: TextStyle(fontSize: 7, fontWeight: FontWeight.w900, color: selected ? OkeyXColors.mint : Colors.white54, letterSpacing: .35)),
          ),
        ),
      );
}

class _RadioStationCard extends StatelessWidget {
  final OkeyXRadioStation station;
  final bool selected;
  final bool favorite;
  final Color color;
  final IconData icon;
  final String category;
  final VoidCallback onFavorite;
  final VoidCallback onPlay;

  const _RadioStationCard({
    required this.station,
    required this.selected,
    required this.favorite,
    required this.color,
    required this.icon,
    required this.category,
    required this.onFavorite,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPlay,
          borderRadius: BorderRadius.circular(15),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              gradient: LinearGradient(colors: [color.withValues(alpha: selected ? .17 : .08), Colors.white.withValues(alpha: .025)]),
              border: Border.all(color: color.withValues(alpha: selected ? .62 : .22), width: selected ? 1.4 : 1),
              boxShadow: selected ? [BoxShadow(color: color.withValues(alpha: .12), blurRadius: 12)] : null,
            ),
            child: Row(children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: .13), border: Border.all(color: color.withValues(alpha: .35))),
                child: Icon(selected ? Icons.graphic_eq_rounded : icon, color: color, size: 16),
              ),
              const SizedBox(width: 8),
              Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(station.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900)),
                Text(selected ? 'ÇALIYOR • CANLI' : '$category • CANLI', maxLines: 1, style: TextStyle(fontSize: 5.8, color: selected ? color : Colors.white38, fontWeight: FontWeight.w900, letterSpacing: .25)),
              ])),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                onPressed: onFavorite,
                icon: Icon(favorite ? Icons.star_rounded : Icons.star_border_rounded, color: favorite ? OkeyXColors.gold : Colors.white30, size: 17),
              ),
              Icon(selected ? Icons.graphic_eq_rounded : Icons.play_circle_fill_rounded, color: selected ? color : Colors.white54, size: 21),
            ]),
          ),
        ),
      );
}

class _RadioEmptyFavorites extends StatelessWidget {
  final VoidCallback onShowPopular;
  const _RadioEmptyFavorites({required this.onShowPopular});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: .025), borderRadius: BorderRadius.circular(17), border: Border.all(color: Colors.white10)),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.star_border_rounded, color: OkeyXColors.gold, size: 28),
          const SizedBox(height: 5),
          const Text('Henüz favori istasyonun yok', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900)),
          Text('İstasyon kartındaki yıldızla favori ekleyebilirsin.', style: TextStyle(fontSize: 6.5, color: Colors.white.withValues(alpha: .45))),
          const SizedBox(height: 7),
          TextButton(onPressed: onShowPopular, child: const Text('POPÜLERİ GÖSTER', style: TextStyle(fontSize: 7, fontWeight: FontWeight.w900))),
        ]),
      );
}

class _RadioLiveDot extends StatefulWidget {
  const _RadioLiveDot();
  @override
  State<_RadioLiveDot> createState() => _RadioLiveDotState();
}

class _RadioLiveDotState extends State<_RadioLiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
  }
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _controller,
        builder: (_, __) => Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(shape: BoxShape.circle, color: OkeyXColors.danger.withValues(alpha: .55 + _controller.value * .45), boxShadow: [BoxShadow(color: OkeyXColors.danger.withValues(alpha: .2 + _controller.value * .3), blurRadius: 6)]),
        ),
      );
}

class _RadioEqualizer extends StatefulWidget {
  final Color color;
  final bool compact;
  const _RadioEqualizer({required this.color, required this.compact});
  @override
  State<_RadioEqualizer> createState() => _RadioEqualizerState();
}

class _RadioEqualizerState extends State<_RadioEqualizer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1050))..repeat();
  }
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _controller,
        builder: (_, __) => SizedBox(
          width: widget.compact ? 33 : 43,
          height: widget.compact ? 27 : 34,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            for (var i = 0; i < 5; i++)
              Container(
                width: widget.compact ? 3 : 4,
                height: 6 + (widget.compact ? 18 : 25) * (.18 + .82 * ((math.sin((_controller.value * math.pi * 2) + i * 1.17) + 1) / 2)),
                decoration: BoxDecoration(color: widget.color, borderRadius: BorderRadius.circular(5), boxShadow: [BoxShadow(color: widget.color.withValues(alpha: .25), blurRadius: 4)]),
              ),
          ]),
        ),
      );
}
