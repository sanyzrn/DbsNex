import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'car_logic.dart';
import 'car_reminder_sheet.dart';
import 'car_reminders.dart';
import 'controller.dart';
import 'editor_draft.dart';
import 'maintenance_widgets.dart';
import 'models.dart';
import 'strings.dart';
import 'units.dart';

/// The car's own facts: third-party insurance and technical inspection, each
/// a date the person typed and each with an optional reminder a chosen number
/// of days before (fourteen by default). Nothing is fetched and no date is
/// assumed; a missing date says so.
class CarPanel extends StatelessWidget {
  const CarPanel({
    super.key,
    required this.controller,
    required this.asset,
    required this.now,
  });

  final MaintenanceController controller;
  final MaintenanceAsset asset;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final s = maintenanceStrings;
    if (asset.type != 'car') return const SizedBox.shrink();
    return NexPanel(
      key: const ValueKey('maintenance-car-panel'),
      title: s(context, 'carTitle'),
      icon: Icons.directions_car_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CarExpiryRow(
            itemKey: 'insurance',
            label: s(context, 'insuranceLabel'),
            date: asset.insuranceExpiresAt,
            leadDays: asset.insuranceLeadDays,
            controller: controller,
            asset: asset,
            now: now,
          ),
          const SizedBox(height: NexSpacing.sm),
          CarExpiryRow(
            itemKey: 'inspection',
            label: s(context, 'inspectionLabel'),
            date: asset.inspectionExpiresAt,
            leadDays: asset.inspectionLeadDays,
            controller: controller,
            asset: asset,
            now: now,
          ),
          const SizedBox(height: NexSpacing.xs),
          Text(
            s(context, 'carNoDateNote'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// One expiry — insurance or inspection — with its countdown, date entry and
/// reminder lead time.
class CarExpiryRow extends StatelessWidget {
  const CarExpiryRow({
    super.key,
    required this.itemKey,
    required this.label,
    required this.date,
    required this.leadDays,
    required this.controller,
    required this.asset,
    required this.now,
  });

  final String itemKey;
  final String label;
  final DateTime? date;
  final int leadDays;
  final MaintenanceController controller;
  final MaintenanceAsset asset;
  final DateTime now;

  Future<void> _pickDate(BuildContext context) async {
    final today = dayOf(now);
    final initial = date == null || date!.isBefore(today) ? today : date!;
    final picked = await nexPickModuleDate(
      context,
      initial: initial,
      first: DateTime(today.year - 2),
      last: DateTime(today.year + 30),
    );
    if (picked == null || !context.mounted) return;
    await _write(context, date: dayOf(picked));
  }

  Future<void> _write(BuildContext context, {DateTime? date}) async {
    final next = MaintenanceAsset(
      id: asset.id,
      nickname: asset.nickname,
      type: asset.type,
      model: asset.model,
      purchasedAt: asset.purchasedAt,
      notes: asset.notes,
      meterKind: asset.meterKind,
      distanceUnit: asset.distanceUnit,
      insuranceExpiresAt: itemKey == 'insurance'
          ? date
          : asset.insuranceExpiresAt,
      inspectionExpiresAt: itemKey == 'inspection'
          ? date
          : asset.inspectionExpiresAt,
      insuranceLeadDays: asset.insuranceLeadDays,
      inspectionLeadDays: asset.inspectionLeadDays,
      archived: asset.archived,
    );
    final l10n = AppLocalizations.of(context);
    try {
      await controller.saveAsset(
        next,
        existing: asset,
        editedKeys: [
          itemKey == 'insurance' ? 'insuranceExpiresAt' : 'inspectionExpiresAt',
        ],
      );
      // A renewed date moves its reminder with it (2.8.4).
      await CarReminders.planOne(controller.store, asset.id, l10n);
    } catch (_) {
      if (context.mounted) maintenanceWriteFailure(context);
    }
  }

  String _status(BuildContext context, int? days) {
    final s = maintenanceStrings;
    final persian = NexModuleStrings.persian(context);
    String count(int value) => persian ? persianDigits('$value') : '$value';
    if (days == null) return s(context, 'carDateUnset');
    if (days == 0) return s(context, 'carDueToday');
    return days > 0
        ? s(context, 'carDaysLeft', {'n': count(days)})
        : s(context, 'carDaysPast', {'n': count(-days)});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = maintenanceStrings;
    final days = CarLogic.daysLeft(date, now);
    final overdue = days != null && days < 0;
    final soon = days != null && days >= 0 && days <= leadDays;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: theme.textTheme.titleSmall)),
            Text(
              _status(context, days),
              style: theme.textTheme.bodySmall?.copyWith(
                color: overdue
                    ? theme.colorScheme.error
                    : soon
                    ? NexHue.amber.of(theme.brightness)
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: NexSpacing.xs),
        Row(
          children: [
            Expanded(
              child: Text(
                date == null
                    ? s(context, 'carDateUnset')
                    : fullDateLabel(context, date!),
                style: theme.textTheme.bodyLarge,
              ),
            ),
            TextButton(
              key: ValueKey('maintenance-car-date-$itemKey'),
              onPressed: () => unawaited(_pickDate(context)),
              child: Text(s(context, date == null ? 'carDateSet' : 'editDate')),
            ),
          ],
        ),
        Wrap(
          spacing: NexSpacing.sm,
          children: [
            TextButton.icon(
              key: ValueKey('maintenance-car-remind-$itemKey'),
              onPressed: date == null
                  ? null
                  : () => unawaited(
                      nexShowSheet<void>(
                        context: context,
                        builder: (_) => CarReminderSheet(
                          controller: controller,
                          asset: asset,
                          itemKey: itemKey,
                          label: label,
                          date: date!,
                        ),
                      ),
                    ),
              icon: Icon(
                CarReminders.on(asset, itemKey)
                    ? Icons.notifications_active_outlined
                    : Icons.notifications_outlined,
              ),
              label: Text(
                s(
                  context,
                  CarReminders.on(asset, itemKey) ? 'carRemindOn' : 'carRemind',
                  {
                    'n': NexModuleStrings.persian(context)
                        ? persianDigits('$leadDays')
                        : '$leadDays',
                  },
                ),
              ),
            ),
            // Renewal day: one tap moves the date a year on, with the
            // documented month-end convention; a reminder follows it. The
            // month-end rule means 29 February lands on 28 February in a
            // non-leap year — the same convention the intervals keep.
            if (date != null)
              TextButton.icon(
                key: ValueKey('maintenance-car-renew-$itemKey'),
                onPressed: () =>
                    unawaited(_write(context, date: addMonths(date!, 12))),
                icon: const Icon(Icons.autorenew_outlined),
                label: Text(s(context, 'carRenewYear')),
              ),
          ],
        ),
      ],
    );
  }
}
