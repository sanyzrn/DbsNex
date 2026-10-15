import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/maintenance/models.dart';
import 'package:nex_client/modules/maintenance/units.dart';
import 'package:nex_client/modules/maintenance/costs.dart';
import 'package:nex_client/modules/maintenance/logic.dart';

void main() {
  final now = DateTime(2026, 10, 14, 12);
  final asset = MaintenanceAsset(
    id: 'a',
    nickname: 'Car',
    type: 'car',
    meterKind: MeterKind.distance,
    distanceUnit: DistanceUnit.km,
  );
  final event = ServiceEvent(
    id: 'e',
    assetId: 'a',
    task: 'Oil',
    date: DateTime(2026, 10, 1),
    meter: 100000,
    meterUnit: DistanceUnit.km,
  );
  const rule = IntervalRule(
    id: 'r',
    assetId: 'a',
    task: 'oil',
    months: 6,
    meters: 10000,
    meterUnit: DistanceUnit.km,
  );
  MaintenanceReading reading(
    int value, {
    bool corrected = false,
    DateTime? at,
  }) => MaintenanceReading(
    id: 'm',
    assetId: 'a',
    value: value,
    kind: MeterKind.distance,
    unit: DistanceUnit.km,
    at: at ?? DateTime(2026, 10, 14, 10),
    corrected: corrected,
  );
  test('fractional Persian and Arabic readings have explicit scale', () {
    expect(parseMeterInput('۱۲۳٫۴۵۶'), 123456);
    expect(parseMeterInput('١٢٣.٤٥٦'), 123456);
    expect(parseMeterInput('1.0001'), isNull);
    expect(parseMeterInput('1000000000.001'), isNull);
    expect(parseMeterInput('-1'), isNull);
    expect(convertMilli(25146000, DistanceUnit.km, DistanceUnit.mi), 15625000);
  });
  test('manual reading triggers usage while calendar due stays future', () {
    final standing = ruleStandings(
      asset,
      [event],
      [rule],
      now,
      readings: [reading(110000500)],
    ).single;
    expect(standing.dueByMeter, isTrue);
    expect(standing.dueByTime(now), isFalse);
    expect(standing.lastDone!.id, 'e');
    expect(standing.timeDue, DateTime(2027, 4, 1));
    expect(standing.currentMeter, 110000500);
    expect(standing.nextDueMeter, 110000000);
  });
  test(
    'correction below baseline needs information without resetting service',
    () {
      final standing = ruleStandings(
        asset,
        [event],
        [rule],
        now,
        readings: [reading(500, corrected: true)],
      ).single;
      expect(standing.meterUnknown, isTrue);
      expect(standing.dueByMeter, isFalse);
      expect(standing.lastDone!.id, 'e');
      expect(standing.unknown, isTrue);
    },
  );
  test('no service baseline is never invented as zero', () {
    final s = ruleStandings(
      asset,
      [],
      [rule],
      now,
      readings: [reading(999999000)],
    ).single;
    expect(s.nextDueMeter, isNull);
    expect(s.dueNow(now), isFalse);
    expect(s.unknown, isTrue);
  });
  test('future readings and future services do not become current', () {
    final future = ServiceEvent(
      id: 'f',
      assetId: 'a',
      task: 'Oil',
      date: DateTime(2027),
      meter: 200000,
      meterUnit: DistanceUnit.km,
    );
    final s = ruleStandings(
      asset,
      [event, future],
      [rule],
      now,
      readings: [reading(200000000, at: DateTime(2027))],
    ).single;
    expect(s.currentMeter, 100000000);
    expect(s.lastDone!.id, 'e');
  });
  test('calendar rejects normalized invalid dates and clamps leap month', () {
    expect(maintenanceCalendar('2026-02-30T00:00:00'), isNull);
    expect(
      maintenanceCalendar('2024-02-29T23:00:00-12:00'),
      DateTime(2024, 2, 29),
    );
    expect(addMonths(DateTime(2024, 1, 31), 1), DateTime(2024, 2, 29));
    expect(() => addMonths(DateTime(9999, 12, 31), 1), throwsRangeError);
    expect(
      IntervalRule.fromBody('r', {
        'assetId': 'a',
        'task': 'Oil',
        'months': 12001,
      }),
      isNull,
    );
  });
  test('currency exponents, Unicode amounts and free service are exact', () {
    expect(parseCostAmount('۱۲٫۳۴۵', costCurrencyOf('KWD')!).minor, 12345);
    expect(
      parseCostAmount('1.1', costCurrencyOf('JPY')!).error,
      CostAmountError.tooPrecise,
    );
    expect(parseTomanCost('۰').minor, 0);
    expect(
      ServiceEvent.fromBody('e', {
        ...event.toBody(),
        'cost': 1,
        'currency': 'USD',
        'currency_exponent': 3,
      }).valid,
      isFalse,
    );
    expect(
      ServiceEvent.fromBody('e', {
        ...event.toBody(),
        'cost': 0,
        'currency': 'JPY',
        'currency_exponent': 0,
      }).valid,
      isTrue,
    );
  });
  test('mixed costs stay separate and totals exceed machine int safely', () {
    final events = [
      for (var i = 0; i < 10000; i++)
        ServiceEvent(
          id: '$i',
          assetId: 'a',
          task: 'Oil',
          date: now,
          cost: costMax,
          currency: 'USD',
        ),
      ServiceEvent(
        id: 'j',
        assetId: 'a',
        task: 'Oil',
        date: now,
        cost: 10,
        currency: 'JPY',
      ),
    ];
    expect(
      assetCostTotals(events)['USD'],
      BigInt.from(costMax) * BigInt.from(10000),
    );
    expect(assetCostTotals(events)['JPY'], BigInt.from(10));
  });
  test(
    'invalid scale and incompatible hours unit are refused without casts',
    () {
      final b = reading(100).toBody();
      expect(MaintenanceReading.fromBody('m', {...b, 'scale': 1000.0}), isNull);
      expect(
        MaintenanceReading.fromBody('m', {...b, 'meterKind': 'hours'}),
        isNull,
      );
    },
  );
}
