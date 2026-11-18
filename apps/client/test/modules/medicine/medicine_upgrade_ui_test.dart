import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/medicine/medicine_detail.dart';
import 'package:nex_client/modules/medicine/medicine_expiry_page.dart';
import 'package:nex_client/modules/medicine/medicine_models.dart';
import 'package:nex_client/modules/medicine/medicine_reminders.dart';
import 'package:nex_client/modules/medicine/module.dart';
import 'package:nex_client/modules/medicine/medicine_repository.dart';
import 'package:nex_client/modules/medicine/medicine_today_page.dart';

import 'medicine_upgrade_support.dart';

/// The upgrade's surfaces: boxes, places, the Today page and the reminders
/// planned from a routine. Synthetic, neutral placeholders throughout.
void main() {
  group('boxes, places and today', () {
    testWidgets('a box is added, listed and deleted with undo', (tester) async {
      final h = await upgradeHarness();
      final store = NexModuleStore(h.services, 'medicine');
      await store.put('medicine', 'm1', {'v': 3, 'name': 'Medicine A'});
      final undo = await MedicineRepository.addBox(
        store,
        'm1',
        expiresAt: DateTime.now().subtract(const Duration(days: 2)),
      );
      final boxes = await store.list('box');
      expect(boxes, hasLength(1));
      expect(MedicineModels.readDay(boxes.single.body, 'expiresAt'), isNotNull);

      await pumpMedicine(tester, MedicineExpiryPage(store: store));
      expect(find.text('Medicine A'), findsOneWidget);
      expect(find.text('Expired'), findsOneWidget);
      await undo();
      expect(await store.list('box'), isEmpty);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('a place keeps where, how much and when', (tester) async {
      final h = await upgradeHarness();
      final store = NexModuleStore(h.services, 'medicine');
      await store.put('medicine', 'm1', {'v': 3, 'name': 'Medicine A'});
      await pumpMedicine(
        tester,
        Scaffold(
          body: MedicineDetailSheet(
            store: store,
            record: medicineRecord('m1', {'v': 3, 'name': 'Medicine A'}),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('medicine-add-place')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('medicine-place-name')),
        'Corner pharmacy',
      );
      await tester.enterText(
        find.byKey(const ValueKey('medicine-place-price')),
        '12,500',
      );
      await tester.tap(find.byKey(const ValueKey('medicine-place-save')));
      await tester.pumpAndSettle();

      final saved = (await store.list('source')).single;
      expect(saved.body['place'], 'Corner pharmacy');
      expect(saved.body['priceRial'], 125000);
      expect(MedicineModels.readDay(saved.body, 'at'), isNotNull);
      expect(find.text('Corner pharmacy'), findsOneWidget);
      expect(find.textContaining('12,500 tomans'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Today logs one routine moment a tap', (tester) async {
      final h = await upgradeHarness();
      final store = NexModuleStore(h.services, 'medicine');
      await store.put('medicine', 'm1', {
        'v': 3,
        'name': 'Medicine A',
        'person': 'Sara',
        'quantity': 30,
        'doseUnits': 2,
        'times': ['00:01'],
        'warnDays': 3,
      });
      await pumpMedicine(tester, MedicineTodayPage(store: store));
      expect(find.text('Medicine A'), findsWidgets);
      expect(find.textContaining('Sara'), findsWidgets);

      await tester.tap(
        find.byKey(ValueKey('medicine-today-taken-${_today()}-m1-00:01')),
      );
      await tester.pumpAndSettle();

      final dose = (await store.list('dose')).single;
      expect(dose.body['action'], 'taken');
      expect(dose.body['slot'], '00:01');
      expect(dose.body['takenUnits'], 2);
      expect((await store.get('medicine', 'm1'))!['quantity'], 28);
      expect(find.textContaining('Taken at'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('reminders built from the routine', () {
    Future<BuildContext> pumpHost(WidgetTester tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (inner) {
              context = inner;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      return context;
    }

    String nextHour() {
      final soon = DateTime.now().add(const Duration(hours: 1));
      return '${soon.hour.toString().padLeft(2, '0')}:'
          '${soon.minute.toString().padLeft(2, '0')}';
    }

    testWidgets('name the medicine, the person and the time', (tester) async {
      final h = await upgradeHarness();
      final store = ReminderStore(h.services);
      final context = await pumpHost(tester);
      final time = nextHour();
      await MedicineReminders.sync(context, store, [
        medicineRecord('m1', {
          'v': 3,
          'name': 'Medicine A',
          'person': 'Sara',
          'times': [time],
          'warnDays': 10,
        }),
      ]);

      expect(store.armed, isNotEmpty);
      expect(store.armed.first.title, 'Medicine A');
      expect(store.armed.first.body, contains('Sara'));
      expect(store.armed.first.body, contains(time));
    });

    testWidgets('an every-day routine rings daily, needing no upkeep; '
        'a weekday routine is planned a week ahead (2.8.4)', (tester) async {
      final h = await upgradeHarness();
      final store = ReminderStore(h.services);
      final context = await pumpHost(tester);
      await MedicineReminders.sync(context, store, [
        medicineRecord('daily', {
          'v': 3,
          'name': 'Every day',
          'times': ['08:00', '14:00', '20:00'],
        }),
        medicineRecord('week', {
          'v': 3,
          'name': 'Weekdays',
          'times': ['08:00', '14:00', '20:00'],
          'weekdays': [1, 2, 3, 4, 5, 6, 7],
        }),
      ]);
      expect(store.daily, {
        'med-daily-d0800',
        'med-daily-d1400',
        'med-daily-d2000',
      });
      final weekly = store.armed.where((a) => a.sourceId == 'week').toList();
      // Three a day for a week — not the eight the first version stopped at.
      expect(weekly.length, greaterThanOrEqualTo(21));
      expect(weekly.every((a) => !store.daily.contains(a.key)), isTrue);
    });

    testWidgets('Nex keeps them ahead on start, without the cabinet opened '
        '(2.8.4)', (tester) async {
      final h = await upgradeHarness();
      final store = ReminderStore(h.services);
      await tester.runAsync(
        () => store.put('medicine', 'm1', {
          'v': 3,
          'name': 'Medicine A',
          'times': ['09:00'],
        }),
      );
      await tester.runAsync(
        () => const MedicineModule().keepUp(
          store,
          lookupAppLocalizations(const Locale('en')),
        ),
      );
      expect(store.daily, {'med-m1-d0900'});
    });

    testWidgets('an archived medicine arms nothing', (tester) async {
      final h = await upgradeHarness();
      final store = ReminderStore(h.services);
      final context = await pumpHost(tester);
      await MedicineReminders.sync(context, store, [
        medicineRecord('m1', {
          'name': 'Medicine A',
          'archived': true,
          'times': [nextHour()],
        }),
      ]);
      expect(store.armed, isEmpty);
    });
  });
}

/// The civil day the test's keys use, matching the page's own format.
String _today() {
  final now = DateTime.now();
  return '${now.year}-${now.month}-${now.day}';
}
