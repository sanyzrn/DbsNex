import 'package:flutter/material.dart';

/// Light/Dark token pairs from `05-design.md` (Phase 1.7).
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

ThemeData nexLightTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: NexColors.bgPrimaryLight,
    colorScheme: const ColorScheme.light(
      surface: NexColors.bgPrimaryLight,
      onSurface: NexColors.textPrimaryLight,
      primary: NexColors.accentLight,
      onPrimary: NexColors.bgPrimaryLight,
      secondary: NexColors.textSecondaryLight,
      outline: NexColors.borderLight,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: NexColors.bgPrimaryLight,
      foregroundColor: NexColors.textPrimaryLight,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: NexColors.accentLight,
      foregroundColor: NexColors.bgPrimaryLight,
    ),
    dividerColor: NexColors.borderLight,
    textTheme: _textTheme(NexColors.textPrimaryLight, NexColors.textSecondaryLight),
  );
}

ThemeData nexDarkTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: NexColors.bgPrimaryDark,
    colorScheme: const ColorScheme.dark(
      surface: NexColors.bgPrimaryDark,
      onSurface: NexColors.textPrimaryDark,
      primary: NexColors.accentDark,
      onPrimary: NexColors.bgPrimaryDark,
      secondary: NexColors.textSecondaryDark,
      outline: NexColors.borderDark,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: NexColors.bgPrimaryDark,
      foregroundColor: NexColors.textPrimaryDark,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: NexColors.accentDark,
      foregroundColor: NexColors.bgPrimaryDark,
    ),
    dividerColor: NexColors.borderDark,
    textTheme: _textTheme(NexColors.textPrimaryDark, NexColors.textSecondaryDark),
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
