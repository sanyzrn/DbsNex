import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ui/nex_ui.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/screens/settings_sheet.dart';
import 'package:nex_client/screens/widget_settings_screen.dart';
import 'support/nex_harness.dart';

void main() {
  for (final dark in [false, true]) {
    for (final highContrast in [false, true]) {
      testWidgets('settings panel glass, dark=$dark contrast=$highContrast', (
        tester,
      ) async {
        final h = await NexTestHarness.create();
        addTearDown(h.dispose);
        tester.view.physicalSize = const Size(400, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        Future<void> show(Widget page) async {
          await tester.pumpWidget(
            MaterialApp(
              theme: dark
                  ? nexDarkTheme(liquidGlass: true)
                  : nexLightTheme(liquidGlass: true),
              locale: Locale(dark ? 'fa' : 'en'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(highContrast: highContrast, disableAnimations: true),
                child: child!,
              ),
              home: page,
            ),
          );
          await tester.pumpAndSettle();
        }

        await show(
          SettingsSheet(services: h.services, preferences: h.preferences),
        );
        final search = find.byKey(const ValueKey('settings-search-surface'));
        expect(tester.widget(search), isA<NexSurface>());
        expect(
          find.descendant(of: search, matching: find.byType(BackdropFilter)),
          findsNothing,
        );
        final input = find.descendant(
          of: search,
          matching: find.byType(TextField),
        );
        expect(tester.widget<TextField>(input).decoration!.filled, isFalse);
        final profile = find.byKey(const ValueKey('settings-profile-surface'));
        expect(tester.widget(profile), isA<NexSurface>());
        expect(
          find.descendant(of: profile, matching: find.byType(BackdropFilter)),
          findsNothing,
        );
        await show(
          WidgetSettingsScreen(
            services: h.services,
            preferences: h.preferences,
          ),
        );
        expect(find.byType(NexSurface), findsNWidgets(3));
        for (final surface in find.byType(NexSurface).evaluate()) {
          expect(
            find.descendant(
              of: find.byWidget(surface.widget),
              matching: find.byType(BackdropFilter),
            ),
            findsNothing,
          );
        }
        // Filtering remains interactive after the material change.
        final l10n = lookupAppLocalizations(Locale(dark ? 'fa' : 'en'));
        await tester.tap(
          find.widgetWithText(FilterChip, l10n.noteType('text')),
        );
        await tester.pumpAndSettle();
        expect(h.preferences.widgetTypes, contains('text'));
        expect(tester.takeException(), isNull);
      });
    }
  }
}
