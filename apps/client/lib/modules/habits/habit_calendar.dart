import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'habit_math.dart';
import 'habit_model.dart';
import 'module.dart';

/// A habit's whole history as months, in the calendar the reader uses —
/// Jalali or Gregorian. A tap marks or unmarks that day, today or earlier:
/// the same check-in record as the button on Today, keyed by the same
/// civil date, so a day entered here and a day entered there are one thing.
///
/// A day later than today cannot be marked; a day before the habit began
/// can, because people start tracking after they started doing.
class HabitCalendarPanel extends StatefulWidget {
  const HabitCalendarPanel({
    super.key,
    required this.doneKeys,
    required this.firstDay,
    required this.onToggle,
    this.busy = false,
  });

  /// Civil dates (`YYYY-MM-DD`) with a check-in.
  final Set<String> doneKeys;

  /// Dart weekday (1 Monday … 7 Sunday) the weeks start on.
  final int firstDay;
  final ValueChanged<String> onToggle;
  final bool busy;

  @override
  State<HabitCalendarPanel> createState() => _HabitCalendarPanelState();
}

class _HabitCalendarPanelState extends State<HabitCalendarPanel> {
  NexModuleMonth? _month;

  @override
  Widget build(BuildContext context) {
    final strings = habitsStrings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final solar = NexModuleCalendar.solarOf(context);
    final persian = NexModuleStrings.persian(context);
    final now = DateTime.now();
    final current = NexModuleMonth.of(now, solar: solar);
    // The calendar can change under an open page (a setting); start again
    // from this month rather than showing a month of the other calendar.
    final month = _month != null && _month!.solar == solar ? _month! : current;
    final today = DateTime(now.year, now.month, now.day);
    final blanks = month.leadingBlanks(widget.firstDay);
    final cells = blanks + month.days;
    final rows = (cells / 7).ceil();

    Widget cell(int index) {
      final day = index - blanks + 1;
      if (day < 1 || day > month.days) return const SizedBox(height: 44);
      final date = month.dayAt(day);
      final key = dateKeyOf(date);
      final done = widget.doneKeys.contains(key);
      final future = date.isAfter(today);
      final isToday = date == today;
      final label = nexModuleDateLabel(context, date);
      final number = nexDigits('$day', persian: persian);
      final fill = done ? scheme.primary : Colors.transparent;
      final textColor = done
          ? scheme.onPrimary
          : future
          ? scheme.outline
          : scheme.onSurface;
      return Semantics(
        button: !future,
        enabled: !future,
        selected: done,
        label: strings(context, done ? 'dayDone' : 'dayNotDone', {
          'date': label,
        }),
        excludeSemantics: true,
        child: InkResponse(
          key: ValueKey('habit-day-$key'),
          onTap: future || widget.busy ? null : () => widget.onToggle(key),
          radius: 24,
          child: SizedBox(
            height: 44,
            child: Center(
              child: Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: fill,
                  border: isToday && !done
                      ? Border.all(color: scheme.primary, width: 1.5)
                      : null,
                ),
                child: Text(
                  number,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: textColor,
                    fontWeight: done || isToday ? FontWeight.w600 : null,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return NexPanel(
      title: strings(context, 'calendar'),
      icon: Icons.calendar_month_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                key: const ValueKey('habit-month-previous'),
                tooltip: strings(context, 'previousMonth'),
                icon: const Icon(Icons.chevron_left),
                onPressed: () => setState(() => _month = month.shift(-1)),
              ),
              Expanded(
                child: Text(
                  month.title(context),
                  key: const ValueKey('habit-month-title'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              IconButton(
                key: const ValueKey('habit-month-next'),
                tooltip: strings(context, 'nextMonth'),
                icon: const Icon(Icons.chevron_right),
                onPressed: month == current
                    ? null
                    : () => setState(() => _month = month.shift(1)),
              ),
            ],
          ),
          Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Center(
                    child: Text(
                      strings(
                        context,
                        'wd${(widget.firstDay.clamp(1, 7) - 1 + i) % 7 + 1}',
                      ),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: NexSpacing.xs),
          for (var r = 0; r < rows; r++)
            Row(
              children: [
                for (var c = 0; c < 7; c++) Expanded(child: cell(r * 7 + c)),
              ],
            ),
          const SizedBox(height: NexSpacing.xs),
          Text(
            strings(context, 'calendarHint'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// How often the habit was kept, in words and numbers — never a grade.
/// Days since it began are the only days that count.
class HabitRatePanel extends StatelessWidget {
  const HabitRatePanel({
    super.key,
    required this.habit,
    required this.dateKeys,
    required this.firstDay,
  });

  final Habit habit;
  final Iterable<String> dateKeys;
  final int firstDay;

  @override
  Widget build(BuildContext context) {
    final strings = habitsStrings;
    final theme = Theme.of(context);
    final now = DateTime.now();
    final lines = <String>[];
    if (habit.weekly) {
      final rate = HabitMath.weeklyRate(
        habit,
        dateKeys,
        now,
        firstDay: firstDay,
      );
      if (rate.possible > 0) {
        lines.add(
          strings(context, 'rateWeeks', {
            'done': rate.done,
            'weeks': rate.possible,
            'pct': rate.percent,
          }),
        );
      }
    } else {
      for (final days in const [7, 30, 90]) {
        final rate = HabitMath.dailyRate(habit, dateKeys, now, days);
        // A window longer than the habit's life repeats the shorter one;
        // say it once.
        if (rate.possible == 0 || (lines.isNotEmpty && rate.possible < days)) {
          continue;
        }
        lines.add(
          strings(context, 'rateDays', {
            'n': rate.possible < days ? rate.possible : days,
            'done': rate.done,
            'days': rate.possible,
            'pct': rate.percent,
          }),
        );
      }
    }
    if (lines.isEmpty) return const SizedBox.shrink();
    return NexPanel(
      title: strings(context, 'rateTitle'),
      icon: Icons.insights_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(line, style: theme.textTheme.bodyMedium),
            ),
          const SizedBox(height: NexSpacing.xs),
          Text(
            strings(context, 'rateNote'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
