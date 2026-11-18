import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'car_logic.dart';
import 'car_reminders.dart';
import 'controller.dart';
import 'local_values.dart';
import 'maintenance_widgets.dart';
import 'models.dart';
import 'strings.dart';
import 'units.dart';

/// The reminder's lead time: days before the typed date, fourteen by
/// default, editable and remembered on the asset. Setting it also stores the
/// opt-in device alert through the platform, so permission checks and
/// auto-cancel apply.
class CarReminderSheet extends StatefulWidget {
  const CarReminderSheet({
    super.key,
    required this.controller,
    required this.asset,
    required this.itemKey,
    required this.label,
    required this.date,
  });

  final MaintenanceController controller;
  final MaintenanceAsset asset;
  final String itemKey;
  final String label;
  final DateTime date;

  @override
  State<CarReminderSheet> createState() => _CarReminderSheetState();
}

class _CarReminderSheetState extends State<CarReminderSheet> {
  late final _days = TextEditingController(
    text:
        '${widget.itemKey == 'insurance' ? widget.asset.insuranceLeadDays : widget.asset.inspectionLeadDays}',
  );
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _days.dispose();
    super.dispose();
  }

  int? get _value {
    final text = LocalValues.ascii(_days.text.trim());
    final value = int.tryParse(text);
    return value == null || value < 0 || value > 365 ? null : value;
  }

  Future<void> _save() async {
    if (_busy) return;
    final days = _value;
    final now = DateTime.now();
    if (days == null) {
      setState(() => _error = maintenanceStrings(context, 'carReminderBad'));
      return;
    }
    if (!CarLogic.reminderFits(widget.date, days, now)) {
      setState(() => _error = maintenanceStrings(context, 'carReminderPast'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    // Captured before the write: nothing reads a context across an await.
    final l10n = AppLocalizations.of(context);
    final savedMessage = maintenanceStrings(context, 'carReminderSaved');
    final notSet = maintenanceStrings(context, 'carReminderNotSet');
    try {
      await _write(days: days, on: true);
      final ok = await CarReminders.planOne(
        widget.controller.store,
        widget.asset.id,
        l10n,
      );
      if (!ok) await _write(days: days, on: false);
      if (!mounted) return;
      if (ok) {
        Navigator.pop(context);
        NexBannerHost.of(context)
            ?.show(kind: NexBannerKind.done, message: savedMessage);
      } else {
        setState(() {
          _busy = false;
          _error = notSet;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = notSet;
        });
      }
    }
  }

  bool get _on => CarReminders.on(widget.asset, widget.itemKey);

  /// Writes this item's lead time and whether its reminder is on.
  Future<void> _write({required int days, required bool on}) {
    final insurance = widget.itemKey == 'insurance';
    final a = widget.asset;
    return widget.controller.saveAsset(
      MaintenanceAsset(
        id: a.id,
        nickname: a.nickname,
        type: a.type,
        model: a.model,
        purchasedAt: a.purchasedAt,
        notes: a.notes,
        meterKind: a.meterKind,
        distanceUnit: a.distanceUnit,
        insuranceExpiresAt: a.insuranceExpiresAt,
        inspectionExpiresAt: a.inspectionExpiresAt,
        insuranceLeadDays: insurance ? days : a.insuranceLeadDays,
        inspectionLeadDays: insurance ? a.inspectionLeadDays : days,
        insuranceRemind: insurance ? on : a.insuranceRemind,
        inspectionRemind: insurance ? a.inspectionRemind : on,
        archived: a.archived,
      ),
      existing: a,
      editedKeys: ['${widget.itemKey}LeadDays', '${widget.itemKey}Remind'],
    );
  }

  /// Turns this reminder off: the flag goes and so does the alarm.
  Future<void> _turnOff() async {
    if (_busy) return;
    setState(() => _busy = true);
    final message = maintenanceStrings(context, 'carReminderOffDone');
    final notSaved = maintenanceStrings(context, 'carReminderNotSet');
    try {
      final lead = CarReminders.leadDays(widget.asset, widget.itemKey);
      await _write(days: lead, on: false);
      await widget.controller.store.clearReminder(
        CarReminders.key(widget.itemKey, widget.asset.id),
      );
      if (!mounted) return;
      Navigator.pop(context);
      NexBannerHost.of(context)
          ?.show(kind: NexBannerKind.done, message: message);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = notSaved;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = maintenanceStrings;
    final theme = Theme.of(context);
    final days = _value;
    return Padding(
      padding: EdgeInsets.only(
        left: NexSpacing.md,
        right: NexSpacing.md,
        top: NexSpacing.md,
        bottom: NexSpacing.md + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s(context, 'carReminderTitle'),
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: NexSpacing.xs),
            Text(
              '${widget.label} · ${fullDateLabel(context, widget.date)}',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: NexSpacing.md),
            Wrap(
              spacing: NexSpacing.sm,
              children: [
                for (final choice in const [7, 14, 30])
                  ChoiceChip(
                    key: ValueKey('maintenance-car-days-$choice'),
                    label: Text(
                      NexModuleStrings.persian(context)
                          ? persianDigits('$choice')
                          : '$choice',
                    ),
                    selected: _days.text.trim() == '$choice',
                    onSelected: (_) => setState(() {
                      _days.text = '$choice';
                      _error = null;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: NexSpacing.sm),
            NexAutoDirection(
              controller: _days,
              builder: (context, direction) => TextField(
                key: const ValueKey('maintenance-car-lead-days'),
                controller: _days,
                textDirection: direction,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: s(context, 'carReminderDays'),
                  helperText: _error,
                ),
                onChanged: (_) => setState(() => _error = null),
              ),
            ),
            if (days != null)
              Padding(
                padding: const EdgeInsets.only(top: NexSpacing.xs),
                child: Text(
                  s(context, 'reminderAt', {
                    'time': fullDateLabel(
                      context,
                      CarLogic.reminderAt(widget.date, days),
                    ),
                  }),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            const SizedBox(height: NexSpacing.md),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const ValueKey('maintenance-car-reminder-save'),
                onPressed: _busy ? null : _save,
                child: Text(s(context, 'carReminderTitle')),
              ),
            ),
            if (_on) ...[
              const SizedBox(height: NexSpacing.sm),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  key: const ValueKey('maintenance-car-reminder-off'),
                  onPressed: _busy ? null : _turnOff,
                  child: Text(s(context, 'carReminderOff')),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
