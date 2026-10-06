import 'package:nex_core/nex_core.dart';
import 'package:test/test.dart';

void main() {
  CycleDate d(int y, int m, int day) => CycleDate(y, m, day);
  var n = 0;
  CyclePeriod period(CycleDate start, [int? days]) => CyclePeriod(
    id: 'p${n++}',
    start: start,
    end: days == null ? null : start.addDays(days - 1),
  );

  /// Periods every [lengths] days from [first], each five days long.
  List<CyclePeriod> history(CycleDate first, List<int> lengths) {
    final out = [period(first, 5)];
    var at = first;
    for (final l in lengths) {
      at = at.addDays(l);
      out.add(period(at, 5));
    }
    return out;
  }

  group('CycleDate', () {
    test('counts whole days across months, years and DST', () {
      expect(d(2026, 3, 1).daysSince(d(2026, 2, 1)), 28);
      expect(d(2027, 1, 1).daysSince(d(2026, 12, 31)), 1);
      expect(d(2026, 3, 29).addDays(1), d(2026, 3, 30));
      expect(CycleDate.parse('2026-10-06'), d(2026, 10, 6));
      expect(d(2026, 10, 6).toString(), '2026-10-06');
    });
  });

  test('nothing logged, nothing predicted', () {
    expect(CyclePredictor.predict(periods: [], today: d(2026, 10, 6)), isNull);
  });

  test(
    'one period: the given typical lengths, low confidence, a wide range',
    () {
      final p = CyclePredictor.predict(
        periods: [period(d(2026, 10, 1))],
        today: d(2026, 10, 3),
        typicalCycle: 30,
        typicalPeriod: 6,
      )!;
      expect(p.cycleDay, 3);
      expect(p.inPeriod, isTrue);
      expect(p.nextStart, d(2026, 10, 31));
      expect(p.averagePeriod, 6);
      expect(p.confidence, CycleConfidence.low);
      expect(p.nextLatest.daysSince(p.nextEarliest), greaterThanOrEqualTo(6));
      expect(p.cyclesUsed, 0);
    },
  );

  test(
    'regular cycles: their own average, high confidence, a narrow range',
    () {
      final periods = history(d(2026, 5, 1), [30, 31, 30, 30]);
      final last = periods.last.start;
      final p = CyclePredictor.predict(
        periods: periods,
        today: last.addDays(10),
      )!;
      expect(p.averageCycle, 30);
      expect(p.confidence, CycleConfidence.high);
      expect(p.nextStart, last.addDays(30));
      expect(p.nextLatest.daysSince(p.nextEarliest), 2);
      expect(p.ovulation, p.nextStart.addDays(-14));
      expect(p.fertile.start, p.ovulation.addDays(-5));
      expect(p.fertile.end, p.ovulation.addDays(1));
      expect(p.inPeriod, isFalse);
      expect(p.cycleDay, 11);
      expect(p.alerts, isEmpty);
      expect(p.upcoming, hasLength(3));
      expect(p.upcoming[1].period.start, p.nextStart.addDays(30));
    },
  );

  test('cycles that vary widen the range and say so', () {
    final periods = history(d(2026, 1, 1), [24, 38, 27, 40, 22]);
    final p = CyclePredictor.predict(
      periods: periods,
      today: periods.last.start.addDays(3),
    )!;
    expect(p.confidence, CycleConfidence.low);
    expect(p.alerts, contains(CycleAlert.irregular));
    expect(
      p.nextLatest.daysSince(p.nextEarliest),
      greaterThanOrEqualTo(2 * p.variability.ceil()),
    );
  });

  test('a missed log is not taken for a 60-day cycle', () {
    // 28, then a month nobody logged (56), then 28.
    final periods = history(d(2026, 1, 1), [28, 56, 28, 28]);
    final p = CyclePredictor.predict(
      periods: periods,
      today: periods.last.start,
    )!;
    expect(p.averageCycle, 28);
  });

  test('late by more than ten days past the range', () {
    final periods = history(d(2026, 1, 1), [28, 28, 28]);
    final p = CyclePredictor.predict(
      periods: periods,
      today: periods.last.start.addDays(28 + 1 + 11),
    )!;
    expect(p.alerts, contains(CycleAlert.late));
    expect(p.daysUntilNext, lessThan(0));
  });

  test('a period still open after eight days is worth a word', () {
    final p = CyclePredictor.predict(
      periods: [period(d(2026, 10, 1))],
      today: d(2026, 10, 10),
    )!;
    expect(p.alerts, contains(CycleAlert.longPeriod));
    expect(p.inPeriod, isTrue);
    // And one forgotten open for weeks stops counting as "in period".
    final forgotten = CyclePredictor.predict(
      periods: [period(d(2026, 9, 1))],
      today: d(2026, 10, 1),
    )!;
    expect(forgotten.inPeriod, isFalse);
  });

  test('short and long cycles', () {
    final short = history(d(2026, 1, 1), [28, 19]);
    expect(
      CyclePredictor.predict(periods: short, today: short.last.start)!.alerts,
      contains(CycleAlert.shortCycle),
    );
    final long = history(d(2026, 1, 1), [28, 45]);
    expect(
      CyclePredictor.predict(periods: long, today: long.last.start)!.alerts,
      contains(CycleAlert.longCycle),
    );
  });

  test('a start logged in the future is ignored', () {
    final p = CyclePredictor.predict(
      periods: [period(d(2026, 10, 1), 5), period(d(2026, 12, 1))],
      today: d(2026, 10, 6),
    )!;
    expect(p.lastStart, d(2026, 10, 1));
  });
}
