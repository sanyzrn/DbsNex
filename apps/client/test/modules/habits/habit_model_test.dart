import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/habits/habit_model.dart';

ModuleRecord record(
  String id,
  Map<String, Object?> body, {
  DateTime? updatedAt,
}) => ModuleRecord(
  module: 'habits',
  kind: 'habit',
  id: id,
  body: body,
  updatedAt: updatedAt ?? DateTime(2026, 10, 12),
);

void main() {
  group('Habit.fromRecord', () {
    test('reads a well-formed record', () {
      final habit = Habit.fromRecord(
        record('h1', {
          'name': 'Stretch',
          'note': 'before coffee',
          'schedule': 'weekly',
          'target': 3,
          'archived': true,
          'createdAt': '2026-09-01T08:00:00.000',
        }),
      );
      expect(habit.id, 'h1');
      expect(habit.name, 'Stretch');
      expect(habit.note, 'before coffee');
      expect(habit.weekly, isTrue);
      expect(habit.target, 3);
      expect(habit.archived, isTrue);
      expect(habit.createdAt, DateTime.parse('2026-09-01T08:00:00.000'));
    });

    test('missing fields read as their defaults, not as a crash', () {
      final habit = Habit.fromRecord(record('h1', {}));
      expect(habit.name, '');
      expect(habit.note, '');
      expect(habit.weekly, isFalse);
      expect(habit.target, 1);
      expect(habit.archived, isFalse);
      expect(habit.createdAt.year, 1970);
    });

    test('wrong-typed fields read as their defaults', () {
      final habit = Habit.fromRecord(
        record('h1', {
          'name': 42,
          'note': true,
          'schedule': 'sometimes',
          'target': 'many',
          'archived': 'yes',
          'createdAt': 'not a date',
        }),
      );
      expect(habit.name, '');
      expect(habit.note, '');
      expect(habit.weekly, isFalse);
      expect(habit.target, 1);
      expect(habit.archived, isFalse);
      expect(habit.createdAt.year, 1970);
    });

    test('a weekly target outside 1–7 is clamped', () {
      expect(
        Habit.fromBody('a', {'schedule': 'weekly', 'target': 0}).target,
        1,
      );
      expect(
        Habit.fromBody('a', {'schedule': 'weekly', 'target': 12}).target,
        7,
      );
      expect(
        Habit.fromBody('a', {'schedule': 'weekly', 'target': -3}).target,
        1,
      );
    });

    test('toJson round-trips through fromBody', () {
      final habit = Habit(
        id: 'h1',
        name: 'Stretch',
        note: '',
        weekly: true,
        target: 4,
        archived: false,
        createdAt: DateTime(2026, 9, 1, 8),
      );
      final again = Habit.fromBody('h1', habit.toJson());
      expect(again.name, habit.name);
      expect(again.weekly, isTrue);
      expect(again.target, 4);
      expect(again.archived, isFalse);
      expect(again.createdAt, habit.createdAt);
    });

    test('withFields keeps the identity fields', () {
      final habit = Habit(
        id: 'h1',
        name: 'A',
        note: 'n',
        weekly: false,
        target: 1,
        archived: true,
        createdAt: DateTime(2026, 9, 1),
      );
      final edited = habit.withFields(name: 'B', weekly: true, target: 5);
      expect(edited.id, 'h1');
      expect(edited.archived, isTrue, reason: 'editing never un-archives');
      expect(edited.createdAt, habit.createdAt);
      expect(edited.name, 'B');
      expect(edited.weekly, isTrue);
      expect(edited.target, 5);
    });
  });

  group('HabitCheck', () {
    test('reads a well-formed check-in', () {
      final check = HabitCheck.fromRecord(
        record('h1:2026-10-12', {
          'habit': 'h1',
          'date': '2026-10-12',
          'at': '2026-10-12T08:30:00.000',
        }),
      );
      expect(check.habitId, 'h1');
      expect(check.dateKey, '2026-10-12');
      expect(check.at, DateTime.parse('2026-10-12T08:30:00.000'));
    });

    test('a malformed date is unknown and never invents a check-in', () {
      final check = HabitCheck.fromRecord(
        record('x', {'habit': 'h1', 'date': 'garbage', 'at': 'also garbage'}),
      );
      expect(check.dateKey, '');
      expect(check.at.year, 1970);
    });

    test('a full ISO timestamp still yields its civil date', () {
      final check = HabitCheck.fromRecord(
        record('x', {
          'habit': 'h1',
          'date': '2026-10-12T23:59:00.000',
          'at': '2026-10-12T23:59:00.000',
        }),
      );
      expect(check.dateKey, '2026-10-12');
    });

    test('the id of a day’s check-in is the habit and the date', () {
      expect(HabitCheck.idFor('h1', '2026-10-12'), 'h1:2026-10-12');
    });

    test('toJson writes the fields the reader reads', () {
      final check = HabitCheck(
        id: 'h1:2026-10-12',
        habitId: 'h1',
        dateKey: '2026-10-12',
        at: DateTime(2026, 10, 12, 8, 30),
      );
      final body = check.toJson();
      expect(body['habit'], 'h1');
      expect(body['date'], '2026-10-12');
      expect(body['at'], contains('2026-10-12T08:30'));
    });
  });

  group('date keys', () {
    test('zero-padded civil dates', () {
      expect(dateKeyOf(DateTime(2026, 3, 7)), '2026-03-07');
      expect(dateKeyOf(DateTime(2026, 12, 31, 23, 59)), '2026-12-31');
    });

    test('parsing accepts real dates only', () {
      expect(tryParseDateKey('2026-10-12'), DateTime.utc(2026, 10, 12));
      expect(
        tryParseDateKey('2026-02-29'),
        isNull,
        reason: '2026 is not a leap year',
      );
      expect(tryParseDateKey('2024-02-29'), DateTime.utc(2024, 2, 29));
      expect(
        tryParseDateKey('2026-02-30'),
        isNull,
        reason: 'Dart would roll it into March',
      );
      expect(tryParseDateKey('2026-13-01'), isNull);
      expect(tryParseDateKey('garbage'), isNull);
      expect(
        tryParseDateKey('2026-10-12T08:00'),
        isNull,
        reason: 'keys are dates, not instants',
      );
    });

    test('whole civil days between keys, signed', () {
      expect(daysBetweenKeys('2026-10-01', '2026-10-12'), 11);
      expect(daysBetweenKeys('2026-10-12', '2026-10-12'), 0);
      expect(daysBetweenKeys('2026-10-12', '2026-10-01'), -11);
      expect(daysBetweenKeys('garbage', '2026-10-12'), 0);
    });
  });
}
