import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/theme_presets.dart';
import 'package:nex_client/screens/settings_sheet.dart';
import 'package:nex_ui/nex_ui.dart';
import 'support/nex_harness.dart';

void main() {
  for (final locale in ['en', 'fa']) {
    for (final reduced in [false, true]) {
      testWidgets(
        '$locale reduced=$reduced: Appearance keeps themes on their own page',
        (tester) async {
          final h = await NexTestHarness.create();
          addTearDown(h.dispose);
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final l10n = lookupAppLocalizations(Locale(locale));
          await tester.pumpWidget(
            MaterialApp(
              locale: Locale(locale),
              theme: locale == 'fa' ? nexDarkTheme() : nexLightTheme(),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  disableAnimations: reduced,
                  textScaler: const TextScaler.linear(1.6),
                ),
                child: child!,
              ),
              home: SettingsSheet(
                services: h.services,
                preferences: h.preferences,
              ),
            ),
          );
          await tester.tap(find.text(l10n.appearance));
          await tester.pumpAndSettle();
          expect(
            find.descendant(
              of: find.byType(AppBar),
              matching: find.text(l10n.appearance),
            ),
            findsOneWidget,
          );
          expect(find.byKey(const ValueKey('palette-classic')), findsNothing);
          final themes = find.byKey(const ValueKey('appearance-themes'));
          await tester.scrollUntilVisible(
            themes,
            250,
            scrollable: find.byType(Scrollable).last,
          );
          await tester.ensureVisible(themes);
          await tester.pumpAndSettle();
          await tester.tap(themes);
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('palette-classic')), findsOneWidget);
          for (final id in ['bauhaus', 'porcelain', 'circuit', 'afterimage']) {
            final tile = find.byKey(ValueKey('palette-$id'));
            await tester.scrollUntilVisible(
              tile,
              250,
              scrollable: find.byType(Scrollable).last,
            );
            expect(tile, findsOneWidget);
            await tester.tap(tile);
            await tester.pumpAndSettle();
            expect(h.preferences.themePreset, id);
            expect(tester.takeException(), isNull);
          }
          expect(
            nexThemePresets.map((p) => p.id).toSet().length,
            nexThemePresets.length,
          );
          await tester.tap(find.byType(BackButton).first);
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('palette-afterimage')),
            findsNothing,
          );
          expect(h.preferences.themePreset, 'afterimage');
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
