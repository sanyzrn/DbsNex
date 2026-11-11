part of 'nex_tokens.dart';

/// Light and OLED Night from the supplied Soft UI demo. These are app-facing
/// renderers; the older nexLightTheme/nexNightTheme APIs stay unchanged for
/// existing embedders and visual regression baselines.
abstract final class NexSoftLightColors {
  static const background = Color(0xFFFFFFFF);
  static const card = Color(0xFFF4F5F8);
  static const elevated = Color(0xFFE9ECF1);
  static const text = Color(0xFF14171C);
  // A step of real margin rather than the 4.54 the old grey scraped past
  // the elevated container with: the tightest pair in the Light theme
  // clears AA on every ground now, not just the card (V-15).
  static const muted = Color(0xFF5F6876);
  static const line = Color(0xFFE6E9EE);
  static const outline = Color(0xFF737C8C);
  static const accent = Color(0xFF0084F7);
  static const accentText = NexColors.accentStrongLight;
  static const accentContainer = Color(0xFFE3F1FF);
  static const accentFill = NexColors.accentStrongLight;
  static const captureFill = accent;
}

abstract final class NexOledNightColors {
  static const background = NexNightColors.background;
  static const card = NexNightColors.card;
  static const elevated = NexNightColors.elevated;
  static const text = NexNightColors.text;
  static const muted = NexNightColors.muted;
  static const line = NexNightColors.line;
  static const outline = NexNightColors.outline;
  static const accentText = NexNightColors.accentText;
  static const accentContainer = NexNightColors.accentContainer;
  static const accentFill = NexNightColors.accentFilled;
  static const captureFill = NexNightColors.accent;
}

/// White page, gently tinted cards, softened secondary text and no decorative
/// borders or elevation. Glass and a user-selected accent remain opt-in.
ThemeData nexSoftLightTheme({
  bool comfortMode = false,
  bool liquidGlass = false,
  bool transparentScaffold = false,
  String? fontFamily,
  Color? accentSeed,
}) {
  final palette = accentSeed == null
      ? NexColors.defaultAccent
      : nexAccentPaletteFrom(accentSeed);
  final accent = palette.strongLight;
  final selected = accentSeed == null
      ? NexSoftLightColors.accentContainer
      : Color.alphaBlend(
          accent.withValues(alpha: 0.16),
          NexSoftLightColors.card,
        );
  final theme = _theme(
    brightness: Brightness.light,
    comfortMode: false,
    background: NexSoftLightColors.background,
    card: NexSoftLightColors.card,
    elevated: NexSoftLightColors.elevated,
    primary: NexSoftLightColors.text,
    secondary: NexSoftLightColors.muted,
    border: NexSoftLightColors.outline,
    borderSoft: NexSoftLightColors.line,
    accent: accent,
    accentStrong: palette.strongLight,
    onAccent: Colors.white,
    accentOnInverse: palette.dark,
    fontFamily: fontFamily ?? nexLatinFont,
    liquidGlass: liquidGlass,
    transparentScaffold: transparentScaffold,
    minimal: true,
  );
  return _flattenSoftAppearance(
    theme,
    primaryContainer: selected,
    onPrimaryContainer: nexReadableOn(accent, selected),
    filled: palette.strongLight,
    filledInk: Colors.white,
    fab: accentSeed == null ? NexSoftLightColors.accent : palette.strongLight,
    fabInk: Colors.white,
  );
}

/// True-black OLED page, subtly lifted charcoal cards and soft grey-white text.
ThemeData nexOledNightTheme({
  bool comfortMode = false,
  bool liquidGlass = false,
  bool transparentScaffold = false,
  String? fontFamily,
  Color? accentSeed,
}) {
  final custom = accentSeed == null ? null : nexAccentPaletteFrom(accentSeed);
  final accent = custom?.dark ?? NexOledNightColors.accentText;
  final filled = custom?.strongDark ?? NexOledNightColors.accentFill;
  final selected = custom == null
      ? NexOledNightColors.accentContainer
      : Color.alphaBlend(
          accent.withValues(alpha: 0.16),
          NexOledNightColors.card,
        );
  final theme = _theme(
    brightness: Brightness.dark,
    comfortMode: false,
    background: NexOledNightColors.background,
    card: NexOledNightColors.card,
    elevated: NexOledNightColors.elevated,
    primary: NexOledNightColors.text,
    secondary: NexOledNightColors.muted,
    border: NexOledNightColors.outline,
    borderSoft: NexOledNightColors.line,
    accent: accent,
    accentStrong: filled,
    onAccent: const Color(0xFF0B0A09),
    // See NexSoftDarkColors: the dark snackbar's fill is the light text
    // colour, so the accent drawn for light cards has to be walked against
    // it (V-03).
    accentOnInverse: nexReadableOn(
      custom?.strongLight ?? NexColors.accentStrongLight,
      NexOledNightColors.text,
    ),
    fontFamily: fontFamily ?? nexLatinFont,
    liquidGlass: liquidGlass,
    transparentScaffold: transparentScaffold,
    minimal: true,
  );
  return _flattenSoftAppearance(
    theme,
    primaryContainer: selected,
    onPrimaryContainer: nexReadableOn(accent, selected),
    filled: filled,
    filledInk: custom == null ? Colors.white : const Color(0xFF0B0A09),
    fab: custom?.strongDark ?? NexOledNightColors.captureFill,
    fabInk: custom == null ? Colors.white : const Color(0xFF0B0A09),
  );
}

/// Both new app appearances share the existing minimal surface contract.
/// Do not remove focus, validation or high-contrast state outlines.
ThemeData _flattenSoftAppearance(
  ThemeData theme, {
  required Color primaryContainer,
  required Color onPrimaryContainer,
  required Color filled,
  required Color filledInk,
  required Color fab,
  required Color fabInk,
}) => theme.copyWith(
  colorScheme: theme.colorScheme.copyWith(
    primaryContainer: primaryContainer,
    onPrimaryContainer: onPrimaryContainer,
    surfaceTint: Colors.transparent,
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: theme.filledButtonTheme.style?.copyWith(
      backgroundColor: WidgetStatePropertyAll(filled),
      foregroundColor: WidgetStatePropertyAll(filledInk),
    ),
  ),
  floatingActionButtonTheme: theme.floatingActionButtonTheme.copyWith(
    backgroundColor: fab,
    foregroundColor: fabInk,
    disabledElevation: 0,
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: theme.outlinedButtonTheme.style?.copyWith(
      backgroundColor: WidgetStatePropertyAll(
        theme.colorScheme.surfaceContainerHigh,
      ),
      foregroundColor: WidgetStatePropertyAll(theme.colorScheme.onSurface),
    ),
  ),
  dividerTheme: const DividerThemeData(color: Colors.transparent),
  menuTheme: const MenuThemeData(
    style: MenuStyle(
      elevation: WidgetStatePropertyAll(0),
      shadowColor: WidgetStatePropertyAll(Colors.transparent),
    ),
  ),
  chipTheme: theme.chipTheme.copyWith(
    side: BorderSide.none,
    elevation: 0,
    pressElevation: 0,
    shadowColor: Colors.transparent,
    selectedShadowColor: Colors.transparent,
  ),
);
