import 'package:flutter/material.dart';

/// OKEYX "Renkli Premium" paleti: gece indigosu zemin, canlı altın, turkuaz,
/// pembe ve mor vurgular; masada zümrüt çuha.
/// Eski adlar korunur (tüm ekranlar bunları kullanıyor), değerleri yeni temaya
/// göre güncellendi.
abstract final class OkeyXColors {
  static const ink = Color(0xFF0B0726);
  static const night = Color(0xFF120B36);
  static const deep = Color(0xFF1A1247);
  static const panel = Color(0xF21C134D);
  static const panelSoft = Color(0xE6231A5E);
  static const teal = Color(0xFF12C9A0);
  /// Olumlu/aktif vurgu (eski turkuazın yerini yumuşak nane yeşili aldı).
  static const cyan = Color(0xFF3DF2D0);
  static const electricBlue = Color(0xFF4D7CFF);
  /// Pirinç/altın vurgu.
  static const gold = Color(0xFFFFCB45);
  static const amber = Color(0xFFFFA62B);
  static const flame = Color(0xFFC2412F);
  static const mint = Color(0xFF5BFFB6);
  static const danger = Color(0xFFFF5470);
  static const ruby = Color(0xFFFF4D8D);
  static const rubyDeep = Color(0xFF8F2637);

  static const cream = Color(0xFFFFF7E6);
  static const text = Color(0xFFF7F4FF);
  static const muted = Color(0xFFB4ADEB);
  static const dim = Color(0xFF7A72B8);
  static const line = Color(0x40A58BFF);
  static const line2 = Color(0x80B79CFF);
  static const brassLight = Color(0xFFFBE7A8);
  static const brass = Color(0xFFD9A94E);
  static const brassDark = Color(0xFF9A6A24);
  static const brassShadow = Color(0xFF8A3A00);
  static const felt = Color(0xFF155E43);
  static const feltDark = Color(0xFF0B3A29);

  // Taş renkleri (gerçek okey taşı tonları)
  static const tileRed = Color(0xFFB8231B);
  static const tileBlue = Color(0xFF1B3F93);
  static const tileBlack = Color(0xFF19152C);
  static const tileYellow = Color(0xFFCF880B);
}

/// Yazı tipleri (pubspec.yaml'da paketlenir).
abstract final class OkeyXFonts {
  static const sans = 'Montserrat';
  static const serif = 'Lora';
  static const number = 'ArchivoBlack';
}

ThemeData buildOkeyXTheme() {
  const scheme = ColorScheme.dark(
    primary: OkeyXColors.gold,
    onPrimary: Color(0xFF150E3D),
    secondary: OkeyXColors.ruby,
    onSecondary: OkeyXColors.ink,
    surface: OkeyXColors.deep,
    onSurface: OkeyXColors.text,
    error: OkeyXColors.danger,
    onError: Colors.white,
  );

  final rounded = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
  final base = ThemeData(useMaterial3: true, brightness: Brightness.dark, fontFamily: OkeyXFonts.sans);
  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: OkeyXColors.ink,
    dividerColor: OkeyXColors.line,
    splashColor: OkeyXColors.gold.withValues(alpha: .10),
    highlightColor: OkeyXColors.gold.withValues(alpha: .06),
    textTheme: base.textTheme.apply(bodyColor: OkeyXColors.text, displayColor: OkeyXColors.text, fontFamily: OkeyXFonts.sans),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xF2120C35),
      contentTextStyle: const TextStyle(color: OkeyXColors.cream, fontFamily: OkeyXFonts.sans, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: OkeyXColors.line2)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: const Color(0xFA120B33),
      titleTextStyle: const TextStyle(fontFamily: OkeyXFonts.serif, fontWeight: FontWeight.w700, fontSize: 20, color: OkeyXColors.cream),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: OkeyXColors.line2, width: 1.2),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: Color(0xFA120B33), modalBackgroundColor: Color(0xFA120B33)),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0x66000000),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      labelStyle: const TextStyle(color: OkeyXColors.muted, fontWeight: FontWeight.w700),
      floatingLabelStyle: const TextStyle(color: OkeyXColors.gold, fontWeight: FontWeight.w800),
      hintStyle: const TextStyle(color: OkeyXColors.dim),
      prefixIconColor: OkeyXColors.gold,
      suffixIconColor: OkeyXColors.muted,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: OkeyXColors.line2, width: 1.2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: OkeyXColors.gold, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: OkeyXColors.danger),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: OkeyXColors.gold,
        foregroundColor: const Color(0xFF150E3D),
        disabledBackgroundColor: const Color(0x33E9C070),
        shape: rounded,
        textStyle: const TextStyle(fontFamily: OkeyXFonts.sans, fontWeight: FontWeight.w800, letterSpacing: .4),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: OkeyXColors.gold,
        foregroundColor: const Color(0xFF150E3D),
        shape: rounded,
        textStyle: const TextStyle(fontFamily: OkeyXFonts.sans, fontWeight: FontWeight.w800),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: OkeyXColors.cream,
        backgroundColor: const Color(0x660B0721),
        side: const BorderSide(color: OkeyXColors.line2, width: 1.3),
        shape: rounded,
        textStyle: const TextStyle(fontFamily: OkeyXFonts.sans, fontWeight: FontWeight.w800),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: OkeyXColors.gold, textStyle: const TextStyle(fontWeight: FontWeight.w800)),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: const Color(0x10FFEBC8),
      selectedColor: OkeyXColors.gold.withValues(alpha: .85),
      secondarySelectedColor: OkeyXColors.gold,
      side: const BorderSide(color: OkeyXColors.line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      labelStyle: const TextStyle(color: OkeyXColors.cream, fontWeight: FontWeight.w800, fontSize: 12),
      secondaryLabelStyle: const TextStyle(color: Color(0xFF150E3D), fontWeight: FontWeight.w800, fontSize: 12),
      checkmarkColor: const Color(0xFF150E3D),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : const Color(0xFFACA7DB)),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? const Color(0xFF2BAA74) : const Color(0x22FFFFFF)),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: OkeyXColors.gold,
      inactiveTrackColor: const Color(0x66000000),
      thumbColor: const Color(0xFFFFF4D6),
      overlayColor: OkeyXColors.gold.withValues(alpha: .12),
      trackHeight: 5,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: OkeyXColors.cyan, linearTrackColor: Color(0x66000000)),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: const Color(0xFFFFE9B0), highlightColor: OkeyXColors.gold.withValues(alpha: .10))),
    popupMenuTheme: PopupMenuThemeData(color: const Color(0xFA120B33), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: OkeyXColors.line2))),
  );
}

/// Ekran arka planı: gece indigosu + renkli ışık lekeleri.
const okeyXBackdrop = BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1B0F4A), Color(0xFF0B0726), Color(0xFF062A3A)],
  ),
);
