import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'module.dart';
import 'quit_model.dart';
import 'quit_calendar_math.dart';

class QuitWeeks extends StatelessWidget {
  const QuitWeeks({
    super.key,
    required this.attempt,
    required this.cravings,
    required this.past,
  });
  final QuitAttempt attempt;
  final List<Craving> cravings;
  final List<QuitAttempt> past;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), scheme = theme.colorScheme;
    final cells = quitCalendarDays(attempt, past, cravings, DateTime.now());
    Color color(QuitDayStatus status) => switch (status) {
      QuitDayStatus.lapse => scheme.error,
      QuitDayStatus.craving => scheme.tertiary,
      QuitDayStatus.unlogged => scheme.outlineVariant,
      QuitDayStatus.outside => scheme.surfaceContainerHighest,
    };
    String label(QuitDayStatus status) =>
        smokeFreeStrings(context, switch (status) {
          QuitDayStatus.lapse => 'legendLapse',
          QuitDayStatus.craving => 'legendCraving',
          QuitDayStatus.unlogged => 'legendUnknown',
          QuitDayStatus.outside => 'legendOutside',
        });
    return NexPanel(
      title: smokeFreeStrings(context, 'calendarHeading'),
      icon: Icons.calendar_view_month_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, bounds) {
              final side = (bounds.maxWidth - 6 * NexSpacing.xs) / 7;
              return Wrap(
                spacing: NexSpacing.xs,
                runSpacing: NexSpacing.xs,
                children: [
                  for (var i = 0; i < 7; i++)
                    SizedBox(
                      width: side,
                      child: Text(
                        smokeFreeStrings(
                          context,
                          'weekday${(cells.first.day.weekday - 1 + i) % 7 + 1}',
                        ),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelSmall,
                      ),
                    ),
                  for (final cell in cells)
                    Tooltip(
                      message:
                          '${nexModuleDateLabel(context, cell.day)} · ${label(cell.status)}',
                      child: Semantics(
                        label:
                            '${nexModuleDateLabel(context, cell.day)} · ${label(cell.status)}',
                        child: SizedBox(
                          width: side,
                          height: side,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: color(cell.status),
                              border: cell.status == QuitDayStatus.outside
                                  ? Border.all(color: scheme.outlineVariant)
                                  : null,
                              borderRadius: BorderRadius.circular(NexRadius.xs),
                            ),
                            child: cell.status == QuitDayStatus.lapse
                                ? Icon(
                                    Icons.remove,
                                    color: scheme.onError,
                                    size: NexSpacing.md,
                                  )
                                : cell.status == QuitDayStatus.craving
                                ? Icon(
                                    Icons.waves_outlined,
                                    color: scheme.onTertiary,
                                    size: NexSpacing.md,
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: NexSpacing.sm),
          Wrap(
            spacing: NexSpacing.md,
            runSpacing: NexSpacing.sm,
            children: [
              for (final status in QuitDayStatus.values)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: NexSpacing.sm,
                      height: NexSpacing.sm,
                      decoration: BoxDecoration(
                        color: color(status),
                        border: status == QuitDayStatus.outside
                            ? Border.all(color: scheme.outlineVariant)
                            : null,
                        borderRadius: BorderRadius.circular(NexRadius.xs),
                      ),
                    ),
                    const SizedBox(width: NexSpacing.xs),
                    Text(label(status), style: theme.textTheme.bodySmall),
                  ],
                ),
            ],
          ),
          const SizedBox(height: NexSpacing.sm),
          Text(
            smokeFreeStrings(context, 'calendarHonest'),
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
