import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

abstract final class NexColors {
  static const bgPrimaryLight = Color(0xFFFFFFFF);
  static const bgPrimaryDark = Color(0xFF0A0A0A);
  static const bgElevatedLight = Color(0xFFF5F4F2);
  static const bgElevatedDark = Color(0xFF171717);
  static const textPrimaryLight = Color(0xFF111113);
  static const textPrimaryDark = Color(0xFFFAFAFA);
  static const textSecondaryLight = Color(0xFF68686D);
  static const textSecondaryLightComfort = Color(0xFF625E56);
  static const textSecondaryDark = Color(0xFFA3A3A3);
  static const textSecondaryDarkComfort = Color(0xFFAAA094);
  static const borderLight = Color(0xFFEBEAE8);
  static const borderDark = Color(0xFF262626);
  static const bgPrimaryLightComfort = Color(0xFFF7F1E6);
  static const bgPrimaryDarkComfort = Color(0xFF17130F);
  static const textPrimaryLightComfort = Color(0xFF2E2A22);
  static const textPrimaryDarkComfort = Color(0xFFD9CFC0);
  static const swipeDelete = Color(0xFFC0392B);

  /// The non-destructive half of the ADR-022 pair. Deliberately not a second
  /// red and not a saturated brand colour: a desaturated slate reads as
  /// "organize", stays quiet next to the delete panel, and clears 4.5:1
  /// against the white label it carries.
  static const swipeAddTag = Color(0xFF4A5568);

  static const cardRadius = 22.0;
}

abstract final class NexSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const contentGap = 14.0;
  static const md = 16.0;
  static const cardInset = 18.0;
  static const lg = 24.0;
  static const xl = 32.0;
}

abstract final class NexMotion {
  static const fast = Duration(milliseconds: 120);
  static const standard = Duration(milliseconds: 180);
  static const curve = Curves.easeOutCubic;
}

const nexMinTapTarget = 44.0;
const nexCaptureFabSize = 64.0;
const nexSwipeThreshold = 0.35;

ThemeData nexLightTheme({bool comfortMode = false}) => _theme(
  brightness: Brightness.light,
  background: comfortMode ? NexColors.bgPrimaryLightComfort : NexColors.bgPrimaryLight,
  elevated: comfortMode ? const Color(0xFFF0E8DA) : NexColors.bgElevatedLight,
  primary: comfortMode ? NexColors.textPrimaryLightComfort : NexColors.textPrimaryLight,
  secondary: comfortMode ? NexColors.textSecondaryLightComfort : NexColors.textSecondaryLight,
  border: NexColors.borderLight,
);

ThemeData nexDarkTheme({bool comfortMode = false}) => _theme(
  brightness: Brightness.dark,
  background: comfortMode ? NexColors.bgPrimaryDarkComfort : NexColors.bgPrimaryDark,
  elevated: comfortMode ? const Color(0xFF1F1A15) : NexColors.bgElevatedDark,
  primary: comfortMode ? NexColors.textPrimaryDarkComfort : NexColors.textPrimaryDark,
  secondary: comfortMode ? NexColors.textSecondaryDarkComfort : NexColors.textSecondaryDark,
  border: NexColors.borderDark,
);

ThemeData _theme({
  required Brightness brightness,
  required Color background,
  required Color elevated,
  required Color primary,
  required Color secondary,
  required Color border,
}) {
  final scheme = ColorScheme.fromSeed(seedColor: primary, brightness: brightness).copyWith(
    surface: background,
    onSurface: primary,
    primary: primary,
    onPrimary: background,
    secondary: secondary,
    outline: border,
    surfaceContainerHighest: elevated,
    error: NexColors.swipeDelete,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
    fontFamily: !kIsWeb && Platform.isWindows ? 'Segoe UI Variable' : null,
    focusColor: primary.withValues(alpha: 0.16),
    appBarTheme: AppBarTheme(backgroundColor: background, elevation: 0, scrolledUnderElevation: 0),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: primary,
      foregroundColor: background,
      elevation: 1,
      sizeConstraints: const BoxConstraints.tightFor(width: nexCaptureFabSize, height: nexCaptureFabSize),
    ),
    dividerColor: border,
    // Android's default zoom transition scales and clips the whole page, which
    // reads as heavy next to the rest of the app. The Cupertino slide is the
    // motion this design language already implies: short, horizontal, and
    // interruptible by an edge swipe back.
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
      },
    ),
    // The default ripple races out from the touch point and lands after the
    // gesture is over. A ripple that fades in place keeps taps feeling
    // immediate, which is the whole promise of the capture path.
    splashFactory: InkSparkle.splashFactory,
    textTheme: TextTheme(
      displaySmall: TextStyle(fontSize: 30, fontWeight: FontWeight.w600, color: primary, height: 1.18),
      titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: primary, height: 1.4),
      titleMedium: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: primary, height: 1.4),
      bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w400, color: primary, height: 1.5),
      bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: primary, height: 1.5),
      bodySmall: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: secondary, height: 1.4),
    ),
  );
}

double nexContrastRatio(Color a, Color b) {
  final high = math.max(a.computeLuminance(), b.computeLuminance());
  final low = math.min(a.computeLuminance(), b.computeLuminance());
  return (high + 0.05) / (low + 0.05);
}

String nexFormatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}