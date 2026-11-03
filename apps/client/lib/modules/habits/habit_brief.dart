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

  String localText(
    AppLocalizations l10n, {
    bool includeCompleted = false,
    int maxWords = 28,
  }) {
    final persian = l10n.localeName.startsWith('fa');
    String describe(({Habit habit, HabitStanding standing}) row) {
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
    }

    if (includeCompleted) return rows.take(4).map(describe).join('\n');

    // Action-oriented briefs do not spend rows on routine daily completions.
    final pending = rows.where(
      (row) =>
          !row.standing.todayDone &&
          !(row.habit.weekly && row.standing.weekCount >= row.habit.target),
    );
    final lines = pending.take(4).map(describe).toList();
    final milestones = rows.where(
      (row) => row.habit.weekly && row.standing.weekCount >= row.habit.target,
    );
    if (lines.length < 4 && milestones.isNotEmpty) {
      // One combined, bounded acknowledgement, after pending actions.
      final phrase = milestones.take(2).map(describe).join(' · ');
      final words = phrase.split(RegExp(r'\s+'));
      lines.add(
        words.length <= maxWords
            ? phrase
            : '${words.take(maxWords).join(' ')}…',
      );
    }
    return lines.join('\n');
  }
}
