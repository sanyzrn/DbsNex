part of 'nex_tokens.dart';

/// Neutral roles from the supplied Soft UI reference. The former dark ramp
/// and renderer stay unchanged for Night and existing component consumers.
abstract final class NexSoftDarkColors {
  static const background = Color(0xFF141821);
  static const card = Color(0xFF1C212C);
  static const elevated = Color(0xFF252B38);
  static const text = Color(0xFFD9DDE6);
  static const muted = Color(0xFF98A1B5);
  static const accent = Color(0xFF0084F7);
  static const accentText = Color(0xFF5AB0FF);
  static const accentContainer = Color(0xFF16304D);
  // 3.30:1 against the dark card (the old 3:1-missing fill was 2.93), with
  // white ink at 4.88 — both floors cleared (V-07). Same step for Night.
  static const accentFilled = Color(0xFF0A73C8);
  static const line = Color(0xFF2D3443);
  // Functional focus/high-contrast outlines remain visible.
  static const outline = Color(0xFF7F8AA0);
}

/// OLED Night keeps its own tones without changing the legacy NexColors ramp.
abstract final class NexNightColors {
  static const background = Color(0xFF000000);
  static const card = Color(0xFF0E0F12);
  static const elevated = Color(0xFF1A1C21);
  static const text = Color(0xFFD9DDE6);
  static const muted = Color(0xFF8E96A8);
  static const accent = Color(0xFF0084F7);
  static const accentText = Color(0xFF5AB0FF);
  static const accentContainer = Color(0xFF0F2A47);
  static const accentFilled = NexSoftDarkColors.accentFilled;
  static const line = Color(0xFF24272E);
  // Focus and high-contrast outlines remain available even with flat cards.
  static const outline = Color(0xFF7F8AA0);
}

/// OLED Night uses the existing flat OLED renderer, not legacy nexDarkTheme.
/// The public legacy nexDarkTheme remains unchanged for existing consumers.
ThemeData nexNightTheme({
  bool comfortMode = false,
  bool liquidGlass = false,
  bool transparentScaffold = false,
  String? fontFamily,
  Color? accentSeed,
}) => nexOledNightTheme(
  comfortMode: comfortMode,
  liquidGlass: liquidGlass,
  transparentScaffold: transparentScaffold,
  fontFamily: fontFamily,
  accentSeed: accentSeed,
);

/// Tonal, flat Dark with opt-in glass and the existing custom accent controls.
ThemeData nexSoftDarkTheme({
  bool comfortMode = false,
  bool liquidGlass = false,
  bool transparentScaffold = false,
  String? fontFamily,
  Color? accentSeed,
}) {
  final custom = accentSeed == null ? null : nexAccentPaletteFrom(accentSeed);
  final accent = custom?.dark ?? NexSoftDarkColors.accentText;
  final filled = custom?.strongDark ?? NexSoftDarkColors.accentFilled;
  final filledInk = custom == null ? Colors.white : const Color(0xFF0B0A09);
  final theme = _theme(
    brightness: Brightness.dark,
    comfortMode: false,
    background: NexSoftDarkColors.background,
    card: NexSoftDarkColors.card,
    elevated: NexSoftDarkColors.elevated,
    primary: NexSoftDarkColors.text,
    secondary: NexSoftDarkColors.muted,
    border: NexSoftDarkColors.outline,
    borderSoft: NexSoftDarkColors.line,
    accent: accent,
    accentStrong: filled,
    onAccent: const Color(0xFF0B0A09),
    // The dark snackbar is an inverse surface filled with the light text
    // colour, so the strong-light accent has to be re-walked against that
    // fill — measured against the light card it landed at 3.80:1 on the one
    // word in the toast that is a button (V-03).
    accentOnInverse: nexReadableOn(
      custom?.strongLight ?? NexColors.accentStrongLight,
      NexSoftDarkColors.text,
    ),
    fontFamily: fontFamily ?? nexLatinFont,
    liquidGlass: liquidGlass,
    transparentScaffold: transparentScaffold,
    minimal: true,
  );
  // Use the reference's deeper blue for small white button text (4.5:1).
  // Its main blue remains the capture glyph's fill (non-text contrast).
  return theme.copyWith(
    colorScheme: theme.colorScheme.copyWith(
      primaryContainer: custom == null
          ? NexSoftDarkColors.accentContainer
          : Color.alphaBlend(
              accent.withValues(alpha: 0.16),
              NexSoftDarkColors.card,
            ),
      onPrimaryContainer: accent,
      surfaceTint: Colors.transparent,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: theme.filledButtonTheme.style?.copyWith(
        backgroundColor: WidgetStatePropertyAll(filled),
        foregroundColor: WidgetStatePropertyAll(filledInk),
      ),
    ),
    floatingActionButtonTheme: theme.floatingActionButtonTheme.copyWith(
      backgroundColor: custom?.strongDark ?? NexSoftDarkColors.accent,
      foregroundColor: filledInk,
      disabledElevation: 0,
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: theme.outlinedButtonTheme.style?.copyWith(
        backgroundColor: const WidgetStatePropertyAll(
          NexSoftDarkColors.elevated,
        ),
        foregroundColor: const WidgetStatePropertyAll(NexSoftDarkColors.text),
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
}
