import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/theme_presets.dart';
import 'package:nex_client/screens/profile_screen.dart';
import 'package:nex_client/screens/profile/profile_header.dart';
import 'package:nex_ui/nex_ui.dart';

import 'support/nex_harness.dart';

void main() {
  test('glass preserves reading surfaces and palette contrast', () {
    double contrast(Color a, Color b) {
      double luminance(Color c) {
        double linear(double v) => v <= 0.04045
            ? v / 12.92
            : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
        return 0.2126 * linear(c.r) +
            0.7152 * linear(c.g) +
            0.0722 * linear(c.b);
      }

      final x = luminance(a), y = luminance(b);
      return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
    }

    for (final preset in nexThemePresets) {
      for (final dark in [false, true]) {
        final theme = nexApplyThemePreset(
          dark
              ? nexDarkTheme(liquidGlass: true)
              : nexLightTheme(liquidGlass: true),
          preset.id,
          null,
        );
        expect(theme.colorScheme.surface.a, 1);
        expect(theme.colorScheme.surfaceContainerLowest.a, 1);
        final wash = theme.extension<NexVisualStyle>()!.glassWash;
        for (final background in [
          Colors.white,
          Colors.black,
          Colors.red,
          Colors.blue,
          Colors.green,
        ]) {
          var surface = background;
          for (final film in [...wash.films, wash.lift, wash.anchor]) {
            surface = Color.alphaBlend(film, surface);
          }
          expect(
            contrast(theme.colorScheme.onSurface, surface),
            greaterThanOrEqualTo(4.5),
            reason: '${preset.id}, dark=$dark, background=$background',
          );
        }
      }
    }
  });

  test(
    'retired glass preference does not opt into the redesigned material',
    () async {
      final h = await NexTestHarness.create(
        preferences: {'appearance.liquid_glass': true},
      );
      addTearDown(h.dispose);
      expect(h.preferences.liquidGlass, isFalse);
      await h.preferences.setLiquidGlass(true);
      expect(h.preferences.liquidGlass, isTrue);
      await h.preferences.setLiquidGlass(false);
      expect(h.preferences.liquidGlass, isFalse);
    },
  );

  for (final preset in nexThemePresets) {
    for (final dark in [false, true]) {
      testWidgets('${preset.id} dark=$dark: birthday uses the correct ink', (
        tester,
      ) async {
        final h = await NexTestHarness.create();
        addTearDown(h.dispose);
        await h.preferences.setThemePreset(preset.id);
        await h.preferences.setProfileBirthday(DateTime(2000, 3, 10));
        final theme = nexApplyThemePreset(
          dark ? nexDarkTheme() : nexLightTheme(),
          preset.id,
          null,
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ProfileScreen(
              services: h.services,
              preferences: h.preferences,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final header = tester.widget<ProfileHeader>(find.byType(ProfileHeader));
        final countdown = tester.widget<Text>(find.text(header.birthdayLine!));
        final ink = const {'classic', 'graphite'}.contains(preset.id)
            ? theme.colorScheme.onSurface
            : theme.colorScheme.onPrimaryContainer;
        expect(countdown.style!.color, ink);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
