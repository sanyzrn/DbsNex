import 'dart:async';
import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';
import 'controller.dart';
import 'models.dart';
import 'logic.dart';
import 'units.dart';
import 'strings.dart';
import 'reading_editor.dart';
import 'maintenance_widgets.dart';
import 'maintenance_undo.dart';
import 'maintenance_common.dart';
import 'editor_draft.dart';

class ReadingPanel extends StatelessWidget {
  const ReadingPanel({
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
    final s = maintenanceStrings,
        theme = Theme.of(context),
        fa = NexModuleStrings.persian(context);
    final current = latestEnteredMeter(
      asset,
      controller.events,
      controller.readings,
      now,
    );
    final unit = s(
      context,
      asset.meterKind == MeterKind.hours
          ? 'unitHours'
          : asset.distanceUnit == DistanceUnit.mi
          ? 'unitMi'
          : 'unitKm',
    );
    final history =
        controller.readings.where((r) => r.assetId == asset.id).toList()
          // Deterministic order for same-instant readings: the id decides.
          ..sort(
            (a, b) => b.at.compareTo(a.at) != 0
                ? b.at.compareTo(a.at)
                : b.id.compareTo(a.id),
          );
    return NexPanel(
      title: s(context, 'readingValue'),
      icon: Icons.speed_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            current == null
                ? s(context, 'readingUnknown')
                : '${formatMeterValue(current.value, persian: fa)} $unit',
            style: theme.textTheme.titleLarge,
          ),
          if (current != null)
            Text(
              s(context, 'readingAsOf', {
                'date': fullDateLabel(context, current.at),
              }),
              style: theme.textTheme.bodySmall,
            ),
          if (current?.converted == true)
            Text(
              s(context, 'convertedReading'),
              style: theme.textTheme.bodySmall,
            ),
          const SizedBox(height: NexSpacing.sm),
          OutlinedButton.icon(
            key: const ValueKey('maintenance-update-reading'),
            onPressed: asset.archived
                ? null
                : () => unawaited(
                    showReadingEditor(
                      context,
                      controller: controller,
                      asset: asset,
                    ),
                  ),
            icon: const Icon(Icons.edit_outlined),
            label: Text(s(context, 'updateReading')),
          ),
          if (history.isNotEmpty)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(s(context, 'readingHistory')),
              children: [
                for (final row in history)
                  _ReadingRow(controller: controller, reading: row),
              ],
            ),
        ],
      ),
    );
  }
}

class _ReadingRow extends StatelessWidget {
  const _ReadingRow({required this.controller, required this.reading});
  final MaintenanceController controller;
  final MaintenanceReading reading;
  Future<void> _delete(BuildContext context) async {
    final s = maintenanceStrings;
    final approved = await confirmMaintenanceDelete(
      context,
      title: s(context, 'readingDeleteTitle'),
      body: s(context, 'readingDeleteBody'),
    );
    if (!approved || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context),
        message = s(context, 'readingDeleted'),
        undo = s(context, 'undo'),
        failure = s(context, 'undoFailed');
    try {
      await controller.deleteReading(reading.id);
      if (context.mounted) {
        MaintenanceUndo.offer(
          messenger,
          message: message,
          undoLabel: undo,
          failureMessage: failure,
          restore: () => controller.restore(
            'reading',
            reading.id,
            parentId: reading.assetId,
          ),
        );
      }
    } catch (_) {
      if (context.mounted) maintenanceWriteFailure(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = maintenanceStrings, fa = NexModuleStrings.persian(context);
    final unit = s(
      context,
      reading.kind == MeterKind.hours
          ? 'unitHours'
          : reading.unit == DistanceUnit.mi
          ? 'unitMi'
          : 'unitKm',
    );
    return ListTile(
      key: ValueKey('maintenance-reading-${reading.id}'),
      contentPadding: EdgeInsets.zero,
      title: Text(
        '${formatMeterValue(reading.value, scale: reading.scale, persian: fa)} $unit',
        textDirection: TextDirection.ltr,
      ),
      subtitle: Text(fullDateLabel(context, reading.at.toLocal())),
      trailing: IconButton(
        tooltip: s(context, 'delete'),
        icon: const Icon(Icons.delete_outline),
        onPressed: () => unawaited(_delete(context)),
      ),
    );
  }
}

/// Malformed rules remain visible and deletable with exact raw Undo.
class InvalidRuleRow extends StatelessWidget {
  const InvalidRuleRow({
    super.key,
    required this.controller,
    required this.record,
    required this.asset,
  });
  final MaintenanceController controller;
  final ModuleRecord record;
  final MaintenanceAsset asset;
  Future<void> _delete(BuildContext context) async {
    final s = maintenanceStrings;
    final accepted = await confirmMaintenanceDelete(
      context,
      title: s(context, 'deleteRuleTitle'),
      body: s(context, 'deleteRuleBody'),
    );
    if (!accepted || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context),
        message = s(context, 'deletedRule'),
        undo = s(context, 'undo'),
        failure = s(context, 'undoFailed');
    try {
      await controller.deleteRule(record.id);
      if (context.mounted) {
        MaintenanceUndo.offer(
          messenger,
          message: message,
          undoLabel: undo,
          failureMessage: failure,
          restore: () =>
              controller.restore('rule', record.id, parentId: asset.id),
        );
      }
    } catch (_) {
      if (context.mounted) maintenanceWriteFailure(context);
    }
  }

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(
      record.body['task'] is String
          ? record.body['task'] as String
          : maintenanceStrings(context, 'reviewRule'),
    ),
    subtitle: Text(maintenanceStrings(context, 'reviewRule')),
    trailing: IconButton(
      tooltip: maintenanceStrings(context, 'delete'),
      icon: const Icon(Icons.delete_outline),
      onPressed: () => unawaited(_delete(context)),
    ),
  );
}
