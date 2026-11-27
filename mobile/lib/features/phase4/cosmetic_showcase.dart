import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_theme.dart';
import '../../widgets/okx_kit.dart';
import '../../widgets/tile_widget.dart';

/// Mağaza vitrini: 3D görünümlü kozmetik kartları ve "masada dene" önizlemesi.
///
/// Kart parmakla sürüklenince eğilir (perspektif), bırakınca yaylanarak
/// yerine döner; boşta hafifçe salınır. Üstünde eğimle kayan bir parlama
/// vardır. Efsanevi/epik ürünlerin arkasında nefes alan bir ışık halkası olur.
/// Önizlemeler gerçek oyun görselleriyle çizilir (ıstaka, taş, çuha).

Color rarityColor(String rarity) => switch (rarity) {
      'legendary' => const Color(0xFFFFC75A),
      'epic' => const Color(0xFFBC86FF),
      'rare' => const Color(0xFF68CBFF),
      _ => const Color(0xFF9FB3C8),
    };

String rarityLabel(String rarity) => switch (rarity) {
      'legendary' => 'EFSANEVİ',
      'epic' => 'EPİK',
      'rare' => 'NADİR',
      _ => 'SIRADAN',
    };

Color cosmeticAccent(String id) {
  if (id.contains('gold') || id.contains('royal') || id.contains('crown')) return const Color(0xFFFFC845);
  if (id.contains('sakura') || id.contains('rose')) return const Color(0xFFFF9AB8);
  if (id.contains('ice')) return const Color(0xFF9DEBFF);
  if (id.contains('ember') || id.contains('phoenix') || id.contains('sunset')) return const Color(0xFFFF8D58);
  if (id.contains('neon')) return const Color(0xFFB46BFF);
  if (id.contains('bosphorus')) return const Color(0xFF3FD8E0);
  if (id.contains('obsidian') || id.contains('carbon')) return const Color(0xFF9DA8B4);
  if (id.contains('midnight')) return const Color(0xFF8B8DFF);
  if (id.contains('marble')) return const Color(0xFFE8E2D6);
  return const Color(0xFF54E2BE);
}

/// Parmakla çevrilebilen 3D eğim sarmalayıcı.
class Tilt3D extends StatefulWidget {
  const Tilt3D({super.key, required this.child, this.maxAngle = .38, this.idleSway = true});
  final Widget child;
  final double maxAngle;
  final bool idleSway;

  @override
  State<Tilt3D> createState() => _Tilt3DState();
}

class _Tilt3DState extends State<Tilt3D> with TickerProviderStateMixin {
  double _rx = 0, _ry = 0;
  late final AnimationController _spring = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
  late final AnimationController _sway = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();
  double _fromX = 0, _fromY = 0;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _spring.addListener(() {
      final t = Curves.elasticOut.transform(_spring.value);
      setState(() {
        _rx = _fromX * (1 - t);
        _ry = _fromY * (1 - t);
      });
    });
  }

  @override
  void dispose() {
    _spring.dispose();
    _sway.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return GestureDetector(
      onPanStart: (_) {
        _spring.stop();
        _dragging = true;
      },
      onPanUpdate: (d) => setState(() {
        _ry = (_ry + d.delta.dx * .012).clamp(-widget.maxAngle, widget.maxAngle);
        _rx = (_rx - d.delta.dy * .012).clamp(-widget.maxAngle, widget.maxAngle);
      }),
      onPanEnd: (_) {
        _dragging = false;
        _fromX = _rx;
        _fromY = _ry;
        _spring.forward(from: 0);
      },
      child: AnimatedBuilder(
        animation: _sway,
        builder: (context, child) {
          final idle = (widget.idleSway && !_dragging && !reduce) ? math.sin(_sway.value * 2 * math.pi) * .07 : 0.0;
          final ry = _ry + idle;
          final rx = _rx + (widget.idleSway && !reduce ? math.cos(_sway.value * 2 * math.pi) * .03 : 0.0);
          final m = Matrix4.identity()
            ..setEntry(3, 2, .0013)
            ..rotateX(rx)
            ..rotateY(ry);
          return Transform(
            alignment: Alignment.center,
            transform: m,
            child: Stack(children: [
              child!,
              // Eğimle kayan cam parlaması.
              Positioned.fill(
                child: IgnorePointer(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment(-1.4 + ry * 3, -1),
                          end: Alignment(1.4 + ry * 3, 1),
                          colors: const [Color(0x00FFFFFF), Color(0x26FFFFFF), Color(0x00FFFFFF)],
                          stops: const [.38, .5, .62],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ]),
          );
        },
        child: widget.child,
      ),
    );
  }
}

/// Nadir ürünlerin arkasındaki nefes alan ışık halkası.
class RarityHalo extends StatefulWidget {
  const RarityHalo({super.key, required this.color, required this.child, this.strong = false});
  final Color color;
  final Widget child;
  final bool strong;

  @override
  State<RarityHalo> createState() => _RarityHaloState();
}

class _RarityHaloState extends State<RarityHalo> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (context, child) => DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(color: widget.color.withValues(alpha: (widget.strong ? .30 : .16) + .18 * _c.value), blurRadius: 18 + 14 * _c.value, spreadRadius: -2),
            ],
          ),
          child: child,
        ),
        child: widget.child,
      );
}

/// Ürünün gerçek oyun görselleriyle önizlemesi.
class CosmeticPreview extends StatelessWidget {
  const CosmeticPreview({super.key, required this.item, this.height = 92});
  final Map<String, dynamic> item;
  final double height;

  @override
  Widget build(BuildContext context) {
    final id = '${item['id']}';
    final category = '${item['category']}';
    final accent = cosmeticAccent(id);
    Widget content;
    switch (category) {
      case 'rack':
        content = Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, .002)
              ..rotateX(-.42),
            child: Stack(alignment: Alignment.center, children: [
              Image.asset('assets/rack/${id}_back.webp', fit: BoxFit.contain, errorBuilder: (_, __, ___) => const SizedBox()),
              Image.asset('assets/rack/${id}_front.webp', fit: BoxFit.contain, errorBuilder: (_, __, ___) => _fallbackBar(accent)),
            ]),
          ),
        );
      case 'tiles':
        content = Center(
          child: SizedBox(
            width: 128,
            height: height - 10,
            child: Stack(alignment: Alignment.bottomCenter, children: [
              for (var i = 0; i < 3; i++)
                Transform(
                  alignment: Alignment.bottomCenter,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, .0018)
                    ..translate((i - 1) * 32.0, i == 1 ? -6.0 : 0.0)
                    ..rotateZ((i - 1) * .16)
                    ..rotateY((i - 1) * -.35),
                  child: SizedBox(
                    width: 42,
                    height: 60,
                    child: TileWidget(
                      tile: GameTile(id: 'p$i', number: const [7, 13, 1][i], colorIndex: const [0, 3, 1][i]),
                      skinId: id,
                    ),
                  ),
                ),
            ]),
          ),
        );
      case 'cloth':
        content = Center(
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, .002)
              ..rotateX(.62),
            child: Container(
              width: 150,
              height: 74,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(60),
                border: Border.all(color: const Color(0xFF5A3418), width: 6),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .5), blurRadius: 14, offset: const Offset(0, 10))],
              ),
              child: OkxFelt(theme: id, borderRadius: BorderRadius.circular(54), child: const SizedBox.expand()),
            ),
          ),
        );
      case 'frame':
        content = Center(child: FrameRing(color: accent, legendary: '${item['rarity']}' == 'legendary', size: 64, child: const Icon(Icons.person_rounded, color: Colors.white70, size: 32)));
      default:
        content = Center(child: Icon(_iconFor(category, id), size: 46, color: accent));
    }
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: RadialGradient(center: const Alignment(0, -.2), radius: 1.0, colors: [accent.withValues(alpha: .22), const Color(0x00000000)]),
        color: Colors.black.withValues(alpha: .22),
        border: Border.all(color: Colors.white10),
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(14), child: content),
    );
  }

  static Widget _fallbackBar(Color accent) => Container(height: 22, decoration: BoxDecoration(color: accent.withValues(alpha: .6), borderRadius: BorderRadius.circular(6)));

  static IconData _iconFor(String category, String id) => switch (category) {
        'avatar' => id.contains('fox') || id.contains('cat') ? Icons.pets_rounded : id.contains('phoenix') ? Icons.local_fire_department_rounded : Icons.shield_rounded,
        'music_kit' => Icons.album_rounded,
        'sound_pack' => Icons.graphic_eq_rounded,
        'victory_fx' => Icons.celebration_rounded,
        'spawn_fx' => id.contains('fire') ? Icons.local_fire_department_rounded : id.contains('lightning') ? Icons.bolt_rounded : Icons.login_rounded,
        'emoji_pack' => Icons.emoji_emotions_rounded,
        'title' => Icons.workspace_premium_rounded,
        _ => Icons.auto_awesome_rounded,
      };
}

/// Profil çerçevesi: metalik halka, efsanevide dönen ışık.
class FrameRing extends StatefulWidget {
  const FrameRing({super.key, required this.color, required this.child, this.size = 60, this.legendary = false});
  final Color color;
  final Widget child;
  final double size;
  final bool legendary;

  @override
  State<FrameRing> createState() => _FrameRingState();
}

class _FrameRingState extends State<FrameRing> with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.color;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _spin,
        builder: (context, child) => Container(
          padding: EdgeInsets.all(widget.size * .07),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: SweepGradient(
              transform: GradientRotation(widget.legendary ? _spin.value * 2 * math.pi : 0),
              colors: [c, Colors.white, c.withValues(alpha: .55), c, Colors.white70, c],
            ),
            boxShadow: [BoxShadow(color: c.withValues(alpha: .55), blurRadius: 14)],
          ),
          child: child,
        ),
        child: Container(
          decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF1B124A)),
          alignment: Alignment.center,
          child: widget.child,
        ),
      ),
    );
  }
}

/// 3D mağaza kartı.
class CosmeticCard3D extends StatelessWidget {
  const CosmeticCard3D({
    super.key,
    required this.item,
    required this.width,
    required this.busy,
    required this.onBuy,
    required this.onEquip,
    required this.onTry,
  });

  final Map<String, dynamic> item;
  final double width;
  final bool busy;
  final VoidCallback onBuy;
  final VoidCallback onEquip;
  final VoidCallback onTry;

  @override
  Widget build(BuildContext context) {
    final rarity = '${item['rarity'] ?? 'common'}';
    final rc = rarityColor(rarity);
    final owned = item['owned'] == true;
    final equipped = item['equipped'] == true;
    final diamonds = item['currency'] == 'diamonds';
    final price = (item['price'] as num?)?.toInt() ?? 0;
    final original = (item['original_price'] as num?)?.toInt() ?? price;
    final discount = (item['discount_percent'] as num?)?.toInt() ?? 0;
    final tryable = const {'rack', 'tiles', 'cloth', 'frame'}.contains('${item['category']}');
    final card = Container(
      width: width,
      padding: const EdgeInsets.fromLTRB(9, 9, 9, 9),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [rc.withValues(alpha: .26), const Color(0xF0160E3D), const Color(0xF70B0722)],
        ),
        border: Border.all(color: rc.withValues(alpha: equipped ? .95 : .5), width: equipped ? 2 : 1.2),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Stack(children: [
          CosmeticPreview(item: item),
          Positioned(
            left: 6,
            top: 6,
            child: _chip(rarityLabel(rarity), rc, dark: true),
          ),
          if (discount > 0 && !owned) Positioned(right: 6, top: 6, child: _chip('%$discount İNDİRİM', const Color(0xFFFF5A7A))),
          if (owned) Positioned(right: 6, top: 6, child: _chip(equipped ? 'KULLANILIYOR' : 'SENDE', equipped ? const Color(0xFF54E2BE) : Colors.white70, dark: true)),
        ]),
        const SizedBox(height: 7),
        Text('${item['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.white)),
        const SizedBox(height: 7),
        Row(children: [
          if (tryable)
            SizedBox(
              width: 34,
              height: 32,
              child: IconButton.filledTonal(
                tooltip: 'Masada dene',
                padding: EdgeInsets.zero,
                onPressed: () {
                  HapticFeedback.selectionClick();
                  onTry();
                },
                icon: const Icon(Icons.visibility_rounded, size: 16),
              ),
            ),
          if (tryable) const SizedBox(width: 6),
          Expanded(
            child: SizedBox(
              height: 32,
              child: owned
                  ? FilledButton.icon(
                      onPressed: equipped || busy ? null : onEquip,
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1F9E7C), padding: const EdgeInsets.symmetric(horizontal: 6)),
                      icon: Icon(equipped ? Icons.check_circle_rounded : Icons.checkroom_rounded, size: 15),
                      label: FittedBox(child: Text(equipped ? 'TAKILI' : 'KULLAN', style: const TextStyle(fontWeight: FontWeight.w900))),
                    )
                  : FilledButton(
                      onPressed: busy ? null : onBuy,
                      style: FilledButton.styleFrom(backgroundColor: rc.withValues(alpha: .9), foregroundColor: const Color(0xFF160E3F), padding: const EdgeInsets.symmetric(horizontal: 6)),
                      child: FittedBox(
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(diamonds ? Icons.diamond_rounded : Icons.monetization_on_rounded, size: 14),
                          const SizedBox(width: 4),
                          if (discount > 0 && original > price) ...[
                            Text(_fmt(original), style: const TextStyle(fontSize: 10, decoration: TextDecoration.lineThrough, fontWeight: FontWeight.w700)),
                            const SizedBox(width: 4),
                          ],
                          Text(_fmt(price), style: const TextStyle(fontWeight: FontWeight.w900)),
                        ]),
                      ),
                    ),
            ),
          ),
        ]),
      ]),
    );
    final glowing = rarity == 'legendary' || rarity == 'epic' || equipped;
    return Tilt3D(child: glowing ? RarityHalo(color: equipped ? const Color(0xFF54E2BE) : rc, strong: rarity == 'legendary', child: card) : card);
  }

  static Widget _chip(String text, Color c, {bool dark = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: dark ? const Color(0xCC0B0720) : c,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: c.withValues(alpha: .8)),
        ),
        child: Text(text, style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: .4, color: dark ? c : const Color(0xFF1A0F3A))),
      );

  static String _fmt(int v) => v.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
}

/// "Masada dene": seçili ürünü, takılı diğer kozmetiklerle birlikte mini
/// bir masada gösterir. Satın almadan nasıl duracağını görürsün.
Future<void> showTryOnTable(
  BuildContext context, {
  required Map<String, dynamic> item,
  required Map<String, String> loadout,
  VoidCallback? onBuy,
  VoidCallback? onEquip,
}) {
  final category = '${item['category']}';
  final look = {...loadout, category: '${item['id']}'};
  final cloth = look['cloth'] ?? 'cloth_green';
  final rack = (look['rack'] ?? 'rack_classic');
  final tiles = look['tiles'] ?? 'tiles_classic';
  final frame = look['frame'] ?? 'frame_none';
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Kapat',
    barrierColor: const Color(0xCC05030F),
    transitionDuration: const Duration(milliseconds: 320),
    transitionBuilder: (context, a, _, child) => Opacity(opacity: a.value, child: Transform.scale(scale: .9 + .1 * Curves.easeOutBack.transform(a.value), child: child)),
    pageBuilder: (context, _, __) {
      final size = MediaQuery.sizeOf(context);
      final w = math.min(size.width * .92, 760.0);
      final h = math.min(size.height * .86, 380.0);
      final owned = item['owned'] == true;
      return Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: w,
            height: h,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: rarityColor('${item['rarity']}').withValues(alpha: .7), width: 1.5),
              boxShadow: const [BoxShadow(color: Color(0xAA000000), blurRadius: 30)],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(23),
              child: Stack(children: [
                Positioned.fill(child: OkxFelt(theme: cloth, photo: true)),
                // Rakip koltukları (çerçeve önizlemesi üstte).
                Positioned(
                  top: 14,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      frame == 'frame_none'
                          ? const CircleAvatar(radius: 26, backgroundColor: Color(0xFF1B124A), child: Icon(Icons.person_rounded, color: Colors.white70))
                          : FrameRing(color: cosmeticAccent(frame), legendary: frame.contains('royal') || frame.contains('dragon'), size: 58, child: const Icon(Icons.person_rounded, color: Colors.white70)),
                      const SizedBox(height: 4),
                      const Text('SEN', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white70)),
                    ]),
                  ),
                ),
                // Ortadaki taşlar (seçili taş kaplaması).
                Align(
                  alignment: const Alignment(0, -.05),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    for (final t in const [(9, 0), (10, 0), (11, 0), (12, 0)])
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1.5),
                        child: SizedBox(width: 34, height: 49, child: TileWidget(tile: GameTile(id: 'm${t.$1}', number: t.$1, colorIndex: t.$2), skinId: tiles)),
                      ),
                  ]),
                ),
                // Istaka + elindeki taşlar.
                Positioned(
                  left: w * .08,
                  right: w * .08,
                  bottom: 8,
                  height: h * .34,
                  child: Stack(alignment: Alignment.bottomCenter, children: [
                    Positioned.fill(child: Image.asset('assets/rack/${rack}_back.webp', fit: BoxFit.fill, errorBuilder: (_, __, ___) => const SizedBox())),
                    Positioned(
                      left: 18,
                      right: 18,
                      top: h * .03,
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        for (var i = 0; i < 9; i++)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 1),
                            child: SizedBox(
                              width: 30,
                              height: 43,
                              child: TileWidget(tile: GameTile(id: 'r$i', number: const [1, 2, 3, 5, 5, 5, 8, 12, 13][i], colorIndex: const [1, 1, 1, 0, 2, 3, 3, 0, 0][i]), skinId: tiles),
                            ),
                          ),
                      ]),
                    ),
                    Positioned.fill(child: Image.asset('assets/rack/${rack}_front.webp', fit: BoxFit.fill, errorBuilder: (_, __, ___) => const SizedBox())),
                  ]),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton.filledTonal(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close_rounded)),
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: const Color(0xCC0B0720), borderRadius: BorderRadius.circular(12)),
                    child: Text('MASADA DENE • ${item['name']}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: OkeyXColors.gold)),
                  ),
                ),
                if (onBuy != null || onEquip != null)
                  Positioned(
                    right: 12,
                    top: h * .42,
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        (owned ? onEquip : onBuy)?.call();
                      },
                      icon: Icon(owned ? Icons.checkroom_rounded : Icons.shopping_bag_rounded),
                      label: Text(owned ? 'KULLAN' : 'SATIN AL'),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      );
    },
  );
}
