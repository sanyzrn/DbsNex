import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/maintenance/car_logic.dart';
import 'package:nex_client/modules/maintenance/asset_page.dart';
import 'package:nex_client/modules/maintenance/maintenance_screen.dart';
import 'package:nex_client/modules/maintenance/units.dart';

import '../../support/nex_harness.dart';

/// The car as the home screen sees it, after this pass: its own insurance
/// and inspection dates decide the card's group and subtitle (a car with
/// no interval rule no longer sits under "No schedule" while its
/// insurance runs out), the archived group's heading says what archiving
/// does, and a renewal is one tap on the asset page.
void main() {
  test('renewal uses the selected calendar and clamps leap days', () {
    expect(
      CarLogic.renewalDate(nexGregorianDate(1399, 12, 30), solar: true),
      nexGregorianDate(1400, 12, 29),
    );
    expect(
      CarLogic.renewalDate(DateTime(2024, 2, 29), solar: false),
      DateTime(2025, 2, 28),
    );
  });

  late NexTestHarness h;
  late NexModuleStore store;

  setUp(() async {
    h = await NexTestHarness.create(name: 'car_home_');
    store = NexModuleStore(h.services, 'maintenance');
  });
  tearDown(() => h.dispose());

  Future<void> pumpHome(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
  }) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MaintenanceScreen(store: store),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpAsset(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AssetPage(store: store, assetId: 'a1'),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a car with no rules still lands where its dates put it', (
    tester,
  ) async {
    final now = DateTime.now();
    await store.put('asset', 'a1', {
      'nickname': 'Pride',
      'type': 'car',
      'meterKind': 'none',
      'insuranceExpiresAt': now.add(const Duration(days: 3)).toIso8601String(),
      'schema': 2,
    });
    await pumpHome(tester);
    // Not "No schedule": the insurance is three days out, so the car is
    // coming up, and the card says which date and when.
    expect(find.text('Coming up · 1'), findsOneWidget);
    expect(
      find.textContaining('Third-party insurance · in 3 days'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('an expired insurance is due now, ahead of any rule', (
    tester,
  ) async {
    final now = DateTime.now();
    await store.put('asset', 'a1', {
      'nickname': 'Pride',
      'type': 'car',
      'meterKind': 'none',
      'insuranceExpiresAt': now
          .subtract(const Duration(days: 2))
          .toIso8601String(),
      'schema': 2,
    });
    await pumpHome(tester);
    expect(find.text('Due now · 1'), findsOneWidget);
    expect(find.text('Nothing due'), findsNothing);
    expect(
      find.textContaining('Third-party insurance · 2 days past'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the archived group heading says what archiving does', (
    tester,
  ) async {
    await store.put('asset', 'a1', {
      'nickname': 'Pride',
      'type': 'car',
      'meterKind': 'none',
      'archived': true,
      'schema': 2,
    });
    await pumpHome(tester);
    expect(find.text('Archived · 1'), findsOneWidget);
    expect(find.textContaining('kept with all its history'), findsOneWidget);
    // A bai-gani heading never offered the word "Unarchive" as its note.
    expect(find.text('Unarchive'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'renewal adds a year to the typed date, and the stored date follows',
    (tester) async {
      await store.put('asset', 'a1', {
        'nickname': 'Pride',
        'type': 'car',
        'meterKind': 'none',
        'insuranceExpiresAt': DateTime(2027, 3, 20).toIso8601String(),
        'schema': 2,
      });
      await pumpAsset(tester);
      final button = find.byKey(
        const ValueKey('maintenance-car-renew-insurance'),
      );
      await Scrollable.ensureVisible(tester.element(button), alignment: 0.4);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      final saved = (await store.get('asset', 'a1'))!;
      expect(
        saved['insuranceExpiresAt'],
        addMonths(DateTime(2027, 3, 20), 12).toIso8601String(),
      );
      // The countdown follows the new date.
      final now = DateTime.now();
      final days = daysBetween(
        DateTime(now.year, now.month, now.day),
        DateTime(2028, 3, 20),
      );
      expect(find.textContaining('in $days days'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
}
