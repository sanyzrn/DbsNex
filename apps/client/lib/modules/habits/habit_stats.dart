import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'habit_math.dart';
import 'habit_model.dart';
import 'habit_row.dart';
import 'habit_visuals.dart';
import 'module.dart';

/// The top of a habit's page (2.4.0): its mark and name on its own colour,
/// the plan in a line, the streak as the big number, and its strength as a
/// ring beside it.
class HabitHero extends StatelessWidget {
  const HabitHero({
    super.key,
    required this.habit,
    required this.standing,
    required this.firstDay,
  });

  final Habit habit;
  final HabitStanding standing;
  final int firstDay;

  @override
  Widget build(BuildContext context) {
    final strings = habitsStrings;
    final theme = Theme.of(context);
    final persian = NexModuleStrings.persian(context);
    final hue = habitHueOf(habit);
    const white = Colors.white;
    final name = habit.name.isEmpty ? strings(context, 'untitled') : habit.name;
    final plan = habitPlanLine(context, habit, firstDay);
    final goal = habit.counted
        ? ' · ${strings(context, 'goalLine', {'goal': habit.goal, 'unit': habit.unit.isEmpty ? strings(context, 'unitTimes') : habit.unit})}'
        : '';
    final streakLabel = standing.streak == 0
        ? strings(context, standing.total == 0 ? 'noCheckins' : 'freshStreak')
        : strings(context, habit.weekly ? 'streakWeek' : 'streakDay', {
            'n': standing.streak,
          });
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [hue.deep, Color.lerp(hue.deep, hue.base, 0.55)!],
        ),
        borderRadius: BorderRadius.circular(NexRadius.xl),
        boxShadow: [
          BoxShadow(
            color: hue.deep.withValues(alpha: 0.3),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(NexRadius.xl),
        child: Stack(
          children: [
            PositionedDirectional(
              end: -18,
              top: -18,
              child: Icon(
                habitIconOf(habit),
                size: 132,
                color: white.withValues(alpha: 0.08),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(NexSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: white.withValues(alpha: 0.18),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(NexSpacing.sm),
                          child: Icon(habitIconOf(habit), color: white),
                        ),
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
                              style: theme.textTheme.titleLarge?.copyWith(
                                color: white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              '$plan$goal',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: white.withValues(alpha: 0.85),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: NexSpacing.lg),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.local_fire_department_rounded,
                                  color: white,
                                  size: 28,
                                ),
                                const SizedBox(width: NexSpacing.xs),
                                Flexible(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: AlignmentDirectional.centerStart,
                                    child: Text(
                                      nexDigits(
                                        '${standing.streak}',
                                        persian: persian,
                                      ),
                                      style: theme.textTheme.displaySmall
                                          ?.copyWith(
                                            color: white,
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              streakLabel,
                              key: const ValueKey('habit-streak-label'),
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: white,
                              ),
                            ),
                            if (standing.graceNow)
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: NexSpacing.xs,
                                ),
                                child: Text(
                                  strings(
                                    context,
                                    habit.weekly ? 'graceNowWeek' : 'graceNow',
                                  ),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: white.withValues(alpha: 0.92),
                                  ),
                                ),
                              )
                            else if (standing.graceInside)
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: NexSpacing.xs,
                                ),
                                child: Text(
                                  strings(
                                    context,
                                    habit.weekly
                                        ? 'graceInsideWeek'
                                        : 'graceInside',
                                  ),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: white.withValues(alpha: 0.85),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Semantics(
                        label: strings(context, 'strengthSays', {
                          'n': standing.strength,
                        }),
                        excludeSemantics: true,
                        child: Column(
                          children: [
                            HabitRing(
                              size: 76,
                              stroke: 7,
                              color: white,
                              track: white.withValues(alpha: 0.22),
                              progress: standing.strength / 100,
                              child: Text(
                                nexDigits(
                                  '${standing.strength}%',
                                  persian: persian,
                                ),
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(height: NexSpacing.xs),
                            Text(
                              strings(context, 'strength'),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: white.withValues(alpha: 0.85),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (habit.weekly) ...[
                    const SizedBox(height: NexSpacing.md),
                    _WeekDots(habit: habit, standing: standing),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// This week's check-ins against the target, on the hero.
class _WeekDots extends StatelessWidget {
  const _WeekDots({required this.habit, required this.standing});

  final Habit habit;
  final HabitStanding standing;

  @override
  Widget build(BuildContext context) {
    const white = Colors.white;
    final text = habitsStrings(context, 'weekProgress', {
      'done': standing.weekCount,
      'target': habit.target,
    });
    return Row(
      children: [
        for (var i = 0; i < habit.target; i++)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 6),
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < standing.weekCount
                    ? white
                    : white.withValues(alpha: 0.25),
              ),
            ),
          ),
        const SizedBox(width: NexSpacing.xs),
        Flexible(
          child: Text(
            text,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: white),
          ),
        ),
      ],
    );
  }
}

/// Three numbers under the hero: the best streak, how many days kept, and
/// the last thirty days (or finished weeks) as a share.
class HabitStatTiles extends StatelessWidget {
  const HabitStatTiles({
    super.key,
    required this.habit,
    required this.standing,
    required this.dateKeys,
    required this.amounts,
    required this.firstDay,
    required this.color,
  });

  final Habit habit;
  final HabitStanding standing;
  final List<String> dateKeys;
  final Map<String, int> amounts;
  final int firstDay;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final strings = habitsStrings;
    final persian = NexModuleStrings.persian(context);
    final now = DateTime.now();
    final rate = habit.weekly
        ? HabitMath.weeklyRate(habit, dateKeys, now, firstDay: firstDay, amounts: amounts)
        : HabitMath.dailyRate(habit, dateKeys, now, 30, amounts: amounts);
    String digits(Object v) => nexDigits('$v', persian: persian);
    return Row(
      children: [
        Expanded(
          child: _Stat(
            key: const ValueKey('habit-stat-best'),
            icon: Icons.emoji_events_rounded,
            color: color,
            value: digits(standing.best),
            label: strings(context, habit.weekly ? 'bestWeeks' : 'bestDays'),
          ),
        ),
        const SizedBox(width: NexSpacing.sm),
        Expanded(
          child: _Stat(
            key: const ValueKey('habit-stat-total'),
            icon: Icons.check_circle_rounded,
            color: color,
            value: digits(standing.total),
            label: strings(context, 'totalKept'),
          ),
        ),
        const SizedBox(width: NexSpacing.sm),
        Expanded(
          child: _Stat(
            key: const ValueKey('habit-stat-rate'),
            icon: Icons.insights_rounded,
            color: color,
            value: rate.possible == 0 ? '–' : digits('${rate.percent}%'),
            label: strings(context, habit.weekly ? 'rate12Weeks' : 'rate30'),
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    super.key,
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      container: true,
      label: '$label: $value',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            color.withValues(alpha: 0.08),
            scheme.surfaceContainerLow,
          ),
          borderRadius: BorderRadius.circular(NexRadius.lg),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: NexSpacing.sm,
            vertical: NexSpacing.md,
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(height: NexSpacing.xs),
              Text(
                value,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sixteen weeks of the habit as one picture, with the key to its marks.
class HabitSeasonPanel extends StatelessWidget {
  const HabitSeasonPanel({
    super.key,
    required this.habit,
    required this.logged,
    required this.color,
    required this.firstDay,
  });

  final Habit habit;
  final Map<DateTime, int> logged;
  final Color color;
  final int firstDay;

  @override
  Widget build(BuildContext context) {
    final strings = habitsStrings;
    return NexPanel(
      title: strings(context, 'season'),
      icon: Icons.grid_view_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HabitHeatmap(
            habit: habit,
            logged: logged,
            color: color,
            firstDay: firstDay,
          ),
          const SizedBox(height: NexSpacing.md),
          HabitMarkLegend(
            color: color,
            labels: [
              strings(context, 'legendDone'),
              strings(context, 'legendPartial'),
              strings(context, 'legendMissed'),
              strings(context, 'legendOff'),
            ],
          ),
        ],
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
/// ago — each carrying the platform calendar's own writing of the same
/// day (`nexModuleDateLabel`), so a Persian reader sees Jalali and never a
/// Gregorian date labelled as one. An amount day says how much.
class HabitHistory extends StatelessWidget {
  const HabitHistory({
    super.key,
    required this.habit,
    required this.checks,
    required this.color,
  });

  final Habit habit;
  final List<HabitCheck> checks;
  final Color color;

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
    final visible = checks.take(20).toList();
    return Column(
      children: [
        for (final (index, check) in visible.indexed)
          NexGroupedRow(
            index: index,
            count: visible.length,
            child: ListTile(
              dense: true,
              leading: HabitDayMark(
                size: 16,
                color: color,
                state: check.progressFor(habit.goal) >= habit.goal
                    ? HabitDayState.done
                    : HabitDayState.partial,
              ),
              title: Text(_relative(check.dateKey, strings, context)),
              subtitle: habit.counted
                  ? Text(
                      strings(context, 'amountProgress', {
                        'done': check.progressFor(habit.goal),
                        'goal': habit.goal,
                        'unit': habit.unit.isEmpty
                            ? strings(context, 'unitTimes')
                            : habit.unit,
                      }),
                    )
                  : null,
              trailing: _trailing(context, checks, check),
            ),
          ),
      ],
    );
  }

  /// The absolute day beside its relative words, and — only when old
  /// records really did double-write one day — how many raw records that
  /// day holds.
  Widget _trailing(
    BuildContext context,
    List<HabitCheck> checks,
    HabitCheck check,
  ) {
    final strings = habitsStrings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final civil = civilOfKey(check.dateKey);
    if (civil == null) return const SizedBox.shrink();
    final onDay = checks.where((c) => c.dateKey == check.dateKey).length;
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          nexModuleDateLabel(context, civil),
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        if (onDay > 1)
          Text(
            strings(context, 'totalCheckins', {'n': onDay}),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
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

/// When the habit began, in the reader's calendar; nothing when unknown.
String? habitStartedLine(BuildContext context, Habit habit) =>
    habit.createdAt.millisecondsSinceEpoch > 0
    ? habitsStrings(context, 'startedOn', {
        'date': nexModuleDateLabel(context, habit.createdAt),
      })
    : null;