import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ui/nex_ui.dart';

void main() {
  group('nexAccentPaletteFrom', () {
    test('preserves the seed\'s hue across all four roles', () {
      final seed = const Color(0xFF2E9E5B); // an arbitrary green
      final palette = nexAccentPaletteFrom(seed);
      final seedHue = HSLColor.fromColor(seed).hue;

      for (final shade in [
        palette.light,
        palette.strongLight,
        palette.dark,
        palette.strongDark,
      ]) {
        expect(
          HSLColor.fromColor(shade).hue,
          closeTo(seedHue, 0.5),
          reason:
              'a recoloured accent that drifts hue stops being the '
              'colour someone actually picked',
        );
      }
    });

    test('the strong shade is darker than light; dark shades are lighter '
        'than both', () {
      final palette = nexAccentPaletteFrom(const Color(0xFF2563EB));
      double lightnessOf(Color c) => HSLColor.fromColor(c).lightness;

      expect(
        lightnessOf(palette.strongLight),
        lessThan(lightnessOf(palette.light)),
      );
      expect(
        lightnessOf(palette.dark),
        greaterThan(lightnessOf(palette.light)),
      );
      expect(
        lightnessOf(palette.strongDark),
        greaterThan(lightnessOf(palette.dark)),
      );
    });

    test('a near-grey seed still produces four distinct, orderable shades', () {
      // Zero chroma is exactly the failure mode NexColors's own doc comment
      // warns `ColorScheme.fromSeed` falls into — the formula must not
      // inherit it just because someone's custom pick happens to be muted.
      final palette = nexAccentPaletteFrom(const Color(0xFF808080));
      expect(palette.light, isNot(palette.strongLight));
      expect(palette.dark, isNot(palette.strongDark));
    });
  });

  group('NexColors.defaultAccent', () {
    test('is the shipped hex constants, not a run through the formula', () {
      // Bit-exact: nexAccentPaletteFrom's lightness normalisation would nudge
      // these by a rounding sliver, which is a real (if tiny) colour shift
      // for every user who has never touched the accent setting.
      expect(NexColors.defaultAccent.light, NexColors.accentLight);
      expect(NexColors.defaultAccent.strongLight, NexColors.accentStrongLight);
      expect(NexColors.defaultAccent.dark, NexColors.accentDark);
      expect(NexColors.defaultAccent.strongDark, NexColors.accentStrongDark);
    });
  });

  group('nexLightTheme / nexDarkTheme accentSeed', () {
    test('no seed reproduces the shipped default exactly', () {
      expect(
        nexLightTheme().colorScheme.primary,
        NexColors.defaultAccent.light,
      );
      expect(nexDarkTheme().colorScheme.primary, NexColors.defaultAccent.dark);
    });

    test('a custom seed actually changes the resolved theme colour', () {
      const seed = Color(0xFF2E9E5B);
      final theme = nexLightTheme(accentSeed: seed);
      expect(theme.colorScheme.primary, isNot(NexColors.defaultAccent.light));
      expect(theme.colorScheme.primary, nexAccentPaletteFrom(seed).light);
    });

    test(
      'the same seed drives both themes, each taking its own role from it',
      () {
        const seed = Color(0xFFB5482A);
        final palette = nexAccentPaletteFrom(seed);
        expect(
          nexLightTheme(accentSeed: seed).colorScheme.primary,
          palette.light,
        );
        expect(
          nexDarkTheme(accentSeed: seed).colorScheme.primary,
          palette.dark,
        );
      },
    );
  });
}
