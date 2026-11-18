import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/medicine/medicine_detail.dart';
import 'package:nex_client/modules/medicine/medicine_editor.dart';
import 'package:nex_client/modules/medicine/medicine_logic.dart';
import 'package:nex_client/modules/medicine/medicine_models.dart';
import 'package:nex_client/modules/medicine/medicine_money.dart';
import 'package:nex_client/modules/medicine/medicine_schedule.dart';

import 'medicine_upgrade_support.dart';

/// The upgrade's data: a record written before it, the routine's days and
/// dates, the stock forecast and the toman prices. Every entry is a neutral
/// placeholder; nothing here is medical advice.
void main() {
  group('a record written before the upgrade', () {
    final legacy = <String, Object?>{
      'v': 1,
      'name': 'Medicine A',
      'strength': '10 mg',
      'package': 'box',
      'instructions': 'One in the morning',
      'times': ['08:00'],
      'days': 'every day',
      'purpose': 'a private note',
      'quantity': 30,
      'doseUnits': 1,
      'expiresAt': '2027-01-01T00:00:00.000',
      'refillThreshold': 5,
      'archived': false,
      'futureField': {'keep': true},
    };

    testWidgets('opens with every field it had, unchanged', (tester) async {
      final h = await upgradeHarness();
      final store = NexModuleStore(h.services, 'medicine');
      await store.put('medicine', 'm1', legacy);
      await pumpMedicine(
        tester,
        Scaffold(
          body: MedicineDetailSheet(
            store: store,
            record: medicineRecord('m1', legacy),
          ),
        ),
      );
      expect(find.text('Medicine A'), findsOneWidget);
      expect(find.textContaining('30 box'), findsOneWidget);
      expect(find.text('One in the morning'), findsOneWidget);
      expect(find.text('a private note'), findsOneWidget);
      expect(find.textContaining('every day'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an edit keeps every field it did not touch', (tester) async {
      final h = await upgradeHarness();
      final store = NexModuleStore(h.services, 'medicine');
      await store.put('medicine', 'm1', legacy);
      await pumpMedicine(
        tester,
        Scaffold(
          body: MedicineEditorSheet(
            store: store,
            existing: medicineRecord('m1', legacy),
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('medicine-field-name')),
        'Medicine B',
      );
      await tester.tap(find.byKey(const ValueKey('medicine-save')));
      await tester.pumpAndSettle();

      final saved = (await store.get('medicine', 'm1'))!;
      expect(saved['name'], 'Medicine B');
      expect(saved['strength'], '10 mg');
      expect(saved['package'], 'box');
      expect(saved['instructions'], 'One in the morning');
      expect(MedicineModels.readTimes(saved), ['08:00']);
      expect(saved['days'], 'every day');
      expect(saved['purpose'], 'a private note');
      expect(saved['quantity'], 30);
      expect(saved['doseUnits'], 1);
      expect(saved['refillThreshold'], 5);
      expect(saved['futureField'], {'keep': true});
      expect(
        MedicineModels.readDate(saved, 'expiresAt'),
        DateTime.utc(2027, 1, 1),
      );
      // The new fields read as their honest defaults, not as invented data.
      expect(MedicineModels.readPerson(saved), '');
      expect(MedicineModels.readWeekdays(saved), isEmpty);
      expect(MedicineModels.readEveryDays(saved), isNull);
      expect(MedicineModels.readWarnDays(saved), 10);
      expect(tester.takeException(), isNull);
    });
  });

  group('the routine', () {
    final day = DateTime(2026, 11, 16); // a Monday

    test('written days pick the days; every day when none are', () {
      const everyDay = MedicineSchedule(times: ['08:00']);
      expect(everyDay.runsOn(day), isTrue);
      expect(everyDay.runsOn(DateTime(2026, 11, 21)), isTrue);

      const mondays = MedicineSchedule(times: ['08:00'], weekdays: [1]);
      expect(mondays.runsOn(day), isTrue);
      expect(mondays.runsOn(DateTime(2026, 11, 17)), isFalse);
    });

    test('every N days counts from the day it started', () {
      final schedule = MedicineSchedule(
        times: const ['08:00'],
        everyDays: 3,
        anchor: DateTime.utc(2026, 11, 16),
      );
      expect(schedule.runsOn(day), isTrue);
      expect(schedule.runsOn(DateTime(2026, 11, 17)), isFalse);
      expect(schedule.runsOn(DateTime(2026, 11, 19)), isTrue);
    });

    test('start and end dates bound the days it names', () {
      final schedule = MedicineSchedule(
        times: const ['08:00'],
        startsOn: DateTime.utc(2026, 11, 16),
        endsOn: DateTime.utc(2026, 11, 17),
      );
      expect(schedule.runsOn(DateTime(2026, 11, 15)), isFalse);
      expect(schedule.runsOn(day), isTrue);
      expect(schedule.runsOn(DateTime(2026, 11, 18)), isFalse);
    });

    test('moments come in order, only ahead, and respect the limit', () {
      final schedule = MedicineSchedule(times: const ['20:00', '08:00']);
      final moments = schedule.occurrences(
        from: DateTime(2026, 11, 16, 9),
        until: DateTime(2026, 11, 17, 23),
      );
      expect(moments, [
        DateTime(2026, 11, 16, 20),
        DateTime(2026, 11, 17, 8),
        DateTime(2026, 11, 17, 20),
      ]);
      expect(
        schedule
            .occurrences(
              from: DateTime(2026, 11, 16, 9),
              until: DateTime(2026, 11, 18),
              limit: 2,
            )
            .length,
        2,
      );
    });
  });

  group('how long the stock lasts', () {
    const everyDay = MedicineSchedule(times: ['08:00', '20:00']);

    test('quantity ÷ units a day, from the person’s own numbers', () {
      expect(
        MedicineLogic.runsOutInDays(
          quantity: 30,
          doseUnits: 1,
          schedule: everyDay,
        ),
        15,
      );
      expect(
        MedicineLogic.runsOutInDays(
          quantity: 30,
          doseUnits: 2,
          schedule: everyDay,
        ),
        7,
      );
    });

    test('a weekly routine divides the week it covers', () {
      const threeOfSeven = MedicineSchedule(
        times: ['08:00'],
        weekdays: [1, 3, 5],
      );
      expect(
        MedicineLogic.runsOutInDays(
          quantity: 21,
          doseUnits: 1,
          schedule: threeOfSeven,
        ),
        49,
      );
    });

    test('nothing is estimated without both numbers and a time', () {
      expect(
        MedicineLogic.runsOutInDays(
          quantity: 30,
          doseUnits: null,
          schedule: everyDay,
        ),
        isNull,
      );
      expect(
        MedicineLogic.runsOutInDays(
          quantity: null,
          doseUnits: 1,
          schedule: everyDay,
        ),
        isNull,
      );
      expect(
        MedicineLogic.runsOutInDays(
          quantity: 30,
          doseUnits: 1,
          schedule: const MedicineSchedule(times: []),
        ),
        isNull,
      );
    });

    test('the warning is the person’s own number of days', () {
      expect(MedicineLogic.runoutWarning(10, 10), isTrue);
      expect(MedicineLogic.runoutWarning(11, 10), isFalse);
      expect(MedicineLogic.runoutWarning(null, 10), isFalse);
      expect(MedicineModels.readWarnDays(const {}), 10);
      expect(MedicineModels.readWarnDays({'warnDays': 3}), 3);
    });
  });

  group('prices in tomans', () {
    test('typed tomans are stored as whole rials', () {
      expect(MedicineMoney.parse('12,500'), 125000);
      expect(MedicineMoney.parse('۱۲٬۵۰۰'), 125000);
      expect(MedicineMoney.parse('12.5'), 125);
    });

    test('anything that is not a price is refused', () {
      expect(MedicineMoney.parse(''), isNull);
      expect(MedicineMoney.parse('-20'), isNull);
      expect(MedicineMoney.parse('12.55'), isNull);
      expect(MedicineMoney.parse('a lot'), isNull);
      expect(MedicineMoney.parse('9007199254740992'), isNull);
    });
  });
}
