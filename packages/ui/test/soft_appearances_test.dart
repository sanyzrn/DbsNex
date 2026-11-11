import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ui/nex_ui.dart';

void main() {
  test('Soft Light uses demo surfaces and no decorative material', () {
    final theme = nexSoftLightTheme();
    final c = theme.colorScheme;
    expect(c.surface, NexSoftLightColors.background);
    expect(c.surfaceContainerLowest, NexSoftLightColors.card);
    expect(c.surfaceContainerHigh, NexSoftLightColors.elevated);
    expect(c.onSurface, NexSoftLightColors.text);
    expect(c.onSurfaceVariant, NexSoftLightColors.muted);
    expect(c.primaryContainer, NexSoftLightColors.accentContainer);
    expect(c.primary, NexColors.accentStrongLight);
    expect(c.outline, NexSoftLightColors.outline);
    expect(
      theme.floatingActionButtonTheme.backgroundColor,
      NexSoftLightColors.accent,
    );
    for (final surface in [c.surfaceContainerLowest, c.surfaceContainerHigh]) {
      expect(nexContrastRatio(c.outline, surface), greaterThanOrEqualTo(3));
      expect(
        nexContrastRatio(c.onSurfaceVariant, surface),
        greaterThanOrEqualTo(4.5),
      );
    }
    expect(
      nexContrastRatio(c.primary, c.surfaceContainerLowest),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      nexContrastRatio(c.primary, c.primaryContainer),
      greaterThanOrEqualTo(4.5),
    );
    expect(theme.extension<NexVisualStyle>()!.minimal, isTrue);
    expect(theme.shadowColor, Colors.transparent);
    expect(theme.dialogTheme.elevation, 0);
    expect(theme.bottomSheetTheme.modalElevation, 0);
    expect(theme.popupMenuTheme.elevation, 0);
    expect(theme.chipTheme.side, BorderSide.none);
    expect(
      (theme.inputDecorationTheme.enabledBorder! as OutlineInputBorder)
          .borderSide,
      BorderSide(color: c.outline, width: 1),
    );
  });

  test('OLED Night is true black with muted, readable text', () {
    final theme = nexOledNightTheme();
    final c = theme.colorScheme;
    expect(c.surface, NexOledNightColors.background);
    expect(c.surfaceContainerLowest, NexOledNightColors.card);
    expect(c.surfaceContainerHigh, NexOledNightColors.elevated);
    expect(c.onSurface, NexOledNightColors.text);
    expect(c.onSurfaceVariant, NexOledNightColors.muted);
    expect(c.primaryContainer, NexOledNightColors.accentContainer);
    expect(theme.extension<NexVisualStyle>()!.minimal, isTrue);
    expect(theme.shadowColor, Colors.transparent);
    expect(theme.dialogTheme.elevation, 0);
    expect(theme.bottomSheetTheme.modalElevation, 0);
    expect(theme.popupMenuTheme.elevation, 0);
    expect(theme.chipTheme.side, BorderSide.none);
    expect(
      (theme.inputDecorationTheme.enabledBorder! as OutlineInputBorder)
          .borderSide,
      BorderSide(color: c.outline, width: 1),
    );
  });

  for (final night in [false, true]) {
    for (final seed in <Color?>[
      null,
      const Color(0xFFB61615),
      const Color(0xFFFFD600),
    ]) {
      for (final glass in [false, true]) {
        test(
          '${night ? 'OLED Night' : 'Soft Light'}: contrast, accent and glass '
          '$seed / $glass',
          () {
            final theme = night
                ? nexOledNightTheme(accentSeed: seed, liquidGlass: glass)
                : nexSoftLightTheme(accentSeed: seed, liquidGlass: glass);
            final c = theme.colorScheme;
            if (!night) {
              expect(c.outline, NexSoftLightColors.outline);
              if (seed == null) {
                expect(c.primary, NexColors.accentStrongLight);
                expect(
                  theme.floatingActionButtonTheme.backgroundColor,
                  NexSoftLightColors.accent,
                );
              } else {
                expect(
                  c.primaryContainer,
                  Color.alphaBlend(
                    c.primary.withValues(alpha: 0.16),
                    NexSoftLightColors.card,
                  ),
                );
              }
            }
            for (final ground in [
              c.surface,
              c.surfaceContainerLowest,
              c.surfaceContainerHigh,
            ]) {
              expect(
                nexContrastRatio(c.onSurface, ground),
                greaterThanOrEqualTo(4.5),
              );
              expect(
                nexContrastRatio(c.onSurfaceVariant, ground),
                greaterThanOrEqualTo(4.5),
              );
            }
            // The toast is an inverse capsule: its action token is measured
            // against the fill it actually sits on (V-03).
            expect(
              nexContrastRatio(
                theme.snackBarTheme.actionTextColor!,
                theme.snackBarTheme.backgroundColor!,
              ),
              greaterThanOrEqualTo(4.5),
            );
            // Stock M3 chips and segmented buttons draw their selected state
            // from these two roles; the pair is held to the text floor.
            expect(
              nexContrastRatio(c.onSecondaryContainer, c.secondaryContainer),
              greaterThanOrEqualTo(4.5),
            );
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
            expect(theme.extension<NexVisualStyle>()!.minimal, isTrue);
            expect(theme.extension<NexVisualStyle>()!.liquidGlass, glass);
          },
        );
      }
    }
  }

  test('previous library renderers and Soft Dark remain available', () {
    expect(nexLightTheme().colorScheme.surface, NexColors.bgPrimaryLight);
    expect(nexNightTheme().colorScheme, nexOledNightTheme().colorScheme);
    expect(nexDarkTheme().scaffoldBackgroundColor, NexColors.bgPrimaryDark);
    expect(
      nexSoftDarkTheme().colorScheme.surface,
      NexSoftDarkColors.background,
    );
    expect(nexSoftDarkTheme().extension<NexVisualStyle>()!.minimal, isTrue);
  });

  // The Soft Dark theme the app ships carries the same edge-set guards the
  // light and night loops above hold (the inverse-capsule action V-03, the
  // filled-button boundary V-07, the badge dot V-08).
  test('Soft Dark: inverse capsule action, button boundary, badge dot', () {
    final theme = nexSoftDarkTheme();
    final c = theme.colorScheme;
    expect(
      nexContrastRatio(
        theme.snackBarTheme.actionTextColor!,
        theme.snackBarTheme.backgroundColor!,
      ),
      greaterThanOrEqualTo(4.5),
    );
    final filled = theme.filledButtonTheme.style!.backgroundColor!;
    expect(
      nexContrastRatio(filled.resolve({})!, c.surfaceContainerLowest),
      greaterThanOrEqualTo(3),
    );
    expect(
      nexContrastRatio(filled.resolve({})!, c.surface),
      greaterThanOrEqualTo(3),
    );
    for (final ground in [
      NexSoftDarkColors.card,
      NexSoftDarkColors.background,
    ]) {
      expect(
        nexContrastRatio(NexColors.dangerDark, ground),
        greaterThanOrEqualTo(3),
        reason:
            'the badge dot is the app\'s whole "something waits here" '
            'vocabulary (V-08)',
      );
    }
    // Night shares the dark step and the same token walk.
    final night = nexOledNightTheme();
    expect(
      nexContrastRatio(
        night.snackBarTheme.actionTextColor!,
        night.snackBarTheme.backgroundColor!,
      ),
      greaterThanOrEqualTo(4.5),
    );
    final nightFill = night.filledButtonTheme.style!.backgroundColor!;
    expect(
      nexContrastRatio(nightFill.resolve({})!, NexOledNightColors.card),
      greaterThanOrEqualTo(3),
    );
    expect(
      nexContrastRatio(NexColors.dangerDark, NexOledNightColors.card),
      greaterThanOrEqualTo(3),
    );
  });

  // The Persian ramp runs body leading at ≈1.6 — the shipped Vazirmatn's ink
  // exceeds a tighter line box at every style (V-05) — and the Latin ramp is
  // unchanged.
  test('Persian body leading breathes; Latin stays on its own ramp', () {
    final latin = nexSoftLightTheme().textTheme;
    final persian = nexSoftLightTheme(fontFamily: nexPersianFont).textTheme;
    expect(latin.bodyLarge!.height, closeTo(22 / 15, 0.01));
    expect(latin.bodyMedium!.height, closeTo(20 / 14, 0.01));
    expect(persian.bodyLarge!.height, closeTo(24 / 15, 0.01));
    expect(persian.bodyMedium!.height, closeTo(22 / 14, 0.01));
    // The standard card's two preview rows already reserve exactly this.
    expect(_previewHeight(persian.bodyLarge!), lessThanOrEqualTo(24.0));
  });
}

double _previewHeight(TextStyle body) => body.fontSize! * body.height!;
