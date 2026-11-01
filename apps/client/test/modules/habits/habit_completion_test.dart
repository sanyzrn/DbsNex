import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations_en.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/habits/habit_log.dart';
import 'package:nex_client/modules/habits/habit_math.dart';
import 'package:nex_client/modules/habits/habit_model.dart';
import 'package:nex_client/modules/habits/habit_reminder.dart';
import 'package:nex_client/modules/habits/module.dart';
import 'package:nex_client/modules/habits/record_bundle.dart';

class MemoryHabits implements NexModuleStore {
  final records = <String, Map<String, Map<String, Object?>>>{};
  @override
  Future<Map<String, Object?>?> get(String kind, String id) async =>
      records[kind]?[id];
  @override
  Future<void> put(String kind, String id, Map<String, Object?> body) async {
    records.putIfAbsent(kind, () => {})[id] = Map.of(body);
  }

  @override
  Future<void> delete(String kind, String id) async {
    records[kind]?.remove(id);
  }

  @override
  Future<List<ModuleRecord>> list(String kind) async => [
    for (final e in (records[kind] ?? {}).entries)
      ModuleRecord(
        module: 'habits',
        kind: kind,
        id: e.key,
        body: e.value,
        updatedAt: DateTime(2026, 10, 29),
      ),
  ];
  @override
  Future<bool> setReminder(
    String key, {
    required String sourceKind,
    required String sourceId,
    required DateTime at,
    required String title,
    required String body,
  }) async {
    await put('__reminder', key, {'at': at.toIso8601String()});
    return true;
  }

  @override
  Future<void> clearReminder(String key) => delete('__reminder', key);
  @override
  Future<void> withdrawReminder(String key) => delete('__reminder', key);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final now = DateTime(2026, 10, 29, 10);
  final l10n = AppLocalizationsEn();
  Habit habit({
    String id = 'h',
    String plan = 'daily',
    int goal = 8,
    List<int> days = const [1, 4],
  }) => Habit.fromBody(id, {
    'name': 'Water',
    'schedule': plan,
    'goal': goal,
    'target': 2,
    'days': days,
    'every': 3,
    'createdAt': '2026-10-01T08:00:00',
  });
  HabitCheck check(String day, {int? amount}) => HabitCheck(
    id: 'h:$day',
    habitId: 'h',
    dateKey: day,
    at: now,
    amount: amount,
  );

  test('all screen standings distinguish partial amounts and legacy ticks', () {
    final h = habit();
    final partial = HabitMath.fromChecks(h, [
      check('2026-10-29', amount: 5),
    ], now);
    expect(partial.todayAmount, 5);
    expect(partial.todayDone, isFalse);
    expect(partial.total, 0);
    final legacy = HabitMath.fromChecks(h, [check('2026-10-29')], now);
    expect(legacy.todayAmount, 8);
    expect(legacy.todayDone, isTrue);
  });

  test('partial days do not meet weekly targets in the rate', () {
    final h = habit(plan: 'weekly');
    final keys = ['2026-10-19', '2026-10-20'];
    expect(
      HabitMath.weeklyRate(
        h,
        keys,
        now,
        amounts: {for (final key in keys) key: 4},
      ).done,
      0,
    );
    expect(
      HabitMath.weeklyRate(
        h,
        keys,
        now,
        amounts: {for (final key in keys) key: 8},
      ).done,
      1,
    );
  });

  test('reminders skip off days and days whose amount reached the goal', () {
    final h = habit(plan: 'days');
    expect(
      habitNextReminder(h, [], minutes: 1200, now: now),
      DateTime(2026, 10, 29, 20),
    );
    expect(
      habitNextReminder(
        h,
        [check('2026-10-29', amount: 8)],
        minutes: 1200,
        now: now,
      ),
      DateTime(2026, 11, 2, 20),
    );
    expect(
      habitNextReminder(habit(plan: 'every'), [], minutes: 1200, now: now),
      DateTime(2026, 10, 31, 20),
    );
  });

  test('a met weekly target waits until the next week', () {
    final h = habit(plan: 'weekly');
    expect(
      habitNextReminder(
        h,
        [check('2026-10-25'), check('2026-10-27')],
        minutes: 1200,
        now: now,
      ),
      DateTime(2026, 10, 31, 20),
    );
  });

  test(
    'daily legacy reminder migrates before replacement and survives rearming',
    () async {
      final store = MemoryHabits();
      final h = habit();
      await store.put('__reminder', 'habit:h', {
        'repeat': 'daily',
        'at': now.toIso8601String(),
      });
      await habitArmReminder(store, l10n, h, now: now);
      expect((await store.get('remind', 'h'))?['on'], isTrue);
      expect((await store.get('__reminder', 'habit:h'))?['repeat'], isNull);
      await habitArmReminder(
        store,
        l10n,
        h,
        now: now.add(const Duration(days: 1)),
      );
      expect(await store.get('__reminder', 'habit:h'), isNotNull);
      await habitArmReminder(
        store,
        l10n,
        Habit.fromBody('h', h.toJson()..['archived'] = true),
        now: now,
      );
      expect(await store.get('__reminder', 'habit:h'), isNull);
      expect((await store.get('remind', 'h'))?['on'], isTrue);
      await habitArmReminder(store, l10n, h, now: now);
      expect(await store.get('__reminder', 'habit:h'), isNotNull);
    },
  );

  test(
    'clear and Undo restore the exact amount record, including unknown fields',
    () async {
      final store = MemoryHabits();
      final h = habit();
      final body = {
        'habit': 'h',
        'date': '2026-10-29',
        'amount': 5,
        'future': 'keep',
      };
      await store.put('check', 'h:2026-10-29', body);
      final log = HabitLog(store, l10n);
      final previous = await log.setAmount(h, '2026-10-29', 0);
      expect(await store.get('check', 'h:2026-10-29'), isNull);
      await log.restore(h, '2026-10-29', previous);
      expect(await store.get('check', 'h:2026-10-29'), body);
    },
  );

  test(
    'delete and Undo include history, draft and reminder preference',
    () async {
      final store = MemoryHabits();
      await store.put('habit', 'h', habit().toJson());
      await store.put('remind', 'h', {'on': true, 'minutes': 1200});
      await store.put('draft', 'habit:h', {'name': 'Unsaved'});
      await store.put('check', 'h:2026-10-29', {'habit': 'h', 'amount': 5});
      final bundle = await RecordBundle.capture(
        store,
        'habit',
        'h',
        'check',
        'habit',
      );
      await bundle.delete();
      expect(await store.get('remind', 'h'), isNull);
      await bundle.restore();
      expect((await store.get('remind', 'h'))?['minutes'], 1200);
      expect((await store.get('draft', 'habit:h'))?['name'], 'Unsaved');
      expect((await store.get('check', 'h:2026-10-29'))?['amount'], 5);
    },
  );

  test('local brief counts only active, unfinished habits due today', () async {
    final store = MemoryHabits();
    final day = dateKeyOf(DateTime.now());
    await store.put('habit', 'h', habit().toJson());
    await store.put('habit', 'a', habit(id: 'a').toJson()..['archived'] = true);
    const module = HabitsModule();
    expect(await module.briefLine(store, l10n), '1 habit left for today');
    await store.put('check', 'h:$day', {
      'habit': 'h',
      'date': day,
      'amount': 5,
    });
    expect(await module.briefLine(store, l10n), '1 habit left for today');
    await store.put('check', 'h:$day', {
      'habit': 'h',
      'date': day,
      'amount': 8,
    });
    expect(await module.briefLine(store, l10n), isNull);
  });
}
