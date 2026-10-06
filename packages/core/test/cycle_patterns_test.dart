import 'package:nex_core/nex_core.dart';
import 'package:test/test.dart';

void main() {
  CycleDate d(int m, int day) => CycleDate(2026, m, day);
  final periods = [
    CyclePeriod(id: 'a', start: d(1, 1), end: d(1, 5)),
    CyclePeriod(id: 'b', start: d(1, 29), end: d(2, 2)),
    CyclePeriod(id: 'c', start: d(2, 26), end: d(3, 2)),
    CyclePeriod(id: 'd', start: d(3, 26), end: d(3, 30)),
  ];
  CycleDayLog log(CycleDate day, Set<CycleSymptom> symptoms) =>
      CycleDayLog(day: day, symptoms: symptoms);

  test('a headache two days before each period is a pattern', () {
    final found = CyclePatterns.find(
      periods: periods,
      logs: [
        log(d(1, 27), {CycleSymptom.headache}),
        log(d(2, 24), {CycleSymptom.headache}),
        log(d(3, 24), {CycleSymptom.headache}),
      ],
    );
    final p = found.single;
    expect(p.symptom, CycleSymptom.headache);
    expect(p.phase, CyclePhase.beforePeriod);
    expect(p.cycles, 3);
    expect(p.daysBefore, 2);
  });

  test('cramps on period days are a period pattern', () {
    final found = CyclePatterns.find(
      periods: periods,
      logs: [
        log(d(1, 1), {CycleSymptom.cramps}),
        log(d(1, 29), {CycleSymptom.cramps}),
      ],
    );
    expect(found.single.phase, CyclePhase.period);
  });

  test('one cycle is not a pattern, nor is a symptom that comes whenever', () {
    expect(
      CyclePatterns.find(
        periods: periods,
        logs: [
          log(d(1, 27), {CycleSymptom.headache}),
        ],
      ),
      isEmpty,
    );
    expect(
      CyclePatterns.find(
        periods: periods,
        logs: [
          log(d(1, 27), {CycleSymptom.fatigue}),
          log(d(2, 24), {CycleSymptom.fatigue}),
          for (final day in [8, 10, 18, 20, 21])
            log(d(2, day), {CycleSymptom.fatigue}),
        ],
      ),
      isEmpty,
    );
  });

  test('with fewer than two periods there is nothing to measure against', () {
    expect(
      CyclePatterns.find(
        periods: [periods.first],
        logs: [
          log(d(1, 2), {CycleSymptom.cramps}),
        ],
      ),
      isEmpty,
    );
  });
}
