import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'module.dart';
import 'quit_habits.dart';
import 'quit_model.dart';
import 'smoke_math.dart';

/// The habit as the person calls it: a preset's name, or what they wrote.
String quitHabitLabel(BuildContext context, QuitAttempt attempt) =>
    attempt.habit == 'custom' && attempt.name.isNotEmpty
    ? attempt.name
    : smokeFreeStrings(context, 'habit_${quitPresetOf(attempt.habit).key}');

/// What is being done without, for "N days without …".
String quitWithout(BuildContext context, QuitAttempt attempt) =>
    attempt.habit == 'custom'
    ? (attempt.name.isEmpty
          ? smokeFreeStrings(context, 'habit_custom')
          : attempt.name)
    : smokeFreeStrings(context, 'without_${quitPresetOf(attempt.habit).key}');

/// What one of it is called, for "≈ 40 cups not had".
String quitUnit(BuildContext context, QuitAttempt attempt) =>
    smokeFreeStrings(context, 'unit_${quitPresetOf(attempt.habit).key}');

/// Minutes said as hours and minutes.
String quitDuration(BuildContext context, int minutes) {
  final strings = smokeFreeStrings;
  final persian = NexModuleStrings.persian(context);
  final h = minutes ~/ 60, m = minutes % 60;
  String digits(int n) => persian ? _persianDigits('$n') : '$n';
  return h == 0
      ? strings(context, 'durationM', {'m': digits(m)})
      : strings(context, 'durationHM', {'h': digits(h), 'm': digits(m)});
}

String _persianDigits(String s) =>
    s.replaceAllMapped(RegExp('[0-9]'), (m) => '۰۱۲۳۴۵۶۷۸۹'[int.parse(m[0]!)]);

/// Days, hours and minutes since the attempt began, kept current every half
/// minute for as long as it is on screen. An attempt that starts later says
/// when instead.
class LiveCounter extends StatefulWidget {
  const LiveCounter({super.key, required this.startedAt, this.style});

  final DateTime startedAt;
  final TextStyle? style;

  @override
  State<LiveCounter> createState() => _LiveCounterState();
}

class _LiveCounterState extends State<LiveCounter> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = smokeFreeStrings;
    final persian = NexModuleStrings.persian(context);
    final now = DateTime.now();
    if (widget.startedAt.isAfter(now)) {
      final days = SmokeMath.elapsedDays(now, widget.startedAt);
      return Text(
        days <= 1
            ? strings(context, 'startsTomorrow')
            : strings(context, 'startsIn', {'n': days}),
        key: const ValueKey('quit-counter'),
        style: widget.style,
      );
    }
    final e = QuitElapsed.between(widget.startedAt, now);
    String d(int n) => persian ? _persianDigits('$n') : '$n';
    return Semantics(
      container: true,
      child: Text(
        strings(context, 'counterDHM', {
          'd': d(e.days),
          'h': d(e.hours),
          'm': d(e.minutes),
        }),
        key: const ValueKey('quit-counter'),
        style: widget.style,
      ),
    );
  }
}

/// The marks reached, and the next one — a way to see where you are.
class QuitMarks extends StatelessWidget {
  const QuitMarks({super.key, required this.days});

  final int days;

  @override
  Widget build(BuildContext context) {
    final strings = smokeFreeStrings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final persian = NexModuleStrings.persian(context);
    final reached = quitMilestonesAt(days, quitMilestones);
    return NexPanel(
      title: strings(context, 'marksHeading'),
      icon: Icons.military_tech_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: NexSpacing.sm,
            runSpacing: NexSpacing.xs,
            children: [
              for (final mark in quitMilestones)
                Chip(
                  key: ValueKey('quit-mark-$mark'),
                  avatar: Icon(
                    reached.earned.contains(mark)
                        ? Icons.check_circle
                        : Icons.circle_outlined,
                    size: 18,
                    color: reached.earned.contains(mark)
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
                  ),
                  label: Text(
                    strings(context, 'markDays', {
                      'n': persian ? _persianDigits('$mark') : '$mark',
                    }),
                  ),
                ),
            ],
          ),
          if (reached.next != null) ...[
            const SizedBox(height: NexSpacing.sm),
            Text(
              strings(context, 'nextMark', {
                'n': persian
                    ? _persianDigits('${reached.next}')
                    : '${reached.next}',
              }),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// How the last five weeks went, a day to a square — kept, a craving, a
/// lapse, or not yet — read from the person's own records.
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

  static const _weeks = 5;

  @override
  Widget build(BuildContext context) {
    final strings = smokeFreeStrings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final today = DateTime.now();
    final end = DateTime(today.year, today.month, today.day);
    final first = end.subtract(const Duration(days: _weeks * 7 - 1));
    DateTime day(DateTime d) => DateTime(d.year, d.month, d.day);
    final cravingDays = {for (final c in cravings) day(c.at.toLocal())};
    final lapseDays = {
      for (final a in past)
        if (a.endedWhy == 'lapse' && a.endedAt != null)
          day(a.endedAt!.toLocal()),
    };
    final start = day(attempt.startedAt.toLocal());
    Color colour(DateTime d) {
      if (lapseDays.contains(d)) return scheme.error;
      if (d.isBefore(start)) return scheme.surfaceContainerHighest;
      if (cravingDays.contains(d)) return scheme.tertiary;
      return scheme.primary;
    }

    final cells = [
      for (var i = 0; i < _weeks * 7; i++) first.add(Duration(days: i)),
    ];
    return NexPanel(
      title: strings(context, 'calendarHeading'),
      icon: Icons.calendar_view_month_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            label: strings(context, 'calendarHeading'),
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final d in cells)
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: colour(
                        d,
                      ).withValues(alpha: d.isAfter(end) ? 0.15 : 0.85),
                      borderRadius: BorderRadius.circular(NexRadius.xs),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: NexSpacing.sm),
          Wrap(
            spacing: NexSpacing.md,
            runSpacing: NexSpacing.xs,
            children: [
              _Legend(scheme.primary, strings(context, 'legendClean')),
              _Legend(scheme.tertiary, strings(context, 'legendCraving')),
              _Legend(scheme.error, strings(context, 'legendLapse')),
              _Legend(
                scheme.surfaceContainerHighest,
                strings(context, 'legendLater'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend(this.colour, this.label);

  final Color colour;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: colour,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      const SizedBox(width: NexSpacing.xs),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}
