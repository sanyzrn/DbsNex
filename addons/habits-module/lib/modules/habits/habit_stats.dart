import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'habit_math.dart';
import 'habit_model.dart';
import 'module.dart';

/// The streak, said plainly: the number, what a grace state means, and for
/// a weekly habit, this week's dots toward the target.
class HabitStreakPanel extends StatelessWidget {
  const HabitStreakPanel({
    super.key,
    required this.habit,
    required this.standing,
  });

  final Habit habit;
  final HabitStanding standing;

  @override
  Widget build(BuildContext context) {
    final strings = habitsStrings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final streakLabel = standing.streak == 0
        ? strings(context, standing.total == 0 ? 'noCheckins' : 'freshStreak')
        : strings(context, habit.weekly ? 'streakWeek' : 'streakDay', {
            'n': standing.streak,
          });
    return NexPanel(
      title: strings(context, 'schedule'),
      icon: habit.weekly ? Icons.date_range_outlined : Icons.today_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            streakLabel,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (standing.total > 0) ...[
            const SizedBox(height: NexSpacing.xs),
            Text(
              strings(context, 'totalCheckins', {'n': standing.total}),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          if (standing.graceInside) ...[
            const SizedBox(height: NexSpacing.xs),
            Text(
              strings(
                context,
                habit.weekly ? 'graceInsideWeek' : 'graceInside',
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          if (standing.graceNow) ...[
            const SizedBox(height: NexSpacing.xs),
            Text(
              strings(context, habit.weekly ? 'graceNowWeek' : 'graceNow'),
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.primary),
            ),
          ],
          if (habit.weekly) ...[
            const SizedBox(height: NexSpacing.md),
            HabitWeekDots(habit: habit, standing: standing),
          ],
        ],
      ),
    );
  }
}

/// This week's check-ins against the target — each mark a day, the row the
/// week so far. The dots answer "how many more?" without a number hunt.
class HabitWeekDots extends StatelessWidget {
  const HabitWeekDots({super.key, required this.habit, required this.standing});

  final Habit habit;
  final HabitStanding standing;

  @override
  Widget build(BuildContext context) {
    final strings = habitsStrings;
    final scheme = Theme.of(context).colorScheme;
    final color = scheme.primary;
    return Semantics(
      label: strings(context, 'weekProgress', {
        'done': standing.weekCount,
        'target': habit.target,
      }),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: NexSpacing.sm,
            runSpacing: NexSpacing.sm,
            children: [
              for (var i = 0; i < habit.target; i++)
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < standing.weekCount
                        ? color
                        : scheme.surfaceContainerHighest,
                  ),
                ),
            ],
          ),
          const SizedBox(height: NexSpacing.xs),
          Text(
            strings(context, 'weekProgress', {
              'done': standing.weekCount,
              'target': habit.target,
            }),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// The last fourteen days as one quiet row of marks — the shape of the
/// habit at a glance, and the honest version of what the streak rests on.
class HabitTwoWeekDots extends StatelessWidget {
  const HabitTwoWeekDots({super.key, required this.standing});

  final HabitStanding standing;

  @override
  Widget build(BuildContext context) {
    final strings = habitsStrings;
    final scheme = Theme.of(context).colorScheme;
    final color = scheme.primary;
    final done = standing.recent.where((d) => d).length;
    return NexPanel(
      title: strings(context, 'recentDays', {'n': HabitMath.recentDays}),
      icon: Icons.calendar_view_week_outlined,
      child: Semantics(
        label: strings(context, 'recentSummary', {
          'done': done,
          'n': HabitMath.recentDays,
        }),
        child: Wrap(
          spacing: NexSpacing.sm,
          runSpacing: NexSpacing.sm,
          children: [
            for (final wasDone in standing.recent)
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: wasDone ? color : scheme.surfaceContainerHighest,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class HabitNotePanel extends StatelessWidget {
  const HabitNotePanel({super.key, required this.note});

  final String note;

  @override
  Widget build(BuildContext context) => NexPanel(
    icon: Icons.notes_outlined,
    child: NexTextDirection(
      text: note,
      child: Text(note, style: Theme.of(context).textTheme.bodyMedium),
    ),
  );
}

/// Recent check-ins as honest relative dates — today, yesterday, N days
/// ago. No calendar is drawn that the platform cannot honestly draw.
class HabitHistory extends StatelessWidget {
  const HabitHistory({super.key, required this.checks});

  final List<HabitCheck> checks;

  @override
  Widget build(BuildContext context) {
    final strings = habitsStrings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final checks = this.checks
        .where(
          (c) =>
              tryParseDateKey(c.dateKey) != null &&
              daysBetweenKeys(c.dateKey, dateKeyOf(DateTime.now())) >= 0,
        )
        .toList();
    if (checks.isEmpty) {
      // The streak panel above already says there are no check-ins; here
      // only the encouragement remains, so the page never repeats itself.
      return Padding(
        padding: const EdgeInsetsDirectional.all(NexSpacing.md),
        child: Text(
          strings(context, 'firstCheckin'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return Column(
      children: [
        for (final (index, check) in checks.take(20).indexed)
          NexGroupedRow(
            index: index,
            count: checks.take(20).length,
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.check_circle_outline, size: 20),
              title: Text(_relative(check.dateKey, strings, context)),
              trailing: Text(
                strings(context, 'totalCheckins', {
                  'n': checks.where((c) => c.dateKey == check.dateKey).length,
                }),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
      ],
    );
  }

  String _relative(
    String dateKey,
    NexModuleStrings strings,
    BuildContext context,
  ) {
    final days = daysBetweenKeys(dateKey, dateKeyOf(DateTime.now()));
    if (days == 0) return strings(context, 'today');
    if (days == 1) return strings(context, 'yesterday');
    return strings(context, 'daysAgo', {'n': days});
  }
}
