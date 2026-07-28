import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ui/nex_ui.dart';

/// The token contract, stated as contrast relationships rather than as hex
/// values copied out of a mockup.
///
/// This file used to pin the exact colours — including
/// `borderLight == 0xFFEBEAE8`, which is 1.20:1 against the surface it sat on.
/// A token test that pins a failing value is a test defending the bug, so the
/// assertions are now about what each pairing has to *do*.
void main() {
  /// (name, card, page, elevated, border, borderSoft, text, secondary)
  final themes = <String, List<Color>>{
    'light': [
      NexColors.bgCardLight,
      NexColors.bgPrimaryLight,
      NexColors.bgElevatedLight,
      NexColors.borderLight,
      NexColors.borderSoftLight,
      NexColors.textPrimaryLight,
      NexColors.textSecondaryLight,
    ],
    'dark': [
      NexColors.bgCardDark,
      NexColors.bgPrimaryDark,
      NexColors.bgElevatedDark,
      NexColors.borderDark,
      NexColors.borderSoftDark,
      NexColors.textPrimaryDark,
      NexColors.textSecondaryDark,
    ],
    'comfort light': [
      NexColors.bgCardLightComfort,
      NexColors.bgPrimaryLightComfort,
      NexColors.bgElevatedLightComfort,
      NexColors.borderLightComfort,
      NexColors.borderSoftLightComfort,
      NexColors.textPrimaryLightComfort,
      NexColors.textSecondaryLightComfort,
    ],
    'comfort dark': [
      NexColors.bgCardDarkComfort,
      NexColors.bgPrimaryDarkComfort,
      NexColors.bgElevatedDarkComfort,
      NexColors.borderDarkComfort,
      NexColors.borderSoftDarkComfort,
      NexColors.textPrimaryDarkComfort,
      NexColors.textSecondaryDarkComfort,
    ],
  };

  themes.forEach((name, c) {
    final [card, page, elevated, border, borderSoft, text, secondary] = c;

    group(name, () {
      test('a card is a different surface from the page behind it', () {
        // Not a contrast requirement — a depth one. Both were #FFFFFF, so the
        // card had no fill of its own and the hairline was carrying the whole
        // boundary on its own.
        expect(card, isNot(page));
      });

      test('the card boundary clears the 3:1 non-text floor (WCAG 1.4.11)', () {
        expect(nexContrastRatio(border, card), greaterThanOrEqualTo(3.0));
      });

      test('the divider token is quieter than the boundary token', () {
        // One token used to do both jobs, which meant either the dividers
        // shouted or the boundaries whispered. They whispered.
        expect(
          nexContrastRatio(borderSoft, card),
          lessThan(nexContrastRatio(border, card)),
        );
      });

      test('a filled container inside a card is actually visible', () {
        // The 56px note-type disc was at 1.10:1 — a deliberate design element
        // rendering as nothing at all.
        expect(nexContrastRatio(elevated, card), greaterThanOrEqualTo(1.3));
        expect(nexContrastRatio(border, elevated), greaterThanOrEqualTo(1.6));
      });

      test('body and secondary text both clear 4.5:1 on the card', () {
        expect(nexContrastRatio(text, card), greaterThanOrEqualTo(4.5));
        expect(nexContrastRatio(secondary, card), greaterThanOrEqualTo(4.5));
      });

      test('body and secondary text both clear 4.5:1 on the page', () {
        expect(nexContrastRatio(text, page), greaterThanOrEqualTo(4.5));
        expect(nexContrastRatio(secondary, page), greaterThanOrEqualTo(4.5));
      });
    });
  });

  test('the accent is legible as a 2px ring on every ground', () {
    // The focus ring, the caret and the active filter are all drawn in it, and
    // a ring is non-text: 3:1.
    for (final ground in [
      NexColors.bgCardLight,
      NexColors.bgPrimaryLight,
      NexColors.bgCardLightComfort,
      NexColors.bgPrimaryLightComfort,
    ]) {
      expect(
        nexContrastRatio(NexColors.accentLight, ground),
        greaterThanOrEqualTo(3.0),
        reason: 'light accent on $ground',
      );
    }
    for (final ground in [
      NexColors.bgCardDark,
      NexColors.bgPrimaryDark,
      NexColors.bgCardDarkComfort,
      NexColors.bgPrimaryDarkComfort,
    ]) {
      expect(
        nexContrastRatio(NexColors.accentDark, ground),
        greaterThanOrEqualTo(3.0),
        reason: 'dark accent on $ground',
      );
    }
  });

  test('white text is legible on the filled accent', () {
    expect(
      nexContrastRatio(const Color(0xFFFFFFFF), NexColors.accentStrongLight),
      greaterThanOrEqualTo(4.5),
    );
  });

  test('the accent is not mistakable for the destructive colour', () {
    // Contrast ratio cannot answer this — it measures luminance, and two
    // colours of opposite hue can share one. The question is angular.
    double apart(Color a, Color b) {
      final delta =
          (HSVColor.fromColor(a).hue - HSVColor.fromColor(b).hue).abs();
      return delta > 180 ? 360 - delta : delta;
    }

    // Delete and "Nex is live" are the two most colour-loaded moments in the
    // app, and they must never be confusable. This is the argument against an
    // accent that sits between the destructive red and the amber that the
    // suggested tag palette already uses.
    expect(apart(NexColors.accentLight, NexColors.danger), greaterThan(90));
    expect(apart(NexColors.accentLight, const Color(0xFFF0A93B)),
        greaterThan(90));
  });

  test('destructive intent and invalid input are separate roles', () {
    expect(NexColors.danger, isNot(NexColors.error));
  });

  test('swipe action panels carry legible white labels', () {
    // Both panels label themselves in white, in either theme, so each colour
    // has to clear the body-text floor on its own — the theme cannot rescue it.
    for (final background in [NexColors.swipeDelete, NexColors.swipeAddTag]) {
      expect(
        nexContrastRatio(const Color(0xFFFFFFFF), background),
        greaterThanOrEqualTo(4.5),
      );
    }
    // The non-destructive action must not read as a second delete.
    expect(NexColors.swipeAddTag, isNot(NexColors.swipeDelete));
  });

  test('the tap-target floor is the one the platforms actually ask for', () {
    // 44 was Apple's number; Material asks 48 and WCAG 2.5.8 asks 24. The
    // token now clears all three.
    expect(nexMinTapTarget, greaterThanOrEqualTo(48));
  });

  test('inner radii are concentric with the card, not arbitrary', () {
    // A 22px outer radius wrapping a 16px inner radius at an 18px inset is a
    // mismatched curve; the correct inner radius for that inset was 4.
    expect(
      NexRadius.inside(NexRadius.lg, NexSpacing.cardInset),
      NexRadius.lg - NexSpacing.cardInset,
    );
  });

  test('every Material text slot is defined, so none falls through', () {
    final t = nexLightTheme().textTheme;
    final slots = <String, TextStyle?>{
      'displayLarge': t.displayLarge,
      'displayMedium': t.displayMedium,
      'displaySmall': t.displaySmall,
      'headlineLarge': t.headlineLarge,
      'headlineMedium': t.headlineMedium,
      'headlineSmall': t.headlineSmall,
      'titleLarge': t.titleLarge,
      'titleMedium': t.titleMedium,
      'titleSmall': t.titleSmall,
      'bodyLarge': t.bodyLarge,
      'bodyMedium': t.bodyMedium,
      'bodySmall': t.bodySmall,
      'labelLarge': t.labelLarge,
      'labelMedium': t.labelMedium,
      'labelSmall': t.labelSmall,
    };
    slots.forEach((name, style) {
      expect(style?.fontSize, isNotNull, reason: '$name has no size');
      // Variable fonts need the weight on the axis, not only in fontWeight,
      // or the whole app renders at one instance on some platforms.
      expect(style?.fontVariations, isNotEmpty, reason: '$name has no wght');
    });
    // No fractional sizes: 12.5 never lands on a pixel boundary.
    for (final style in slots.values) {
      expect(style!.fontSize! % 1, 0, reason: '${style.fontSize} is fractional');
    }
    // A heading and body text one point apart carry no size signal.
    expect(t.titleMedium!.fontSize! - t.bodyLarge!.fontSize!, greaterThan(2));
    // The caption floor for sustained secondary reading.
    expect(t.bodySmall!.fontSize, greaterThanOrEqualTo(13));
  });

  test('one typeface is named, on every platform', () {
    // `ThemeData.fontFamily` is not readable back, so the family is checked
    // where it actually lands: on every resolved text style.
    expect(
      nexLightTheme(fontFamily: nexPersianFont).textTheme.bodyLarge!.fontFamily,
      nexPersianFont,
    );
    expect(
      nexLightTheme().textTheme.bodyLarge!.fontFamily,
      nexLatinFont,
    );
    expect(nexFontFor(const Locale('fa')), nexPersianFont);
    expect(nexFontFor(const Locale('en')), nexLatinFont);
    expect(nexFontFor(null), nexLatinFont);
  });

  test('no colour role is left to be generated from a near-grey seed', () {
    // `fromSeed` produced these from a chroma-zero seed; inversePrimary in
    // particular is live as the Undo action's colour.
    final scheme = nexLightTheme().colorScheme;
    expect(scheme.inversePrimary, NexColors.accentLight);
    expect(scheme.primary, NexColors.accentLight);
    expect(scheme.outline, NexColors.borderLight);
    expect(scheme.outlineVariant, NexColors.borderSoftLight);
    expect(scheme.error, NexColors.error);
  });
}
