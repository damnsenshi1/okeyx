import 'package:flutter/material.dart';


/// Oyun türü: 101 Okey ya da Klasik Okey. İki büyük, eşit genişlikte sekme.
class OkxModeTabs extends StatelessWidget {
  const OkxModeTabs({super.key, required this.classic, required this.onChanged, this.height = 46, this.onFelt = true});

  /// true: Klasik Okey, false: 101 Okey.
  final bool classic;
  final ValueChanged<bool> onChanged;
  final double height;
  final bool onFelt;

  @override
  Widget build(BuildContext context) => Container(
        height: height,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: onFelt ? const Color(0x59000000) : const Color(0x33000000),
          borderRadius: BorderRadius.circular(height / 2),
          border: Border.all(color: const Color(0x33E8C478)),
        ),
        child: Row(children: [
          for (final opt in const [(false, '101 OKEY', 'Seri ve çift açmalı'), (true, 'KLASİK OKEY', '14 taşı diz, bitir')])
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(opt.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(height / 2),
                    gradient: classic == opt.$1
                        ? const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFF6DC95), Color(0xFFC99440)])
                        : null,
                    boxShadow: classic == opt.$1 ? const [BoxShadow(color: Color(0x66000000), blurRadius: 6, offset: Offset(0, 2))] : const [],
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text(
                        opt.$2,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: height * .30,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .8,
                          color: classic == opt.$1 ? okxTextDarkMode : const Color(0xFFE9DDC2),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ]),
      );
}

const okxTextDarkMode = Color(0xFF2B1906);

/// İki seçenekli, tam yazılı seçim: "Katlamasız | Katlamalı" gibi.
/// Hiçbir zaman kayan şerit olmaz; dar alanda yazı ölçeklenir.
class OkxPairSwitch extends StatelessWidget {
  const OkxPairSwitch({
    super.key,
    required this.left,
    required this.right,
    required this.rightSelected,
    required this.onChanged,
    this.leftIcon,
    this.rightIcon,
    this.height = 36,
    this.enabled = true,
  });

  final String left;
  final String right;
  final bool rightSelected;
  final ValueChanged<bool> onChanged;
  final IconData? leftIcon;
  final IconData? rightIcon;
  final double height;
  final bool enabled;

  Widget _side(bool isRight) {
    final selected = isRight == rightSelected;
    final label = isRight ? right : left;
    final icon = isRight ? rightIcon : leftIcon;
    final fg = selected ? okxTextDarkMode : const Color(0xFFD8CCB0);
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => onChanged(isRight) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(height / 2),
            gradient: selected ? const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFF6DC95), Color(0xFFC99440)]) : null,
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (icon != null) ...[Icon(icon, size: height * .42, color: fg), const SizedBox(width: 4)],
                Text(label, maxLines: 1, style: TextStyle(fontSize: height * .34, fontWeight: FontWeight.w800, letterSpacing: .3, color: fg)),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: enabled ? 1 : .42,
        child: Container(
          height: height,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: const Color(0x52000000),
            borderRadius: BorderRadius.circular(height / 2),
            border: Border.all(color: const Color(0x26FFFFFF)),
          ),
          child: Row(children: [_side(false), _side(true)]),
        ),
      );
}

/// 101 Okey için üç ikili seçim (Klasik Okey'de yalnızca Yardımlı/Yardımsız).
class OkxRuleSwitches extends StatelessWidget {
  const OkxRuleSwitches({
    super.key,
    required this.variant,
    required this.turbo,
    required this.assisted,
    required this.onVariant,
    required this.onTurbo,
    required this.onAssisted,
    this.height = 36,
    this.gap = 8,
  });

  /// 'non_fold' | 'fold' | 'duz'
  final String variant;
  final bool turbo;
  final bool assisted;
  final ValueChanged<String> onVariant;
  final ValueChanged<bool> onTurbo;
  final ValueChanged<bool> onAssisted;
  final double height;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final classic = variant == 'duz';
    final items = <Widget>[
      if (!classic)
        OkxPairSwitch(
          left: 'Katlamasız',
          right: 'Katlamalı',
          rightSelected: variant == 'fold',
          height: height,
          onChanged: (r) => onVariant(r ? 'fold' : 'non_fold'),
        ),
      if (!classic)
        OkxPairSwitch(
          left: 'Normal',
          right: 'Turbo',
          rightIcon: Icons.bolt_rounded,
          rightSelected: turbo,
          height: height,
          onChanged: onTurbo,
        ),
      OkxPairSwitch(
        left: 'Yardımlı',
        right: 'Yardımsız',
        leftIcon: Icons.auto_fix_high_rounded,
        rightSelected: !assisted,
        height: height,
        onChanged: (r) => onAssisted(!r),
      ),
    ];
    return Row(children: [
      for (var i = 0; i < items.length; i++) ...[
        if (i > 0) SizedBox(width: gap),
        Expanded(child: items[i]),
      ],
      if (classic) ...[SizedBox(width: gap), const Expanded(flex: 2, child: SizedBox())],
    ]);
  }
}

/// Kısa kural özeti: "101 Okey • Katlamalı • Turbo • Yardımlı"
String okxRuleSummary({required String variant, required bool turbo, required bool assisted}) {
  final parts = <String>[
    variant == 'duz' ? 'Klasik Okey' : '101 Okey',
    if (variant != 'duz') variant == 'fold' ? 'Katlamalı' : 'Katlamasız',
    if (variant != 'duz') turbo ? 'Turbo' : 'Normal',
    assisted ? 'Yardımlı' : 'Yardımsız',
  ];
  return parts.join(' • ');
}
