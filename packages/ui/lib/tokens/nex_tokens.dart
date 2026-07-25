import 'package:flutter/material.dart';

/// Light/Dark (+ Comfort) token pairs from `05-design.md`.
abstract final class NexColors {
  static const Color bgPrimaryLight = Color(0xFFFFFFFF);
  static const Color bgPrimaryDark = Color(0xFF0A0A0A);
  static const Color bgElevatedLight = Color(0xFFF5F5F5);
  static const Color bgElevatedDark = Color(0xFF171717);
  static const Color textPrimaryLight = Color(0xFF0A0A0A);
  static const Color textPrimaryDark = Color(0xFFFAFAFA);
  static const Color textSecondaryLight = Color(0xFF6B6B6B);
  static const Color textSecondaryDark = Color(0xFFA3A3A3);
  static const Color borderLight = Color(0xFFE5E5E5);
  static const Color borderDark = Color(0xFF262626);
  static const Color accentLight = Color(0xFF0A0A0A);
  static const Color accentDark = Color(0xFFFAFAFA);

  // Comfort Mode exact deltas from 05-design.md §Comfort Mode.
  static const Color bgPrimaryLightComfort = Color(0xFFF7F1E6);
  static const Color bgPrimaryDarkComfort = Color(0xFF17130F);
  static const Color textPrimaryLightComfort = Color(0xFF2E2A22);
  static const Color textPrimaryDarkComfort = Color(0xFFD9CFC0);

  /// Muted red for Delete swipe reveal only (05-design.md §Swipe Actions).
  static const Color swipeDelete = Color(0xFFE24B3B);
}

abstract final class NexSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
}

/// Minimum tap target (05-design.md).
const double nexMinTapTarget = 44;

/// Swipe reveal threshold as a fraction of card width.
const double nexSwipeThreshold = 0.35;

ThemeData nexLightTheme({bool comfortMode = false}) {
  final bg = comfortMode ? NexColors.bgPrimaryLightComfort : NexColors.bgPrimaryLight;
  final on = comfortMode
      ? NexColors.textPrimaryLightComfort
      : NexColors.textPrimaryLight;
  final elevated = comfortMode
      ? const Color(0xFFF0E8DA)
      : NexColors.bgElevatedLight;
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: bg,
    colorScheme: ColorScheme.light(
      surface: bg,
      onSurface: on,
      primary: on,
      onPrimary: bg,
      secondary: NexColors.textSecondaryLight,
      outline: NexColors.borderLight,
      surfaceContainerHighest: elevated,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      foregroundColor: on,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: on,
      foregroundColor: bg,
    ),
    dividerColor: NexColors.borderLight,
    textTheme: _textTheme(on, NexColors.textSecondaryLight),
  );
}

ThemeData nexDarkTheme({bool comfortMode = false}) {
  final bg = comfortMode ? NexColors.bgPrimaryDarkComfort : NexColors.bgPrimaryDark;
  final on =
      comfortMode ? NexColors.textPrimaryDarkComfort : NexColors.textPrimaryDark;
  final elevated = comfortMode
      ? const Color(0xFF1F1A15)
      : NexColors.bgElevatedDark;
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: bg,
    colorScheme: ColorScheme.dark(
      surface: bg,
      onSurface: on,
      primary: on,
      onPrimary: bg,
      secondary: NexColors.textSecondaryDark,
      outline: NexColors.borderDark,
      surfaceContainerHighest: elevated,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      foregroundColor: on,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: on,
      foregroundColor: bg,
    ),
    dividerColor: NexColors.borderDark,
    textTheme: _textTheme(on, NexColors.textSecondaryDark),
  );
}

TextTheme _textTheme(Color primary, Color secondary) {
  return TextTheme(
    titleLarge: TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w600,
      color: primary,
      height: 1.4,
    ),
    titleMedium: TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.w600,
      color: primary,
      height: 1.4,
    ),
    bodyLarge: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w400,
      color: primary,
      height: 1.5,
    ),
    bodyMedium: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      color: primary,
      height: 1.5,
    ),
    bodySmall: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w500,
      color: secondary,
      height: 1.4,
    ),
  );
}

/// Relative luminance contrast ratio (WCAG).
double nexContrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}
