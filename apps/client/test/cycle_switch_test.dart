import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/screens/settings_sheet.dart';
import 'package:nex_client/screens/tools_screen.dart';

import 'support/nex_harness.dart';

/// «Cycle» can be turned off completely, keeping its data or not.
void main() {
  late NexTestHarness harness;

  setUp(() async {
    harness = await NexTestHarness.create(
      name: 'nex_cycle_switch_',
      preferences: {'cycle.set_up': true},
    );
    await harness.services.cycleStartPeriod(DateTime(2026, 10, 1));
  });

  tearDown(() => harness.dispose());

  Widget host(Widget child) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );

  Future<void> turnOff(WidgetTester tester, String choice) async {
    await tester.pumpWidget(
      host(
        SettingsSheet(
          services: harness.services,
          preferences: harness.preferences,
        ),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> scrollTo(Finder target) async {
      await tester.scrollUntilVisible(
        target,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
    }

    await scrollTo(find.text('Sections'));
    await tester.tap(find.text('Sections'));
    await tester.pumpAndSettle();
    await scrollTo(find.text('Show Cycle'));
    await tester.tap(find.text('Show Cycle'));
    await tester.pumpAndSettle();
    expect(find.text('Turn off Cycle?'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('cycle-off-$choice')));
    await tester.pumpAndSettle();
  }

  testWidgets('on by default, with its tile in Tools', (tester) async {
    expect(harness.preferences.cycleEnabled, isTrue);
    await tester.pumpWidget(
      host(
        ToolsScreen(
          services: harness.services,
          preferences: harness.preferences,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Cycle'), findsOneWidget);
  });

  testWidgets('off, keeping the data: the tile goes, the data stays', (
    tester,
  ) async {
    await turnOff(tester, 'keep');
    expect(harness.preferences.cycleEnabled, isFalse);
    expect(await harness.services.cyclePeriods(), hasLength(1));
    expect(harness.preferences.cycleSetUp, isTrue);

    await tester.pumpWidget(
      host(
        ToolsScreen(
          services: harness.services,
          preferences: harness.preferences,
        ),
      ),
    );
    await tester.pumpAndSettle();
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
}
