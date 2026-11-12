import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/theme_presets.dart';
import 'package:nex_ui/nex_ui.dart';

/// The redesigned ramps, held to every floor the app's own surfaces are held
/// to — the same contract `scaffold_test.dart` keeps for the shipped ramps —
/// plus the pairing floors a whole-app theme adds: its accent as text, the
/// ink on its fills and containers, its capture button, and its glass.
void main() {
  double contrast(Color a, Color b) =>
      nexContrast(a.withValues(alpha: 1), b.withValues(alpha: 1));

  Color blend(Color film, Color backdrop) => Color.alphaBlend(film, backdrop);

  for (final preset in nexThemePresets.where((p) => p.id != 'classic')) {
    for (final dark in [false, true]) {
      // The bases the app actually composes presets over.
      final base = dark
          ? nexSoftDarkTheme(liquidGlass: true, transparentScaffold: true)
          : nexSoftLightTheme(liquidGlass: true, transparentScaffold: true);
      final theme = nexApplyThemePreset(base, preset.id, null);
      final c = theme.colorScheme;
      final visual = theme.extension<NexVisualStyle>()!;

      test('${preset.id} ${dark ? 'dark' : 'light'}: the ramp holds', () {
        // Structure: a Soft UI theme, flat and see-through over its motif.
        expect(visual.minimal, isTrue);
        // Still is the one palette whose whole point is that nothing
        // decorative is drawn, glass included.
        expect(visual.liquidGlass, preset.id == 'still' ? isFalse : isTrue);
        expect(visual.baseColor, c.surface);
        expect(theme.scaffoldBackgroundColor.a, 0);

        // Surfaces: distinct, with the functional boundary at 3:1 and the
        // divider quieter than the boundary.
        expect(c.surfaceContainerLow, isNot(c.surface));
        expect(
          contrast(c.outline, c.surfaceContainerLow),
          greaterThanOrEqualTo(3),
        );
        expect(
          contrast(c.outlineVariant, c.surfaceContainerLow),
          lessThan(contrast(c.outline, c.surfaceContainerLow)),
        );

        // Ink on every ground it is drawn on.
        for (final ground in [
          c.surface,
          c.surfaceContainerLowest,
          c.surfaceContainerLow,
          c.surfaceContainer,
          c.surfaceContainerHigh,
          c.surfaceContainerHighest,
        ]) {
          expect(
            contrast(c.onSurface, ground),
            greaterThanOrEqualTo(4.5),
            reason: 'onSurface on $ground',
          );
          expect(
            contrast(c.onSurfaceVariant, ground),
            greaterThanOrEqualTo(4.5),
            reason: 'onSurfaceVariant on $ground',
          );
          expect(
            contrast(c.primary, ground),
            greaterThanOrEqualTo(4.5),
            reason: 'primary as text on $ground',
          );
        }

        // The pairings Material actually renders.
        expect(contrast(c.onPrimary, c.primary), greaterThanOrEqualTo(4.5));
        expect(
          contrast(c.primaryContainer, c.onPrimaryContainer),
          greaterThanOrEqualTo(4.5),
        );
        const enabled = <WidgetState>{};
        expect(
          contrast(
            theme.filledButtonTheme.style!.foregroundColor!.resolve(enabled)!,
            theme.filledButtonTheme.style!.backgroundColor!.resolve(enabled)!,
          ),
          greaterThanOrEqualTo(4.5),
          reason: 'a filled button carries its own label',
        );
        expect(
          contrast(
            theme.floatingActionButtonTheme.foregroundColor!,
            theme.floatingActionButtonTheme.backgroundColor!,
          ),
          greaterThanOrEqualTo(3),
          reason: 'the capture glyph is a graphical object',
        );
        // A quiet button's label is the palette's own tone, un-derived.
        expect(
          theme.textButtonTheme.style!.foregroundColor!.resolve(enabled),
          c.primary,
        );
      });

      test(
        '${preset.id} ${dark ? 'dark' : 'light'}: glass ink stays readable',
        () {
          // The wash the theme's own page asks for, over the worst
          // backdrops a note can put behind a pane.
          for (final background in [
            Colors.white,
            Colors.black,
            Colors.red,
            Colors.blue,
            Colors.green,
          ]) {
            var surface = background;
            for (final film in [
              ...visual.glassWash.films,
              visual.glassWash.lift,
              visual.glassWash.anchor,
            ]) {
              surface = blend(film, surface);
            }
            expect(
              contrast(c.onSurface, surface),
              greaterThanOrEqualTo(4.5),
              reason: 'panel ink over $background',
            );
          }
          expect(
            contrast(
              c.onSurface,
              visual.floatingContrastGround(theme.brightness),
            ),
            greaterThanOrEqualTo(4.5),
            reason: 'floating ink on its worst ground',
          );
        },
      );
    }
  }

  test('classic is the base, untouched', () {
    final base = nexSoftLightTheme();
    final themed = nexApplyThemePreset(base, 'classic', null);
    expect(themed, same(base));
    // An unknown id never invents a look.
    expect(nexApplyThemePreset(base, 'nope', null), same(base));
    expect(nexThemeTexture('nope'), NexThemeTexture.none);
    expect(nexThemePresetSeed('nope'), isNull);
  });

  test('every preset seeds, textures and describes itself', () {
    expect(nexThemePresets.length, 15);
    expect(
      nexThemePresets.map((p) => p.id).toSet().length,
      nexThemePresets.length,
    );
    for (final preset in nexThemePresets) {
      final plain = const {'classic', 'still'}.contains(preset.id);
      expect(
        nexThemeTexture(preset.id) == NexThemeTexture.none,
        plain,
        reason: preset.id,
      );
      expect(
        preset.en.isNotEmpty && preset.fa.isNotEmpty,
        isTrue,
        reason: '${preset.id}: names',
      );
      expect(
        preset.enDescription.isNotEmpty && preset.faDescription.isNotEmpty,
        isTrue,
        reason: '${preset.id}: descriptions',
      );
      if (preset.id != 'classic') {
        expect(
          nexThemePresetSeed(preset.id),
          preset.light!.accent,
          reason: preset.id,
        );
        expect(preset.light!.brightness, Brightness.light, reason: preset.id);
        expect(preset.dark!.brightness, Brightness.dark, reason: preset.id);
      }
    }
  });

  test('a picked accent keeps its hue on every palette', () {
    const red = Color(0xFFD32F2F);
    double hueOf(Color c) => HSLColor.fromColor(c).hue;
    double satOf(Color c) => HSLColor.fromColor(c).saturation;
    for (final preset in nexThemePresets.where((p) => p.id != 'classic')) {
      for (final dark in [false, true]) {
        final theme = nexApplyThemePreset(
          dark ? nexSoftDarkTheme() : nexSoftLightTheme(),
          preset.id,
          red,
        );
        final hue = hueOf(theme.colorScheme.primary);
        expect(
          hue < 20 || hue > 340,
          isTrue,
          reason: '${preset.id} dark=$dark: $hue',
        );
        expect(
          satOf(theme.colorScheme.primary),
          greaterThan(0.6),
          reason: '${preset.id} dark=$dark',
        );
        // And its label pair still clears the text floor.
        expect(
          contrast(
            theme.filledButtonTheme.style!.foregroundColor!.resolve(
              const <WidgetState>{},
            )!,
            theme.filledButtonTheme.style!.backgroundColor!.resolve(
              const <WidgetState>{},
            )!,
          ),
          greaterThanOrEqualTo(4.5),
          reason: '${preset.id} dark=$dark: picked-accent label',
        );
      }
    }
  });

  test('custom accents stay readable on every palette surface', () {
    const seeds = [
      Colors.red,
      Colors.orange,
      Colors.yellow,
      Colors.green,
      Colors.cyan,
      Colors.blue,
      Colors.purple,
      Colors.pink,
      Colors.grey,
      Colors.white,
      Colors.black,
      Color(0x40808080),
    ];
    for (final preset in nexThemePresets.where((p) => p.id != 'classic')) {
      for (final ramp in [preset.light!, preset.dark!]) {
        for (final seed in seeds) {
          final custom = ramp.withAccent(seed);
          final reason = '${preset.id} ${ramp.brightness} $seed';
          expect(custom.accent.a, 1, reason: reason);
          for (final ground in [custom.page, custom.card, custom.elevated]) {
            expect(
              contrast(custom.accent, ground),
              greaterThanOrEqualTo(4.5),
              reason: '$reason: accent text',
            );
          }
          for (final pair in [
            (custom.accent, custom.onAccent),
            (custom.fill, custom.fillInk),
            (custom.container, custom.containerInk),
            (custom.ink, custom.resolvedAccentOnInverse),
          ]) {
            expect(
              contrast(pair.$1, pair.$2),
              greaterThanOrEqualTo(4.5),
              reason: '$reason: label pair',
            );
          }
        }
      }
    }
  });

  test('palettes retain the current glass optics and chosen font', () {
    for (final dark in [false, true]) {
      final base = dark
          ? nexSoftDarkTheme(liquidGlass: true, fontFamily: nexPersianFont)
          : nexSoftLightTheme(liquidGlass: true, fontFamily: nexPersianFont);
      final original = base.extension<NexVisualStyle>()!;
      for (final preset in nexThemePresets.where(
        (p) => p.id != 'classic' && p.id != 'still',
      )) {
        final theme = nexApplyThemePreset(base, preset.id, null);
        final visual = theme.extension<NexVisualStyle>()!;
        expect(visual.glassAura, original.glassAura, reason: preset.id);
        expect(visual.glassBounce, original.glassBounce, reason: preset.id);
        expect(visual.glassVibrancy, original.glassVibrancy, reason: preset.id);
        expect(visual.glassEdgeWidth, original.glassEdgeWidth, reason: preset.id);
        expect(visual.glassGrain, original.glassGrain, reason: preset.id);
        expect(visual.blurSigma, original.blurSigma, reason: preset.id);
        expect(theme.textTheme.bodyLarge!.fontFamily, nexPersianFont);
      }
    }
  });

  test('Graphite stays grey around a picked accent', () {
    const red = Color(0xFFD32F2F);
    final scheme = nexApplyThemePreset(
      nexSoftLightTheme(accentSeed: red),
      'graphite',
      red,
    ).colorScheme;
    double satOf(Color c) => HSLColor.fromColor(c).saturation;
    expect(satOf(scheme.surface), lessThan(0.05));
    expect(satOf(scheme.surfaceContainerLow), lessThan(0.05));
    expect(satOf(scheme.primary), greaterThan(0.6));
  });

  test("Still keeps its identity: sage, flat and glass-free", () {
    final theme = nexApplyThemePreset(nexSoftDarkTheme(), 'still', null);
    final visual = theme.extension<NexVisualStyle>()!;
    expect(theme.colorScheme.primary, const Color(0xFFB1C9B7));
    expect(visual.minimal, isTrue);
    expect(visual.liquidGlass, isFalse);
    expect(nexThemeTexture('still'), NexThemeTexture.none);
  });
}
