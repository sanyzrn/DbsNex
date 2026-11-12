part of 'nex_tokens.dart';

/// A designed surface ramp: the colours one Soft UI appearance is built from.
///
/// The shipped appearances ([nexSoftLightTheme], [nexSoftDarkTheme],
/// [nexOledNightTheme]) pass hand-picked constants into the same constructor a
/// ramp feeds — this class is those constants, named, so a whole-app theme can
/// carry its own designed set of them without re-deriving anything from a seed.
///
/// Two accent steps, the split the shipped Soft Light theme already makes
/// between `#006DCC` and `#0084F7`: [accent] is the deep, text-safe one that
/// draws marks, focus rings and quiet button labels (held to 4.5:1 against its
/// own [card] and [page]), and [fab] is the vibrant one the capture button
/// wears, where only the 3:1 graphical floor applies.
@immutable
class NexSurfaceRamp {
  const NexSurfaceRamp({
    required this.brightness,
    required this.page,
    required this.card,
    required this.elevated,
    required this.ink,
    required this.muted,
    required this.line,
    required this.outline,
    required this.accent,
    required this.onAccent,
    required this.fill,
    required this.fillInk,
    required this.container,
    required this.containerInk,
    required this.fab,
    required this.fabInk,
    this.accentOnInverse,
  });

  final Brightness brightness;

  /// The ground behind the cards.
  final Color page;

  /// A note card, a sheet, a dialog: paper on the desk.
  final Color card;

  /// Filled containers inside a card — the note type disc, chips at rest.
  final Color elevated;

  /// Primary text.
  final Color ink;

  /// Secondary text, dates and captions.
  final Color muted;

  /// Quiet dividers between rows of one surface. Never carries a boundary
  /// alone, and is deliberately quieter than [outline].
  final Color line;

  /// Boundaries you can act on. Held to 3:1 against [card].
  final Color outline;

  /// The deep, text-safe accent: `colorScheme.primary`.
  final Color accent;

  /// `colorScheme.onPrimary` — what sits on [accent].
  final Color onAccent;

  /// A filled button's ground, and its label.
  final Color fill;
  final Color fillInk;

  /// The selected container (`primaryContainer`) and its ink — the wash a
  /// selected chip or an active filter carries.
  final Color container;
  final Color containerInk;

  /// The capture button's ground and glyph.
  final Color fab;
  final Color fabInk;

  /// The toast action's colour, read on a capsule filled with [ink]. Null
  /// derives it: [nexReadableOn] of [accent] against [ink].
  final Color? accentOnInverse;

  /// The same ramp with somebody's own accent in place of the designed one.
  ///
  /// The neutrals are a theme's identity and stay; only the accent roles
  /// follow the pick. The accent keeps the picked hue and is walked only
  /// far enough to clear the 4.5:1 text floor on all three surfaces, since
  /// it also labels quiet buttons. Fills take the label-safe step the shipped
  /// appearances derive for a custom seed, so a filled button's label keeps
  /// its 4.5:1 whatever lightness somebody picked. Graphite is the honest
  /// extreme: grey everywhere but the accent someone chose.
  NexSurfaceRamp withAccent(Color picked) {
    final dark = brightness == Brightness.dark;
    final opaque = picked.withValues(alpha: 1);
    final palette = nexAccentPaletteFrom(opaque);
    // All ramp surfaces share a brightness. The brightest dark surface or
    // dimmest light surface is the hardest ground for the accent's text.
    final ground = [page, card, elevated].reduce((a, b) {
      final brighter = a.computeLuminance() > b.computeLuminance();
      return dark == brighter ? a : b;
    });
    final mark = nexReadableOn(opaque, ground);
    final deep = dark ? palette.strongDark : palette.strongLight;
    final deepInk = dark ? const Color(0xFF0B0A09) : const Color(0xFFFFFFFF);
    final washedCard = Color.alphaBlend(mark.withValues(alpha: 0.16), card);
    return NexSurfaceRamp(
      brightness: brightness,
      page: page,
      card: card,
      elevated: elevated,
      ink: ink,
      muted: muted,
      line: line,
      outline: outline,
      accent: mark,
      // Primary can carry text as well as icons.
      onAccent: nexContrast(const Color(0xFFFFFFFF), mark) >= 4.5
          ? const Color(0xFFFFFFFF)
          : const Color(0xFF0B0A09),
      fill: deep,
      fillInk: deepInk,
      container: washedCard,
      containerInk: nexReadableOn(mark, washedCard),
      fab: deep,
      fabInk: deepInk,
      accentOnInverse: nexReadableOn(palette.strongLight, ink),
    );
  }

  /// [accentOnInverse], derived when it was not pinned.
  Color get resolvedAccentOnInverse =>
      accentOnInverse ?? nexReadableOn(accent, ink);
}

/// The glass wash a page's own colour asks for.
///
/// The shipped appearances pin their washes by hand — a blue-grey anchor over
/// the Soft Dark page, a cream one over Comfort Mode — because a neutral film
/// over a coloured page reads as faintly off-hue. A theme's page carries the
/// same need, so the anchor and lift take the page's own hue at the lightness
/// the shipped anchors sit, saturation eased to the chroma they carry. The
/// films, and every floor the glass tests hold, are the shipped structure.
NexGlassWash nexGlassWashFromPage(
  Color page, {
  required Brightness brightness,
  required bool floating,
}) {
  final dark = brightness == Brightness.dark;
  final hsl = HSLColor.fromColor(page);
  Color tone(double lightness) => hsl
      .withSaturation((hsl.saturation * 0.7).clamp(0.0, 0.18))
      .withLightness(lightness)
      .toColor();

  if (!dark) {
    final anchor = tone(0.86);
    return NexGlassWash(
      films: [
        Colors.black.withValues(alpha: floating ? 0.02 : 0.06),
        Colors.white.withValues(alpha: floating ? 0.42 : 0.32),
      ],
      lift: Colors.white.withValues(alpha: floating ? 0.06 : 0.08),
      anchor: anchor.withValues(alpha: floating ? 0.30 : 0.54),
    );
  }
  return NexGlassWash(
    films: [
      Colors.white.withValues(alpha: floating ? 0.02 : 0.05),
      Colors.black.withValues(alpha: floating ? 0.66 : 0.48),
    ],
    lift: tone(0.16).withValues(alpha: floating ? 0.10 : 0.42),
    anchor: tone(0.21).withValues(alpha: floating ? 0.02 : 0.30),
  );
}

/// A Soft UI theme recoloured end-to-end by [ramp].
///
/// This is the constructor the whole-app themes ride: the same `_theme`
/// structure and the same flatten pass [nexSoftLightTheme] applies, with the
/// ramp's colours in every slot. Nothing is derived from a seed — the ramp is
/// the design — so a theme keeps its own neutral ramp, its own two accent
/// steps and its own glass wash (taken from its page, the way the shipped
/// appearances take theirs from theirs).
ThemeData nexSoftThemeFromRamp({
  required NexSurfaceRamp ramp,
  bool liquidGlass = false,
  bool transparentScaffold = false,
  String? fontFamily,
}) {
  final theme = _theme(
    brightness: ramp.brightness,
    comfortMode: false,
    background: ramp.page,
    card: ramp.card,
    elevated: ramp.elevated,
    primary: ramp.ink,
    secondary: ramp.muted,
    border: ramp.outline,
    borderSoft: ramp.line,
    accent: ramp.accent,
    accentStrong: ramp.fill,
    onAccent: ramp.onAccent,
    accentOnInverse: ramp.resolvedAccentOnInverse,
    fontFamily: fontFamily ?? nexLatinFont,
    liquidGlass: liquidGlass,
    transparentScaffold: transparentScaffold,
    minimal: true,
  );
  // The same flatten pass the shipped soft appearances apply, with the ramp's
  // own accent steps: the selected container is the theme's wash, not a tonal
  // step of the accent, and the capture button wears the vibrant step.
  final flattened = theme.copyWith(
    colorScheme: theme.colorScheme.copyWith(
      primaryContainer: ramp.container,
      onPrimaryContainer: ramp.containerInk,
      surfaceTint: Colors.transparent,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: theme.filledButtonTheme.style?.copyWith(
        backgroundColor: WidgetStatePropertyAll(ramp.fill),
        foregroundColor: WidgetStatePropertyAll(ramp.fillInk),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      // A quiet button's label is the ramp's own accent, un-derived. The
      // base theme darkens the classic accent for these labels (LOC-07) and
      // leaves dark's to the platform default; a designed accent is already
      // a text tone, on either brightness.
      style: theme.textButtonTheme.style?.merge(
        TextButton.styleFrom(
          foregroundColor: ramp.accent,
          disabledForegroundColor: ramp.ink.withValues(alpha: 0.38),
        ),
      ),
    ),
    floatingActionButtonTheme: theme.floatingActionButtonTheme.copyWith(
      backgroundColor: ramp.fab,
      foregroundColor: ramp.fabInk,
      disabledElevation: 0,
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: theme.outlinedButtonTheme.style?.copyWith(
        backgroundColor: WidgetStatePropertyAll(ramp.elevated),
        foregroundColor: WidgetStatePropertyAll(ramp.ink),
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
  if (!liquidGlass) return flattened;
  // Glass is on: the washes take the page's own colour, so a warm page keeps
  // warm glass exactly the way Comfort Mode's cream anchor keeps its.
  final visual = flattened.extension<NexVisualStyle>();
  if (visual == null) return flattened;
  return flattened.copyWith(
    extensions: [
      ...flattened.extensions.values.where((e) => e is! NexVisualStyle),
      visual.copyWith(
        glassWash: nexGlassWashFromPage(
          ramp.page,
          brightness: ramp.brightness,
          floating: false,
        ),
        floatingGlassWash: nexGlassWashFromPage(
          ramp.page,
          brightness: ramp.brightness,
          floating: true,
        ),
      ),
    ],
  );
}
