import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/habits/habit_math.dart';
import 'package:nex_client/modules/habits/habit_model.dart';
import 'package:nex_client/modules/habits/week_settings.dart';

void main() {
  Habit habit({bool weekly = false}) => Habit(
    id: 'h',
    name: 'Walk',
    note: '',
    weekly: weekly,
    target: 1,
    archived: false,
    createdAt: DateTime(2026),
  );
  test('each of seven start days defines exactly one stable civil week', () {
    for (var first = 1; first <= 7; first++) {
      final start = HabitMath.weekStartOf(
        DateTime.utc(2026, 10, 12),
        firstDay: first,
      );
      expect(start.weekday, first);
      for (var offset = 0; offset < 7; offset++) {
        expect(
          HabitMath.weekStartOf(
            start.add(Duration(days: offset)),
            firstDay: first,
          ),
          start,
        );
      }
    }
    expect(readFirstDay(null), DateTime.saturday);
    expect(readFirstDay({'firstDay': 9}), DateTime.saturday);
    expect(readFirstDay({'firstDay': 1}), DateTime.monday);
  });
  test('separated missed days consume one grace in the whole run', () {
    final result = HabitMath.standing(habit(), [
      '2026-10-06',
      '2026-10-08',
      '2026-10-10',
    ], DateTime(2026, 10, 10));
    expect(result.streak, 2);
    expect(result.graceInside, isTrue);
  });
  test('outstanding grace cannot also forgive an earlier gap', () {
    final result = HabitMath.standing(habit(), [
      '2026-10-06',
      '2026-10-08',
      '2026-10-09',
    ], DateTime(2026, 10, 11));
    expect(result.streak, 2);
    expect(result.graceNow, isTrue);
    expect(result.graceInside, isFalse);
  });
  test('weekly grace uses the same single-gap policy', () {
    final result = HabitMath.standing(habit(weekly: true), [
      '2026-09-12',
      '2026-09-26',
      '2026-10-10',
    ], DateTime(2026, 10, 10));
    expect(result.streak, 2);
    expect(result.graceInside, isTrue);
  });
  test('changing week start changes grouping and keeps all check-ins', () {
    final dates = ['2026-10-11', '2026-10-12'];
    final monday = HabitMath.standing(
      habit(weekly: true),
      dates,
      DateTime(2026, 10, 12),
      firstDay: 1,
    );
    final sunday = HabitMath.standing(
      habit(weekly: true),
      dates,
      DateTime(2026, 10, 12),
      firstDay: 7,
    );
    expect(monday.weekCount, 1);
    expect(monday.streak, 2);
    expect(sunday.weekCount, 2);
    expect(sunday.streak, 1);
    expect(monday.total, sunday.total);
  });
}
