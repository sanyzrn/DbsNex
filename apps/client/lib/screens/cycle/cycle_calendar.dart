import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../widgets/feature_label.dart';
import 'cycle_format.dart';
import 'cycle_space.dart';

/// A month of the cycle: logged periods filled in rose, the expected ones
/// washed in it, the fertile window in teal, and a dot on every day with
/// something noted. Solar months and a Saturday-first week in Persian.
class CycleCalendar extends StatefulWidget {
  const CycleCalendar({
    super.key,
    required this.periods,
    required this.prediction,
    required this.logged,
    required this.solar,
    required this.onDay,
    required this.onMonth,
    this.today,
  });

  final List<CyclePeriod> periods;
  final CyclePrediction? prediction;

  /// Days with something noted.
  final Set<CycleDate> logged;
  final bool solar;

  /// A past day, or today, was tapped.
  final ValueChanged<DateTime> onDay;

  /// The page turned: the first and last day now on screen, so the caller
  /// can load what was noted on them.
  final void Function(DateTime from, DateTime to) onMonth;

  final DateTime? today;

  @override
  State<CycleCalendar> createState() => _CycleCalendarState();
}

class _CycleCalendarState extends State<CycleCalendar> {
  late DateTime _anchor = DateUtils.dateOnly(widget.today ?? DateTime.now());

  DateTime get _today => DateUtils.dateOnly(widget.today ?? DateTime.now());

  (DateTime, DateTime) get _range {
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

  void _step(int direction) {
    setState(() {
      if (widget.solar) {
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
    });
    final (from, to) = _range;
    widget.onMonth(from, to);
  }

  DateTime _weekStart(DateTime day) {
    final first = widget.solar ? DateTime.saturday : DateTime.monday;
    final back = (day.weekday - first) % 7;
    return DateTime(day.year, day.month, day.day - back);
  }

  bool _inLogged(CycleDate day) => widget.periods.any(
    (p) => p.contains(day) && (!p.isOpen || !day.isAfter(CycleDate.of(_today))),
  );

  bool _inPredicted(CycleDate day) {
    final p = widget.prediction;
    if (p == null) return false;
    return p.upcoming.any(
      (u) => !day.isBefore(u.period.start) && !day.isAfter(u.period.end),
    );
  }

  bool _inFertile(CycleDate day) {
    final p = widget.prediction;
    if (p == null) return false;
    final windows = [p.fertile, ...p.upcoming.skip(1).map((u) => u.fertile)];
    return windows.any((w) => !day.isBefore(w.start) && !day.isAfter(w.end));
  }

  bool _isOvulation(CycleDate day) {
    final p = widget.prediction;
    if (p == null) return false;
    return day == p.ovulation ||
        p.upcoming.skip(1).any((u) => day == u.fertile.end.addDays(-1));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (from, to) = _range;
    final start = _weekStart(from);
    final days = <DateTime>[
      for (
        var d = start;
        !d.isAfter(to);
        d = DateTime(d.year, d.month, d.day + 1)
      )
        d,
    ];
    while (days.length % 7 != 0) {
      final last = days.last;
      days.add(DateTime(last.year, last.month, last.day + 1));
    }
    final labels = MaterialLocalizations.of(context).narrowWeekdays;
    final firstIndex = widget.solar ? 6 : 1;
    final rose = cyclePeriodColor(theme.brightness);
    final teal = cycleFertileColor(theme.brightness);
    return Column(
      mainAxisSize: MainAxisSize.min,
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
                cycleMonthTitle(context, from, solar: widget.solar),
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
                  child: day.isBefore(from) || day.isAfter(to)
                      ? const SizedBox(height: 44)
                      : _cell(context, day, rose: rose, teal: teal),
                ),
            ],
          ),
        const SizedBox(height: NexSpacing.sm),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: NexSpacing.md,
          runSpacing: NexSpacing.xs,
          children: [
            _legend(context, rose, l10n.cycleLegendPeriod, filled: true),
            _legend(context, rose, l10n.cycleLegendPredicted, filled: false),
            _legend(context, teal, l10n.cycleLegendFertile, filled: true),
          ],
        ),
      ],
    );
  }

  Widget _cell(
    BuildContext context,
    DateTime day, {
    required Color rose,
    required Color teal,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final date = CycleDate.of(day);
    final isToday = DateUtils.isSameDay(day, _today);
    final future = day.isAfter(_today);
    final logged = _inLogged(date);
    final predicted = !logged && future && _inPredicted(date);
    final fertile = !logged && !predicted && _inFertile(date);
    final ovulation = fertile && _isOvulation(date);
    final hasNote = widget.logged.contains(date);
    final number = widget.solar ? nexPersianDate(day).day : day.day;

    final Color? fill = logged
        ? null
        : predicted
        ? rose.withValues(alpha: 0.16)
        : fertile
        ? teal.withValues(alpha: ovulation ? 0.32 : 0.18)
        : null;
    final Border? border = predicted
        ? Border.all(color: rose.withValues(alpha: 0.7), width: 1.5)
        : isToday
        ? Border.all(color: rose, width: 1.8)
        : null;
    final textColor = logged ? Colors.white : scheme.onSurface;

    return Semantics(
      button: !future,
      label: cycleDayMonth(context, day, solar: widget.solar),
      excludeSemantics: true,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: future ? null : () => widget.onDay(day),
        child: SizedBox(
          height: 44,
          child: Center(
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: fill,
                gradient: logged
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [rose, cycleMauve(theme.brightness)],
                      )
                    : null,
                shape: BoxShape.circle,
                border: border,
                boxShadow: logged
                    ? [
                        BoxShadow(
                          color: rose.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    cycleDigits(context, number),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: future && !predicted && !fertile
                          ? scheme.onSurfaceVariant
                          : textColor,
                      fontWeight: isToday || logged ? FontWeight.w700 : null,
                    ),
                  ),
                  if (hasNote)
                    Container(
                      width: 4,
                      height: 4,
                      margin: const EdgeInsets.only(top: 1),
                      decoration: BoxDecoration(
                        color: logged ? Colors.white : scheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _legend(
    BuildContext context,
    Color color,
    String label, {
    required bool filled,
  }) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled ? color : color.withValues(alpha: 0.16),
            border: filled ? null : Border.all(color: color, width: 1.5),
          ),
        ),
        const SizedBox(width: NexSpacing.xs),
        Text(label, style: theme.textTheme.labelSmall),
      ],
    );
  }
}
