import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ui/nex_ui.dart';

void main() {
  test('Soft Dark uses the supplied neutral ramp and flat surfaces', () {
    final theme = nexSoftDarkTheme();
    final c = theme.colorScheme;
    expect(c.surface, const Color(0xFF141821));
    expect(c.surfaceContainerLowest, const Color(0xFF1C212C));
    expect(c.surfaceContainerHigh, const Color(0xFF252B38));
    expect(c.onSurface, const Color(0xFFD9DDE6));
    expect(c.onSurfaceVariant, const Color(0xFF98A1B5));
    expect(c.primaryContainer, const Color(0xFF16304D));
    expect(theme.extension<NexVisualStyle>()!.minimal, isTrue);
    expect(theme.extension<NexVisualStyle>()!.liquidGlass, isFalse);
    expect(theme.shadowColor, Colors.transparent);
    expect(theme.dialogTheme.elevation, 0);
    expect(theme.popupMenuTheme.elevation, 0);
    expect(theme.bottomSheetTheme.modalElevation, 0);
    expect(theme.floatingActionButtonTheme.elevation, 0);
    expect(
      (theme.inputDecorationTheme.enabledBorder! as OutlineInputBorder)
          .borderSide,
      BorderSide.none,
    );
    expect(
      (theme.inputDecorationTheme.focusedBorder! as OutlineInputBorder)
          .borderSide
          .width,
      greaterThan(0),
    );
  });

  for (final seed in <Color?>[
    null,
    const Color(0xFFB61615),
    const Color(0xFFFFD600),
  ]) {
    for (final glass in [false, true]) {
      test('readable text, custom accent and glass: $seed / $glass', () {
        final theme = nexSoftDarkTheme(accentSeed: seed, liquidGlass: glass);
        final c = theme.colorScheme;
        for (final ground in [
          c.surface,
          c.surfaceContainerLowest,
          c.surfaceContainerHigh,
        ]) {
          for (final ink in [c.onSurface, c.onSurfaceVariant, c.primary]) {
            expect(nexContrastRatio(ink, ground), greaterThanOrEqualTo(4.5));
          }
        }
        expect(
          nexContrastRatio(c.onPrimaryContainer, c.primaryContainer),
          greaterThanOrEqualTo(4.5),
        );
        final style = theme.filledButtonTheme.style!;
        expect(
          nexContrastRatio(
            style.foregroundColor!.resolve({})!,
            style.backgroundColor!.resolve({})!,
          ),
          greaterThanOrEqualTo(4.5),
        );
        expect(theme.extension<NexVisualStyle>()!.liquidGlass, glass);
        expect(
          nexContrastRatio(c.primary, c.onPrimary),
          greaterThanOrEqualTo(4.5),
        );
        if (glass) {
          final visual = theme.extension<NexVisualStyle>()!;
          for (final wash in [visual.glassWash, visual.floatingGlassWash]) {
            for (final backdrop in [
              Colors.white,
              Colors.black,
              Colors.red,
              Colors.green,
              Colors.blue,
            ]) {
              var ground = backdrop;
              for (final film in [...wash.films, wash.lift, wash.anchor]) {
                ground = Color.alphaBlend(film, ground);
              }
              expect(
                nexContrastRatio(c.onSurface, ground),
                greaterThanOrEqualTo(4.5),
              );
            }
          }
        }
        if (seed != null) {
          expect(c.primary, isNot(NexSoftDarkColors.accentText));
        }
        expect(
          nexContrastRatio(c.outline, c.surfaceContainerLowest),
          greaterThanOrEqualTo(3),
        );
      });
    }
  }

  test('Night exactly retains the former Dark renderer', () {
    for (final glass in [false, true]) {
      for (final seed in <Color?>[null, const Color(0xFFB61615)]) {
        final night = nexNightTheme(liquidGlass: glass, accentSeed: seed);
        final legacy = nexDarkTheme(liquidGlass: glass, accentSeed: seed);
        expect(night.colorScheme, legacy.colorScheme);
        expect(night.textTheme, legacy.textTheme);
        expect(
          night.floatingActionButtonTheme,
          legacy.floatingActionButtonTheme,
        );
        expect(night.inputDecorationTheme, legacy.inputDecorationTheme);
        expect(
          night.extension<NexVisualStyle>()!.glassWash,
          legacy.extension<NexVisualStyle>()!.glassWash,
        );
        expect(
          night.extension<NexVisualStyle>()!.baseColor,
          legacy.extension<NexVisualStyle>()!.baseColor,
        );
      }
    }
  });
}
