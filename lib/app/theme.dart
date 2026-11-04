import 'package:flutter/material.dart';

/// Calm blue for trust, warm orange for "act now"; large radii, flat surfaces.
const _brand = Color(0xFF1565A8);
const _accent = Color(0xFFE8833A);

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: _brand,
    brightness: brightness,
    tertiary: _accent,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
    scaffoldBackgroundColor: scheme.surface,
    textTheme: _typeScale(scheme),
  );
  final radius = BorderRadius.circular(20);
  return base.copyWith(
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
        color: scheme.onSurface,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: radius),
      margin: EdgeInsets.zero,
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      side: BorderSide(color: scheme.outlineVariant),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHigh,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainer,
      indicatorColor: scheme.primaryContainer,
      elevation: 0,
      height: 68,
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 20),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      showDragHandle: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
  );
}

/// One small type scale for the whole app, so sizes stay consistent:
/// heading 26, title 20 / 16, body 16 / 15 / 13, label 14 / 12 / 11.
/// No extra letter spacing: Material's default spreads Japanese text apart.
TextTheme _typeScale(ColorScheme c) {
  TextStyle t(double size, FontWeight w, [double height = 1.4]) => TextStyle(
    fontSize: size,
    fontWeight: w,
    height: height,
    letterSpacing: 0,
    color: c.onSurface,
  );
  return TextTheme(
    displayLarge: t(34, FontWeight.w800, 1.2),
    displayMedium: t(30, FontWeight.w800, 1.2),
    displaySmall: t(28, FontWeight.w800, 1.2),
    headlineLarge: t(28, FontWeight.w800, 1.25),
    headlineMedium: t(26, FontWeight.w800, 1.25),
    headlineSmall: t(24, FontWeight.w700, 1.25),
    titleLarge: t(20, FontWeight.w700, 1.3),
    titleMedium: t(16, FontWeight.w700, 1.35),
    titleSmall: t(14, FontWeight.w700, 1.35),
    bodyLarge: t(16, FontWeight.w400, 1.6),
    bodyMedium: t(15, FontWeight.w400, 1.5),
    bodySmall: t(13, FontWeight.w400, 1.45),
    labelLarge: t(14, FontWeight.w600, 1.3),
    labelMedium: t(12, FontWeight.w600, 1.3),
    labelSmall: t(11, FontWeight.w600, 1.3),
  );
}
