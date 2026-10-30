import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'habit_math.dart';
import 'habit_model.dart';
import 'habit_visuals.dart';
import 'module.dart';

/// How a habit's plan reads in a line: «Every day», «Sat · Mon · Wed»,
/// «3 times a week», «Every 2 days».
String habitPlanLine(BuildContext context, Habit habit, int firstDay) {
  final strings = habitsStrings;
  return switch (habit.plan) {
    HabitPlan.daily => strings(context, 'daily'),
    HabitPlan.weekly => strings(
      context,
      habit.target == 1 ? 'oneTarget' : 'targetLabel',
      {'n': habit.target},
    ),
    HabitPlan.days => [
      for (var i = 0; i < 7; i++)
        if (habit.days.contains((firstDay - 1 + i) % 7 + 1))
          strings(context, 'wdShort${(firstDay - 1 + i) % 7 + 1}'),
    ].join(' · '),
    HabitPlan.every => strings(context, 'everyN', {'n': habit.every}),
  };
}

/// One habit on Today: a tile in the habit's own colour, the big mark on
/// its leading edge — a tick, or a ring that fills with the day's amount —
/// and beside it the name, where the habit stands, and its last seven days
/// as a chain.
class HabitTile extends StatelessWidget {
  const HabitTile({
    super.key,
    required this.habit,
    required this.standing,
    required this.logged,
    required this.firstDay,
    required this.busy,
    required this.onMark,
    required this.onAmount,
    required this.onOpen,
  });

  final Habit habit;
  final HabitStanding standing;
  final Map<DateTime, int> logged;
  final int firstDay;
  final bool busy;

  /// The tap on the mark: a tick toggled, or one more of the amount.
  final VoidCallback onMark;

  /// A long press on the mark: the amount sheet.
  final VoidCallback onAmount;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final strings = habitsStrings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = habitColor(context, habit);
    final done = standing.todayDone;
    final persian = NexModuleStrings.persian(context);
    final name = habit.name.isEmpty ? strings(context, 'untitled') : habit.name;

    final String status;
    if (habit.counted) {
      status = strings(context, 'amountProgress', {
        'done': standing.todayAmount,
        'goal': habit.goal,
        'unit': habit.unit.isEmpty ? strings(context, 'unitTimes') : habit.unit,
      });
    } else if (habit.weekly) {
      status = strings(context, 'weekProgress', {
        'done': standing.weekCount,
        'target': habit.target,
      });
    } else {
      status = habitPlanLine(context, habit, firstDay);
    }
    final resting = !standing.dueToday && !done;
    final weekMet = habit.weekly && !done && standing.weekCount >= habit.target;

    final tint = Color.alphaBlend(
      color.withValues(alpha: done ? 0.16 : 0.07),
      scheme.surfaceContainerLow,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: NexSpacing.sm),
      child: Material(
        color: tint,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NexRadius.lg),
          side: BorderSide(color: color.withValues(alpha: done ? 0.45 : 0.18)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('habit-open-${habit.id}'),
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              NexSpacing.sm,
              NexSpacing.sm,
              NexSpacing.md,
              NexSpacing.sm,
            ),
            child: Row(
              children: [
                _Mark(
                  key: ValueKey('habit-today-${habit.id}'),
                  habit: habit,
                  standing: standing,
                  color: color,
                  onTap: busy ? null : onMark,
                  onLongPress: busy || !habit.counted ? null : onAmount,
                ),
                const SizedBox(width: NexSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          decoration: done && !habit.counted
                              ? TextDecoration.lineThrough
                              : null,
                          decorationColor: color,
                          decorationThickness: 2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        resting
                            ? strings(context, 'restToday')
                            : weekMet
                            ? strings(context, 'weekMet')
                            : status,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      if (standing.graceNow && !done && !resting)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            strings(
                              context,
                              habit.weekly ? 'graceNowWeek' : 'graceNowShort',
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: color,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      const SizedBox(height: NexSpacing.xs),
                      HabitChain(habit: habit, logged: logged, color: color),
                    ],
                  ),
                ),
                if (standing.streak >= 2) ...[
                  const SizedBox(width: NexSpacing.sm),
                  Semantics(
                    label: strings(
                      context,
                      habit.weekly ? 'streakWeek' : 'streakDay',
                      {'n': standing.streak},
                    ),
                    excludeSemantics: true,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.local_fire_department_rounded,
                          color: color,
                          size: 22,
                        ),
                        Text(
                          nexDigits('${standing.streak}', persian: persian),
                          key: ValueKey('habit-streak-${habit.id}'),
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: color,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The big mark: the habit's icon inside a ring. A tick fills the circle
/// with the habit's colour and pops a check in; an amount fills the ring
/// a step at a time.
class _Mark extends StatelessWidget {
  const _Mark({
    super.key,
    required this.habit,
    required this.standing,
    required this.color,
    required this.onTap,
    required this.onLongPress,
  });

  final Habit habit;
  final HabitStanding standing;
  final Color color;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final strings = habitsStrings;
    final done = standing.todayDone;
    final progress = habit.counted
        ? standing.todayAmount / habit.goal
        : done
        ? 1.0
        : 0.0;
    final label = habit.counted
        ? strings(context, done ? 'amountDoneHint' : 'addOne', {
            'done': standing.todayAmount,
            'goal': habit.goal,
          })
        : strings(context, done ? 'undoCheckIn' : 'checkIn');
    return Semantics(
      button: true,
      checked: done,
      enabled: onTap != null,
      label: label,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        onLongPress: onLongPress,
        radius: 32,
        child: SizedBox.square(
          dimension: 56,
          child: Center(
            child: HabitRing(
              size: 52,
              stroke: 4,
              color: color,
              track: color.withValues(alpha: 0.22),
              progress: progress,
              child: AnimatedContainer(
                duration: NexMotion.of(context, NexMotion.standard),
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done ? color : color.withValues(alpha: 0.12),
                ),
                child: AnimatedSwitcher(
                  duration: NexMotion.of(context, NexMotion.pop),
                  switchInCurve: NexMotion.popCurve,
                  transitionBuilder: (child, animation) =>
                      ScaleTransition(scale: animation, child: child),
                  child: Icon(
                    done ? Icons.check_rounded : habitIconOf(habit),
                    key: ValueKey(done),
                    size: 22,
                    color: done ? Colors.white : color,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}