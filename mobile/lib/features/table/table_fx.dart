// mobile/lib/features/table/table_fx.dart
// Masa üstü efekt katmanı: taş uçuşu (yay, 3D çevirme, gölge, iniş ezilmesi)
// ve gerçek parçacık dumanı. Emoji/yazı karakteri kullanmaz.
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../widgets/tile_widget.dart';

/// Bir GlobalKey'in ekran koordinatındaki merkezi.
Offset centerOfKey(GlobalKey key) {
  final box = key.currentContext?.findRenderObject() as RenderBox?;
  if (box == null || !box.attached) return Offset.zero;
  return box.localToGlobal(box.size.center(Offset.zero));
}

class TableFxController {
  _TableFxLayerState? _state;

  /// Taşı [from] noktasından [to] noktasına uçurur (ekran koordinatları).
  /// [flip] true ise kapalı taş uçarken açılır (desteden çekme).
  void flyTile({
    required GameTile tile,
    required Offset from,
    required Offset to,
    Size size = const Size(44, 62),
    String skinId = 'tiles_ivory',
    bool flip = false,
    bool puffOnLand = true,
    Duration duration = const Duration(milliseconds: 560),
    VoidCallback? onLand,
  }) {
    final s = _state;
    if (s == null) {
      onLand?.call();
      return;
    }
    s._fly(tile, from, to, size, skinId, flip, puffOnLand, duration, onLand);
  }

  /// Verilen ekran noktasında duman çıkarır.
  void puff(Offset at, {Color color = const Color(0xFFCFD4DA)}) =>
      _state?._puff(at, color);

  /// Konumlar katmanın genişlik/yüksekliğinin oranı (0..1) olarak verilir.
  void flyTileFrac({
    required GameTile tile,
    required Offset from,
    required Offset to,
    Size size = const Size(34, 48),
    String skinId = 'tiles_ivory',
    bool flip = false,
    bool puffOnLand = true,
    Duration duration = const Duration(milliseconds: 520),
    VoidCallback? onLand,
  }) {
    final s = _state;
    if (s == null) {
      onLand?.call();
      return;
    }
    final area = s._layerSize();
    s._fly(tile, Offset(from.dx * area.width, from.dy * area.height),
        Offset(to.dx * area.width, to.dy * area.height), size, skinId, flip,
        puffOnLand, duration, onLand, local: true);
  }

  /// Kazanma kutlaması: masanın üstünde altın/turkuaz/kırmızı konfeti patlamaları.
  void confetti() {
    const colors = [Color(0xFFFFC531), Color(0xFF5EF0D0), Color(0xFFFF5C3D), Color(0xFFFFFFFF)];
    const spots = [Offset(.25, .35), Offset(.75, .35), Offset(.50, .25), Offset(.35, .55), Offset(.65, .55), Offset(.50, .45)];
    for (var i = 0; i < spots.length * 2; i++) {
      Future<void>.delayed(Duration(milliseconds: 90 * i), () {
        puffFrac(spots[i % spots.length], color: colors[i % colors.length]);
      });
    }
  }

  void puffFrac(Offset at, {Color color = const Color(0xFFCFD4DA)}) {
    final s = _state;
    if (s == null) return;
    final area = s._layerSize();
    s._puff(Offset(at.dx * area.width, at.dy * area.height), color, global: false);
  }
}

class TableFxLayer extends StatefulWidget {
  const TableFxLayer({super.key, required this.controller, required this.child});
  final TableFxController controller;
  final Widget child;

  @override
  State<TableFxLayer> createState() => _TableFxLayerState();
}

class _TableFxLayerState extends State<TableFxLayer> {
  final Map<int, Widget> _fx = {};
  int _nextId = 0;

  @override
  void initState() {
    super.initState();
    widget.controller._state = this;
  }

  @override
  void didUpdateWidget(TableFxLayer old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller._state = null;
      widget.controller._state = this;
    }
  }

  @override
  void dispose() {
    if (widget.controller._state == this) widget.controller._state = null;
    super.dispose();
  }

  Offset _local(Offset global) {
    final box = context.findRenderObject() as RenderBox?;
    return box == null ? global : box.globalToLocal(global);
  }

  bool get _reduced => MediaQuery.of(context).disableAnimations;

  void _add(Widget Function(int id) build) {
    final id = _nextId++;
    setState(() => _fx[id] = build(id));
  }

  void _remove(int id) {
    if (mounted) setState(() => _fx.remove(id));
  }

  Size _layerSize() {
    final box = context.findRenderObject() as RenderBox?;
    return (box != null && box.hasSize) ? box.size : MediaQuery.of(context).size;
  }

  void _fly(GameTile tile, Offset from, Offset to, Size size, String skinId,
      bool flip, bool puffOnLand, Duration duration, VoidCallback? onLand,
      {bool local = false}) {
    if (_reduced) {
      onLand?.call();
      return;
    }
    final f = local ? from : _local(from);
    final t = local ? to : _local(to);
    _add((id) => _FlyingTileFx(
          key: ValueKey('fly$id'),
          tile: tile,
          from: f,
          to: t,
          size: size,
          skinId: skinId,
          flip: flip,
          duration: duration,
          onLand: () {
            HapticFeedback.lightImpact();
            if (puffOnLand) _puff(t, const Color(0xFFCFD4DA), global: false);
            onLand?.call();
          },
          onDone: () => _remove(id),
        ));
  }

  void _puff(Offset at, Color color, {bool global = true}) {
    if (_reduced) return;
    final p = global ? _local(at) : at;
    _add((id) => _PuffFx(
          key: ValueKey('puff$id'),
          origin: p,
          color: color,
          onDone: () => _remove(id),
        ));
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: widget.child),
        if (_fx.isNotEmpty)
          Positioned.fill(
            child: IgnorePointer(
              child: Stack(clipBehavior: Clip.none, children: _fx.values.toList()),
            ),
          ),
      ],
    );
  }
}

class _FlyingTileFx extends StatefulWidget {
  const _FlyingTileFx({
    super.key,
    required this.tile,
    required this.from,
    required this.to,
    required this.size,
    required this.skinId,
    required this.flip,
    required this.duration,
    required this.onLand,
    required this.onDone,
  });
  final GameTile tile;
  final Offset from;
  final Offset to;
  final Size size;
  final String skinId;
  final bool flip;
  final Duration duration;
  final VoidCallback onLand;
  final VoidCallback onDone;

  @override
  State<_FlyingTileFx> createState() => _FlyingTileFxState();
}

class _FlyingTileFxState extends State<_FlyingTileFx>
    with SingleTickerProviderStateMixin {
  static const _flightShare = .86;
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.duration);
  bool _landed = false;

  @override
  void initState() {
    super.initState();
    _c.addListener(() {
      if (!_landed && _c.value >= _flightShare) {
        _landed = true;
        widget.onLand();
      }
    });
    _c.forward().whenComplete(() {
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        final p = Curves.easeOutCubic.transform((t / _flightShare).clamp(0.0, 1.0));
        final land = ((t - _flightShare) / (1 - _flightShare)).clamp(0.0, 1.0);
        final ground = Offset.lerp(widget.from, widget.to, p)!;
        final dist = (widget.to - widget.from).distance;
        final arc = math.sin(math.pi * p);
        final lift = arc * math.min(46.0, dist * .16);
        final squash = math.sin(math.pi * land) * .04;
        // Taşlar uçarken de düz kalır (eğik taş istenmiyor).
        const tilt = 0.0;
        final flipAngle = widget.flip ? (1 - p) * math.pi : 0.0;
        final showBack = flipAngle > math.pi / 2;
        final tile = widget.flip ? widget.tile.copyWith(faceDown: showBack) : widget.tile;
        final lifted = 1 + arc * .10;
        final shadowScale = 1 - arc * .25;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: ground.dx - s.width * .45,
              top: ground.dy + s.height * .30,
              width: s.width * .9,
              height: s.height * .22,
              child: Transform.scale(
                scale: shadowScale,
                child: Opacity(
                  opacity: .30 * (1 - arc * .45),
                  child: const ClipOval(child: ColoredBox(color: Colors.black)),
                ),
              ),
            ),
            Positioned(
              left: ground.dx - s.width / 2,
              top: ground.dy - lift - s.height / 2,
              width: s.width,
              height: s.height,
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, .0012)
                  ..rotateZ(tilt)
                  ..rotateY(showBack ? flipAngle - math.pi : flipAngle)
                  ..scale(lifted + squash, lifted - squash, 1.0),
                child: TileWidget(tile: tile, skinId: widget.skinId),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Particle {
  _Particle(this.dx, this.rise, this.size, this.delay, this.spark);
  final double dx;
  final double rise;
  final double size;
  final double delay;
  final bool spark;
}

class _PuffFx extends StatefulWidget {
  const _PuffFx({super.key, required this.origin, required this.color, required this.onDone});
  final Offset origin;
  final Color color;
  final VoidCallback onDone;

  @override
  State<_PuffFx> createState() => _PuffFxState();
}

class _PuffFxState extends State<_PuffFx> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 650));
  late final List<_Particle> _ps;

  @override
  void initState() {
    super.initState();
    final rnd = math.Random();
    _ps = [
      // Taş çuhaya inince hafif toz; abartılı duman yok.
      for (var i = 0; i < 7; i++)
        _Particle((rnd.nextDouble() - .5) * 44, 10 + rnd.nextDouble() * 18,
            5 + rnd.nextDouble() * 7, rnd.nextDouble() * .15, false),
      for (var i = 0; i < 3; i++)
        _Particle((rnd.nextDouble() - .5) * 60, 8 + rnd.nextDouble() * 16,
            3 + rnd.nextDouble() * 3, rnd.nextDouble() * .1, true),
    ];
    _c.forward().whenComplete(() {
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => CustomPaint(
        size: Size.infinite,
        painter: _PuffPainter(_c.value, _ps, widget.origin, widget.color),
      ),
    );
  }
}

class _PuffPainter extends CustomPainter {
  _PuffPainter(this.t, this.ps, this.origin, this.color);
  final double t;
  final List<_Particle> ps;
  final Offset origin;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in ps) {
      final q = ((t - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
      if (q <= 0) continue;
      final ease = Curves.easeOutCubic.transform(q);
      final pos = origin + Offset(p.dx * ease, -p.rise * ease);
      if (p.spark) {
        canvas.drawCircle(
          pos,
          p.size * .22 * (1 - q * .6),
          Paint()..color = const Color(0xFFFFD27A).withValues(alpha: 1 - q),
        );
      } else {
        final fade = q < .18 ? q / .18 : (1 - q) / .82;
        final r = p.size * (.5 + 1.7 * q);
        canvas.drawCircle(
          pos,
          r,
          Paint()
            ..color = color.withValues(alpha: .46 * fade)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * .45),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_PuffPainter old) => old.t != t;
}
