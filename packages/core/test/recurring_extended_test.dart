import 'package:nex_core/nex_core.dart';
import 'package:test/test.dart';

NexCommitment item(
  DateTime due, {
  NexCadence cadence = NexCadence.months,
  Map<String, dynamic> details = const {},
}) => NexCommitment(
  id: 'a',
  title: 'Example',
  cadence: cadence,
  every: 1,
  dueAt: due,
  createdAt: due,
  updatedAt: due,
  details: {'anchor': due.toIso8601String(), ...details},
);
void main() {
  test('monthly anchor returns to the 31st after February', () {
    final jan = item(DateTime(2026, 1, 31, 9));
    final feb = jan.met(jan.dueAt);
    expect(feb.dueAt, DateTime(2026, 2, 28, 9));
    expect(feb.met(feb.dueAt).dueAt, DateTime(2026, 3, 31, 9));
    expect(feb.history.single['action'], 'done');
  });
  test('Persian months and last day retain the solar schedule', () {
    final start = nexGregorianDate(1404, 6, 31);
    final c = item(start, details: {'solar': true, 'monthDay': 0});
    final next = c.met(start);
    expect(nexPersianDate(next.dueAt), (year: 1404, month: 7, day: 30));
    expect(nexPersianDate(next.met(next.dueAt).dueAt), (
      year: 1404,
      month: 8,
      day: 30,
    ));
  });
  test('selected weekdays respect a two-week cadence', () {
    final c = item(
      DateTime(2026, 9, 28, 9),
      cadence: NexCadence.weeks,
      details: {
        'weekdays': [1, 3],
      },
    ).copyWith(every: 2);
    final wed = c.met(c.dueAt);
    expect(wed.dueAt, DateTime(2026, 9, 30, 9));
    expect(wed.met(wed.dueAt).dueAt, DateTime(2026, 10, 12, 9));
  });
  test('a snoozed occurrence does not shift the monthly anchor', () {
    final c = item(DateTime(2026, 1, 1, 9));
    final snoozed = c.copyWith(
      dueAt: DateTime(2026, 1, 5, 9),
      details: {...c.details, 'scheduledDue': c.dueAt.toIso8601String()},
    );
    final next = snoozed.met(snoozed.dueAt);
    expect(next.dueAt, DateTime(2026, 2, 1, 9));
    expect(next.details['scheduledDue'], isNull);
  });
}
