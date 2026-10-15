import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/habits/habit_math.dart';
import 'package:nex_client/modules/habits/habit_model.dart';

/// The streak rules, exactly as the README states them: one missed
/// interval is forgiven — never counted — a second one ends the run, and
/// the same stored history gives the same streak whatever today is.
void main() {
  final habit = Habit(
    id: 'h1',
    name: 'Stretch',
    note: '',
    weekly: false,
    target: 1,
    archived: false,
    createdAt: DateTime(2026, 1, 1),
  );
  Habit weekly(int target) => Habit(
    id: 'h1',
    name: 'Gym',
    note: '',
    weekly: true,
    target: target,
    archived: false,
    createdAt: DateTime(2026, 1, 1),
  );

  Habit habitWithCreatedAt(DateTime created) => Habit(
    id: 'h1',
    name: '',
    note: '',
    weekly: false,
    target: 1,
    archived: false,
    createdAt: created,
  );

  group('week boundaries', () {
    test('weeks start on Saturday', () {
      // 2026-10-10 is a Saturday.
      expect(HabitMath.weekStartOf(DateTime.utc(2026, 10, 10)).day, 10);
      // Sunday belongs to the week that began the day before.
      expect(HabitMath.weekStartOf(DateTime.utc(2026, 10, 11)).day, 10);
      // Friday ends the week; the next day begins a new one.
      expect(HabitMath.weekStartOf(DateTime.utc(2026, 10, 16)).day, 10);
      expect(HabitMath.weekStartOf(DateTime.utc(2026, 10, 17)).day, 17);
      // …and across a month boundary.
      expect(HabitMath.weekKeyOf('2026-11-01'), '2026-10-31');
    });

    test('every weekday maps to its own Saturday', () {
      final saturday = DateTime.utc(2026, 10, 10);
      for (var offset = 0; offset < 7; offset++) {
        final day = saturday.add(Duration(days: offset));
        expect(HabitMath.weekStartOf(day), saturday, reason: '$day');
      }
    });
  });

  group('daily streaks', () {
    test('consecutive days count, today included', () {
      final s = HabitMath.standing(habit, [
        '2026-10-08',
        '2026-10-09',
        '2026-10-10',
        '2026-10-11',
        '2026-10-12',
      ], DateTime(2026, 10, 12));
      expect(s.streak, 5);
      expect(s.todayDone, isTrue);
      expect(s.graceNow, isFalse);
      expect(s.graceInside, isFalse);
      expect(s.total, 5);
    });

    test('today pending does not break yesterday’s streak', () {
      final s = HabitMath.standing(habit, [
        '2026-10-10',
        '2026-10-11',
      ], DateTime(2026, 10, 12));
      expect(s.streak, 2);
      expect(s.todayDone, isFalse);
      expect(s.graceNow, isFalse);
    });

    test('one missed day is forgiven, not counted', () {
      final s = HabitMath.standing(habit, [
        '2026-10-08',
        '2026-10-09',
        '2026-10-11',
        '2026-10-12',
      ], DateTime(2026, 10, 12));
      // 10-10 was missed; the run counts its four completed days.
      expect(s.streak, 4);
      expect(s.graceInside, isTrue);
      expect(s.graceNow, isFalse);
    });

    test('two missed days end the run', () {
      final s = HabitMath.standing(habit, [
        '2026-10-08',
        '2026-10-09',
        '2026-10-12',
      ], DateTime(2026, 10, 12));
      expect(s.streak, 1);
      expect(s.graceInside, isFalse);
    });

    test('the run ends at its own start, not at history’s start', () {
      final s = HabitMath.standing(habit, [
        '2026-09-01',
        '2026-10-11',
        '2026-10-12',
      ], DateTime(2026, 10, 12));
      expect(s.streak, 2);
      expect(s.graceInside, isFalse);
    });

    test('standing on grace: last check-in two days ago', () {
      final s = HabitMath.standing(habit, [
        '2026-10-10',
      ], DateTime(2026, 10, 12));
      expect(s.streak, 1);
      expect(s.graceNow, isTrue);
      expect(
        s.graceInside,
        isFalse,
        reason:
            'nothing was missed *between* '
            'completions — the grace day is simply yesterday',
      );
    });

    test('dead: last check-in three days ago', () {
      final s = HabitMath.standing(habit, [
        '2026-10-09',
      ], DateTime(2026, 10, 12));
      expect(s.streak, 0);
      expect(s.graceNow, isFalse);
    });

    test('future check-ins are ignored everywhere', () {
      final s = HabitMath.standing(habit, [
        '2026-10-12',
        '2026-10-13',
        '2027-01-01',
      ], DateTime(2026, 10, 12));
      expect(s.streak, 1);
      expect(s.total, 1);
      expect(s.todayDone, isTrue);
    });

    test('a leap day is just a day', () {
      final s = HabitMath.standing(habit, [
        '2024-02-28',
        '2024-02-29',
        '2024-03-01',
      ], DateTime(2024, 3, 1));
      expect(s.streak, 3);
    });

    test('check-ins across midnight are two civil days', () {
      final lateNight = DateTime(2026, 10, 11, 23, 59);
      final justAfter = DateTime(2026, 10, 12, 0, 1);
      expect(daysBetweenKeys(dateKeyOf(lateNight), dateKeyOf(justAfter)), 1);
    });

    test('a DST boundary cannot shift a civil day', () {
      // Most of the northern hemisphere leaves DST in late October; the
      // keys are UTC midnights, so the day count is exact either way.
      expect(daysBetweenKeys('2026-10-24', '2026-10-26'), 2);
    });
  });

  group('weekly streaks', () {
    test('weeks meeting the target count, partial weeks do not', () {
      // Weeks: 2026-10-03 (3 of 3), 2026-10-10 (3 of 3), current week.
      final s = HabitMath.standing(
        weekly(3),
        [
          '2026-10-03',
          '2026-10-05',
          '2026-10-07',
          '2026-10-10',
          '2026-10-13',
          '2026-10-15',
        ],
        DateTime(2026, 10, 16), // Friday of the second week
      );
      expect(s.streak, 2);
      expect(s.weekCount, 3, reason: 'the current week is 2026-10-10’s');
    });

    test('one unmet week is forgiven, not counted', () {
      // 2026-10-03 week met, 2026-10-10 week missed, 2026-10-17 week met,
      // current week partial.
      final s = HabitMath.standing(weekly(2), [
        '2026-10-03',
        '2026-10-05',
        '2026-10-17',
        '2026-10-19',
      ], DateTime(2026, 10, 21));
      expect(s.streak, 2);
      expect(s.graceInside, isTrue);
      expect(s.graceNow, isFalse);
    });

    test('two unmet weeks end the run', () {
      final s = HabitMath.standing(weekly(2), [
        '2026-10-03',
        '2026-10-05',
        '2026-10-24',
        '2026-10-26',
      ], DateTime(2026, 10, 28));
      expect(s.streak, 1);
      expect(s.graceInside, isFalse);
    });

    test('a Saturday check-in opens the new week', () {
      // Friday 2026-10-09 and Saturday 2026-10-10 are different weeks.
      final s = HabitMath.standing(weekly(1), [
        '2026-10-09',
        '2026-10-10',
      ], DateTime(2026, 10, 10));
      expect(s.weekCount, 1);
      expect(s.streak, 2);
    });

    test('standing on grace: last met week is two weeks back', () {
      // Met week of 2026-10-03; the week of 2026-10-10 was missed; the
      // current week (2026-10-17) is still being written.
      final s = HabitMath.standing(weekly(2), [
        '2026-10-03',
        '2026-10-04',
      ], DateTime(2026, 10, 20));
      expect(s.streak, 1);
      expect(s.graceNow, isTrue);
    });

    test('dead: last met week three weeks back', () {
      final s = HabitMath.standing(weekly(2), [
        '2026-10-03',
        '2026-10-04',
      ], DateTime(2026, 10, 27));
      expect(s.streak, 0);
    });

    test('zero and empty check-ins', () {
      final s = HabitMath.standing(weekly(4), [], DateTime(2026, 10, 12));
      expect(s.streak, 0);
      expect(s.weekCount, 0);
      expect(s.total, 0);
      expect(s.todayDone, isFalse);
    });
  });

  group('the recent-days window', () {
    test('covers fourteen days, oldest first', () {
      final s = HabitMath.standing(habit, [
        '2026-10-12',
      ], DateTime(2026, 10, 12));
      expect(s.recent.length, HabitMath.recentDays);
      expect(s.recent.last, isTrue, reason: 'today is the last mark');
      expect(s.recent.where((d) => d).length, 1);
    });
  });

  test('creation date never participates in the arithmetic', () {
    final s = HabitMath.standing(habitWithCreatedAt(DateTime(2020, 1, 1)), [
      '2026-10-11',
      '2026-10-12',
    ], DateTime(2026, 10, 12));
    expect(s.streak, 2);
  });
}
