part of 'logic_test.dart';

void _logicCases2() {
  group('derived fields recompute from the records', () {
    test('editing or deleting the last event moves the due date', () {
      // Two events; the newest is the anchor.
      final withTwo = ruleStandings(
        asset(),
        [event('e1', DateTime(2026, 4, 1)), event('e2', DateTime(2026, 9, 1))],
        [rule(months: 1)],
        now,
      );
      expect(withTwo.single.timeDue, DateTime(2026, 10, 1));

      // e2 deleted: the anchor is e1 again.
      final withOne = ruleStandings(
        asset(),
        [event('e1', DateTime(2026, 4, 1))],
        [rule(months: 1)],
        now,
      );
      expect(withOne.single.timeDue, DateTime(2026, 5, 1));
    });

    test('the task match is by label, case-insensitive', () {
      final standings = ruleStandings(
        asset(),
        [event('e1', DateTime(2026, 10, 1), task: 'Oil Change')],
        [rule(task: 'oil change', months: 6)],
        now,
      );
      expect(standings.single.lastDone?.id, 'e1');
    });
  });

  group('costs and corrections', () {
    test('cost totals are per currency, manual only', () {
      final totals = assetCostTotals([
        event('e1', DateTime(2026, 1, 1), cost: 100000, currency: 'IRR'),
        event('e2', DateTime(2026, 2, 1), cost: 250000, currency: 'IRR'),
        event('e3', DateTime(2026, 3, 1), cost: 999, currency: 'USD'),
        event('e4', DateTime(2026, 4, 1)), // no cost: nothing
      ]);
      expect(totals['IRR'], BigInt.from(350000));
      expect(totals['USD'], BigInt.from(999));
      expect(totals, hasLength(2));
      expect(assetCostTotals([]), isEmpty);
    });

    test('a lower reading than the latest is flagged as a correction', () {
      final events = [
        event(
          'e1',
          DateTime(2026, 1, 1),
          meter: 50000,
          meterUnit: DistanceUnit.km,
        ),
        event(
          'e2',
          DateTime(2026, 6, 1),
          meter: 60000,
          meterUnit: DistanceUnit.km,
        ),
      ];
      expect(meterGoesBackwards(events, 'car', DistanceUnit.km, 59000), isTrue);
      expect(
        meterGoesBackwards(events, 'car', DistanceUnit.km, 61000),
        isFalse,
      );
      // Editing e2: its own reading is excluded from the comparison.
      expect(
        meterGoesBackwards(
          events,
          'car',
          DistanceUnit.km,
          55000,
          excludingEventId: 'e2',
        ),
        isFalse, // 55000 > e1's 50000
      );
      // Compare physical distances using the declared km/mi ratio.
      expect(meterGoesBackwards(events, 'car', DistanceUnit.mi, 100), isTrue);
    });

    test('latest event of a task, for the repeat entry', () {
      final events = [
        event('e1', DateTime(2026, 1, 1), task: 'oil change'),
        event('e2', DateTime(2026, 6, 1), task: 'oil change'),
        event('e3', DateTime(2026, 5, 1), task: 'brakes'),
      ];
      expect(latestEventOfTask(events, 'car', 'Oil Change')?.id, 'e2');
      expect(latestEventOfTask(events, 'car', 'brakes')?.id, 'e3');
      expect(latestEventOfTask(events, 'car', 'nothing'), isNull);
    });
  });

  group('defensive record reading', () {
    test('assets: malformed bodies are incomplete, not crashes', () {
      final noName = MaintenanceAsset.fromBody('a', {'type': 'car'});
      expect(noName.valid, isFalse);
      expect(noName.nickname, 'a'); // the id stands in
      final badType = MaintenanceAsset.fromBody('b', {
        'nickname': 'X',
        'type': 'ufo',
      });
      expect(badType.valid, isFalse);
      expect(badType.type, 'other');
      final badDate = MaintenanceAsset.fromBody('c', {
        'nickname': 'X',
        'type': 'car',
        'purchasedAt': 'nope',
      });
      expect(badDate.valid, isFalse);
      expect(badDate.purchasedAt, isNull);
      final good = MaintenanceAsset.fromBody('d', {
        'nickname': 'X',
        'type': 'car',
        'meterKind': 'distance',
        'distanceUnit': 'mi',
        'archived': true,
        'purchasedAt': '2026-01-15T00:00:00',
      });
      expect(good.valid, isTrue);
      expect(good.meterKind, MeterKind.distance);
      expect(good.distanceUnit, DistanceUnit.mi);
      expect(good.archived, isTrue);
      expect(good.purchasedAt, DateTime(2026, 1, 15));
      // Round trip.
      final read = MaintenanceAsset.fromBody('d2', good.toBody());
      expect(read.nickname, good.nickname);
      expect(read.meterKind, good.meterKind);
      expect(read.distanceUnit, good.distanceUnit);
    });

    test('events: bad fields are incomplete, not crashes', () {
      final noTask = ServiceEvent.fromBody('e', {
        'assetId': 'car',
        'date': '2026-01-01T00:00:00',
      });
      expect(noTask.valid, isFalse);
      final noAsset = ServiceEvent.fromBody('e', {
        'task': 'x',
        'date': '2026-01-01T00:00:00',
      });
      expect(noAsset.valid, isFalse);
      final badMeter = ServiceEvent.fromBody('e', {
        'assetId': 'car',
        'task': 'x',
        'date': '2026-01-01T00:00:00',
        'meter': -5,
      });
      expect(badMeter.valid, isFalse);
      expect(badMeter.meter, isNull);
      final costWithoutCurrency = ServiceEvent.fromBody('e', {
        'assetId': 'car',
        'task': 'x',
        'date': '2026-01-01T00:00:00',
        'cost': 100,
      });
      expect(costWithoutCurrency.valid, isFalse);
      final good = ServiceEvent.fromBody('e', {
        'assetId': 'car',
        'task': 'x',
        'date': '2026-01-01T00:00:00',
        'cost': 100,
        'currency': 'IRR',
        'meter': 50,
        'meterUnit': 'km',
        'provider': 'shop',
      });
      expect(good.valid, isTrue);
      expect(good.meterUnit, DistanceUnit.km);
      final read = ServiceEvent.fromBody('e2', good.toBody());
      expect(read.cost, 100);
      expect(read.meter, 50);
      expect(read.meterUnit, DistanceUnit.km);
      expect(read.provider, 'shop');
    });

    test('rules: nothing positive is nothing at all', () {
      expect(
        IntervalRule.fromBody('r', {'assetId': 'car', 'task': 'x', 'days': 0}),
        isNull,
      );
      expect(
        IntervalRule.fromBody('r', {
          'assetId': 'car',
          'task': 'x',
          'months': -3,
        }),
        isNull,
      );
      expect(
        IntervalRule.fromBody('r', {'assetId': 'car', 'task': 'x'}),
        isNull,
      );
      expect(
        IntervalRule.fromBody('r', {'assetId': 'car', 'days': 10}), // no task
        isNull,
      );
      expect(
        IntervalRule.fromBody(
          'r',
          {'assetId': 'car', 'task': 'x', 'meters': 10}, // no unit
        ),
        isNull,
      );
      final good = IntervalRule.fromBody('r', {
        'assetId': 'car',
        'task': 'x',
        'days': 10,
        'meters': 1000,
        'meterUnit': 'mi',
      });
      expect(good!.days, 10);
      expect(good.meters, 1000);
      expect(good.meterUnit, DistanceUnit.mi);
      expect(good.hasTime, isTrue);
      expect(good.hasUsage, isTrue);
      // An invalid known interval must not become a different valid rule.
      final tolerant = IntervalRule.fromBody('r', {
        'assetId': 'car',
        'task': 'x',
        'days': 5,
        'meters': 'lots',
      });
      expect(tolerant, isNull);
    });
  });
}
