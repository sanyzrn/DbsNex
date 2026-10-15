import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';
import 'habit_model.dart';
import 'habit_math.dart';
import 'module.dart';

/// One habit on Today: the big one-tap mark on the leading edge, the name
/// and a quiet status line beside it. The mark explains itself through
/// semantics, because it is the screen's whole point.
class HabitRow extends StatelessWidget {
  const HabitRow({
    super.key,
    required this.index,
    required this.count,
    required this.habit,
    required this.dates,
    required this.onToggle,
    required this.onOpen,
    required this.firstDay,
    required this.busy,
  });

  final int firstDay;
  final bool busy;
  final int index;
  final int count;
  final Habit habit;
  final List<String> dates;
  final VoidCallback onToggle;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final strings = habitsStrings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final standing = HabitMath.standing(
      habit,
      dates,
      DateTime.now(),
      firstDay: firstDay,
    );
    final name = habit.name.isEmpty ? strings(context, 'untitled') : habit.name;

    final status = StringBuffer();
    if (habit.weekly) {
      status.write(
        strings(context, 'weekProgress', {
          'done': standing.weekCount,
          'target': habit.target,
        }),
      );
    } else {
      status.write(strings(context, 'daily'));
    }
    if (standing.streak > 0) {
      status.write(' · ');
      status.write(
        strings(context, habit.weekly ? 'streakWeek' : 'streakDay', {
          'n': standing.streak,
        }),
      );
    }

    return NexGroupedRow(
      index: index,
      count: count,
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: NexSpacing.xs,
              end: NexSpacing.sm,
            ),
            child: _TodayMark(
              key: ValueKey('habit-today-${habit.id}'),
              done: standing.todayDone,
              onTap: busy ? null : onToggle,
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: onOpen,
              child: Padding(
                padding: EdgeInsetsDirectional.only(
                  top: NexSpacing.md,
                  bottom: NexSpacing.md,
                  end: NexSpacing.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: NexSpacing.xs),
                    Text(
                      status.toString(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (standing.graceNow)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(
                          top: NexSpacing.xs,
                        ),
                        child: Text(
                          strings(
                            context,
                            habit.weekly ? 'graceNowWeek' : 'graceNow',
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.primary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The one-tap mark: a 48dp circle that fills with the module's hue and
/// pops its check in when the day is done. Tapping it again takes the
/// check-in back — the honest undo for an accidental check.
class _TodayMark extends StatelessWidget {
  const _TodayMark({super.key, required this.done, required this.onTap});

  final bool done;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = scheme.primary;
    final strings = habitsStrings;
    return Semantics(
      button: true,
      checked: done,
      enabled: onTap != null,
      label: strings(context, done ? 'undoCheckIn' : 'checkIn'),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 48,
          height: 48,
          child: AnimatedContainer(
            duration: NexMotion.of(context, NexMotion.fast),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done ? color : Colors.transparent,
              border: Border.all(
                color: done ? color : scheme.outline,
                width: 2,
              ),
            ),
            alignment: Alignment.center,
            child: AnimatedScale(
              scale: done ? 1 : 0,
              duration: NexMotion.of(context, NexMotion.pop),
              curve: NexMotion.popCurve,
              child: Icon(
                Icons.check_rounded,
                size: 26,
                color: scheme.onPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
