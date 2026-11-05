part of 'nex_tokens.dart';

/// Light and OLED Night from the supplied Soft UI demo. These are app-facing
/// renderers; the older nexLightTheme/nexNightTheme APIs stay unchanged for
/// existing embedders and visual regression baselines.
abstract final class NexSoftLightColors {
  static const background = Color(0xFFFFFFFF);
  static const card = Color(0xFFF4F5F8);
  static const elevated = Color(0xFFE9ECF1);
  static const text = Color(0xFF14171C);
  static const muted = Color(0xFF626B7A);
  static const line = Color(0xFFE6E9EE);
  static const outline = Color(0xFF657080);
  static const accentText = Color(0xFF0069C4);
  static const accentContainer = Color(0xFFE3F1FF);
  static const accentFill = Color(0xFF0069C4);
  static const captureFill = Color(0xFF0084F7);
}

abstract final class NexOledNightColors {
  static const background = Color(0xFF000000);
  static const card = Color(0xFF0E0F12);
  static const elevated = Color(0xFF1A1C21);
  static const text = Color(0xFFD9DDE6);
  static const muted = Color(0xFF8E96A8);
  static const line = Color(0xFF24272E);
  static const outline = Color(0xFF6A7588);
  static const accentText = Color(0xFF5AB0FF);
  static const accentContainer = Color(0xFF0F2A47);
  static const accentFill = Color(0xFF0069C4);
  static const captureFill = Color(0xFF0084F7);
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
  final custom = accentSeed == null ? null : nexAccentPaletteFrom(accentSeed);
  final accent = custom?.light ?? NexSoftLightColors.accentText;
  final filled = custom?.strongLight ?? NexSoftLightColors.accentFill;
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
    accentStrong: filled,
    onAccent: Colors.white,
    accentOnInverse: custom?.dark ?? NexColors.accentDark,
    fontFamily: fontFamily ?? nexLatinFont,
    liquidGlass: liquidGlass,
    transparentScaffold: transparentScaffold,
    minimal: true,
  );
  return _flattenSoftAppearance(
    theme,
    primaryContainer: custom == null
        ? NexSoftLightColors.accentContainer
        : Color.alphaBlend(
            accent.withValues(alpha: 0.12),
            NexSoftLightColors.card,
          ),
    onPrimaryContainer: accent,
    filled: filled,
    filledInk: Colors.white,
    fab: custom?.light ?? NexSoftLightColors.captureFill,
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
    accentOnInverse: custom?.strongLight ?? NexColors.accentStrongLight,
    fontFamily: fontFamily ?? nexLatinFont,
    liquidGlass: liquidGlass,
    transparentScaffold: transparentScaffold,
    minimal: true,
  );
  return _flattenSoftAppearance(
    theme,
    primaryContainer: custom == null
        ? NexOledNightColors.accentContainer
        : Color.alphaBlend(
            accent.withValues(alpha: 0.16),
            NexOledNightColors.card,
          ),
    onPrimaryContainer: accent,
    filled: filled,
    filledInk: custom == null ? Colors.white : const Color(0xFF0B0A09),
    fab: custom?.strongDark ?? NexOledNightColors.captureFill,
    fabInk: custom == null ? Colors.white : const Color(0xFF0B0A09),
  );
}

/// All three new app appearances share the existing minimal surface contract.
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
