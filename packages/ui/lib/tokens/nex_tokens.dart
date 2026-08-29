import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../widgets/nex_swipe_back.dart';
import 'nex_accent_palette.dart';
import 'nex_appearance.dart';

/// Every colour in Nex: one neutral ramp per theme, plus one accent.
///
/// The ramp is chosen; the floors are not. Two rules hold whatever the greys
/// are, and `scaffold_test.dart` is what holds them:
///
/// * **A card's fill is not the page's fill.** They were both `#FFFFFF` once,
///   which left a 1.20:1 hairline as the only thing separating a note from the
///   page behind it — below the point many people can resolve a boundary at
///   all, on the app's main tap target. The page is a tone off the card now,
///   the border clears 3:1, and a shadow sits under it: three signals where
///   there was one.
/// * **A boundary and a divider are not the same token.** `border` marks
///   something you can act on and is held to 3:1; `borderSoft` is decoration
///   between rows and is deliberately quiet. One token was doing both jobs, so
///   both were wrong.
///
/// Three values here are one to seven steps off what was picked by eye, and
/// the arithmetic is the reason: `#969595` came to 2.99 against white and
/// `#2B2B2B` to 1.18 against the dark card. Nobody can see the difference
/// between 2.99 and 3.03 — which is exactly why the floor has to be checked
/// rather than judged.
abstract final class NexColors {
  /* ------------------------------------------------------------- light */

  /// The page behind the cards.
  static const bgPrimaryLight = Color(0xFFF5F6F6);

  /// A card, a sheet, a dialog: paper on the desk.
  static const bgCardLight = Color(0xFFFFFFFF);

  /// Filled containers inside a card — the note type disc, chips at rest.
  static const bgElevatedLight = Color(0xFFE0E0E0);

  static const textPrimaryLight = Color(0xFF262626);
  static const textSecondaryLight = Color(0xFF5C5C5C);

  /// Boundaries you can act on. Held to 3:1 against the card.
  static const borderLight = Color(0xFF959494);

  /// Dividers between rows of one surface. Never carries a boundary alone.
  static const borderSoftLight = Color(0xFFF5F6F6);

  /* -------------------------------------------------------------- dark */

  // Warmer and a touch lighter than it was (#141414) — moved toward the
  // Nex_ui Figma redesign's near-black, which reads closer to this than to
  // pure neutral. Kept comfortably below bgCardDark rather than matching the
  // Figma screen background exactly (#20201F is close enough to the current
  // card colour that using it here would read as the card sitting *behind*
  // the page instead of elevated above it — the Figma file's own card colour
  // wasn't confirmed before its MCP access hit a rate limit).
  // Darker than it was, to open the step up to the card above it. The cards
  // used to carry a shadow, and four values of lightness plus that shadow was
  // enough of an edge; with the shadow gone the tonal step is the only thing
  // marking where a card starts, and four values cannot be seen.
  //
  // The page moved rather than the card, deliberately. Lightening the card
  // would have walked it toward `bgElevatedDark` and `borderDark`, and the
  // scaffold tests caught exactly that — the disc inside a card fell to
  // 1.21:1 and the boundary token to 2.81:1. Moving the page away costs
  // nothing on either.
  static const bgPrimaryDark = Color(0xFF131312);
  static const bgCardDark = Color(0xFF1E1E1E);
  static const bgElevatedDark = Color(0xFF323232);
  static const textPrimaryDark = Color(0xFFF2F2F3);
  static const textSecondaryDark = Color(0xFFABABAB);
  static const borderDark = Color(0xFF686965);
  static const borderSoftDark = Color(0xFF000000);

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

  /// The shipped palette, exactly — not run through [nexAccentPaletteFrom],
  /// so nobody who has never touched the accent setting sees so much as a
  /// rounding-level shift in it. The formula only takes over once someone
  /// actually picks a seed of their own (see [nexLightTheme]).
  static const defaultAccent = NexAccentPalette(
    light: accentLight,
    strongLight: accentStrongLight,
    dark: accentDark,
    strongDark: accentStrongDark,
  );

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

  /// The rest of the swipe set, added when the gesture stopped being a pair.
  ///
  /// Muted on purpose, and all from the same family as [swipeAddTag]: these
  /// panels fill half the screen for a moment, and a set of bright hues would
  /// make the timeline feel like a different app depending on which way you
  /// swiped. Every one of them carries a white label, so every one clears
  /// 4.5:1 against white — which is what rules out the obvious cheerful
  /// choices for the amber and green.
  static const swipePin = Color(0xFF8A6D1F);
  static const swipeRemind = Color(0xFF2F6F5E);
  static const swipeShare = Color(0xFF3D5A80);
  static const swipeAsk = Color(0xFF5B4B8A);
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

  /// How long a toast's content takes to pop in — see [NexToastPop].
  static const toastPop = Duration(milliseconds: 380);
}

/// One radius scale. Inner radii are derived from an outer radius minus the
/// inset that separates them, so concentric corners actually stay concentric.
///
/// [lg] is the card radius, and it is the only name for it. It used to live on
/// [NexColors] as well — a radius on the colour class — and the app reached for
/// whichever of the two names was nearer, so the same corner was written two
/// ways in the same sheet.
abstract final class NexRadius {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 20.0;
  static const xl = 28.0;

  /// What a pill-shaped control 48dp tall actually comes out at.
  ///
  /// The search field is a [StadiumBorder], so its corners are half its
  /// height. Anything too tall to be a stadium itself — the daily digest card
  /// — matches that curvature by using this number directly, rather than by
  /// becoming a stadium and bowing its sides out.
  static const pill = nexMinTapTarget / 2;

  /// The radius a shape nested [inset] inside a [outer]-radius shape needs in
  /// order to look concentric with it.
  static double inside(double outer, double inset) =>
      math.max(xs, outer - inset);

  /// The leading icon box and photo thumbnail on a card.
  ///
  /// Matches the Nex_ui Figma redesign's icon-box radius ratio (~0.3 of the
  /// box's own size) rather than [inside] concentric with the card or a
  /// fraction of the card's own [lg] radius — both of those tied the leading
  /// element's roundness to a number about the card, when the box shrank on
  /// its own terms and needed a roundness to match.
  static const cardLeading = 14.0;
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
  vertical: NexSpacing.sm,
);

/// The type glyph's container on a card, and the photo thumbnail's size.
///
/// Smaller than it was — the Nex_ui Figma redesign's icon box scales
/// noticeably down against the rest of its layout, from the 56dp this used
/// to be. It is never its own tap target (the whole card is, via the
/// [InkWell] in `_CardBody`), so nothing here is bound by [nexMinTapTarget].
/// It is never its own tap target (the whole card is, via the [InkWell] in
/// `_CardBody`), so nothing here is bound by [nexMinTapTarget].
const nexCardLeadingSize = 48.0;

/// How many lines of the note's own words a card shows.
///
/// Two. One was enough to tell cards apart and not enough to tell you what a
/// note *said* — a captured thought is usually a sentence, and a sentence is
/// usually wider than a phone.
const nexCardPreviewLines = 2;

/// One line of the preview, at the theme's bodyLarge line height.
///
/// A constant rather than a measurement, because the card's height has to be
/// known before its text is laid out. Changing bodyLarge means changing this.
const _nexCardPreviewLineHeight = 24.0;

/// One height for every card in the timeline, at the default text size.
///
/// Cards used to size to their content, so a note carrying tags stood taller
/// than one without and a note with two lines of text taller than one with a
/// single line — the list came out ragged, with no relationship between a
/// card's height and anything the reader cares about.
///
/// Two preview lines cost exactly what the leading glyph already did: 24
/// twice, against the glyph's 48. So a two-line preview never had to make the
/// card taller — and briefly did, because the relative time was stacked
/// *under* the preview and that was the part which would not fit. Moving the
/// time beside the glyph gave the text its full height back and the card its
/// original size back.
const nexCardHeight = nexCardLeadingSize + NexSpacing.cardInset * 2;

/// [nexCardHeight], grown only as far as larger text actually needs.
///
/// At the default scale this is exactly [nexCardHeight] — two preview lines
/// and the glyph both come to 48. Past that the lines outgrow the glyph and
/// the card follows them, because the alternative is a fixed box clipping the
/// text of whoever turned the size up. The app's own UI-scale setting composes
/// with the system's and clamps at 1.9, so this can be asked for nearly twice
/// the default.
double nexCardHeightFor(BuildContext context) {
  final lines =
      MediaQuery.textScalerOf(context).scale(_nexCardPreviewLineHeight) *
      nexCardPreviewLines;
  return math.max(nexCardLeadingSize, lines) + NexSpacing.cardInset * 2;
}

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

/// [accentSeed] is the one colour someone actually picks — see
/// [NexAccentPalette] for how the other three roles follow from it. Null
/// (the default) seeds from [NexColors.accentLight] itself, which is why
/// leaving it unset reproduces the shipped palette rather than some other
/// default.
ThemeData nexLightTheme({
  bool comfortMode = false,
  bool liquidGlass = false,
  bool transparentScaffold = false,
  String? fontFamily,
  Color? accentSeed,
}) {
  final palette = accentSeed == null
      ? NexColors.defaultAccent
      : nexAccentPaletteFrom(accentSeed);
  return _theme(
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
    border: comfortMode ? NexColors.borderLightComfort : NexColors.borderLight,
    borderSoft: comfortMode
        ? NexColors.borderSoftLightComfort
        : NexColors.borderSoftLight,
    accent: palette.light,
    accentStrong: palette.strongLight,
    onAccent: const Color(0xFFFFFFFF),
    // The light theme's toast is a near-black capsule, so its action needs
    // the accent drawn for dark grounds.
    accentOnInverse: palette.dark,
    fontFamily: fontFamily ?? nexLatinFont,
    liquidGlass: liquidGlass,
    transparentScaffold: transparentScaffold,
  );
}

ThemeData nexDarkTheme({
  bool comfortMode = false,
  bool liquidGlass = false,
  bool transparentScaffold = false,
  String? fontFamily,
  Color? accentSeed,
}) {
  final palette = accentSeed == null
      ? NexColors.defaultAccent
      : nexAccentPaletteFrom(accentSeed);
  return _theme(
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
    accent: palette.dark,
    accentStrong: palette.strongDark,
    onAccent: const Color(0xFF0B0A09),
    accentOnInverse: palette.strongLight,
    fontFamily: fontFamily ?? nexLatinFont,
    liquidGlass: liquidGlass,
    transparentScaffold: transparentScaffold,
  );
}

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
  required Color accentOnInverse,
  required String fontFamily,
  required bool liquidGlass,
  required bool transparentScaffold,
}) {
  final dark = brightness == Brightness.dark;
  final pageSurface = liquidGlass
      ? background.withValues(alpha: dark ? 0.72 : 0.68)
      : background;
  final cardSurface = liquidGlass
      ? card.withValues(alpha: dark ? 0.76 : 0.74)
      : card;
  final elevatedSurface = liquidGlass
      ? elevated.withValues(alpha: dark ? 0.66 : 0.62)
      : elevated;
  // What a sheet is drawn on. Higher than the other glass surfaces on
  // purpose: a sheet covers the page rather than sitting within it, and it is
  // the one place where seeing the layer underneath is not depth, it is two
  // paragraphs on top of each other.
  final sheetSurface = card.withValues(alpha: dark ? 0.94 : 0.96);
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
    surface: pageSurface,
    onSurface: primary,
    onSurfaceVariant: secondary,
    surfaceContainerLowest: cardSurface,
    surfaceContainerLow: cardSurface,
    surfaceContainer: elevatedSurface,
    surfaceContainerHigh: elevatedSurface,
    surfaceContainerHighest: elevatedSurface,
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
    scaffoldBackgroundColor: transparentScaffold || liquidGlass
        ? Colors.transparent
        : background,
    canvasColor: background,
    fontFamily: fontFamily,
    focusColor: accent.withValues(alpha: 0.12),
    appBarTheme: AppBarTheme(
      backgroundColor: liquidGlass
          ? background.withValues(alpha: dark ? 0.58 : 0.52)
          : transparentScaffold
          ? background.withValues(alpha: 0.94)
          : background,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: liquidGlass
          ? accentStrong.withValues(alpha: 0.88)
          : accentStrong,
      foregroundColor: onAccent,
      elevation: liquidGlass ? 8 : 3,
      sizeConstraints: const BoxConstraints.tightFor(
        width: nexCaptureFabSize,
        height: nexCaptureFabSize,
      ),
    ),
    dividerColor: borderSoft,
    cardTheme: CardThemeData(
      elevation: 0,
      color: cardSurface,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NexRadius.lg),
      ),
    ),
    dialogTheme: DialogThemeData(
      elevation: liquidGlass ? 12 : 6,
      backgroundColor: cardSurface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NexRadius.xl),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      // Not transparent. Transparency here assumed every sheet would wrap
      // itself in a NexGlassSurface, and most do not — the reminder picker,
      // the chat history and the group menu are plain sheets, so they were
      // being drawn with no surface at all and their text sat directly on the
      // timeline. A sheet is a thing you put in front of the page; it has to
      // be able to hold text on its own.
      backgroundColor: liquidGlass ? sheetSurface : card,
      modalBackgroundColor: liquidGlass ? sheetSurface : card,
      surfaceTintColor: Colors.transparent,
      elevation: liquidGlass ? 0 : 8,
      modalElevation: liquidGlass ? 0 : 8,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(NexRadius.xl)),
      ),
      clipBehavior: Clip.antiAlias,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: elevatedSurface,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: NexSpacing.md,
        vertical: NexSpacing.md,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(NexRadius.md),
        borderSide: BorderSide(color: borderSoft),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(NexRadius.md),
        borderSide: BorderSide(color: accent, width: nexFocusRingWidth),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(NexRadius.md),
        borderSide: const BorderSide(color: NexColors.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(NexRadius.md),
        borderSide: const BorderSide(
          color: NexColors.error,
          width: nexFocusRingWidth,
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size.square(nexMinTapTarget),
        shape: const CircleBorder(),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(nexMinTapTarget, nexMinTapTarget),
        padding: const EdgeInsets.symmetric(horizontal: NexSpacing.lg),
        shape: const StadiumBorder(),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(nexMinTapTarget, nexMinTapTarget),
        padding: const EdgeInsets.symmetric(horizontal: NexSpacing.lg),
        shape: const StadiumBorder(),
        side: BorderSide(color: border),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(nexMinTapTarget, nexMinTapTarget),
        padding: const EdgeInsets.symmetric(horizontal: NexSpacing.md),
        shape: const StadiumBorder(),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 450),
      showDuration: const Duration(seconds: 3),
      decoration: ShapeDecoration(
        color: primary.withValues(alpha: 0.94),
        shape: const StadiumBorder(),
      ),
      textStyle: _style(
        size: 12,
        lineHeight: 16,
        weight: FontWeight.w600,
        color: background,
      ),
    ),
    listTileTheme: const ListTileThemeData(
      minTileHeight: nexMinTapTarget,
      contentPadding: EdgeInsets.symmetric(horizontal: NexSpacing.md),
    ),
    // Material 3 draws a switch at 52x32 with a 24-pixel thumb and then pads
    // it out to a 48-pixel tap target on every side, which next to a 14-pixel
    // label is the loudest control on a settings row. `shrinkWrap` drops the
    // padding and `compact` tightens what is left; the switch itself is
    // untouched, so the thing you aim at is still the row.
    switchTheme: SwitchThemeData(
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      // The tick that used to sit inside the thumb is gone with it. iOS puts
      // no glyph in a switch, and at this size it is a mark nobody reads on a
      // control whose whole job is to be read as a position. Flutter's own
      // default is no icon, so this is simply not overridden any more.
    ),
    checkboxTheme: const CheckboxThemeData(
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    ),
    radioTheme: const RadioThemeData(
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    ),
    extensions: [
      NexVisualStyle(
        liquidGlass: liquidGlass,
        baseColor: background,
        // Frosted, not see-through. The first pass at this was tuned like a
        // glass *pane* — half-transparent, a bright white rim, a diagonal
        // sheen — and the result was that whatever sat behind a surface stayed
        // legible through it, so text landed on text. iOS's own materials, and
        // Telegram's, work the other way round: the blur is heavy enough that
        // the backdrop becomes a wash of colour rather than an image, the tint
        // sits high enough to carry text at full contrast, and the only edge
        // is a hairline. Depth comes from the blur and the shadow; none of it
        // comes from letting you read the layer underneath.
        glassTint: card.withValues(alpha: dark ? 0.82 : 0.86),
        // A hairline. In light the rim is a dark one — a white edge on a pale
        // surface is invisible where it matters and glaring where it does not.
        glassBorder: dark
            ? Colors.white.withValues(alpha: 0.10)
            : Colors.black.withValues(alpha: 0.07),
        // No sheen. A diagonal white gradient across every panel is the one
        // thing that reads as a 2013 skeuomorph rather than a system material,
        // and it fights the text sitting on top of it.
        glassHighlight: Colors.transparent,
        glassShadow: Colors.black.withValues(alpha: dark ? 0.40 : 0.12),
        blurSigma: 32,
      ),
    ],
    // A capsule that floats, not a slab pinned to the bottom edge.
    //
    // The default SnackBar is full-bleed with square top corners, which is the
    // one shape in Material that cannot belong to a design language built on
    // rounded, inset cards — it reads as something the framework did rather
    // than something the app said. Floating and stadium-shaped also means it
    // sits *above* the capture button instead of across it.
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: const StadiumBorder(),
      backgroundColor: primary,
      contentTextStyle: _style(
        size: 14,
        lineHeight: 20,
        weight: FontWeight.w500,
        color: background,
      ),
      // Not `accent`: the capsule is an inverse surface, so the accent chosen
      // for the page sits on the wrong ground and lands under 4.5:1 on the one
      // word in the toast that is a button — usually "Undo".
      actionTextColor: accentOnInverse,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: NexSpacing.md,
        vertical: NexSpacing.sm,
      ),
      elevation: 6,
      showCloseIcon: false,
    ),
    // Android's default zoom transition scales and clips the whole page, which
    // reads as heavy next to the rest of the app. The Cupertino slide is the
    // motion this design language already implies: short, horizontal, and
    // interruptible by a swipe back — which this widens to the whole page,
    // because the edge strip it is normally confined to is the one part of a
    // large phone a thumb cannot reach.
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: NexSwipeBackPageTransitionsBuilder(),
        TargetPlatform.iOS: NexSwipeBackPageTransitionsBuilder(),
        TargetPlatform.macOS: NexSwipeBackPageTransitionsBuilder(),
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
}) => TextStyle(
  fontSize: size,
  height: lineHeight / size,
  fontWeight: weight,
  fontVariations: [FontVariation('wght', weight.value.toDouble())],
  color: color,
);

/// All fifteen slots, so nothing falls through.
///
/// The ramp sits one step below where it started, from body text upward —
/// body at 14 rather than 15, and every heading scaled to match. The app was
/// set large enough that a timeline card held two lines where three would fit
/// and Settings ran past the fold sooner than it needed to. Anyone who
/// preferred the old size gets it back from Settings › Text & UI size: one
/// step up is very close to what this used to be.
///
/// The three smallest slots do not move. [bodySmall] is the caption floor for
/// sustained secondary reading — every date, tag and storage figure in the app
/// — and `scaffold_test.dart` holds it at 13 on purpose. A ramp that shrinks
/// its own floor is not a smaller ramp, it is a less readable one.
///
/// Six were defined before, which left every button, chip and list-tile label
/// in the app typeset by Material's defaults — a face and a letter-spacing
/// chosen for Roboto, applied to whatever the platform happened to load. The
/// undefined slots also carried Material's colours rather than these, so
/// component text and body text resolved their colour by different mechanisms.
TextTheme _textTheme({required Color primary, required Color secondary}) =>
    TextTheme(
      displayLarge: _style(
        size: 36,
        lineHeight: 42,
        weight: FontWeight.w600,
        color: primary,
      ),
      displayMedium: _style(
        size: 32,
        lineHeight: 38,
        weight: FontWeight.w600,
        color: primary,
      ),
      displaySmall: _style(
        size: 26,
        lineHeight: 32,
        weight: FontWeight.w600,
        color: primary,
      ),
      headlineLarge: _style(
        size: 32,
        lineHeight: 38,
        weight: FontWeight.w600,
        color: primary,
      ),
      headlineMedium: _style(
        size: 26,
        lineHeight: 32,
        weight: FontWeight.w600,
        color: primary,
      ),
      headlineSmall: _style(
        size: 22,
        lineHeight: 28,
        weight: FontWeight.w600,
        color: primary,
      ),
      titleLarge: _style(
        size: 22,
        lineHeight: 28,
        weight: FontWeight.w600,
        color: primary,
      ),
      // Two points clear of [titleSmall] and four clear of body. A heading
      // one point away from body text carries no size signal at all, so the
      // hierarchy would rest entirely on weight.
      titleMedium: _style(
        size: 18,
        lineHeight: 24,
        weight: FontWeight.w600,
        color: primary,
      ),
      titleSmall: _style(
        size: 16,
        lineHeight: 22,
        weight: FontWeight.w600,
        color: primary,
      ),
      bodyLarge: _style(
        size: 15,
        lineHeight: 22,
        weight: FontWeight.w400,
        color: primary,
      ),
      bodyMedium: _style(
        size: 14,
        lineHeight: 20,
        weight: FontWeight.w400,
        color: primary,
      ),
      // Whole points, never fractional: fractional sizes do not land on pixel
      // boundaries, and this is the style every date, tag and storage figure
      // is set in.
      bodySmall: _style(
        size: 13,
        lineHeight: 18,
        weight: FontWeight.w500,
        color: secondary,
      ),
      labelLarge: _style(
        size: 13,
        lineHeight: 19,
        weight: FontWeight.w600,
        color: primary,
      ),
      labelMedium: _style(
        size: 13,
        lineHeight: 18,
        weight: FontWeight.w600,
        color: primary,
      ),
      labelSmall: _style(
        size: 12,
        lineHeight: 16,
        weight: FontWeight.w600,
        color: secondary,
      ),
    );

/// How much room the system's own bars need at the bottom of a scrolling list.
///
/// The app targets an Android that draws edge to edge unconditionally, so a
/// three-button navigation bar overlaps the window rather than shrinking it.
/// A list has to end above that bar or its last row cannot be read or tapped.
///
/// Padding rather than a `SafeArea`: content should still *scroll* under the
/// bar, which looks right and is what the platform intends — it simply must not
/// *stop* under it.
double nexBottomInset(BuildContext context) =>
    MediaQuery.paddingOf(context).bottom;

/// The colours the assistant announces itself with.
///
/// Not the accent. The accent is the app's own voice — the capture button, a
/// selected chip, a set reminder — and holding that button to reach the
/// assistant lit up in exactly the same blue as tapping it, which said "this
/// is more of the same" about the one gesture that is not.
///
/// Every assistant that has an entrance uses a spectrum rather than a hue for
/// precisely this reason: Apple Intelligence, Gemini and the Assistant all
/// sweep blue through violet and magenta into warm. This is that, at this
/// app's saturation, and it is fixed rather than derived — a colour that
/// means "a model is about to speak" should not change when someone picks a
/// different accent, and these five read on both the light and the dark page.
///
/// It closes on the colour it opened with so a sweep can loop without a seam.
const nexAssistantSpectrum = <Color>[
  Color(0xFF4C8DFF),
  Color(0xFF9B6DFF),
  Color(0xFFE0559B),
  Color(0xFFFF9F45),
  Color(0xFF4C8DFF),
];

/// The strip along the bottom of the window the system keeps for its own
/// navigation gestures.
///
/// On a phone using gesture navigation, a swipe that starts in this strip
/// belongs to Android — it goes home, or opens the recents list. A scrolling
/// list underneath it competes for the same drag, and the result is neither:
/// the list twitches, the gesture is eaten, and which of the two wins depends
/// on the angle of the finger.
///
/// This is the platform's own answer to that. `systemGestureInsets` is
/// documented for exactly this case — Flutter's own example is a slider at
/// the bottom of the screen fighting the back gesture — and it reports zero
/// on a phone with three-button navigation, where there is no such gesture to
/// clash with.
///
/// Content should still be *drawn* under the strip: cutting the list off
/// above it would leave a band of empty page under every screen. It is the
/// touches, not the pixels, that have to stop.
double nexBottomGestureStrip(BuildContext context) =>
    MediaQuery.systemGestureInsetsOf(context).bottom;

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
  'checklist' => Icons.checklist_rtl_outlined,
  'link' => Icons.link_outlined,
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
