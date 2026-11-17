import 'package:flutter/material.dart';

import 'brand.dart';

/// Lychnion palette as explicit tokens (brand canvas, board 4): Paper and
/// Ink by day, Night and Moonlight by night, Harbor Blue (Sky on dark) for
/// actions, the amber Glow as accent. Error red is kept only for official
/// warnings and destructive actions. Large radii, flat surfaces.
const _light = ColorScheme(
  brightness: Brightness.light,
  primary: Brand.harborBlue,
  onPrimary: Colors.white,
  primaryContainer: Color(0xFFD7E3F4),
  onPrimaryContainer: Color(0xFF163A5F),
  secondary: Brand.night,
  onSecondary: Brand.moonlight,
  secondaryContainer: Color(0xFFE3E7EF),
  onSecondaryContainer: Brand.night,
  // Glow is never text on Paper (1.7:1): Glow Deep is the accent colour
  // for text and icons, Glow fills the container.
  tertiary: Brand.glowDeep,
  onTertiary: Colors.white,
  tertiaryContainer: Brand.glow,
  onTertiaryContainer: Brand.night,
  error: Color(0xFFB3261E),
  onError: Colors.white,
  errorContainer: Color(0xFFF9DEDC),
  onErrorContainer: Color(0xFF410E0B),
  surface: Brand.paper,
  onSurface: Brand.ink,
  onSurfaceVariant: Brand.stone,
  surfaceContainerLowest: Colors.white,
  surfaceContainerLow: Color(0xFFF5F2EA),
  surfaceContainer: Color(0xFFF0EDE5),
  surfaceContainerHigh: Brand.moonlight,
  surfaceContainerHighest: Brand.mist,
  // Line, not Mist, for borders that must be seen (Mist is 1.2:1).
  outline: Brand.line,
  outlineVariant: Brand.mist,
  inverseSurface: Brand.night,
  onInverseSurface: Brand.moonlight,
  inversePrimary: Brand.sky,
  shadow: Colors.black,
  scrim: Colors.black,
);

const _dark = ColorScheme(
  brightness: Brightness.dark,
  primary: Brand.sky,
  onPrimary: Brand.night,
  primaryContainer: Brand.harborBlue,
  onPrimaryContainer: Color(0xFFD7E3F4),
  secondary: Brand.moonlight,
  onSecondary: Brand.night,
  secondaryContainer: Color(0xFF2E3D5C),
  onSecondaryContainer: Brand.moonlight,
  tertiary: Brand.glow,
  onTertiary: Brand.night,
  tertiaryContainer: Color(0xFF5C4310),
  onTertiaryContainer: Color(0xFFFCE3AE),
  error: Color(0xFFF2B8B5),
  onError: Color(0xFF601410),
  errorContainer: Color(0xFF8C1D18),
  onErrorContainer: Color(0xFFF9DEDC),
  surface: Brand.night,
  onSurface: Brand.moonlight,
  onSurfaceVariant: Brand.haze,
  surfaceContainerLowest: Color(0xFF101A30),
  surfaceContainerLow: Color(0xFF1B2946),
  surfaceContainer: Brand.night2,
  surfaceContainerHigh: Color(0xFF2A3A5A),
  surfaceContainerHighest: Color(0xFF334466),
  outline: Color(0xFF6B7894),
  outlineVariant: Color(0xFF34435F),
  inverseSurface: Brand.moonlight,
  onInverseSurface: Brand.night,
  inversePrimary: Brand.harborBlue,
  shadow: Colors.black,
  scrim: Colors.black,
);

ThemeData buildTheme(Brightness brightness) {
  final scheme = brightness == Brightness.dark ? _dark : _light;
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
    scaffoldBackgroundColor: scheme.surface,
    fontFamily: Brand.textFont,
    textTheme: _typeScale(scheme),
  );
  final radius = BorderRadius.circular(20);
  final light = brightness == Brightness.light;
  return base.copyWith(
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: Brand.textFont,
        fontSize: 22,
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
        color: scheme.onSurface,
      ),
    ),
    // White cards with a visible edge on Paper; Night 2 cards on Night.
    cardTheme: CardThemeData(
      elevation: 0,
      color: light ? scheme.surfaceContainerLowest : scheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: light ? BorderSide(color: scheme.outline) : BorderSide.none,
      ),
      margin: EdgeInsets.zero,
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      side: BorderSide(color: scheme.outlineVariant),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: light
          ? scheme.surfaceContainerLowest
          : scheme.surfaceContainerHigh,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: BorderSide(color: scheme.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: BorderSide(color: scheme.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: light
          ? scheme.surfaceContainerLowest
          : scheme.surfaceContainerLow,
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
