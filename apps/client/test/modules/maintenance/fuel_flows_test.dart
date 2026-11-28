import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/maintenance/asset_page.dart';
import 'package:nex_client/modules/maintenance/controller.dart';
import 'package:nex_client/modules/maintenance/fuel_editor.dart';
import 'package:nex_client/modules/maintenance/fuel_rates_sheet.dart';
import 'package:nex_client/modules/maintenance/models.dart';
import 'package:nex_client/modules/maintenance/units.dart';

import '../../support/nex_harness.dart';

/// The fuel-side fixes of this polish pass, end to end over a real store:
/// two rates may not share a name (the quota view is by name), an example
/// rate loses its marker once the person takes the row in hand, rows the
/// person touched ask before the sheet closes, a fill-up cannot be logged
/// in the future, and each fill-up says what one litre cost.
///
/// The widget cases seed the store directly and drive the sheets the way
/// a person does — by taps and pumps — because a controller's journaled
/// writes resolve on the test zone's own clock.
void main() {
  late NexTestHarness h;
  late NexModuleStore store;

  setUp(() async {
    h = await NexTestHarness.create(name: 'fuel_flows_');
    store = NexModuleStore(h.services, 'maintenance');
  });
  tearDown(() => h.dispose());

  /// A car, seeded the way a person's data arrives: a plain record.
  Future<void> seedCar() => store.put('asset', 'a1', {
    'nickname': 'Pride',
    'type': 'car',
    'meterKind': 'distance',
    'distanceUnit': 'km',
    'schema': 2,
  });

  /// The same car as the editors see it.
  final car = MaintenanceAsset(
    id: 'a1',
    nickname: 'Pride',
    type: 'car',
    meterKind: MeterKind.distance,
    distanceUnit: DistanceUnit.km,
  );

  Future<void> host(
    WidgetTester tester,
    Future<void> Function(BuildContext) open,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => open(context),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  test('the controller refuses two rates with one name', () async {
    await seedCar();
    final controller = MaintenanceController(store);
    addTearDown(controller.dispose);
    await controller.saveFuelRates('a1', [
      FuelRate(id: 'r1', assetId: 'a1', name: 'Quota', quota: 60000),
    ]);
    await expectLater(
      controller.saveFuelRates('a1', [
        FuelRate(id: 'r1', assetId: 'a1', name: 'Quota', quota: 60000),
        FuelRate(id: 'r2', assetId: 'a1', name: ' Quota ', quota: 0),
      ]),
      // The check trims: a space does not make two rates distinct.
      throwsStateError,
    );
    // The refused write left the saved rate list exactly as it was.
    expect(await store.list('fuel_rate'), hasLength(1));
  });

  test('rate updates keep unknown fields and protect other cars', () async {
    await seedCar();
    await store.put('fuel_rate', 'r1', {
      'assetId': 'a1',
      'name': 'Example',
      'quota': 60000,
      'example': true,
      'extra': 'keep',
    });
    await store.put('fuel_rate', 'r2', {
      'assetId': 'a2',
      'name': 'Other',
      'quota': 0,
    });
    final controller = MaintenanceController(store);
    addTearDown(controller.dispose);

    await controller.saveFuelRates('a1', [
      const FuelRate(id: 'r1', assetId: 'a1', name: 'My rate', quota: 70000),
    ]);
    final saved = (await store.get('fuel_rate', 'r1'))!;
    expect(saved['extra'], 'keep');
    expect(saved.containsKey('example'), isFalse);

    await expectLater(
      controller.saveFuelRates('a1', [
        const FuelRate(id: 'r2', assetId: 'a1', name: 'Invalid', quota: 0),
      ]),
      throwsStateError,
    );
    expect((await store.get('fuel_rate', 'r2'))?['name'], 'Other');
  });

  test(
    'clearing a fill-up note preserves a newer price and extra data',
    () async {
      await seedCar();
      final controller = MaintenanceController(store);
      addTearDown(controller.dispose);
      final original = FuelEntry(
        id: 'f1',
        assetId: 'a1',
        date: DateTime.now(),
        litres: 42500,
        priceRial: 1275000,
        rate: 'Quota',
        notes: 'Old note',
      );
      await store.put('fuel', original.id, {
        ...original.toBody(),
        'priceRial': 2000000,
        'extra': 'keep',
      });
      await controller.saveFuel(
        FuelEntry(
          id: original.id,
          assetId: original.assetId,
          date: original.date,
          litres: original.litres,
          priceRial: original.priceRial,
          rate: original.rate,
        ),
        existing: original,
        editedKeys: ['notes'],
      );
      final saved = (await store.get('fuel', original.id))!;
      expect(saved.containsKey('notes'), isFalse);
      expect(saved['priceRial'], 2000000);
      expect(saved['extra'], 'keep');
    },
  );

  testWidgets(
    'an edited example rate loses its marker, an untouched one keeps it',
    (tester) async {
      await seedCar();
      final controller = MaintenanceController(store);
      addTearDown(controller.dispose);
      await host(
        tester,
        (context) =>
            showFuelRatesSheet(context, controller: controller, asset: car),
      );
      await tester.tap(find.byKey(const ValueKey('maintenance-rate-examples')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Example — check'), findsNWidgets(2));
      await tester.enterText(
        find.byKey(const ValueKey('maintenance-rate-quota-0')),
        '80',
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Example — check'), findsOneWidget);
      final save = find.byKey(const ValueKey('maintenance-rate-save'));
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();
      final rates = await store.list('fuel_rate');
      expect(rates, hasLength(2));
      final edited = rates.firstWhere((r) => r.body['quota'] == 80000);
      expect(edited.body.containsKey('example'), isFalse);
      final untouched = rates.firstWhere((r) => r.body['quota'] == 0);
      expect(untouched.body['example'], isTrue);
    },
  );

  testWidgets(
    'two rows with one name are refused with words, nothing written',
    (tester) async {
      await seedCar();
      final controller = MaintenanceController(store);
      addTearDown(controller.dispose);
      await host(
        tester,
        (context) =>
            showFuelRatesSheet(context, controller: controller, asset: car),
      );
      await tester.tap(find.byKey(const ValueKey('maintenance-rate-examples')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('maintenance-rate-name-1')),
        'Quota',
      );
      await tester.pumpAndSettle();
      final save = find.byKey(const ValueKey('maintenance-rate-save'));
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.text('Two rates cannot share one name.'), findsOneWidget);
      // The sheet stays open with the rows as typed; nothing was written.
      expect(
        find.byKey(const ValueKey('maintenance-rate-name-0')),
        findsOneWidget,
      );
      expect(await store.list('fuel_rate'), isEmpty);
    },
  );

  testWidgets('rows the person touched ask before the sheet closes', (
    tester,
  ) async {
    await seedCar();
    final controller = MaintenanceController(store);
    addTearDown(controller.dispose);
    await host(
      tester,
      (context) =>
          showFuelRatesSheet(context, controller: controller, asset: car),
    );
    // "Add a rate" with no rows fills the pair of examples — the same hint
    // the empty state offers.
    await tester.tap(find.byKey(const ValueKey('maintenance-rate-add')));
    await tester.pumpAndSettle();
    await tester.state<NavigatorState>(find.byType(Navigator).first).maybePop();
    await tester.pumpAndSettle();
    expect(find.text('Discard this entry?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    // Still open; leaving again and discarding really goes.
    await tester.state<NavigatorState>(find.byType(Navigator).first).maybePop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('maintenance-rate-save')), findsNothing);
    expect(await store.list('fuel_rate'), isEmpty);
  });

  testWidgets('a fill-up cannot be logged in the future', (tester) async {
    await seedCar();
    // A draft written on a phone whose clock was behind holds a day that is
    // still ahead here: the editor restores it, and saving refuses.
    await store.put('draft', 'fuel:a1:new', {
      'v': 1,
      'base': jsonEncode({'parentId': 'a1'}),
      'fields': {
        'litres': '40',
        'price': '1000',
        'notes': '',
        'parentId': 'a1',
        'date': DateTime.now().add(const Duration(days: 3)).toIso8601String(),
        'rate': 'Quota',
        'recordId': 'fuel-x',
      },
    });
    final controller = MaintenanceController(store);
    addTearDown(controller.dispose);
    await host(
      tester,
      (context) => showFuelEditor(context, controller: controller, asset: car),
    );
    await tester.pumpAndSettle();
    final save = find.byKey(const ValueKey('maintenance-fuel-save'));
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('Pick today or an earlier day'), findsOneWidget);
    expect(await store.list('fuel'), isEmpty);
    // The sheet stays open with what was typed.
    expect(
      find.byKey(const ValueKey('maintenance-fuel-litres')),
      findsOneWidget,
    );
  });

  testWidgets(
    'a fill-up says what one litre cost, and a no-quota rate shows its used litres',
    (tester) async {
      final now = DateTime.now();
      await seedCar();
      await store.put('fuel_rate', 'r1', {
        'assetId': 'a1',
        'name': 'Quota',
        'quota': 60000,
      });
      await store.put('fuel_rate', 'r2', {
        'assetId': 'a1',
        'name': 'Free',
        'quota': 0,
      });
      await store.put('fuel', 'f1', {
        'assetId': 'a1',
        'date': now.toIso8601String(),
        'litres': 42500,
        'priceRial': 1275000,
        'rate': 'Quota',
      });
      await store.put('fuel', 'f2', {
        'assetId': 'a1',
        'date': now.toIso8601String(),
        'litres': 40000,
        'priceRial': 4200000,
        'rate': 'Free',
      });
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
      // 1,275,000 rials for 42.5 L is 3,000 tomans a litre, said by the
      // person's own two numbers.
      expect(find.text('3,000 tomans per litre'), findsOneWidget);
      expect(find.text('42.5 Litres · Quota'), findsOneWidget);
      // A rate with no quota shows what was bought at it, not a division by
      // zero.
      expect(find.text('40 L · no quota'), findsOneWidget);
      // The quota rate carries the same calm bar a rule does.
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
