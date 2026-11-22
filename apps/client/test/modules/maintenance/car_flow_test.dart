import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/maintenance/asset_page.dart';
import 'package:nex_client/modules/maintenance/car_logic.dart';
import 'package:nex_client/modules/maintenance/models.dart';
import 'package:nex_client/modules/maintenance/service_history.dart';

import '../../support/nex_harness.dart';

/// The car's first-class case: insurance and inspection dates with their
/// lead-time reminders, the fuel log against the person's own rates and
/// quotas, and the service record that carries both.
void main() {
  group('reading a car', () {
    test('car dates and lead times survive a round trip, defaulting to 14', () {
      final body = MaintenanceAsset(
        id: 'a1',
        nickname: 'Pride',
        type: 'car',
        insuranceExpiresAt: DateTime(2027, 3, 20),
        inspectionExpiresAt: DateTime(2027, 1, 5),
      ).toBody();
      expect(body['insuranceLeadDays'], 14);
      final read = MaintenanceAsset.fromBody('a1', body);
      expect(read.valid, isTrue);
      expect(read.insuranceExpiresAt, DateTime(2027, 3, 20));
      expect(read.inspectionExpiresAt, DateTime(2027, 1, 5));
      expect(read.insuranceLeadDays, 14);
    });

    test('an impossible car date is incomplete, not silently dropped', () {
      final read = MaintenanceAsset.fromBody('a1', {
        'nickname': 'Pride',
        'type': 'car',
        'insuranceExpiresAt': '2027-02-30',
      });
      expect(read.valid, isFalse);
      expect(read.insuranceExpiresAt, isNull);
    });

    test('a non-car asset ignores the car fields', () {
      final body = MaintenanceAsset(
        id: 'b1',
        nickname: 'Boiler',
        type: 'boiler',
        insuranceExpiresAt: DateTime(2027, 3, 20),
      ).toBody();
      expect(body.containsKey('insuranceExpiresAt'), isFalse);
    });
  });

  group('fuel records', () {
    test('a fill-up keeps litres, rials and the rate it was bought at', () {
      final entry = FuelEntry(
        id: 'f1',
        assetId: 'a1',
        date: DateTime(2026, 11, 17),
        litres: 42350,
        priceRial: 1250000,
        rate: 'Quota',
      );
      final read = FuelEntry.fromBody('f1', entry.toBody())!;
      expect(read.litres, 42350);
      expect(read.priceRial, 1250000);
      expect(read.rate, 'Quota');
    });

    test('a malformed fill-up is refused rather than counted', () {
      expect(
        FuelEntry.fromBody('f1', {
          'assetId': 'a1',
          'date': '2026-11-17',
          'litres': 0,
          'priceRial': 1,
          'rate': 'Quota',
        }),
        isNull,
      );
      expect(
        FuelEntry.fromBody('f1', {
          'assetId': 'a1',
          'date': '2026-11-17',
          'litres': 1000,
          'priceRial': -1,
          'rate': 'Quota',
        }),
        isNull,
      );
    });

    test('a rate keeps its own quota', () {
      final rate = FuelRate.fromBody('r1', {
        'assetId': 'a1',
        'name': 'Quota',
        'quota': 60000,
      })!;
      expect(rate.quota, 60000);
      expect(rate.example, isFalse);
    });
  });

  group('car arithmetic', () {
    test('days left is calendar-based and signed', () {
      final now = DateTime(2026, 11, 17, 23);
      expect(CarLogic.daysLeft(DateTime(2026, 11, 20), now), 3);
      expect(CarLogic.daysLeft(DateTime(2026, 11, 10), now), -7);
      expect(CarLogic.daysLeft(null, now), isNull);
    });

    test('a reminder rings a chosen number of days before, never past', () {
      final date = DateTime(2026, 12, 1);
      final now = DateTime(2026, 11, 17);
      expect(CarLogic.reminderAt(date, 14), DateTime(2026, 11, 17, 9));
      expect(CarLogic.reminderFits(date, 20, now), isFalse);
      expect(CarLogic.reminderFits(date, 7, now), isTrue);
    });

    test('the fuel month is the solar month for a solar reader', () {
      final first = DateTime(2026, 11, 17);
      final later = DateTime(2026, 12, 5);
      // Azar and Dey are different Jalali months even though both fall in
      // the same civil November/December window used here.
      expect(
        CarLogic.monthKey(first, solar: true),
        isNot(CarLogic.monthKey(later, solar: true)),
      );
      expect(
        CarLogic.monthKey(DateTime(2026, 11, 2), solar: false),
        CarLogic.monthKey(first, solar: false),
      );
    });

    test('monthly totals separate rates and add the price paid', () {
      final now = DateTime(2026, 11, 17);
      final summary = fuelMonthSummary(
        [
          FuelEntry(
            id: 'f1',
            assetId: 'a1',
            date: DateTime(2026, 11, 2),
            litres: 30000,
            priceRial: 900000,
            rate: 'Quota',
          ),
          FuelEntry(
            id: 'f2',
            assetId: 'a1',
            date: DateTime(2026, 11, 10),
            litres: 10000,
            priceRial: 400000,
            rate: 'Free',
          ),
          FuelEntry(
            id: 'f3',
            assetId: 'a1',
            date: DateTime(2026, 10, 10),
            litres: 50000,
            priceRial: 999999,
            rate: 'Quota',
          ),
        ],
        now,
        solar: false,
      );
      expect(summary.litres, 40000);
      expect(summary.priceRial, 1300000);
      expect(summary.litresByRate['Quota'], 30000);
      final quota = FuelRate(
        id: 'r1',
        assetId: 'a1',
        name: 'Quota',
        quota: 60000,
      );
      expect(summary.leftFor(quota), 30000);
    });

    test('tomans become exact rials or are refused', () {
      expect(rialFromTomanInput('12,500'), 125000);
      expect(rialFromTomanInput('12,50'), isNull);
      expect(rialFromTomanInput('12500'), 125000);
      expect(rialFromTomanInput('12500.5'), 125005);
      expect(rialFromTomanInput('12500.55'), isNull);
      expect(formatToman(125005, persian: false), '12,500.5');
      expect(formatToman(125000, persian: true), '۱۲٬۵۰۰');
    });
  });

  group('the car page', () {
    late NexTestHarness h;
    late NexModuleStore store;

    setUp(() async {
      h = await NexTestHarness.create(name: 'maintenance_car_');
      store = NexModuleStore(h.services, 'maintenance');
    });
    tearDown(() => h.dispose());

    Future<void> pumpAsset(WidgetTester tester) async {
      // A tall surface, so the car and fuel panels are built without the
      // test having to drag the page first.
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

    Future<void> seedCar() => store.put('asset', 'a1', {
      'nickname': 'Pride',
      'type': 'car',
      'meterKind': 'distance',
      'distanceUnit': 'km',
      'insuranceExpiresAt': DateTime.now()
          .add(const Duration(days: 40))
          .toIso8601String(),
      'inspectionExpiresAt': DateTime.now()
          .add(const Duration(days: 5))
          .toIso8601String(),
      'schema': 2,
    });

    testWidgets('insurance and inspection show their own countdown', (
      tester,
    ) async {
      await seedCar();
      await pumpAsset(tester);
      expect(
        find.byKey(const ValueKey('maintenance-car-panel')),
        findsOneWidget,
      );
      expect(find.text('Third-party insurance'), findsOneWidget);
      expect(find.text('Technical inspection'), findsOneWidget);
      expect(find.textContaining('in 40 days'), findsOneWidget);
      expect(find.textContaining('in 5 days'), findsOneWidget);
      expect(find.textContaining('Remind me 14 days before'), findsWidgets);
    });

    testWidgets('a new lead time is saved on the car', (tester) async {
      await seedCar();
      await pumpAsset(tester);
      final button = find.byKey(
        const ValueKey('maintenance-car-remind-insurance'),
      );
      await Scrollable.ensureVisible(tester.element(button), alignment: 0.4);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('maintenance-car-lead-days')),
        '20',
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('maintenance-car-reminder-save')),
      );
      await tester.pumpAndSettle();

      final saved = (await store.get('asset', 'a1'))!;
      expect(saved['insuranceLeadDays'], 20);
      // A test build has no notification permission, so the platform
      // refuses to schedule; the sheet says so instead of pretending, and
      // the reminder is not left marked as on.
      expect(find.textContaining('The reminder was not set'), findsOneWidget);
      expect(saved.containsKey('insuranceRemind'), isFalse);
    });

    testWidgets('a fill-up adds to this month at the chosen rate', (
      tester,
    ) async {
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
      await pumpAsset(tester);

      expect(find.textContaining('0 of 60 L'), findsOneWidget);
      final add = find.byKey(const ValueKey('maintenance-fuel-add'));
      await Scrollable.ensureVisible(tester.element(add), alignment: 0.4);
      await tester.pumpAndSettle();
      await tester.tap(add);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('maintenance-fuel-litres')),
        '42.5',
      );
      final price = find.byKey(const ValueKey('maintenance-fuel-price'));
      await tester.enterText(price, '12500');
      expect(tester.widget<TextField>(price).controller!.text, '12,500');
      await tester.tap(
        find.byKey(const ValueKey('maintenance-fuel-rate-Quota')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('maintenance-fuel-save')));
      await tester.pumpAndSettle();

      final fuel = await store.list('fuel');
      expect(fuel, hasLength(1));
      expect(fuel.single.body['litres'], 42500);
      expect(fuel.single.body['priceRial'], 125000);
      expect(fuel.single.body['rate'], 'Quota');
      expect(find.textContaining('42.5 L'), findsWidgets);
    });

    testWidgets('example rates are marked until the person checks them', (
      tester,
    ) async {
      await seedCar();
      await pumpAsset(tester);
      final rates = find.byKey(const ValueKey('maintenance-fuel-rates'));
      await Scrollable.ensureVisible(tester.element(rates), alignment: 0.4);
      await tester.pumpAndSettle();
      await tester.tap(rates);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('maintenance-rate-examples')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Example — check'), findsWidgets);
    });

    testWidgets('the service record carries insurance, inspection and fuel', (
      tester,
    ) async {
      await seedCar();
      await store.put('fuel_rate', 'r1', {
        'assetId': 'a1',
        'name': 'Quota',
        'quota': 60000,
      });
      await store.put('fuel', 'f1', {
        'assetId': 'a1',
        'date': DateTime.now().toIso8601String(),
        'litres': 30000,
        'priceRial': 900000,
        'rate': 'Quota',
      });
      await pumpAsset(tester);
      final context = tester.element(find.byType(AssetPage));
      final asset = MaintenanceAsset.fromBody(
        'a1',
        (await store.get('asset', 'a1'))!,
      );
      final text = serviceHistoryText(
        context,
        asset,
        const [],
        fuel: (await store.list('fuel'))
            .map((r) => FuelEntry.fromBody(r.id, r.body)!),
        rates: (await store.list('fuel_rate'))
            .map((r) => FuelRate.fromBody(r.id, r.body)!),
      );
      expect(text, contains('Insurance:'));
      expect(text, contains('Inspection:'));
      expect(text, contains('Fuel this month'));
      expect(text, contains('30 L'));
      expect(text, contains('90,000 tomans'));
    });
  });
}
