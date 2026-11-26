import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'module.dart';
import 'quit_habits.dart';
import 'quit_model.dart';
import 'smoke_math.dart';
export 'quit_calendar.dart';

/// The habit as the person calls it: a preset's name, or what they wrote.
String quitHabitLabel(BuildContext context, QuitAttempt attempt) =>
    attempt.habit == 'custom' && attempt.name.isNotEmpty
    ? attempt.name
    : smokeFreeStrings(context, 'habit_${quitPresetOf(attempt.habit).key}');

/// The key for a planned start: today, tomorrow, or a plural count. Swapping
/// the arguments to [SmokeMath.elapsedDays] gives the calendar days ahead and
/// clamps a past start to zero, which is what a planned row needs.
String quitStartKey(DateTime startedAt, DateTime now) {
  final days = SmokeMath.elapsedDays(now, startedAt);
  return days == 0
      ? 'startsToday'
      : days == 1
      ? 'startsTomorrow'
      : 'startsIn';
}

String quitStartLabel(BuildContext context, DateTime startedAt, DateTime now) {
  final days = SmokeMath.elapsedDays(now, startedAt);
  return smokeFreeStrings(context, quitStartKey(startedAt, now), {'n': days});
}

/// How a finished attempt's length is said: same day, one day, or N days.
/// The dashboard history and the module's habit list both use this, so an
/// ended attempt never reads as if its count were still running.
String quitAttemptSpanLabel(BuildContext context, QuitAttempt attempt) {
  final span = SmokeMath.attemptSpanDays(attempt);
  return smokeFreeStrings(
    context,
    span == 0
        ? 'attemptSameDay'
        : span == 1
        ? 'attemptOneDay'
        : 'attemptLine',
    {'days': span},
  );
}

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

String _persianDigits(String s) => nexDigits(s, persian: true);

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

class _LiveCounterState extends State<LiveCounter> with WidgetsBindingObserver {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startClock();
  }

  void _startClock() {
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startClock();
      if (mounted) setState(() {});
    } else {
      _tick?.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
