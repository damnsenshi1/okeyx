import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/config.dart';
import '../../widgets/okx_kit.dart';
import '../../widgets/tile_widget.dart';

/// Açılış ekranı: lamba altında ceviz kasnaklı çuha masa, üstünde logo,
/// etrafında süzülen gerçek okey taşları ve pirinç yükleme çubuğu.
class SplashScreen extends StatefulWidget {
  final double progress;
  final String status;
  final String tip;

  const SplashScreen({
    super.key,
    required this.progress,
    required this.status,
    required this.tip,
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _motion;

  static const _floating = [
    (GameTile(id: 's1', number: 1, colorIndex: 0), -.78, -.55, -14.0),
    (GameTile(id: 's2', number: 13, colorIndex: 1), .80, -.62, 12.0),
    (GameTile(id: 's3', number: 7, colorIndex: 3, isJoker: true), -.86, .52, 9.0),
    (GameTile(id: 's4', number: 0, colorIndex: 2, isFakeJoker: true), .84, .48, -10.0),
  ];

  @override
  void initState() {
    super.initState();
    _motion = AnimationController(vsync: this, duration: const Duration(milliseconds: 6000))..repeat();
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.progress.clamp(0.0, 1.0);
    return Scaffold(
      backgroundColor: OkeyXColors.ink,
      body: OkxRoom(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, c) {
              final compact = c.maxHeight < 430;
              final tableW = math.min(c.maxWidth * .62, 640.0);
              final tableH = math.min(c.maxHeight * .52, tableW * .5);
              return AnimatedBuilder(
                animation: _motion,
                builder: (context, _) {
                  final t = _motion.value;
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      for (var i = 0; i < _floating.length; i++)
                        Align(
                          alignment: Alignment(
                            _floating[i].$2,
                            _floating[i].$3 + math.sin((t + i * .25) * math.pi * 2) * .035,
                          ),
                          child: Opacity(
                            opacity: .55,
                            child: Transform.rotate(
                              angle: (_floating[i].$4 + math.sin((t + i * .2) * math.pi * 2) * 3) * math.pi / 180,
                              child: SizedBox(width: compact ? 34 : 44, height: compact ? 48 : 62, child: TileWidget(tile: _floating[i].$1)),
                            ),
                          ),
                        ),
                      Positioned(
                        left: 22,
                        top: 14,
                        child: OkxLeather(
                          radius: 999,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          child: Row(mainAxisSize: MainAxisSize.min, children: const [
                            Icon(Icons.shield_rounded, size: 14, color: OkeyXColors.mint),
                            SizedBox(width: 7),
                            Text('GÜVENLİ BAĞLANTI', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.4, color: OkeyXColors.mint)),
                          ]),
                        ),
                      ),
                      Positioned(
                        right: 24,
                        top: 18,
                        child: Text('v${AppConfig.versionName}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: OkeyXColors.dim)),
                      ),
                      Align(
                        alignment: const Alignment(0, -.30),
                        child: Container(
                          width: tableW,
                          height: tableH,
                          padding: const EdgeInsets.all(12),
                          decoration: walnutDecoration(radius: BorderRadius.circular(tableH / 2)),
                          child: OkxFelt(
                            borderRadius: BorderRadius.circular(tableH / 2),
                            child: Center(
                              child: Transform.scale(
                                scale: 1 + math.sin(t * math.pi * 2) * .015,
                                child: Image.asset(
                                  'assets/brand/okeyx_logo_transparent.png',
                                  height: tableH * .74,
                                  fit: BoxFit.contain,
                                  filterQuality: FilterQuality.medium,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Align(
                        alignment: const Alignment(0, .86),
                        child: SizedBox(
                          width: math.min(c.maxWidth * .62, 560.0),
                          child: OkxLeather(
                            stitch: true,
                            radius: 20,
                            padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        widget.status,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: OkeyXColors.cream),
                                      ),
                                    ),
                                    Text('%${(progress * 100).round()}', style: const TextStyle(fontFamily: OkeyXFonts.number, fontSize: 14, color: OkeyXColors.gold)),
                                  ],
                                ),
                                const SizedBox(height: 9),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: SizedBox(
                                    height: 8,
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        const ColoredBox(color: Color(0x80000000)),
                                        FractionallySizedBox(
                                          alignment: Alignment.centerLeft,
                                          widthFactor: progress,
                                          child: const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF3CCF8E), Color(0xFFFFD56B)]))),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (!compact && widget.tip.isNotEmpty) ...[
                                  const SizedBox(height: 9),
                                  Row(children: [
                                    const Icon(Icons.auto_awesome_rounded, size: 14, color: OkeyXColors.gold),
                                    const SizedBox(width: 7),
                                    Expanded(child: Text(widget.tip, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: OkeyXColors.muted, fontWeight: FontWeight.w600))),
                                  ]),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
