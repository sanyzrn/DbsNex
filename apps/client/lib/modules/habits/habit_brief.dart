import 'dart:convert';

import 'package:nex_client/modules/module_api.dart';
import 'habit_math.dart';
import 'habit_model.dart';
import 'week_settings.dart';

/// A bounded projection, computed locally. Notes and raw check-in history
/// never leave this boundary. Only today's relevant habits are included.
class HabitsBrief {
  const HabitsBrief(this.rows);
  static const empty = HabitsBrief([]);
  final List<({Habit habit, HabitStanding standing})> rows;

  static Future<HabitsBrief> read(NexModuleStore store, DateTime now) async {
    final habits =
        (await store.list(
            'habit',
          )).map(Habit.fromRecord).where((h) => !h.archived).toList()
          ..sort((a, b) => a.id.compareTo(b.id));
    if (habits.isEmpty) return empty;
    final byHabit = <String, List<HabitCheck>>{};
    for (final record in await store.list('check')) {
      final check = HabitCheck.fromRecord(record);
      (byHabit[check.habitId] ??= []).add(check);
    }
    final firstDay = readFirstDay(await store.get('settings', 'week'));
    final rows = <({Habit habit, HabitStanding standing})>[];
    for (final habit in habits) {
      final standing = HabitMath.fromChecks(
        habit,
        byHabit[habit.id] ?? const [],
        now,
        firstDay: firstDay,
      );
      if (!standing.dueToday) continue;
      rows.add((habit: habit, standing: standing));
    }
    // Pending goals first; a completed goal may still give useful context.
    rows.sort((a, b) {
      bool pending(Habit h, HabitStanding st) =>
          !st.todayDone && !(h.weekly && st.weekCount >= h.target);
      final done = (pending(a.habit, a.standing) ? 0 : 1).compareTo(
        pending(b.habit, b.standing) ? 0 : 1,
      );
      return done != 0 ? done : a.habit.id.compareTo(b.habit.id);
    });
    return HabitsBrief(rows.take(12).toList());
  }

  String get source => rows
      .map((row) {
        final h = row.habit;
        final s = row.standing;
        String bounded(String value, int length) =>
            value.length <= length ? value : value.substring(0, length);
        return 'today | HABIT | ${jsonEncode({'name': bounded(h.name, 100), 'plan': h.plan.name, if (h.plan == HabitPlan.days) 'weekdays': h.days.toList()..sort(), if (h.plan == HabitPlan.every) 'everyDays': h.every, 'todayAmount': s.todayAmount, 'dailyGoal': h.goal, if (h.unit.isNotEmpty) 'unit': bounded(h.unit, 32), 'doneToday': s.todayDone, 'dueToday': s.dueToday && !(h.weekly && s.weekCount >= h.target), if (h.weekly) 'weekGoalMet': s.weekCount >= h.target, if (h.weekly) 'weekDone': s.weekCount, if (h.weekly) 'weekGoal': h.target, 'consistencyPercent': s.strength})}';
      })
      .join('\n');

  String localText(AppLocalizations l10n) {
    final persian = l10n.localeName.startsWith('fa');
    return rows
        .take(4)
        .map((row) {
          final h = row.habit;
          final s = row.standing;
          final name = h.name.isEmpty ? (persian ? 'عادت' : 'Habit') : h.name;
          final status = h.counted
              ? '${s.todayAmount}/${h.goal} ${h.unit}'
              : h.weekly
              ? '${s.weekCount}/${h.target} ${persian ? 'این هفته' : 'this week'}'
              : s.todayDone
              ? (persian ? 'انجام شد' : 'done')
              : (persian ? 'برای امروز مانده' : 'left for today');
          return nexDigits('$name: $status', persian: persian);
        })
        .join('\n');
  }
}
