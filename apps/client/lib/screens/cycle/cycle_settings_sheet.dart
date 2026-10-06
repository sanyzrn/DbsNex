import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../platform/cycle_reminders.dart';
import '../../platform/nex_preferences.dart';
import '../../platform/nex_services.dart';
import '../../widgets/nex_banner.dart';
import '../../widgets/nex_dialog.dart';
import '../../widgets/nex_time_picker.dart';
import 'cycle_format.dart';
import 'cycle_space.dart';

/// Reminders, the typical lengths, and deleting everything.
///
/// Resolves to true when the cycle data was deleted, so the screen can go
/// back to its first-run questions.
abstract final class CycleSettingsSheet {
  static Future<bool> show(
    BuildContext context, {
    required NexServices services,
    required NexPreferences preferences,
  }) async =>
      await nexShowSheet<bool>(
        context: context,
        builder: (_) => CycleSheet(
          child: _SettingsSheet(services: services, preferences: preferences),
        ),
      ) ??
      false;
}

class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet({required this.services, required this.preferences});

  final NexServices services;
  final NexPreferences preferences;

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  NexPreferences get _prefs => widget.preferences;

  Future<void> _rearm() => CycleReminders.apply(
    context: context,
    services: widget.services,
    preferences: _prefs,
  );

  Future<void> _toggle(Future<void> Function(bool) set, bool on) async {
    if (on) await widget.services.reminders.requestPermission();
    await set(on);
    if (!mounted) return;
    setState(() {});
    await _rearm();
  }

  Future<void> _pickPillTime() async {
    final minutes = _prefs.cyclePillMinutes;
    final picked = await nexPickTime(
      context,
      initial: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
    );
    if (picked == null) return;
    await _prefs.setCyclePillMinutes(picked.hour * 60 + picked.minute);
    if (!mounted) return;
    setState(() {});
    await _rearm();
  }

  /// Pregnancy asks once where to count from: the first day of the last
  /// period (offered from the log when there is one), or the due date.
  Future<void> _setMode(CycleMode mode) async {
    if (mode == CycleMode.pregnant) {
      final start = await _askPregnancyStart();
      if (start == null) return;
      await _prefs.setCyclePregnancyStart(start);
    }
    await _prefs.setCycleMode(mode);
    if (!mounted) return;
    setState(() {});
    await _rearm();
  }

  Future<CycleDate?> _askPregnancyStart() async {
    final l10n = AppLocalizations.of(context);
    final solar = widget.services.solarCalendar;
    final periods = await widget.services.cyclePeriods();
    if (!mounted) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final suggested = periods.isEmpty ? null : periods.last.start.local;
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.cycleModePregnant),
        content: NexDialogBody(child: Text(l10n.cyclePregnancyNote)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'due'),
            child: Text(l10n.cycleKnowDueDate),
          ),
          TextButton(
            key: const ValueKey('cycle-pregnancy-last-period'),
            onPressed: () => Navigator.pop(dialogContext, 'last'),
            child: Text(l10n.cyclePregnancyStart),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return null;
    if (choice == 'due') {
      final due = await nexPickDate(
        context,
        initial: today.add(const Duration(days: 180)),
        first: today,
        last: today.add(const Duration(days: 300)),
        solar: solar,
      );
      return due == null
          ? null
          : CyclePregnancy.lastPeriodFor(CycleDate.of(due));
    }
    final last = await nexPickDate(
      context,
      initial: suggested ?? today.subtract(const Duration(days: 42)),
      first: today.subtract(const Duration(days: 300)),
      last: today,
      solar: solar,
    );
    return last == null ? null : CycleDate.of(last);
  }

  Future<void> _deleteAll() async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.cycleDeleteAll),
        content: NexDialogBody(child: Text(l10n.cycleDeleteAllConfirm)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            key: const ValueKey('cycle-delete-all-confirm'),
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.services.cycleDeleteAll();
    if (!mounted) return;
    nexShowBanner(
      context,
      message: l10n.cycleDeleted,
      kind: NexBannerKind.done,
    );
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final pill = _prefs.cyclePillMinutes;
    final pillTime = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay(hour: pill ~/ 60, minute: pill % 60),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    return NexSheetBody(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.cycleSettings, style: theme.textTheme.titleLarge),
            const SizedBox(height: NexSpacing.md),
            Text(l10n.cycleMode, style: theme.textTheme.titleSmall),
            RadioGroup<CycleMode>(
              groupValue: _prefs.cycleMode,
              onChanged: (mode) {
                if (mode != null) unawaited(_setMode(mode));
              },
              child: Column(
                children: [
                  for (final mode in CycleMode.values)
                    RadioListTile<CycleMode>(
                      key: ValueKey('cycle-mode-${mode.name}'),
                      contentPadding: EdgeInsets.zero,
                      value: mode,
                      title: Text(cycleModeLabel(l10n, mode)),
                      subtitle: Text(cycleModeHint(l10n, mode)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: NexSpacing.lg),
            Text(l10n.cycleReminders, style: theme.textTheme.titleSmall),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.cycleRemindSoon),
              value: _prefs.cycleRemindSoon,
              onChanged: (on) =>
                  unawaited(_toggle(_prefs.setCycleRemindSoon, on)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.cycleRemindLog),
              value: _prefs.cycleRemindLog,
              onChanged: (on) =>
                  unawaited(_toggle(_prefs.setCycleRemindLog, on)),
            ),
            SwitchListTile(
              key: const ValueKey('cycle-remind-pill'),
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.cycleRemindPill),
              subtitle: _prefs.cycleRemindPill
                  ? Text(cycleDigits(context, pillTime))
                  : null,
              value: _prefs.cycleRemindPill,
              onChanged: (on) =>
                  unawaited(_toggle(_prefs.setCycleRemindPill, on)),
            ),
            if (_prefs.cycleRemindPill)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: _pickPillTime,
                  icon: const Icon(Icons.schedule),
                  label: Text(cycleDigits(context, pillTime)),
                ),
              ),
            Text(
              l10n.cycleRemindersHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: NexSpacing.lg),
            SwitchListTile(
              key: const ValueKey('cycle-assistant-access'),
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.auto_awesome_outlined),
              title: Text(l10n.cycleAssistantAccess),
              subtitle: Text(l10n.cycleAssistantAccessHint),
              value: _prefs.cycleAssistantAccess,
              onChanged: (on) async {
                await _prefs.setCycleAssistantAccess(on);
                if (mounted) setState(() {});
              },
            ),
            const SizedBox(height: NexSpacing.lg),
            Text(l10n.cycleTypicalLengths, style: theme.textTheme.titleSmall),
            _Stepper(
              label: l10n.cycleLegendPeriod,
              value: _prefs.cycleTypicalPeriod,
              min: 1,
              max: 15,
              onChanged: (v) async {
                await _prefs.setCycleTypical(period: v);
                if (mounted) setState(() {});
              },
            ),
            _Stepper(
              label: l10n.cycleAverageCycle,
              value: _prefs.cycleTypicalLength,
              min: 15,
              max: 60,
              onChanged: (v) async {
                await _prefs.setCycleTypical(cycle: v);
                if (mounted) setState(() {});
              },
            ),
            const SizedBox(height: NexSpacing.lg),
            TextButton.icon(
              key: const ValueKey('cycle-delete-all'),
              onPressed: _deleteAll,
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              icon: const Icon(Icons.delete_forever_outlined),
              label: Text(l10n.cycleDeleteAll),
            ),
          ],
        ),
      ),
    );
  }
}

/// A number with − and + either side, for a length in days.
class CycleStepper extends StatelessWidget {
  const CycleStepper({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
        IconButton.outlined(
          tooltip: '−',
          onPressed: value > min ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove),
        ),
        SizedBox(
          width: 72,
          child: Text(
            cycleDigits(context, l10n.cycleDays(value)),
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
        ),
        IconButton.outlined(
          tooltip: '+',
          onPressed: value < max ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }
}

typedef _Stepper = CycleStepper;
