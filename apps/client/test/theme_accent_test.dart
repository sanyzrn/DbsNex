import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/theme_presets.dart';
import 'package:nex_ui/nex_ui.dart';

/// An accent somebody picks shows as that colour on every palette — it was
/// muted to brown on the palettes and ignored outright on Graphite, which
/// read as the choice not being applied.
void main() {
  const red = Color(0xFFD32F2F);

  double hueOf(Color c) => HSLColor.fromColor(c).hue;
  double satOf(Color c) => HSLColor.fromColor(c).saturation;

  for (final preset in nexThemePresets) {
    if (preset.id == 'classic') continue;
    test('${preset.id}: a picked red is red', () {
      for (final base in [
        nexLightTheme(accentSeed: red),
        nexDarkTheme(accentSeed: red),
      ]) {
        final primary = nexApplyThemePreset(
          base,
          preset.id,
          red,
        ).colorScheme.primary;
        final hue = hueOf(primary);
        expect(hue < 20 || hue > 340, isTrue, reason: '$primary');
        expect(satOf(primary), greaterThan(0.6), reason: '$primary');
      }
    });
  }

  test(
    'palette colours reach text and filled buttons in both brightnesses',
    () {
      for (final preset in nexThemePresets.where((p) => p.id != 'classic')) {
        for (final base in [nexLightTheme(), nexDarkTheme()]) {
          final theme = nexApplyThemePreset(base, preset.id, null);
          expect(
            theme.textButtonTheme.style!.foregroundColor!.resolve({}),
            theme.colorScheme.primary,
            reason: '${preset.id}: text button',
          );
          expect(
            theme.filledButtonTheme.style!.backgroundColor!.resolve({}),
            theme.colorScheme.primary,
            reason: '${preset.id}: filled button',
          );
          expect(
            theme.filledButtonTheme.style!.foregroundColor!.resolve({}),
            theme.colorScheme.onPrimary,
          );
        }
      }
    },
  );

  test('a palette with its own seed keeps its own muted look', () {
    final seed = nexThemePresetSeed('paper')!;
    final own = nexApplyThemePreset(nexLightTheme(), 'paper', seed);
    final none = nexApplyThemePreset(nexLightTheme(), 'paper', null);
    expect(own.colorScheme.primary, none.colorScheme.primary);
  });

  test('Graphite stays grey around a picked accent', () {
    final scheme = nexApplyThemePreset(
      nexLightTheme(accentSeed: red),
      'graphite',
      red,
    ).colorScheme;
    expect(satOf(scheme.surface), lessThan(0.05));
    expect(satOf(scheme.primary), greaterThan(0.6));
  });
}
