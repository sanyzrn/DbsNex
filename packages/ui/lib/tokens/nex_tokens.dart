import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Every colour in Nex, drawn from one warm neutral ramp plus one accent.
///
/// Two rules the previous set broke:
///
/// * **A card's fill is not the page's fill.** They were both `#FFFFFF`, which
///   left a 1px `#EBEAE8` hairline — 1.20:1 — as the only thing separating a
///   note from the page behind it. That is below the point at which many people
///   can resolve a boundary at all, and the card is the tap target for opening
///   a note. Now the page is a tone down from the card, the border clears 3:1,
///   and a shadow sits under it: three signals where there was one.
/// * **A boundary and a divider are not the same token.** `border` marks
///   something you can act on and is held to 3:1; `borderSoft` is decoration
///   between rows and is deliberately quiet. One token was doing both jobs, so
///   both were wrong.
abstract final class NexColors {
  /* ------------------------------------------------------------- light */

  /// The page behind the cards.
  static const bgPrimaryLight = Color(0xFFF4F2EE);

  /// A card, a sheet, a dialog: paper on the desk.
  static const bgCardLight = Color(0xFFFFFFFF);

  /// Filled containers inside a card — the note type disc, chips at rest.
  static const bgElevatedLight = Color(0xFFE1DDD6);

  static const textPrimaryLight = Color(0xFF1A1712);
  static const textSecondaryLight = Color(0xFF5F594F);

  /// Boundaries you can act on. Held to 3:1 against the card.
  static const borderLight = Color(0xFF989288);

  /// Dividers between rows of one surface. Never carries a boundary alone.
  static const borderSoftLight = Color(0xFFE3DFD8);

  /* -------------------------------------------------------------- dark */

  static const bgPrimaryDark = Color(0xFF0B0A09);
  static const bgCardDark = Color(0xFF1A1815);
  static const bgElevatedDark = Color(0xFF34312B);
  static const textPrimaryDark = Color(0xFFF7F4EF);
  static const textSecondaryDark = Color(0xFFA9A296);
  static const borderDark = Color(0xFF6E6860);
  static const borderSoftDark = Color(0xFF2C2924);

  /* ------------------------------------------------------ comfort light */

  static const bgPrimaryLightComfort = Color(0xFFEFE7D8);
  static const bgCardLightComfort = Color(0xFFFBF6EC);
  static const bgElevatedLightComfort = Color(0xFFDFD5C1);
  static const textPrimaryLightComfort = Color(0xFF2E2A22);
  static const textSecondaryLightComfort = Color(0xFF5E574A);

  /// Comfort borders are drawn from the comfort ramp. They used to reuse the
  /// default cool grey, which sat visibly off-hue on a warm cream ground and
  /// undid the point of the mode.
  static const borderLightComfort = Color(0xFF978C76);
  static const borderSoftLightComfort = Color(0xFFDDD3BF);

  /* ------------------------------------------------------- comfort dark */

  static const bgPrimaryDarkComfort = Color(0xFF14100C);
  static const bgCardDarkComfort = Color(0xFF221D16);
  static const bgElevatedDarkComfort = Color(0xFF3C342A);
  static const textPrimaryDarkComfort = Color(0xFFE4DACA);
  static const textSecondaryDarkComfort = Color(0xFFADA290);
  static const borderDarkComfort = Color(0xFF746A5B);
  static const borderSoftDarkComfort = Color(0xFF332C22);

  /* ------------------------------------------------------------ accent */

  /// The one colour that means *Nex is doing something*.
  ///
  /// Spent only on the caret, the recording state, focus rings, the active
  /// filter and the commit receipt. If it is on screen, something is live.
  /// Rationing it is what makes it information rather than decoration.
  ///
  /// Ink blue rather than the warm amber an audit proposed: amber sits between
  /// the destructive red below and the amber in the suggested tag palette,
  /// which is the one position a signal colour cannot afford, given that the
  /// two most colour-loaded moments in this app are "delete" and "recording".
  static const accentLight = Color(0xFF2563EB);

  /// Where white text sits on the accent.
  static const accentStrongLight = Color(0xFF1D4ED8);

  /// The accent on a near-black ground, where the light one is too dense.
  static const accentDark = Color(0xFF60A5FA);
  static const accentStrongDark = Color(0xFF93C5FD);

  /* ---------------------------------------------------------- semantic */

  /// "Releasing this will destroy something." Distinct from [error], which is
  /// "what you typed is not valid" — two different meanings that used to
  /// render in exactly the same colour.
  static const danger = Color(0xFFC0392B);
  static const error = Color(0xFFB3261E);

  /// The destructive half of the swipe pair — the same colour as [danger],
  /// named for the place it is used.
  static const swipeDelete = danger;

  /// The non-destructive half of the ADR-022 pair. Deliberately not a second
  /// red and not a saturated brand colour: a desaturated slate reads as
  /// "organize", stays quiet next to the delete panel, and clears 4.5:1
  /// against the white label it carries.
  static const swipeAddTag = Color(0xFF4A5568);

  static const cardRadius = 20.0;
}

/// The 4pt grid. Every gap in the app is one of these.
abstract final class NexSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const contentGap = 16.0;
  static const md = 16.0;
  static const cardInset = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
}

abstract final class NexMotion {
  static const fast = Duration(milliseconds: 120);
  static const standard = Duration(milliseconds: 180);
  static const slow = Duration(milliseconds: 320);

  /// How long a commit receipt takes to fade out.
  static const receipt = Duration(milliseconds: 600);
  static const curve = Curves.easeOutCubic;
}

/// One radius scale. Inner radii are derived from an outer radius minus the
/// inset that separates them, so concentric corners actually stay concentric.
abstract final class NexRadius {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = NexColors.cardRadius;
  static const xl = 28.0;

  /// The radius a shape nested [inset] inside a [outer]-radius shape needs in
  /// order to look concentric with it.
  static double inside(double outer, double inset) =>
      math.max(xs, outer - inset);
}

const nexMinTapTarget = 48.0;
const nexCaptureFabSize = 64.0;
const nexSwipeThreshold = 0.35;

/// How much room a scrolling list leaves under its last item for the capture
/// button to float over.
///
/// Derived, not measured by hand. This was a literal `118` tuned against a
/// 64px button — a number with no stated relationship to anything, which would
/// have silently stopped clearing the button the moment its size token moved.
const nexFabClearance = nexCaptureFabSize + NexSpacing.lg * 2;

/// How wide a focus ring is drawn, and how far it stands off its control.
///
/// The only focus affordance used to be a 16% fill tint — a grey wash on a grey
/// control, which on a shipped desktop target means a keyboard user cannot see
/// where they are.
const nexFocusRingWidth = 2.0;
const nexFocusRingOffset = 2.0;

/// The gutter every timeline card sits in.
///
/// Shared rather than repeated so the swipe panel behind a card can line up
/// with the card exactly. The panel used to run to the physical screen edge
/// while the card stopped short of it, so the two never read as parts of the
/// same object.
const nexCardInsets = EdgeInsets.symmetric(
  horizontal: NexSpacing.md,
  vertical: NexSpacing.xs,
);

/// One height for every card in the timeline.
///
/// Cards used to size to their content, so a note carrying tags stood taller
/// than one without and a note with two lines of text taller than one with a
/// single line — the list came out ragged, with no relationship between a
/// card's height and anything the reader cares about. The budget is fixed
/// here: 32 of inset, two lines of preview at 24, a little slack, and the
/// metadata row.
const nexCardHeight = 120.0;

/// The height reserved for a card's date-and-tags row.
const nexCardMetaHeight = 34.0;

/// The typeface used everywhere except in Persian.
///
/// Shipped as an asset rather than left to the platform. Without it Android
/// renders Roboto, Windows Segoe UI Variable and iOS SF Pro — three faces with
/// three x-heights and three sets of line-break points, which means the same
/// screen has three different densities depending on where it is opened.
const nexLatinFont = 'Inter';

/// The Persian face, chosen for an x-height close enough to Inter's that a
/// mixed-script line does not visibly step.
const nexPersianFont = 'Vazirmatn';

/// The font family for a locale.
String nexFontFor(Locale? locale) =>
    locale?.languageCode == 'fa' ? nexPersianFont : nexLatinFont;

ThemeData nexLightTheme({bool comfortMode = false, String? fontFamily}) =>
    _theme(
      brightness: Brightness.light,
      background: comfortMode
          ? NexColors.bgPrimaryLightComfort
          : NexColors.bgPrimaryLight,
      card: comfortMode ? NexColors.bgCardLightComfort : NexColors.bgCardLight,
      elevated: comfortMode
          ? NexColors.bgElevatedLightComfort
          : NexColors.bgElevatedLight,
      primary: comfortMode
          ? NexColors.textPrimaryLightComfort
          : NexColors.textPrimaryLight,
      secondary: comfortMode
          ? NexColors.textSecondaryLightComfort
          : NexColors.textSecondaryLight,
      border: comfortMode
          ? NexColors.borderLightComfort
          : NexColors.borderLight,
      borderSoft: comfortMode
          ? NexColors.borderSoftLightComfort
          : NexColors.borderSoftLight,
      accent: NexColors.accentLight,
      accentStrong: NexColors.accentStrongLight,
      onAccent: const Color(0xFFFFFFFF),
      fontFamily: fontFamily ?? nexLatinFont,
    );

ThemeData nexDarkTheme({bool comfortMode = false, String? fontFamily}) =>
    _theme(
      brightness: Brightness.dark,
      background: comfortMode
          ? NexColors.bgPrimaryDarkComfort
          : NexColors.bgPrimaryDark,
      card: comfortMode ? NexColors.bgCardDarkComfort : NexColors.bgCardDark,
      elevated: comfortMode
          ? NexColors.bgElevatedDarkComfort
          : NexColors.bgElevatedDark,
      primary: comfortMode
          ? NexColors.textPrimaryDarkComfort
          : NexColors.textPrimaryDark,
      secondary: comfortMode
          ? NexColors.textSecondaryDarkComfort
          : NexColors.textSecondaryDark,
      border: comfortMode ? NexColors.borderDarkComfort : NexColors.borderDark,
      borderSoft: comfortMode
          ? NexColors.borderSoftDarkComfort
          : NexColors.borderSoftDark,
      accent: NexColors.accentDark,
      accentStrong: NexColors.accentStrongDark,
      onAccent: const Color(0xFF0B0A09),
      fontFamily: fontFamily ?? nexLatinFont,
    );

ThemeData _theme({
  required Brightness brightness,
  required Color background,
  required Color card,
  required Color elevated,
  required Color primary,
  required Color secondary,
  required Color border,
  required Color borderSoft,
  required Color accent,
  required Color accentStrong,
  required Color onAccent,
  required String fontFamily,
}) {
  // Declared, not seeded. `ColorScheme.fromSeed` derives a tonal palette from
  // the seed's hue and chroma, and the seed here was near-black — chroma about
  // zero — so every role nobody overrode came out an undesigned grey. One of
  // them, `inversePrimary`, is live as the Undo action's colour: a colour no
  // one chose, on the one control that undoes a deletion.
  final scheme = ColorScheme(
    brightness: brightness,
    primary: accent,
    onPrimary: onAccent,
    primaryContainer: accentStrong,
    onPrimaryContainer: onAccent,
    secondary: secondary,
    onSecondary: background,
    secondaryContainer: elevated,
    onSecondaryContainer: primary,
    tertiary: primary,
    onTertiary: background,
    tertiaryContainer: elevated,
    onTertiaryContainer: primary,
    error: NexColors.error,
    onError: const Color(0xFFFFFFFF),
    errorContainer: NexColors.error.withValues(alpha: 0.12),
    onErrorContainer: NexColors.error,
    surface: background,
    onSurface: primary,
    onSurfaceVariant: secondary,
    surfaceContainerLowest: card,
    surfaceContainerLow: card,
    surfaceContainer: elevated,
    surfaceContainerHigh: elevated,
    surfaceContainerHighest: elevated,
    surfaceTint: accent,
    inverseSurface: primary,
    onInverseSurface: background,
    inversePrimary: accent,
    outline: border,
    outlineVariant: borderSoft,
    shadow: const Color(0xFF000000),
    scrim: const Color(0xFF000000),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
    canvasColor: background,
    fontFamily: fontFamily,
    focusColor: accent.withValues(alpha: 0.12),
    appBarTheme: AppBarTheme(
      backgroundColor: background,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: accentStrong,
      foregroundColor: onAccent,
      elevation: 3,
      sizeConstraints: const BoxConstraints.tightFor(
        width: nexCaptureFabSize,
        height: nexCaptureFabSize,
      ),
    ),
    dividerColor: borderSoft,
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
    textTheme: _textTheme(primary: primary, secondary: secondary),
  );
}

/// One style with its weight applied to the variable font's `wght` axis.
///
/// `fontWeight` alone leaves a variable font at its default instance on some
/// platforms, which would silently render the whole app at one weight.
TextStyle _style({
  required double size,
  required double lineHeight,
  required FontWeight weight,
  required Color color,
}) =>
    TextStyle(
      fontSize: size,
      height: lineHeight / size,
      fontWeight: weight,
      fontVariations: [FontVariation('wght', weight.value.toDouble())],
      color: color,
    );

/// All fifteen slots, so nothing falls through.
///
/// Six were defined before, which left every button, chip and list-tile label
/// in the app typeset by Material's defaults — a face and a letter-spacing
/// chosen for Roboto, applied to whatever the platform happened to load. The
/// undefined slots also carried Material's colours rather than these, so
/// component text and body text resolved their colour by different mechanisms.
TextTheme _textTheme({required Color primary, required Color secondary}) =>
    TextTheme(
      displayLarge: _style(size: 40, lineHeight: 46, weight: FontWeight.w600, color: primary),
      displayMedium: _style(size: 34, lineHeight: 40, weight: FontWeight.w600, color: primary),
      displaySmall: _style(size: 28, lineHeight: 34, weight: FontWeight.w600, color: primary),
      headlineLarge: _style(size: 34, lineHeight: 40, weight: FontWeight.w600, color: primary),
      headlineMedium: _style(size: 28, lineHeight: 34, weight: FontWeight.w600, color: primary),
      headlineSmall: _style(size: 24, lineHeight: 30, weight: FontWeight.w600, color: primary),
      titleLarge: _style(size: 24, lineHeight: 30, weight: FontWeight.w600, color: primary),
      // 20, not the old 17. A heading one point away from body text carries no
      // size signal at all, so the hierarchy rested entirely on weight.
      titleMedium: _style(size: 20, lineHeight: 26, weight: FontWeight.w600, color: primary),
      titleSmall: _style(size: 17, lineHeight: 24, weight: FontWeight.w600, color: primary),
      bodyLarge: _style(size: 16, lineHeight: 24, weight: FontWeight.w400, color: primary),
      bodyMedium: _style(size: 15, lineHeight: 22, weight: FontWeight.w400, color: primary),
      // 13, not 12.5. Fractional sizes do not land on pixel boundaries, and
      // this is the style every date, tag and storage figure is set in.
      bodySmall: _style(size: 13, lineHeight: 18, weight: FontWeight.w500, color: secondary),
      labelLarge: _style(size: 14, lineHeight: 20, weight: FontWeight.w600, color: primary),
      labelMedium: _style(size: 13, lineHeight: 18, weight: FontWeight.w600, color: primary),
      labelSmall: _style(size: 12, lineHeight: 16, weight: FontWeight.w600, color: secondary),
    );

/// The glyph for a note type, and the only place one is chosen.
///
/// A photo note used to be `Icons.image_outlined` on its card and
/// `Icons.photo_outlined` in the type picker — the same concept with two
/// different marks, so the filter and the thing it filters did not correspond.
/// The set is also all one weight: three filled and two outlined in a single
/// five-row list reads as unpolished before anyone can say why.
///
/// [wireName] is the note type's own wire name; null means "every type".
IconData nexNoteTypeIcon(String? wireName) => switch (wireName) {
      'text' => Icons.notes_outlined,
      'voice' => Icons.graphic_eq_outlined,
      'photo' => Icons.image_outlined,
      'file' => Icons.insert_drive_file_outlined,
      _ => Icons.all_inclusive_outlined,
    };

double nexContrastRatio(Color a, Color b) {
  final high = math.max(a.computeLuminance(), b.computeLuminance());
  final low = math.min(a.computeLuminance(), b.computeLuminance());
  return (high + 0.05) / (low + 0.05);
}

/// Parses a `#RRGGBB` tag accent into a colour.
///
/// Returns null for a tag with no colour and for anything malformed, so a bad
/// value stored by an older build renders as "no colour" instead of crashing
/// the timeline. Tag colours are free-form now, not a fixed palette, so this
/// can no longer assume the string came from a list it controls.
Color? nexParseTagColor(String? hex) {
  if (hex == null || hex.length != 7 || !hex.startsWith('#')) return null;
  final value = int.tryParse(hex.substring(1), radix: 16);
  if (value == null) return null;
  return Color(value + 0xFF000000);
}

String nexFormatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

/// The small dot that marks something waiting for attention.
///
/// Nex has no notifications and no badges on its launcher icon; this is the
/// whole of its "there is something here" vocabulary, and it only ever appears
/// inside the app, on the control that leads to the thing.
class NexBadgeDot extends StatelessWidget {
  const NexBadgeDot({super.key, this.size = 8});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: NexColors.danger,
          shape: BoxShape.circle,
          border: Border.all(
            color: Theme.of(context).colorScheme.surface,
            width: 1.5,
          ),
        ),
      );
}
