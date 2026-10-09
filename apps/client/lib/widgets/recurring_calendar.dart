import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

import 'feature_label.dart';

/// The Recurring page as a calendar: a week or a month, how busy each day
/// is, and what falls on the day you tap (W5.4).
///
/// Occurrences come from [nexOccurrences], so a snoozed item shows on the day
/// it was moved to and every later one on its schedule. Only the next
/// occurrence of an item can be moved, from its row here — through the same
/// menu as the list, which already moves one occurrence without touching the
/// schedule.
class RecurringCalendar extends StatefulWidget {
  const RecurringCalendar({
    super.key,
    required this.commitments,
    required this.solar,
    required this.onActions,
    this.today,
  });

  final List<NexCommitment> commitments;

  /// Persian (Solar Hijri) months and a Saturday-first week.
  final bool solar;

  /// The item's own menu: snooze, move to a chosen time, skip, history.
  final ValueChanged<NexCommitment> onActions;

  /// For tests; the real today otherwise.
  final DateTime? today;

  @override
  State<RecurringCalendar> createState() => _RecurringCalendarState();
}

typedef _Occurrence = ({NexCommitment commitment, DateTime at});

class _RecurringCalendarState extends State<RecurringCalendar> {
  bool _month = true;
  late DateTime _anchor = DateUtils.dateOnly(widget.today ?? DateTime.now());
  late DateTime _selected = _anchor;

  DateTime get _today => DateUtils.dateOnly(widget.today ?? DateTime.now());

  static const _persianMonths = [
    ('Farvardin', 'فروردین'),
    ('Ordibehesht', 'اردیبهشت'),
    ('Khordad', 'خرداد'),
    ('Tir', 'تیر'),
    ('Mordad', 'مرداد'),
    ('Shahrivar', 'شهریور'),
    ('Mehr', 'مهر'),
    ('Aban', 'آبان'),
    ('Azar', 'آذر'),
    ('Dey', 'دی'),
    ('Bahman', 'بهمن'),
    ('Esfand', 'اسفند'),
  ];

  bool get _persianDigits =>
      Localizations.localeOf(context).languageCode == 'fa';

  String _digits(Object value) => nexDigits('$value', persian: _persianDigits);

  /// The first and last day of what is on screen.
  (DateTime, DateTime) get _range {
    if (!_month) {
      final start = _weekStart(_anchor);
      return (start, start.add(const Duration(days: 6)));
    }
    if (widget.solar) {
      final p = nexPersianDate(_anchor);
      final first = nexGregorianDate(p.year, p.month, 1);
      final days = nexPersianMonthDays(p.year, p.month);
      return (first, DateTime(first.year, first.month, first.day + days - 1));
    }
    final first = DateTime(_anchor.year, _anchor.month);
    return (
      first,
      DateTime(
        first.year,
        first.month,
        DateUtils.getDaysInMonth(first.year, first.month),
      ),
    );
  }

  /// Saturday for the Persian calendar, Monday otherwise.
  DateTime _weekStart(DateTime day) {
    final first = widget.solar ? DateTime.saturday : DateTime.monday;
    final back = (day.weekday - first) % 7;
    return DateTime(day.year, day.month, day.day - back);
  }

  void _step(int direction) {
    setState(() {
      if (!_month) {
        _anchor = DateTime(
          _anchor.year,
          _anchor.month,
          _anchor.day + 7 * direction,
        );
      } else if (widget.solar) {
        final p = nexPersianDate(_anchor);
        var month = p.month + direction;
        var year = p.year;
        if (month < 1) {
          month = 12;
          year--;
        } else if (month > 12) {
          month = 1;
          year++;
        }
        _anchor = nexGregorianDate(year, month, 1);
      } else {
        _anchor = DateTime(_anchor.year, _anchor.month + direction);
      }
      _selected = _anchor;
    });
  }

  String _title(DateTime start) {
    if (widget.solar) {
      final p = nexPersianDate(_month ? _anchor : start);
      final (en, fa) = _persianMonths[p.month - 1];
      return '${_persianDigits ? fa : en} ${_digits(p.year)}';
    }
    return MaterialLocalizations.of(
      context,
    ).formatMonthYear(_month ? _anchor : start);
  }

  int _dayNumber(DateTime day) =>
      widget.solar ? nexPersianDate(day).day : day.day;

  Map<DateTime, List<_Occurrence>> _occurrences(DateTime from, DateTime to) {
    final byDay = <DateTime, List<_Occurrence>>{};
    final end = DateTime(to.year, to.month, to.day, 23, 59, 59);
    for (final commitment in widget.commitments) {
      for (final at in nexOccurrences(
        commitment,
        from: from,
        to: end,
        max: 200,
      )) {
        byDay.putIfAbsent(DateUtils.dateOnly(at), () => []).add((
          commitment: commitment,
          at: at,
        ));
      }
    }
    for (final list in byDay.values) {
      list.sort((a, b) => a.at.compareTo(b.at));
    }
    return byDay;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (from, to) = _range;
    final byDay = _occurrences(from, to);
    final selected = byDay[_selected] ?? const <_Occurrence>[];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: nexLabel(context, 'Previous', 'قبلی'),
              icon: const Icon(Icons.chevron_left),
              onPressed: () => _step(-1),
            ),
            Expanded(
              child: Text(
                _title(from),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall,
              ),
            ),
            IconButton(
              tooltip: nexLabel(context, 'Next', 'بعدی'),
              icon: const Icon(Icons.chevron_right),
              onPressed: () => _step(1),
            ),
          ],
        ),
        Center(
          child: SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: false,
                label: Text(nexLabel(context, 'Week', 'هفته')),
              ),
              ButtonSegment(
                value: true,
                label: Text(nexLabel(context, 'Month', 'ماه')),
              ),
            ],
            selected: {_month},
            onSelectionChanged: (value) => setState(() {
              _month = value.first;
              _anchor = _selected;
            }),
          ),
        ),
        const SizedBox(height: NexSpacing.sm),
        _grid(context, from, to, byDay),
        const SizedBox(height: NexSpacing.sm),
        if (selected.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: NexSpacing.md),
            child: Text(
              nexLabel(
                context,
                'Nothing due this day.',
                'در این روز چیزی سررسید نیست.',
              ),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          for (final occurrence in selected) _row(context, occurrence),
      ],
    );
  }

  Widget _grid(
    BuildContext context,
    DateTime from,
    DateTime to,
    Map<DateTime, List<_Occurrence>> byDay,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final start = _weekStart(from);
    final days = <DateTime>[
      for (
        var day = start;
        !day.isAfter(to);
        day = DateTime(day.year, day.month, day.day + 1)
      )
        day,
    ];
    while (days.length % 7 != 0) {
      final last = days.last;
      days.add(DateTime(last.year, last.month, last.day + 1));
    }
    final labels = MaterialLocalizations.of(context).narrowWeekdays;
    final firstIndex = widget.solar ? 6 : 1; // narrowWeekdays[0] is Sunday.
    return Column(
      children: [
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Center(
                  child: Text(
                    labels[(firstIndex + i) % 7],
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: NexSpacing.xs),
        for (var row = 0; row < days.length ~/ 7; row++)
          Row(
            children: [
              for (final day in days.skip(row * 7).take(7))
                Expanded(
                  child: _cell(
                    context,
                    day,
                    inRange: !day.isBefore(from) && !day.isAfter(to),
                    count: byDay[day]?.length ?? 0,
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _cell(
    BuildContext context,
    DateTime day, {
    required bool inRange,
    required int count,
  }) {
    // Days of the neighbouring months only complete the grid's first and
    // last rows: blank, like a paper calendar, and not a thing to tap.
    if (!inRange) return const SizedBox(height: 48);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isSelected = DateUtils.isSameDay(day, _selected);
    final isToday = DateUtils.isSameDay(day, _today);
    // Density: how much falls on the day, as depth of tint rather than a
    // number, so a busy week reads at a glance.
    final tint = count == 0
        ? Colors.transparent
        : scheme.primary.withValues(alpha: 0.12 + 0.1 * count.clamp(1, 4));
    return Semantics(
      button: true,
      excludeSemantics: true,
      selected: isSelected,
      label: '${_digits(_dayNumber(day))}, ${_digits(count)}',
      // The action on the node itself (LOC-03): the excluded subtree took
      // the InkWell's with it.
      onTap: () => setState(() => _selected = day),
      child: InkWell(
        borderRadius: BorderRadius.circular(NexRadius.md),
        onTap: () => setState(() => _selected = day),
        child: Container(
          height: 44,
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: tint,
            borderRadius: BorderRadius.circular(NexRadius.md),
            border: isSelected
                ? Border.all(color: scheme.primary, width: 2)
                : isToday
                ? Border.all(color: scheme.outline)
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _digits(_dayNumber(day)),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: isToday ? FontWeight.w700 : null,
                ),
              ),
              if (count > 0)
                Text(
                  _digits(count),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.primary,
                    fontSize: 10,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, _Occurrence occurrence) {
    final theme = Theme.of(context);
    final c = occurrence.commitment;
    final at = occurrence.at;
    final time = MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(at));
    final isNext = at == c.dueAt;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.event_repeat_outlined),
      title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(_digits(time), style: theme.textTheme.bodySmall),
      // Only the next occurrence has a menu: it is the one that can be
      // moved, snoozed or skipped. Later ones are where the schedule says.
      trailing: isNext
          ? IconButton(
              tooltip: nexLabel(
                context,
                'Move or snooze',
                'جابه‌جایی یا تعویق',
              ),
              icon: const Icon(Icons.more_time),
              onPressed: () => widget.onActions(c),
            )
          : null,
    );
  }
}
