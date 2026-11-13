import 'package:flutter/material.dart';
import 'package:nex_ui/nex_ui.dart';

/// Still's own discipline, on top of its designed ramp.
///
/// The ramp ([NexSurfaceRamp] in `theme_presets.dart`) carries Still's
/// colours — warm bone neutrals and quiet sage — and, like every palette,
/// rides the same Soft UI structure as the shipped appearances. What sets
/// Still apart is what it refuses to draw: tonal grouping instead of
/// decorative lines, and no glass optics at all, even when the material is
/// switched on elsewhere. That refusal lives here, on the finished theme,
/// so the ramp itself stays the same designed object every other palette
/// is.
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
        glassSpecular: Colors.transparent,
        glassShade: Colors.transparent,
        glassHighlight: Colors.transparent,
        glassDepth: Colors.transparent,
        glassAura: Colors.transparent,
        glassBounce: Colors.transparent,
        glassVibrancy: 1,
        glassEdgeWidth: 0,
        glassGrain: 0,
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
