import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/habits/habit_math.dart';
import 'package:nex_client/modules/habits/habit_model.dart';
import 'package:nex_client/modules/habits/habit_reminder.dart';

/// Rest days (2.8.14): a rest is the habit's own history, not a setting that
/// moves. Its days are not due, not missed and not in any rate; the streak
/// walks past them and the reminder waits for the first day after them.
void main() {
  Habit habit({HabitPlan plan = HabitPlan.daily}) => Habit(
    id: 'h',
    name: 'Walk',
    note: '',
    weekly: plan == HabitPlan.weekly,
    target: plan == HabitPlan.weekly ? 2 : 1,
    archived: false,
    createdAt: DateTime(2026, 10, 1),
    plan: plan,
  );

  final today = DateTime(2026, 10, 20);
  String key(int day) => '2026-10-${day.toString().padLeft(2, '0')}';

  group('the rest stretch', () {
    test('pausing keeps one stretch and merges the next to touch it', () {
      final rest = habit().pauseUntil(
        DateTime(2026, 10, 20),
        DateTime(2026, 10, 22),
      );
      expect(rest.pauses, [
        const HabitPause(from: '2026-10-20', to: '2026-10-22'),
      ]);
      final longer = rest.pauseUntil(
        DateTime(2026, 10, 23),
        DateTime(2026, 10, 25),
      );
      expect(longer.pauses, hasLength(1));
      expect(longer.pauses.single.to, '2026-10-25');
    });

    test('ending a rest that began today removes it entirely', () {
      final rest = habit().pauseUntil(today, DateTime(2026, 10, 25));
      expect(rest.endPause(today).pauses, isEmpty);
    });

    test('ending early stops yesterday, so today is a habit day again', () {
      final rest = habit().pauseUntil(
        DateTime(2026, 10, 18),
        DateTime(2026, 10, 25),
      );
      final ended = rest.endPause(today);
      expect(
        ended.pauses.single,
        const HabitPause(from: '2026-10-18', to: '2026-10-19'),
      );
      expect(ended.isPausedOn(today), isFalse);
      expect(ended.pauses.single.to, '2026-10-19');
    });

    test('a malformed or reversed stretch is read safely', () {
      final h = Habit.fromBody('h', {
        'name': 'Walk',
        'pauses': [
          {'from': '2026-10-22', 'to': '2026-10-20'},
          {'from': 'not a date', 'to': '2026-10-20'},
          {'from': '2026-02-30', 'to': '2026-03-01'},
        ],
      });
      expect(h.pauses, [
        const HabitPause(from: '2026-10-20', to: '2026-10-22'),
      ]);
    });

    test('touching restored stretches extend as a single rest', () {
      final restored = Habit.fromBody('h', {
        'pauses': [
          {'from': '2026-10-18', 'to': '2026-10-19'},
          {'from': '2026-10-20', 'to': '2026-10-21'},
          {'from': '2026-10-20', 'to': '2026-10-30'},
        ],
      });
      final extended = restored.pauseUntil(today, DateTime(2026, 11, 1));
      expect(extended.pauses, [
        const HabitPause(from: '2026-10-18', to: '2026-11-01'),
      ]);
    });

    test('a rest round-trips in the record', () {
      final rest = habit().pauseUntil(today, DateTime(2026, 10, 25));
      final again = Habit.fromBody('h', rest.toJson());
      expect(again.pauses, rest.pauses);
    });
  });

  group('streaks walk past a rest', () {
    test('a rest day is not due, not missed, and keeps the run', () {
      final rest = habit().pauseUntil(today, DateTime(2026, 10, 22));
      final s = HabitMath.standing(rest, [key(17), key(18), key(19)], today);
      expect(s.streak, 3);
      expect(s.dueToday, isFalse);
      expect(s.todayDone, isFalse);
      expect(
        HabitMath.dayState(
          rest,
          today,
          HabitMath.loggedDays(rest, const [], today),
          today,
        ),
        HabitDayState.off,
      );
    });

    test('a rest in the middle is not a miss either', () {
      final rest = habit().pauseUntil(
        DateTime(2026, 10, 18),
        DateTime(2026, 10, 19),
      );
      final s = HabitMath.standing(rest, [key(16), key(17), key(20)], today);
      expect(s.streak, 3);
      expect(s.graceInside, isFalse);
    });

    test('rates do not count rest days against the habit', () {
      final rest = habit().pauseUntil(
        DateTime(2026, 10, 18),
        DateTime(2026, 10, 19),
      );
      expect(rest.pauses, hasLength(1));
      expect(rest.isPausedOn(DateTime.utc(2026, 10, 18)), isTrue);
      final dates = [for (var day = 15; day <= 17; day++) key(day)];
      final withRest = HabitMath.dailyRate(rest, dates, today, 30);
      final without = HabitMath.dailyRate(habit(), dates, today, 30);
      expect(withRest.done, 3);
      expect(without.possible, greaterThan(0));
      expect(
        withRest.possible,
        without.possible - 2,
        reason: 'the two rest days were not owed',
      );
    });

    test('a weekly rest week neither counts nor breaks the run', () {
      final rest = habit(plan: HabitPlan.weekly)
          .pauseUntil(DateTime(2026, 10, 10), DateTime(2026, 10, 16));
      final dates = ['2026-10-03', '2026-10-04', '2026-10-17', '2026-10-18'];
      final s = HabitMath.standing(rest, dates, today);
      expect(s.streak, 2);
      expect(s.graceInside, isFalse);

      final withRest = HabitMath.weeklyRate(rest, dates, today, firstDay: 6);
      final without = HabitMath.weeklyRate(
        habit(plan: HabitPlan.weekly),
        dates,
        today,
        firstDay: 6,
      );
      expect(without.possible, 2);
      expect(withRest.possible, 1, reason: 'the rest week was not owed');
      expect(withRest.done, 1);
    });

    test('a check-in made during rest stays out of the completion rate', () {
      final rest = habit().pauseUntil(today, DateTime(2026, 10, 22));
      final before = HabitMath.dailyRate(rest, [key(19)], today, 7);
      final after = HabitMath.dailyRate(rest, [key(19), key(20)], today, 7);
      expect((after.done, after.possible), (before.done, before.possible));
      expect(HabitMath.standing(rest, [key(19), key(20)], today).total, 2);
    });

    test('a rest day is still a day a person can log', () {
      final rest = habit().pauseUntil(today, DateTime(2026, 10, 22));
      final s = HabitMath.standing(rest, [key(20)], today);
      expect(s.todayDone, isTrue, reason: 'a check-in during a rest counts');
      expect(
        HabitMath.dayState(
          rest,
          today,
          HabitMath.loggedDays(rest, [
            HabitCheck(
              id: 'h:2026-10-20',
              habitId: 'h',
              dateKey: '2026-10-20',
              at: today,
            ),
          ], today),
          today,
        ),
        HabitDayState.done,
      );
    });
  });

  test('a reminder waits for the first day after the rest', () {
    final rest = habit().pauseUntil(today, DateTime(2026, 10, 22));
    final at = habitNextReminder(
      rest,
      const [],
      minutes: 9 * 60,
      now: DateTime(2026, 10, 20, 8),
    );
    expect(at == null ? '' : dateKeyOf(at), '2026-10-23');
  });

  test('a long restored rest does not exhaust the reminder search', () {
    final rest = habit().pauseUntil(today, DateTime(2028, 10, 20));
    final next = habitNextReminder(rest, const [], minutes: 540, now: today);
    expect(next, DateTime(2028, 10, 21, 9));
  });

  test('a check-in rewrite keeps unknown fields and its original moment', () {
    final check = HabitCheck.fromBody('h:2026-10-20', {
      'habit': 'h',
      'date': '2026-10-20',
      'at': '2026-10-20T08:30:00.000',
      'amount': 3,
      'future': 'kept',
    });
    expect(check.extra, {'future': 'kept'});
    expect(check.toJson()['future'], 'kept');
  });

  test('an old weekly record opens weekly, and unknown fields survive', () {
    final h = Habit.fromBody('h', {
      'weekly': true,
      'target': 3,
      'name': 'Gym',
      'future': {'a': 1},
    });
    expect(h.plan, HabitPlan.weekly);
    expect(h.target, 3);
    final again = Habit.fromBody('h', h.toJson());
    expect(again.plan, HabitPlan.weekly);
    expect(again.toJson()['future'], {'a': 1});
  });
}
