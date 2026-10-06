import 'package:nex_core/nex_core.dart';
import 'package:test/test.dart';

void main() {
  test('modes read back from their names, and only two predict', () {
    for (final mode in CycleMode.values) {
      expect(CycleMode.fromWire(mode.name), mode);
    }
    expect(CycleMode.fromWire('nonsense'), CycleMode.normal);
    expect(CycleMode.values.where((m) => m.predicts), [
      CycleMode.normal,
      CycleMode.conceive,
    ]);
  });

  test('pregnancy is counted in weeks and days from the last period', () {
    final p = CyclePregnancy(
      lastPeriod: const CycleDate(2026, 6, 1),
      today: const CycleDate(2026, 8, 26),
    );
    expect(p.daysAlong, 86);
    expect(p.weeks, 12);
    expect(p.days, 2);
    expect(p.trimester, 1);
    expect(p.dueDate, const CycleDate(2027, 3, 8));
    expect(p.daysToGo, 194);
    expect(p.fraction, closeTo(86 / 280, 1e-9));
  });

  test('a due date gives back the last period it implies', () {
    const due = CycleDate(2027, 3, 8);
    final last = CyclePregnancy.lastPeriodFor(due);
    expect(CyclePregnancy(lastPeriod: last, today: due).dueDate, due);
  });

  test('trimesters change at weeks 14 and 28', () {
    CyclePregnancy at(int days) => CyclePregnancy(
      lastPeriod: const CycleDate(2026, 1, 1),
      today: const CycleDate(2026, 1, 1).addDays(days),
    );
    expect(at(13 * 7 + 6).trimester, 1);
    expect(at(14 * 7).trimester, 2);
    expect(at(27 * 7 + 6).trimester, 2);
    expect(at(28 * 7).trimester, 3);
  });
}
