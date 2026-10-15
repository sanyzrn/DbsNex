part of 'logic_test.dart';

void _logicCases1() {
  group('time intervals', () {
    test('due comes from the latest real service', () {
      final standings = ruleStandings(
        asset(),
        [event('e1', DateTime(2026, 4, 1))],
        [rule(months: 6)],
        now,
      );
      final standing = standings.single;
      expect(standing.timeDue, DateTime(2026, 10, 1));
      expect(standing.dueNow(now), isTrue); // 12 days overdue by Oct 13
      expect(assetGroupOf(asset(), standings, now), AssetGroup.dueNow);
    });

    test('a due date today is due now; tomorrow is coming up', () {
      final dueToday = ruleStandings(
        asset(),
        [event('e1', DateTime(2026, 10, 6))],
        [rule(days: 7)],
        now,
      ).single;
      expect(dueToday.timeDue, DateTime(2026, 10, 13));
      expect(dueToday.dueNow(now), isTrue);

      final dueTomorrow = ruleStandings(
        asset(),
        [event('e1', DateTime(2026, 10, 7))],
        [rule(days: 7)],
        now,
      ).single;
      expect(dueTomorrow.comingUp(now), isTrue);
      expect(dueTomorrow.dueNow(now), isFalse);
    });

    test('a task never done counts from the purchase date, marked', () {
      final standings = ruleStandings(
        asset(purchased: DateTime(2026, 1, 15)),
        [],
        [rule(months: 6)],
        now,
      );
      final standing = standings.single;
      expect(standing.basisPurchase, isTrue);
      expect(standing.timeDue, DateTime(2026, 7, 15));
      expect(standing.dueNow(now), isTrue);
      expect(standing.anchorDate, DateTime(2026, 1, 15));
    });

    test('never done and never dated has no due date', () {
      final standings = ruleStandings(asset(), [], [rule(months: 6)], now);
      expect(standings.single.timeUnknown, isTrue);
      expect(standings.single.timeDue, isNull);
      expect(standings.single.unknown, isTrue);
      expect(assetGroupOf(asset(), standings, now), AssetGroup.needsInfo);
    });

    test('the time progress walks anchor to due', () {
      final standing = ruleStandings(
        asset(),
        [event('e1', DateTime(2026, 7, 14))],
        [rule(days: 90)],
        now,
      ).single;
      // 91 of 90 days have passed: full.
      expect(standing.timeProgress(now), 1);
      final halfway = ruleStandings(
        asset(),
        [event('e1', DateTime(2026, 9, 29))],
        [rule(days: 28)],
        now,
      ).single;
      // 14 of 28 days: halfway.
      expect(halfway.timeProgress(now), closeTo(0.5, 1e-9));
    });
  });

  group('usage intervals', () {
    test('due when the current reading reaches the trigger', () {
      final standings = ruleStandings(
        asset(),
        [
          event(
            'e1',
            DateTime(2026, 4, 1),
            meter: 115000,
            meterUnit: DistanceUnit.km,
          ),
          event(
            'e2',
            DateTime(2026, 9, 20),
            meter: 128000,
            meterUnit: DistanceUnit.km,
          ),
          // A different task carries the current odometer higher.
          event(
            'e3',
            DateTime(2026, 10, 1),
            task: 'tyres',
            meter: 139000,
            meterUnit: DistanceUnit.km,
          ),
        ],
        [rule(meters: 10000, meterUnit: DistanceUnit.km)],
        now,
      );
      final standing = standings.single;
      // Last oil change at 128000; every 10,000: due at 138000.
      expect(standing.nextDueMeter, 138000000);
      // The current odometer is the latest reading of any task.
      expect(standing.currentMeter, 139000000);
      expect(standing.dueNow(now), isTrue);
      expect(assetGroupOf(asset(), standings, now), AssetGroup.dueNow);
    });

    test('no reading ever entered means due unknown — not fine', () {
      final standings = ruleStandings(asset(), [], [
        rule(meters: 10000, meterUnit: DistanceUnit.km),
      ], now);
      final standing = standings.single;
      expect(standing.meterUnknown, isTrue);
      expect(standing.unknown, isTrue);
      expect(standing.dueNow(now), isFalse); // unknown is not due
      expect(assetGroupOf(asset(), standings, now), AssetGroup.needsInfo);
    });

    test('other-unit readings use the declared ratio and conversion flag', () {
      final standings = ruleStandings(
        asset(),
        [
          // Only a miles reading exists; the rule counts km.
          event(
            'e1',
            DateTime(2026, 9, 20),
            meter: 80000,
            meterUnit: DistanceUnit.mi,
          ),
        ],
        [rule(meters: 10000, meterUnit: DistanceUnit.km)],
        now,
      );
      final standing = standings.single;
      expect(standing.currentMeter, 128747520);
      expect(standing.meterUnknown, isFalse);
      expect(standing.converted, isTrue);
    });

    test('running hours follow the same rules', () {
      final standings = ruleStandings(
        asset(meter: MeterKind.hours),
        [event('e1', DateTime(2026, 9, 1), meter: 350, meterUnit: null)],
        [rule(hours: 100)],
        now,
      );
      final standing = standings.single;
      expect(standing.nextDueMeter, 450000);
      expect(standing.currentMeter, 350000);
      expect(standing.dueNow(now), isFalse);
      // No date on this rule: not "coming up" by any date — simply
      // scheduled, and honestly not due.
      expect(
        assetGroupOf(asset(meter: MeterKind.hours), standings, now),
        AssetGroup.scheduled,
      );
    });
  });

  group('both intervals: earliest wins', () {
    test('the earlier date triggers even when the meter is far off', () {
      final standings = ruleStandings(
        asset(),
        [
          event(
            'e1',
            DateTime(2026, 10, 6),
            meter: 10000,
            meterUnit: DistanceUnit.km,
          ),
        ],
        [rule(days: 7, meters: 5000, meterUnit: DistanceUnit.km)],
        now,
      );
      final standing = standings.single;
      expect(standing.timeDue, DateTime(2026, 10, 13));
      expect(standing.nextDueMeter, 15000000);
      expect(standing.currentMeter, 10000000);
      // Date is due today; meter is 5000 away: due by date.
      expect(standing.dueNow(now), isTrue);
    });

    test('the meter triggers even when the date is far off', () {
      final standings = ruleStandings(
        asset(),
        [
          event(
            'e1',
            DateTime(2026, 10, 12),
            meter: 20000,
            meterUnit: DistanceUnit.km,
          ),
        ],
        [rule(days: 365, meters: 5000, meterUnit: DistanceUnit.km)],
        now,
      );
      final standing = standings.single;
      // Meter reached: current 20000 is at the 20000 trigger.
      expect(standing.nextDueMeter, 25000000);
      expect(standing.currentMeter, 20000000);
      expect(standing.dueNow(now), isFalse); // 5000 short of the trigger
      // Date is a year out; nothing due, nothing unknown.
      expect(assetGroupOf(asset(), standings, now), AssetGroup.scheduled);
    });

    test('a reached meter is due even with a far-off date', () {
      final standings = ruleStandings(
        asset(),
        [
          event(
            'e1',
            DateTime(2026, 10, 12),
            meter: 25000,
            meterUnit: DistanceUnit.km,
          ),
          event(
            'e2',
            DateTime(2026, 10, 13),
            task: 'tyres',
            meter: 31000,
            meterUnit: DistanceUnit.km,
          ),
        ],
        [rule(days: 365, meters: 5000, meterUnit: DistanceUnit.km)],
        now,
      );
      // The task's last reading (25000) + 5000 = 30000; current 31000.
      expect(standings.single.nextDueMeter, 30000000);
      expect(standings.single.currentMeter, 31000000);
      expect(standings.single.dueNow(now), isTrue);
      expect(assetGroupOf(asset(), standings, now), AssetGroup.dueNow);
    });
  });

  group('home groups', () {
    test('no rules is no schedule; archived is its own group', () {
      expect(assetGroupOf(asset(), [], now), AssetGroup.noSchedule);
      expect(assetGroupOf(asset(archived: true), [], now), AssetGroup.archived);
    });

    test('rules all due far ahead are scheduled, not schedule-less', () {
      final standings = ruleStandings(
        asset(),
        [event('e1', DateTime(2026, 10, 10))],
        [rule(months: 12)],
        now,
      );
      expect(assetGroupOf(asset(), standings, now), AssetGroup.scheduled);
    });

    test('one overdue rule makes the asset due now', () {
      final standings = ruleStandings(
        asset(),
        [
          event('e1', DateTime(2026, 1, 1)),
          event('e2', DateTime(2026, 5, 1), task: 'brakes'),
        ],
        [rule(months: 12), rule(task: 'brakes', days: 30)],
        now,
      );
      expect(assetGroupOf(asset(), standings, now), AssetGroup.dueNow);
      expect(standings, hasLength(2));
    });
  });
}
