import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'habit_math.dart';
import 'habit_model.dart';
import 'module.dart';

/// A habit's reminder (2.4.0): one switch and a time, ringing only on the
/// habit's own days and never on a day it is already kept. A module
/// reminder rings once, so it is set again for the next such day whenever
/// Nex starts or returns (the module's `keepUp`), whenever a day is checked
/// in, and when the setting or the habit changes.
///
/// The notification says only that a habit is waiting, never which.

/// Where a habit's reminder setting lives: kind `remind`, id the habit's.
const habitRemindKind = 'remind';

/// The platform reminder's key, the same one version 1 used.
String habitReminderKey(String habitId) => 'habit:$habitId';

/// Whether a habit's reminder is on, and its time in minutes after midnight.
typedef HabitReminder = ({bool on, int minutes});

/// Reads the setting. A version-1 habit kept its daily reminder only as the
/// platform record; that reads as on, at the same time.
Future<HabitReminder> habitReadReminder(
  NexModuleStore store,
  String habitId,
) async {
  final body = await store.get(habitRemindKind, habitId);
  if (body != null) {
    final minutes = body['minutes'];
    return (
      on: body['on'] == true,
      minutes: minutes is int && minutes >= 0 && minutes < 1440
          ? minutes
          : 20 * 60,
    );
  }
  final legacy = await store.get('__reminder', habitReminderKey(habitId));
  final at = legacy == null ? null : DateTime.tryParse('${legacy['at']}');
  if (at == null || legacy?['repeat'] != 'daily') {
    return (on: false, minutes: 20 * 60);
  }
  final local = at.toLocal();
  return (on: true, minutes: local.hour * 60 + local.minute);
}

/// When the reminder should next ring: the first of the habit's days, from
/// [now] on, at [minutes], that is not already kept. A weekly target is
/// due on any day of a week that has not met it yet. Null when no such day
/// comes within two months.
DateTime? habitNextReminder(
  Habit habit,
  Iterable<HabitCheck> checks, {
  required int minutes,
  required DateTime now,
  int firstDay = DateTime.saturday,
}) {
  final logged = HabitMath.loggedDays(habit, checks, now);
  final done = {
    for (final entry in logged.entries)
      if (entry.value >= habit.goal) entry.key,
  };
  for (var ahead = 0; ahead <= 60; ahead++) {
    final day = DateTime(now.year, now.month, now.day + ahead);
    final at = DateTime(
      day.year,
      day.month,
      day.day,
      minutes ~/ 60,
      minutes % 60,
    );
    if (!at.isAfter(now)) continue;
    final civil = DateTime.utc(day.year, day.month, day.day);
    if (done.contains(civil)) continue;
    if (habit.weekly) {
      final week = HabitMath.weekStartOf(civil, firstDay: firstDay);
      final count = done
          .where((d) => HabitMath.weekStartOf(d, firstDay: firstDay) == week)
          .length;
      if (count >= habit.target) continue;
    } else if (!HabitMath.dueOn(habit, civil)) {
      continue;
    }
    return at;
  }
  return null;
}

/// Sets [habit]'s reminder for its next day, or clears it. False when it
/// should ring and could not be set.
Future<bool> habitArmReminder(
  NexModuleStore store,
  AppLocalizations l10n,
  Habit habit, {
  List<HabitCheck>? checks,
  int? firstDay,
  DateTime? now,
}) async {
  final key = habitReminderKey(habit.id);
  final reminder = await habitReadReminder(store, habit.id);
  // Persist v1 preferences before replacing its daily platform record.
  if (reminder.on && await store.get(habitRemindKind, habit.id) == null) {
    await store.put(habitRemindKind, habit.id, {
      'v': 1,
      'on': true,
      'minutes': reminder.minutes,
    });
  }
  if (!reminder.on || habit.archived) {
    await store.clearReminder(key);
    return true;
  }
  final mine =
      checks ??
      [
        for (final record in await store.list('check'))
          if (record.body['habit'] == habit.id) HabitCheck.fromRecord(record),
      ];
  final week = firstDay ?? _firstDayOf(await store.get('settings', 'week'));
  final at = habitNextReminder(
    habit,
    mine.where((c) => c.habitId == habit.id),
    minutes: reminder.minutes,
    now: now ?? DateTime.now(),
    firstDay: week,
  );
  if (at == null) {
    await store.clearReminder(key);
    return true;
  }
  return store.setReminder(
    key,
    sourceKind: 'habit',
    sourceId: habit.id,
    at: at,
    title: habitsStrings.text(l10n, 'reminderTitle'),
    body: habitsStrings.text(l10n, 'reminderBody'),
  );
}

int _firstDayOf(Map<String, Object?>? body) {
  final value = body?['firstDay'];
  return value is int && value >= 1 && value <= 7 ? value : DateTime.saturday;
}

/// Moves every habit's reminder to its next day — the module's `keepUp`.
Future<void> habitsKeepUp(NexModuleStore store, AppLocalizations l10n) async {
  final habits = (await store.list('habit')).map(Habit.fromRecord).toList();
  if (habits.isEmpty) return;
  final checks = (await store.list('check')).map(HabitCheck.fromRecord);
  final firstDay = _firstDayOf(await store.get('settings', 'week'));
  final now = DateTime.now();
  for (final habit in habits) {
    try {
      await habitArmReminder(
        store,
        l10n,
        habit,
        checks: checks.where((c) => c.habitId == habit.id).toList(),
        firstDay: firstDay,
        now: now,
      );
    } catch (_) {
      // One habit's reminder failing must not stop the others.
    }
  }
}

/// The reminder's switch and time, on the habit's page.
class HabitReminderTile extends StatefulWidget {
  const HabitReminderTile({
    super.key,
    required this.store,
    required this.habit,
    required this.color,
  });

  final NexModuleStore store;
  final Habit habit;
  final Color color;

  @override
  State<HabitReminderTile> createState() => _HabitReminderTileState();
}

class _HabitReminderTileState extends State<HabitReminderTile> {
  HabitReminder? _reminder;
  bool _busy = false;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final reminder = await habitReadReminder(widget.store, widget.habit.id);
      if (mounted)
        setState(() {
          _reminder = reminder;
          _loadFailed = false;
        });
    } catch (_) {
      if (mounted) setState(() => _loadFailed = true);
    }
  }

  Future<void> _save({bool? on, int? minutes}) async {
    final current = _reminder;
    if (current == null || _busy) return;
    setState(() => _busy = true);
    final l10n = AppLocalizations.of(context);
    final failed = habitsStrings(context, 'reminderFailed');
    void say() {
      if (mounted) nexShowBanner(context, message: failed, kind: NexBannerKind.failed);
    }
    try {
      final next = (on: on ?? current.on, minutes: minutes ?? current.minutes);
      await widget.store.put(habitRemindKind, widget.habit.id, {
        'v': 1,
        'on': next.on,
        'minutes': next.minutes,
      });
      if (mounted) setState(() => _reminder = next);
      final ok = await habitArmReminder(widget.store, l10n, widget.habit);
      if (!ok && next.on) say();
    } catch (_) {
      say();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pick() async {
    final current = _reminder;
    if (current == null) return;
    final picked = await nexPickModuleTime(
      context,
      initial: TimeOfDay(
        hour: current.minutes ~/ 60,
        minute: current.minutes % 60,
      ),
    );
    if (picked == null || !mounted) return;
    await _save(on: true, minutes: picked.hour * 60 + picked.minute);
  }

  @override
  Widget build(BuildContext context) {
    final reminder = _reminder;
    if (_loadFailed) {
      return TextButton(
        onPressed: () => unawaited(_load()),
        child: Text(habitsStrings(context, 'retry')),
      );
    }
    if (reminder == null) return const SizedBox(height: 64);
    final strings = habitsStrings;
    String two(int v) => v.toString().padLeft(2, '0');
    final time = nexDigits(
      '${two(reminder.minutes ~/ 60)}:${two(reminder.minutes % 60)}',
      persian: NexModuleStrings.persian(context),
    );
    final when = switch (widget.habit.plan) {
      HabitPlan.daily => 'reminderEveryDay',
      HabitPlan.weekly => 'reminderWeekly',
      HabitPlan.days || HabitPlan.every => 'reminderOnDays',
    };
    return NexPanel(
      icon: Icons.notifications_active_outlined,
      title: strings(context, 'reminder'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NexSwitchTile(
            key: const ValueKey('habit-reminder-switch'),
            contentPadding: EdgeInsets.zero,
            title: Text(
              reminder.on
                  ? strings(context, 'reminderAt', {'time': time})
                  : strings(context, 'reminderOff'),
            ),
            subtitle: Text(strings(context, when)),
            value: reminder.on,
            onChanged: _busy
                ? null
                : (on) => unawaited(on ? _pick() : _save(on: false)),
          ),
          if (reminder.on)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: const ValueKey('habit-reminder-time'),
                style: TextButton.styleFrom(foregroundColor: widget.color),
                onPressed: _busy ? null : () => unawaited(_pick()),
                icon: const Icon(Icons.schedule),
                label: Text(strings(context, 'reminderChange')),
              ),
            ),
        ],
      ),
    );
  }
}

/// Cancels the alarm while preserving the habit's reminder preference.
Future<void> habitDropReminder(NexModuleStore store, String habitId) async {
  try {
    await store.clearReminder(habitReminderKey(habitId));
  } catch (_) {
    // Rings once at most: the restore on launch drops it for a missing or
    // archived habit.
  }
}
