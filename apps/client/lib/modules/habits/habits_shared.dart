import 'package:nex_client/modules/module_api.dart';

import 'habit_math.dart';
import 'habit_model.dart';
import 'module.dart' show habitsStrings;
import 'week_settings.dart';

/// Habits in the shared shape (2.8.5), and its glance.
///
/// What falls due is a habit still to do today. A day gone by is not owed —
/// a missed day costs nothing here — so only today is ever given.
class HabitsShared {
  const HabitsShared(this.habits, this.checks, {required this.firstDay});

  final List<Habit> habits;
  final List<HabitCheck> checks;
  final int firstDay;

  static Future<HabitsShared> load(NexModuleStore store) async => HabitsShared(
    (await store.list('habit')).map(Habit.fromRecord).toList(),
    (await store.list('check')).map(HabitCheck.fromRecord).toList(),
    firstDay: readFirstDay(await store.get('settings', 'week')),
  );

  ({List<Habit> left, List<Habit> done}) today(DateTime now) {
    final left = <Habit>[], done = <Habit>[];
    for (final habit in habits.where((h) => !h.archived)) {
      final s = HabitMath.fromChecks(
        habit,
        checks.where((c) => c.habitId == habit.id),
        now,
        firstDay: firstDay,
      );
      if (s.todayDone) {
        done.add(habit);
      } else if (s.dueToday && !(habit.weekly && s.weekCount >= habit.target)) {
        left.add(habit);
      }
    }
    return (left: left, done: done);
  }

  /// Everything this module has falling due between [from] and [to]: the
  /// habits left today, when today is in the range.
  List<ModuleDue> duesBetween(DateTime from, DateTime to, {DateTime? now}) {
    final at = now ?? DateTime.now();
    final day = DateTime(at.year, at.month, at.day);
    if (day.isBefore(DateTime(from.year, from.month, from.day)) ||
        day.isAfter(to)) {
      return const [];
    }
    return [
      for (final habit in today(at).left)
        ModuleDue(
          id: 'habit:${habit.id}:${day.toIso8601String().substring(0, 10)}',
          recordKind: 'habit',
          recordId: habit.id,
          at: day,
          title: habit.name,
          kind: 'habit',
        ),
    ];
  }

  /// One line about [record], in the person's own words; null to keep it out.
  static ModuleSummary? summarize(ModuleRecord record) {
    if (record.kind != 'habit') return null;
    final habit = Habit.fromRecord(record);
    if (habit.name.trim().isEmpty || habit.archived) return null;
    return ModuleSummary(title: habit.name.trim());
  }
}

/// The pinned tile and quick view of Habits (2.8.5): done out of today's on
/// the tile, with a ring; each habit's state today in the quick view.
Future<ModuleGlance?> habitsGlance(
  NexModuleStore store,
  AppLocalizations l10n,
  DateTime now,
) async {
  String t(String key, [Map<String, Object?> args = const {}]) =>
      habitsStrings.text(l10n, key, args);
  final shared = await HabitsShared.load(store);
  if (shared.habits.every((h) => h.archived)) {
    return ModuleGlance(headline: l10n.pinHabitsEmpty);
  }
  final (:left, :done) = shared.today(now);
  final total = left.length + done.length;
  if (total == 0) return ModuleGlance(headline: l10n.pinHabitsRest);
  return ModuleGlance(
    headline: l10n.pinHabitsProgress(done.length, total),
    detail: left.isEmpty ? l10n.pinHabitsRest : l10n.pinHabitsLeft(left.length),
    progress: done.length / total,
    facts: [
      for (final habit in left) ModuleGlanceFact(habit.name, t('glanceLeft')),
      for (final habit in done)
        ModuleGlanceFact(habit.name, t('glanceDone'), strong: true),
    ],
  );
}
