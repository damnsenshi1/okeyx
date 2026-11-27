import 'package:flutter/material.dart';

/// OKEYX "Kahvehane Premium" paleti: koyu deri, ceviz, pirinç, çuha yeşili.
/// Eski adlar korunur (tüm ekranlar bunları kullanıyor), değerleri yeni temaya
/// göre güncellendi.
abstract final class OkeyXColors {
  static const ink = Color(0xFF0E0B08);
  static const night = Color(0xFF15110D);
  static const deep = Color(0xFF1D1712);
  static const panel = Color(0xF21D1712);
  static const panelSoft = Color(0xE6251D16);
  static const teal = Color(0xFF2E9E6E);
  /// Olumlu/aktif vurgu (eski turkuazın yerini yumuşak nane yeşili aldı).
  static const cyan = Color(0xFF5FD9A0);
  static const electricBlue = Color(0xFF4F7BB6);
  /// Pirinç/altın vurgu.
  static const gold = Color(0xFFE9C070);
  static const amber = Color(0xFFD9A94E);
  static const flame = Color(0xFFC2412F);
  static const mint = Color(0xFF8FF5C4);
  static const danger = Color(0xFFE0614F);
  static const ruby = Color(0xFFE45B68);
  static const rubyDeep = Color(0xFF8F2637);

  static const cream = Color(0xFFF4EAD2);
  static const text = Color(0xFFF6EEDB);
  static const muted = Color(0xFFB8A684);
  static const dim = Color(0xFF7D6E55);
  static const line = Color(0x38E8C478);
  static const line2 = Color(0x73E8C478);
  static const brassLight = Color(0xFFFBE7A8);
  static const brass = Color(0xFFD9A94E);
  static const brassDark = Color(0xFF9A6A24);
  static const brassShadow = Color(0xFF4A2F0C);
  static const felt = Color(0xFF155E43);
  static const feltDark = Color(0xFF0B3A29);

  // Taş renkleri (gerçek okey taşı tonları)
  static const tileRed = Color(0xFFB8231B);
  static const tileBlue = Color(0xFF1B3F93);
  static const tileBlack = Color(0xFF1D1A16);
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
    onPrimary: Color(0xFF2B1906),
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
      backgroundColor: const Color(0xF2241B13),
      contentTextStyle: const TextStyle(color: OkeyXColors.cream, fontFamily: OkeyXFonts.sans, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: OkeyXColors.line2)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: const Color(0xFA231A12),
      titleTextStyle: const TextStyle(fontFamily: OkeyXFonts.serif, fontWeight: FontWeight.w700, fontSize: 20, color: OkeyXColors.cream),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: OkeyXColors.line2, width: 1.2),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: Color(0xFA231A12), modalBackgroundColor: Color(0xFA231A12)),
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
        foregroundColor: const Color(0xFF2B1906),
        disabledBackgroundColor: const Color(0x33E9C070),
        shape: rounded,
        textStyle: const TextStyle(fontFamily: OkeyXFonts.sans, fontWeight: FontWeight.w800, letterSpacing: .4),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: OkeyXColors.gold,
        foregroundColor: const Color(0xFF2B1906),
        shape: rounded,
        textStyle: const TextStyle(fontFamily: OkeyXFonts.sans, fontWeight: FontWeight.w800),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: OkeyXColors.cream,
        backgroundColor: const Color(0x66140E09),
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
      secondaryLabelStyle: const TextStyle(color: Color(0xFF2B1906), fontWeight: FontWeight.w800, fontSize: 12),
      checkmarkColor: const Color(0xFF2B1906),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : const Color(0xFFCBB98F)),
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
    popupMenuTheme: PopupMenuThemeData(color: const Color(0xFA231A12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: OkeyXColors.line2))),
  );
}

/// Ekran arka planı: koyu deri + üstten sıcak lamba ışığı.
const okeyXBackdrop = BoxDecoration(
  color: OkeyXColors.ink,
  image: DecorationImage(image: AssetImage('assets/textures/leather.jpg'), repeat: ImageRepeat.repeat, opacity: 1),
);
