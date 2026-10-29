import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/habits/habit_math.dart';
import 'package:nex_client/modules/habits/habit_model.dart';

/// Habits 2.0 (2.4.0): chosen days, every N days, amount goals, the strength
/// score and the best streak.
void main() {
  String key(DateTime d) => dateKeyOf(d);
  Habit habit({
    HabitPlan plan = HabitPlan.daily,
    Set<int> days = const {},
    int every = 2,
    int goal = 1,
  }) => Habit(
    id: 'h',
    name: 'H',
    note: '',
    weekly: plan == HabitPlan.weekly,
    target: plan == HabitPlan.weekly ? 3 : 1,
    archived: false,
    createdAt: DateTime(2026, 10, 1),
    plan: plan,
    days: days,
    every: every,
    goal: goal,
  );
  // Tuesday 20 October 2026.
  final today = DateTime(2026, 10, 20);

  group('the record', () {
    test('a version-1 record reads as before; v2 fields round-trip', () {
      final old = Habit.fromBody('a', {
        'name': 'Walk',
        'schedule': 'daily',
        'target': 1,
        'createdAt': '2026-10-01T08:00:00',
      });
      expect(old.plan, HabitPlan.daily);
      expect(old.goal, 1);
      expect(old.counted, isFalse);

      final full = Habit.fromBody('b', {
        'name': 'Water',
        'schedule': 'days',
        'days': [1, 3, 9],
        'goal': 8,
        'unit': 'glasses',
        'icon': 'water',
        'hue': 3,
        'createdAt': '2026-10-01T08:00:00',
      });
      expect(full.plan, HabitPlan.days);
      expect(full.days, {1, 3});
      expect(full.goal, 8);
      expect(Habit.fromBody('b', full.toJson()).unit, 'glasses');
      expect(Habit.fromBody('b', full.toJson()).days, {1, 3});
    });

    test('chosen days with none chosen is every day', () {
      final h = Habit.fromBody('c', {'schedule': 'days', 'days': <int>[]});
      expect(h.plan, HabitPlan.daily);
    });

    test('a check-in without an amount is a whole day done', () {
      final check = HabitCheck(
        id: 'h:2026-10-20',
        habitId: 'h',
        dateKey: '2026-10-20',
        at: _epoch,
      );
      expect(check.progressFor(8), 8);
    });
  });

  group('due days', () {
    test('every N days counts from the day it began', () {
      final h = habit(plan: HabitPlan.every, every: 3);
      expect(HabitMath.dueOn(h, DateTime(2026, 10, 1)), isTrue);
      expect(HabitMath.dueOn(h, DateTime(2026, 10, 2)), isFalse);
      expect(HabitMath.dueOn(h, DateTime(2026, 10, 4)), isTrue);
      expect(HabitMath.dueOn(h, DateTime(2026, 9, 28)), isFalse);
    });

    test('a day off is neither kept nor missed in a streak', () {
      // Monday, Wednesday, Friday.
      final h = habit(
        plan: HabitPlan.days,
        days: const {DateTime.monday, DateTime.wednesday, DateTime.friday},
      );
      // Kept 12, 14, 16 and 19 October; the weekend between is not theirs.
      final s = HabitMath.standing(h, [
        for (final d in [12, 14, 16, 19]) key(DateTime(2026, 10, d)),
      ], today);
      expect(s.dueToday, isFalse);
      expect(s.streak, 4);
      expect(s.graceNow, isFalse);
    });
  });

  group('amounts', () {
    test('a day short of its amount is partly done, not done', () {
      final h = habit(goal: 8);
      final s = HabitMath.standing(
        h,
        [key(today)],
        today,
        amounts: {key(today): 5},
      );
      expect(s.todayDone, isFalse);
      expect(s.todayAmount, 5);
      expect(
        HabitMath.dayState(
          h,
          today,
          HabitMath.loggedDays(h, const [], today)
            ..[DateTime.utc(2026, 10, 20)] = 5,
          today,
        ),
        HabitDayState.partial,
      );
    });

    test('reaching the amount completes the day', () {
      final h = habit(goal: 8);
      final s = HabitMath.standing(
        h,
        [key(today)],
        today,
        amounts: {key(today): 8},
      );
      expect(s.todayDone, isTrue);
    });
  });

  group('strength and best', () {
    test('one missed day lowers strength a little, never to zero', () {
      final h = habit();
      final kept = [
        for (var d = 1; d <= 19; d++)
          if (d != 15) key(DateTime(2026, 10, d)),
      ];
      final all = [for (var d = 1; d <= 19; d++) key(DateTime(2026, 10, d))];
      final withMiss = HabitMath.strength(h, kept, today);
      final perfect = HabitMath.strength(h, all, today);
      expect(withMiss, lessThan(perfect));
      expect(withMiss, greaterThan(perfect - 15));
      expect(withMiss, greaterThan(0));
    });

    test('today still to do does not count against it', () {
      final h = habit();
      final days = [for (var d = 1; d <= 19; d++) key(DateTime(2026, 10, d))];
      expect(
        HabitMath.strength(h, days, today),
        HabitMath.strength(h, days, DateTime(2026, 10, 19)),
      );
    });

    test('the best streak remembers an earlier, longer run', () {
      final h = habit();
      final days = [
        for (var d = 1; d <= 10; d++) key(DateTime(2026, 10, d)),
        key(DateTime(2026, 10, 19)),
        key(DateTime(2026, 10, 20)),
      ];
      final s = HabitMath.standing(h, days, today);
      expect(s.streak, 2);
      expect(s.best, 10);
    });
  });

  test('missed, off, pending and future days are told apart', () {
    final h = habit(
      plan: HabitPlan.days,
      days: const {DateTime.monday, DateTime.tuesday},
    );
    final logged = <DateTime, int>{};
    expect(
      HabitMath.dayState(h, DateTime(2026, 10, 19), logged, today),
      HabitDayState.missed,
    );
    expect(
      HabitMath.dayState(h, DateTime(2026, 10, 18), logged, today),
      HabitDayState.off,
    );
    expect(HabitMath.dayState(h, today, logged, today), HabitDayState.pending);
    expect(
      HabitMath.dayState(h, DateTime(2026, 10, 26), logged, today),
      HabitDayState.future,
    );
    expect(
      HabitMath.dayState(h, DateTime(2026, 9, 28), logged, today),
      HabitDayState.off,
      reason: 'before it began',
    );
  });
}

final _epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
