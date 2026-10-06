import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/screens/cycle_screen.dart';
import 'package:nex_client/screens/profile_screen.dart';
import 'package:nex_client/screens/settings_sheet.dart';
import 'package:nex_client/screens/tools_screen.dart';

import 'support/nex_harness.dart';

/// «Cycle» is switched on and off in the profile: off by default, and off
/// completely, keeping its data or not.
void main() {
  Widget host(Widget child) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );

  Future<void> showTools(WidgetTester tester, NexTestHarness harness) async {
    await tester.pumpWidget(
      host(
        ToolsScreen(
          services: harness.services,
          preferences: harness.preferences,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> showProfile(WidgetTester tester, NexTestHarness harness) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      host(
        ProfileScreen(
          services: harness.services,
          preferences: harness.preferences,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('profile-cycle-switch')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  group('a new install', () {
    late NexTestHarness harness;

    setUp(() async {
      harness = await NexTestHarness.create(name: 'nex_cycle_switch_new_');
    });

    tearDown(() => harness.dispose());

    testWidgets('is off by default, with no tile in Tools', (tester) async {
      expect(harness.preferences.cycleEnabled, isFalse);
      await showTools(tester, harness);
      expect(find.text('Cycle'), findsNothing);
    });

    testWidgets('turns it on in the profile, and opens it from there', (
      tester,
    ) async {
      await showProfile(tester, harness);
      expect(find.textContaining('Everything stays on this phone'), findsOne);
      expect(find.byKey(const ValueKey('profile-cycle-open')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('profile-cycle-switch')));
      await tester.pumpAndSettle();
      expect(harness.preferences.cycleEnabled, isTrue);

      await tester.ensureVisible(
        find.byKey(const ValueKey('profile-cycle-open')),
      );
      await tester.tap(find.byKey(const ValueKey('profile-cycle-open')));
      await tester.pumpAndSettle();
      expect(find.byType(CycleScreen), findsOneWidget);
    });

    testWidgets('Settings search for it points to the profile', (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        host(
          SettingsSheet(
            services: harness.services,
            preferences: harness.preferences,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Show Cycle'), findsNothing);
      await tester.enterText(find.byType(TextField).first, 'cycle');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('settings-search-cycle')));
      await tester.pumpAndSettle();
      expect(find.byType(ProfileScreen), findsOneWidget);
    });
  });

  group('someone already using it', () {
    late NexTestHarness harness;

    setUp(() async {
      harness = await NexTestHarness.create(
        name: 'nex_cycle_switch_',
        preferences: {'cycle.set_up': true},
      );
      await harness.services.cycleStartPeriod(DateTime(2026, 10, 1));
    });

    tearDown(() => harness.dispose());

    Future<void> turnOff(WidgetTester tester, String choice) async {
      await showProfile(tester, harness);
      await tester.tap(find.byKey(const ValueKey('profile-cycle-switch')));
      await tester.pumpAndSettle();
      expect(find.text('Turn off Cycle?'), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('cycle-off-$choice')));
      await tester.pumpAndSettle();
    }

    testWidgets('keeps it on after the update, with its tile in Tools', (
      tester,
    ) async {
      expect(harness.preferences.cycleEnabled, isTrue);
      await showTools(tester, harness);
      expect(find.text('Cycle'), findsOneWidget);
    });

    testWidgets('off, keeping the data: the tile goes, the data stays', (
      tester,
    ) async {
      await turnOff(tester, 'keep');
      expect(harness.preferences.cycleEnabled, isFalse);
      expect(await harness.services.cyclePeriods(), hasLength(1));
      expect(harness.preferences.cycleSetUp, isTrue);

      await showTools(tester, harness);
      expect(find.text('Cycle'), findsNothing);

      // Back on: everything is where it was.
      await harness.preferences.setCycleEnabled(true);
      expect(await harness.services.cyclePeriods(), hasLength(1));
    });

    testWidgets('off, deleting the data: nothing is left', (tester) async {
      await turnOff(tester, 'delete');
      expect(harness.preferences.cycleEnabled, isFalse);
      expect(await harness.services.cyclePeriods(), isEmpty);
      expect(harness.preferences.cycleSetUp, isFalse);
    });
  });
}
