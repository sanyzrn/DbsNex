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
      BorderSide.none,
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
      BorderSide.none,
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
}
