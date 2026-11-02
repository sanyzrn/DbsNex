import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';

/// Still uses tonal grouping instead of decorative lines or elevation.
/// Warm, low-chroma neutrals are a design choice, not a claim that a hue
/// treats stress. Foreground pairs are checked with WCAG relative luminance.
ColorScheme nexStillColors(ColorScheme scheme, {required bool customAccent}) {
  final dark = scheme.brightness == Brightness.dark;
  final surfaces = scheme.copyWith(
    surface: dark ? const Color(0xFF181C19) : const Color(0xFFF4F3EF),
    surfaceDim: dark ? const Color(0xFF181C19) : const Color(0xFFD8DED4),
    surfaceBright: dark ? const Color(0xFF3B453C) : const Color(0xFFFAFAF7),
    surfaceContainerLowest: dark
        ? const Color(0xFF222823)
        : const Color(0xFFFAFAF7),
    surfaceContainerLow: dark
        ? const Color(0xFF202620)
        : const Color(0xFFEEEFE9),
    surfaceContainer: dark ? const Color(0xFF282F2A) : const Color(0xFFE8EBE4),
    surfaceContainerHigh: dark
        ? const Color(0xFF313A32)
        : const Color(0xFFE1E5DD),
    surfaceContainerHighest: dark
        ? const Color(0xFF3B453C)
        : const Color(0xFFD8DED4),
    onSurface: dark ? const Color(0xFFE6E9E2) : const Color(0xFF252B27),
    onSurfaceVariant: dark ? const Color(0xFFB8C2B8) : const Color(0xFF565F58),
    // Keep semantic outlines usable for controls and high-contrast mode.
    // Decorative edges are removed by the visual style, not transparent ink.
    outline: dark ? const Color(0xFF9AA89B) : const Color(0xFF6F7A70),
    outlineVariant: dark ? const Color(0xFF465148) : const Color(0xFFCBD2C7),
    shadow: Colors.transparent,
    surfaceTint: Colors.transparent,
  );
  if (customAccent) return surfaces;
  return surfaces.copyWith(
    primary: dark ? const Color(0xFFB1C9B7) : const Color(0xFF486553),
    onPrimary: dark ? const Color(0xFF1C3427) : const Color(0xFFFFFFFF),
    primaryContainer: dark ? const Color(0xFF344C3C) : const Color(0xFFDAE6DA),
    onPrimaryContainer: dark
        ? const Color(0xFFD8E8DA)
        : const Color(0xFF233E2D),
  );
}

ThemeData nexStillTheme(ThemeData theme) {
  final c = theme.colorScheme;
  final visual = theme.extension<NexVisualStyle>();
  final quietInput = OutlineInputBorder(
    borderRadius: BorderRadius.circular(NexRadius.md),
    borderSide: BorderSide.none,
  );
  return theme.copyWith(
    shadowColor: Colors.transparent,
    dividerColor: Colors.transparent,
    dividerTheme: theme.dividerTheme.copyWith(color: Colors.transparent),
    extensions: [
      ...theme.extensions.values.where((e) => e is! NexVisualStyle),
      ?visual?.copyWith(
        minimal: true,
        liquidGlass: false,
        baseColor: c.surface,
        glassOpaque: c.surfaceContainerLowest,
        glassBorder: Colors.transparent,
        glassRim: Colors.transparent,
        glassShadow: Colors.transparent,
        glassHighlight: Colors.transparent,
        glassDepth: Colors.transparent,
        blurSigma: 0,
      ),
    ],
    appBarTheme: theme.appBarTheme.copyWith(
      elevation: 0,
      scrolledUnderElevation: 0,
      shadowColor: Colors.transparent,
    ),
    cardTheme: theme.cardTheme.copyWith(
      elevation: 0,
      shadowColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NexRadius.lg),
      ),
    ),
    dialogTheme: theme.dialogTheme.copyWith(
      elevation: 0,
      shadowColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NexRadius.xl),
      ),
    ),
    bottomSheetTheme: theme.bottomSheetTheme.copyWith(
      elevation: 0,
      modalElevation: 0,
      shadowColor: Colors.transparent,
    ),
    popupMenuTheme: theme.popupMenuTheme.copyWith(
      elevation: 0,
      shadowColor: Colors.transparent,
    ),
    menuTheme: MenuThemeData(
      style:
          theme.menuTheme.style?.copyWith(
            elevation: const WidgetStatePropertyAll(0),
            shadowColor: const WidgetStatePropertyAll(Colors.transparent),
          ) ??
          const MenuStyle(elevation: WidgetStatePropertyAll(0)),
    ),
    drawerTheme: theme.drawerTheme.copyWith(
      elevation: 0,
      shadowColor: Colors.transparent,
    ),
    floatingActionButtonTheme: theme.floatingActionButtonTheme.copyWith(
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      disabledElevation: 0,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        shadowColor: Colors.transparent,
        foregroundColor: c.onPrimaryContainer,
        backgroundColor: c.primaryContainer,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: theme.outlinedButtonTheme.style?.copyWith(
        side: const WidgetStatePropertyAll(BorderSide.none),
        backgroundColor: WidgetStatePropertyAll(c.surfaceContainerHigh),
        foregroundColor: WidgetStatePropertyAll(c.onSurface),
      ),
    ),
    chipTheme: theme.chipTheme.copyWith(
      side: BorderSide.none,
      elevation: 0,
      pressElevation: 0,
      shadowColor: Colors.transparent,
      selectedShadowColor: Colors.transparent,
    ),
    inputDecorationTheme: theme.inputDecorationTheme.copyWith(
      border: quietInput,
      enabledBorder: quietInput,
      disabledBorder: quietInput,
      // Focus and errors convey state, unlike a decorative card edge.
      focusedBorder: quietInput.copyWith(
        borderSide: BorderSide(color: c.primary, width: nexFocusRingWidth),
      ),
      errorBorder: quietInput.copyWith(borderSide: BorderSide(color: c.error)),
      focusedErrorBorder: quietInput.copyWith(
        borderSide: BorderSide(color: c.error, width: nexFocusRingWidth),
      ),
    ),
  );
}
