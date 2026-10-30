import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'habit_model.dart';
import 'habit_reminder.dart';
import 'habit_visuals.dart';
import 'module.dart';

/// Every way a day is logged — the tap on Today, the amount sheet, a day
/// in the calendar — goes through here, so a day is always one record
/// (`habitId:date`) whichever way it was written, and the reminder is moved
/// on as soon as the day is kept.
class HabitLog {
  HabitLog(this.store, this.l10n);

  final NexModuleStore store;
  final AppLocalizations l10n;

  /// A tick: marks [day] done, or takes it back. Returns the record taken
  /// back, for Undo; null when the day was marked.
  Future<Map<String, Object?>?> toggle(Habit habit, String day) async {
    final id = HabitCheck.idFor(habit.id, day);
    final existing = await store.get('check', id);
    if (existing == null) {
      await store.put('check', id, {
        'habit': habit.id,
        'date': day,
        'at': DateTime.now().toIso8601String(),
      });
    } else {
      await store.delete('check', id);
    }
    await _rearm(habit);
    return existing;
  }

  /// An amount: sets [day]'s total to [amount]; zero removes the day.
  /// Returns the record as it was before, for Undo.
  Future<Map<String, Object?>?> setAmount(
    Habit habit,
    String day,
    int amount,
  ) async {
    final id = HabitCheck.idFor(habit.id, day);
    final existing = await store.get('check', id);
    if (amount <= 0) {
      if (existing != null) await store.delete('check', id);
    } else {
      await store.put('check', id, {
        'habit': habit.id,
        'date': day,
        'at': DateTime.now().toIso8601String(),
        'amount': amount.clamp(0, 99999),
      });
    }
    await _rearm(habit);
    return existing;
  }

  /// Writes back exactly what [toggle] or [setAmount] replaced; null
  /// removes the day again.
  Future<void> restore(
    Habit habit,
    String day,
    Map<String, Object?>? body,
  ) async {
    final id = HabitCheck.idFor(habit.id, day);
    if (body == null) {
      await store.delete('check', id);
    } else {
      await store.put('check', id, body);
    }
    await _rearm(habit);
  }

  Future<void> _rearm(Habit habit) async {
    try {
      await habitArmReminder(store, l10n, habit);
    } catch (_) {
      // The day is saved; the reminder catches up on the next start.
    }
  }
}

/// The amount sheet: how much of [habit]'s goal [day] has reached, with a
/// big number, steps up and down, and a way to fill or clear the day.
/// Returns the new amount, or null when it was left alone.
Future<int?> showHabitAmountSheet(
  BuildContext context, {
  required Habit habit,
  required int current,
}) => nexShowSheet<int>(
  context: context,
  builder: (context) => _AmountSheet(habit: habit, current: current),
);

class _AmountSheet extends StatefulWidget {
  const _AmountSheet({required this.habit, required this.current});

  final Habit habit;
  final int current;

  @override
  State<_AmountSheet> createState() => _AmountSheetState();
}

class _AmountSheetState extends State<_AmountSheet> {
  late int _value = widget.current;

  void _step(int by) => setState(() => _value = (_value + by).clamp(0, 99999));

  @override
  Widget build(BuildContext context) {
    final strings = habitsStrings;
    final theme = Theme.of(context);
    final habit = widget.habit;
    final color = habitColor(context, habit);
    final persian = NexModuleStrings.persian(context);
    final unit = habit.unit.isEmpty
        ? strings(context, 'unitTimes')
        : habit.unit;
    // Bigger steps for bigger goals: twenty pages move in fives.
    final step = habit.goal >= 40
        ? 10
        : habit.goal >= 12
        ? 5
        : 1;
    return SingleChildScrollView(
      padding: const EdgeInsetsDirectional.fromSTEB(
        NexSpacing.md,
        NexSpacing.md,
        NexSpacing.md,
        NexSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            habit.name.isEmpty ? strings(context, 'untitled') : habit.name,
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: NexSpacing.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton.filledTonal(
                key: const ValueKey('habit-amount-minus'),
                tooltip: strings(context, 'less'),
                onPressed: _value == 0 ? null : () => _step(-step),
                icon: const Icon(Icons.remove_rounded),
              ),
              const SizedBox(width: NexSpacing.lg),
              HabitRing(
                size: 132,
                stroke: 9,
                color: color,
                progress: _value / habit.goal,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      nexDigits('$_value', persian: persian),
                      key: const ValueKey('habit-amount-value'),
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                    Text(
                      strings(context, 'ofGoal', {
                        'goal': habit.goal,
                        'unit': unit,
                      }),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: NexSpacing.lg),
              IconButton.filled(
                key: const ValueKey('habit-amount-plus'),
                tooltip: strings(context, 'more1'),
                style: IconButton.styleFrom(backgroundColor: color),
                onPressed: () => _step(step),
                icon: const Icon(Icons.add_rounded, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: NexSpacing.lg),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: NexSpacing.sm,
            runSpacing: NexSpacing.sm,
            children: [
              ActionChip(
                key: const ValueKey('habit-amount-fill'),
                avatar: Icon(Icons.done_all_rounded, color: color, size: 18),
                label: Text(strings(context, 'fillGoal')),
                onPressed: () => setState(() => _value = habit.goal),
              ),
              ActionChip(
                key: const ValueKey('habit-amount-clear'),
                avatar: const Icon(Icons.restart_alt_rounded, size: 18),
                label: Text(strings(context, 'clearDay')),
                onPressed: () => setState(() => _value = 0),
              ),
            ],
          ),
          const SizedBox(height: NexSpacing.lg),
          FilledButton(
            key: const ValueKey('habit-amount-save'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              backgroundColor: habitHueOf(habit).deep,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(context).pop(_value),
            child: Text(AppLocalizations.of(context).save),
          ),
        ],
      ),
    );
  }
}