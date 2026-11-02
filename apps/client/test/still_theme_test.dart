import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/theme_presets.dart';
import 'package:nex_ui/nex_ui.dart';

double _contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return x > y ? (x + 0.05) / (y + 0.05) : (y + 0.05) / (x + 0.05);
}

void main() {
  for (final dark in [false, true]) {
    for (final glass in [false, true]) {
      final base = dark
          ? nexDarkTheme(liquidGlass: glass)
          : nexLightTheme(liquidGlass: glass);
      final theme = nexApplyThemePreset(base, 'still', null);
      test('Still $dark, glass preference $glass: readable and flat', () {
        final c = theme.colorScheme;
        final visual = theme.extension<NexVisualStyle>()!;
        expect(visual.minimal, isTrue);
        expect(visual.liquidGlass, isFalse);
        expect(nexThemeTexture('still'), NexThemeTexture.none);
        for (final surface in [
          c.surface,
          c.surfaceContainerLowest,
          c.surfaceContainerLow,
          c.surfaceContainer,
          c.surfaceContainerHigh,
          c.surfaceContainerHighest,
        ]) {
          for (final ink in [c.onSurface, c.onSurfaceVariant, c.primary]) {
            expect(_contrast(ink, surface), greaterThanOrEqualTo(4.5));
          }
        }
        expect(_contrast(c.primary, c.onPrimary), greaterThanOrEqualTo(4.5));
        expect(_contrast(c.primaryContainer, c.onPrimaryContainer), greaterThanOrEqualTo(4.5));
        expect(theme.floatingActionButtonTheme.highlightElevation, 0);
        expect(theme.dialogTheme.elevation, 0);
        expect(theme.bottomSheetTheme.modalElevation, 0);
        expect(theme.popupMenuTheme.elevation, 0);
        expect((theme.inputDecorationTheme.enabledBorder! as OutlineInputBorder).borderSide, BorderSide.none);
        expect((theme.inputDecorationTheme.focusedBorder! as OutlineInputBorder).borderSide.color, c.primary);
      });

      testWidgets('Still $dark, glass $glass: shared panels lose decorative borders', (tester) async {
        await tester.pumpWidget(MaterialApp(
          theme: theme,
          home: Scaffold(body: Column(children: [
            NexSurface(
              color: theme.colorScheme.surfaceContainerLow,
              border: const BorderSide(color: Colors.red),
              child: const Text('Panel'),
            ),
            NexGlassSurface(
              fallbackColor: theme.colorScheme.surfaceContainerLowest,
              child: const Text('Sheet'),
            ),
          ])),
        ));
        final panel = tester.widget<Material>(find.descendant(
          of: find.byType(NexSurface), matching: find.byType(Material),
        ).first);
        expect((panel.shape! as RoundedRectangleBorder).side, BorderSide.none);
        final sheet = tester.widget<DecoratedBox>(find.descendant(
          of: find.byType(NexGlassSurface), matching: find.byType(DecoratedBox),
        ).first);
        expect((sheet.decoration as BoxDecoration).border, isNull);
        expect((sheet.decoration as BoxDecoration).boxShadow, isNull);
      });
    }
  }
  test('other themes keep their material and Still preserves custom accents', () {
    final base = nexLightTheme(liquidGlass: true);
    final classic = nexApplyThemePreset(base, 'classic', null);
    expect(classic.extension<NexVisualStyle>()!.minimal, isFalse);
    expect(classic.extension<NexVisualStyle>()!.liquidGlass, isTrue);
    const red = Color(0xFFD32F2F);
    final picked = nexApplyThemePreset(base, 'still', red);
    final hue = HSLColor.fromColor(picked.colorScheme.primary).hue;
    expect(hue < 20 || hue > 340, isTrue);
  });
}
