import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'habit_model.dart';
import 'habit_reminder.dart';
import 'module.dart';

/// Rest days (2.8.14): travel, illness, a hard week, the days around Nowruz.
///
/// A rest is stored on the habit as inclusive civil dates, so it is the
/// habit's own history rather than a setting that moves. A rest day is not
/// due, not missed and not in any rate; the reminder waits for the first
/// day after it, and the streak walks past it as if it had not been owed.

/// How many days of the rest are left, today included.
int habitPauseDaysLeft(HabitPause pause, DateTime today) =>
    (daysBetweenKeys(dateKeyOf(today), pause.to) + 1).clamp(0, 4000);

/// «Resting until ۱۲ آبان» — the day the rest ends, in the reader's own
/// calendar (Jalali for a Persian reader, Gregorian otherwise).
String habitPauseLabel(BuildContext context, HabitPause pause) {
  final end = civilOfKey(pause.to);
  return habitsStrings(context, 'pauseEndsOn', {
    'date': end == null ? pause.to : nexModuleDateLabel(context, end),
  });
}

/// Opens the rest sheet: a few one-tap lengths, a chosen last day, and the
/// way back out of a rest that is running now.
Future<void> showHabitPauseSheet(
  BuildContext context,
  NexModuleStore store,
  Habit habit,
) => nexShowSheet<void>(
  context: context,
  builder: (_) => _PauseSheet(store: store, habit: habit),
);

/// Ends the rest covering today and re-arms the reminder. Returns false
/// when the record could not be written; the banner says so.
Future<bool> habitEndRest(
  BuildContext context,
  NexModuleStore store,
  Habit habit,
) async {
  final messenger = NexBannerHost.of(context);
  final l10n = AppLocalizations.of(context);
  final done = habitsStrings(context, 'pauseResumed');
  final failed = habitsStrings(context, 'saveError');
  try {
    final body = await store.get('habit', habit.id);
    if (body == null) return false;
    final next = Habit.fromBody(habit.id, body).endPause(DateTime.now());
    await store.put('habit', next.id, next.toJson());
    try {
      await habitArmReminder(store, l10n, next);
    } catch (_) {
      // The record is saved; the reminder catches up on the next start.
    }
    messenger?.show(message: done);
    return true;
  } catch (_) {
    messenger?.show(kind: NexBannerKind.failed, message: failed);
    return false;
  }
}

class _PauseSheet extends StatefulWidget {
  const _PauseSheet({required this.store, required this.habit});

  final NexModuleStore store;
  final Habit habit;

  @override
  State<_PauseSheet> createState() => _PauseSheetState();
}

class _PauseSheetState extends State<_PauseSheet> {
  bool _busy = false;

  Future<void> _startRest(DateTime last) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = NexBannerHost.of(context);
    final l10n = AppLocalizations.of(context);
    final failed = habitsStrings(context, 'saveError');
    try {
      final body = await widget.store.get('habit', widget.habit.id);
      if (body == null) throw StateError('Habit no longer exists');
      final today = DateTime.now();
      final next = Habit.fromBody(
        widget.habit.id,
        body,
      ).pauseUntil(today, last);
      final endsOn = civilOfKey(next.pauseOn(today)?.to ?? '') ?? last;
      if (!mounted) return;
      final message = habitsStrings(context, 'pauseStarted', {
        'date': nexModuleDateLabel(context, endsOn),
      });
      await widget.store.put('habit', next.id, next.toJson());
      try {
        // Replace the old alarm and its pending snoozes before the new date.
        await habitArmReminder(widget.store, l10n, next, clearPrevious: true);
      } catch (_) {
        // The saved rest is picked up by reminder upkeep.
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger?.show(message: message);
    } catch (_) {
      if (mounted) setState(() => _busy = false);
      messenger?.show(kind: NexBannerKind.failed, message: failed);
    }
  }

  Future<void> _endRest() async {
    if (_busy) return;
    setState(() => _busy = true);
    final saved = await habitEndRest(context, widget.store, widget.habit);
    if (!mounted) return;
    if (saved) {
      Navigator.of(context).pop();
    } else {
      setState(() => _busy = false);
    }
  }

  Future<void> _pauseFor(int days) {
    final today = DateTime.now();
    return _startRest(DateTime(today.year, today.month, today.day + days - 1));
  }

  Future<void> _pauseUntilDay() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await nexPickModuleDate(
      context,
      initial: DateTime(today.year, today.month, today.day + 6),
      first: today,
      last: DateTime(today.year + 1, today.month, today.day),
    );
    if (picked != null && mounted) await _startRest(picked);
  }

  @override
  Widget build(BuildContext context) {
    final strings = habitsStrings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final now = DateTime.now();
    final active = widget.habit.pauseOn(now);
    return SingleChildScrollView(
      padding: const EdgeInsetsDirectional.all(NexSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.pause_circle_outline_rounded, color: scheme.primary),
              const SizedBox(width: NexSpacing.sm),
              Expanded(
                child: Text(
                  strings(context, 'pauseTitle'),
                  style: theme.textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: NexSpacing.sm),
          Text(
            strings(context, 'pauseHint'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (active != null) ...[
            const SizedBox(height: NexSpacing.md),
            Text(
              habitPauseLabel(context, active),
              key: const ValueKey('habit-pause-current'),
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 2),
            Text(
              habitPauseDaysLeft(active, now) <= 1
                  ? strings(context, 'pauseOneLeft')
                  : strings(context, 'pauseLeft', {
                      'n': habitPauseDaysLeft(active, now),
                    }),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: NexSpacing.lg),
          Wrap(
            spacing: NexSpacing.sm,
            runSpacing: NexSpacing.sm,
            children: [
              for (final days in const [1, 3, 7, 14, 30])
                ActionChip(
                  key: ValueKey('habit-pause-$days'),
                  label: Text(
                    days == 1
                        ? strings(context, 'pauseJustToday')
                        : strings(context, 'pauseFor', {'n': days}),
                  ),
                  onPressed: _busy ? null : () => unawaited(_pauseFor(days)),
                ),
            ],
          ),
          const SizedBox(height: NexSpacing.md),
          OutlinedButton.icon(
            key: const ValueKey('habit-pause-until'),
            onPressed: _busy ? null : () => unawaited(_pauseUntilDay()),
            icon: const Icon(Icons.event_outlined),
            label: Text(strings(context, 'pauseUntilDay')),
          ),
          if (active != null) ...[
            const SizedBox(height: NexSpacing.sm),
            FilledButton.tonalIcon(
              key: const ValueKey('habit-pause-resume'),
              onPressed: _busy ? null : () => unawaited(_endRest()),
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(strings(context, 'pauseResume')),
            ),
          ],
          const SizedBox(height: NexSpacing.md),
        ],
      ),
    );
  }
}

/// A habit's page while it is resting: until when, how long is left, and
/// one tap back to the habit.
class HabitPauseBanner extends StatelessWidget {
  const HabitPauseBanner({
    super.key,
    required this.habit,
    required this.color,
    required this.onEnd,
  });

  final Habit habit;
  final Color color;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final pause = habit.pauseOn(now);
    if (pause == null) return const SizedBox.shrink();
    final strings = habitsStrings;
    final theme = Theme.of(context);
    final days = habitPauseDaysLeft(pause, now);
    return NexPanel(
      icon: Icons.pause_circle_outline_rounded,
      title: strings(context, 'pauseTitle'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            habitPauseLabel(context, pause),
            key: const ValueKey('habit-paused-banner'),
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 2),
          Text(
            days <= 1
                ? strings(context, 'pauseOneLeft')
                : strings(context, 'pauseLeft', {'n': days}),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: const ValueKey('habit-pause-end'),
              style: TextButton.styleFrom(foregroundColor: color),
              onPressed: onEnd,
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(strings(context, 'pauseResume')),
            ),
          ),
        ],
      ),
    );
  }
}
