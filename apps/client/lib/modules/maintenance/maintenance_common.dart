import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'strings.dart';
import 'units.dart';

/// The pieces the maintenance editors share: the asset-type pill row,
/// the meter-kind toggles, the discard guard, and small labels.

/// Asks before a sheet with unsaved work closes.
Future<void> confirmMaintenanceDiscard(
  BuildContext context, {
  Future<bool> Function()? discard,
  Future<bool> Function()? keepDraft,
}) async {
  final s = maintenanceStrings;
  final answer = await nexShowDialog<String>(
    context: context,
    builder: (dialogContext) => NexAlertDialog(
      title: Text(s(dialogContext, 'discardTitle')),
      content: NexDialogBody(child: Text(s(dialogContext, 'discardBody'))),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, 'keep'),
          child: Text(s(dialogContext, 'keepEditing')),
        ),
        if (keepDraft != null)
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'draft'),
            child: Text(s(dialogContext, 'keepDraft')),
          ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, 'discard'),
          child: Text(s(dialogContext, 'discard')),
        ),
      ],
    ),
  );
  if (answer == 'discard' || answer == 'draft') {
    final done = answer == 'draft'
        ? await keepDraft!()
        : await (discard?.call() ?? Future.value(true));
    if (done && context.mounted) Navigator.pop(context);
  }
}

/// One asset type (or meter kind), as a pill — 48dp at the tap floor.
/// [type] is the strings key when [label] is not given.
class MaintenanceTypePill extends StatelessWidget {
  const MaintenanceTypePill({
    super.key,
    required this.type,
    required this.selected,
    required this.onTap,
    this.label,
  });

  final String type;
  final bool selected;
  final VoidCallback onTap;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final text =
        label ??
        maintenanceStrings(
          context,
          'type${type[0].toUpperCase()}${type.substring(1)}',
        );
    return Material(
      color: selected ? scheme.primary : scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(NexRadius.pill),
      child: InkWell(
        borderRadius: BorderRadius.circular(NexRadius.pill),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: NexSpacing.md,
          ),
          alignment: Alignment.center,
          child: Text(
            text,
            style: theme.textTheme.labelLarge?.copyWith(
              color: selected ? scheme.onPrimary : scheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

/// The asset type's glyph.
IconData maintenanceTypeIcon(String type) => switch (type) {
  'car' => Icons.directions_car_outlined,
  'motorcycle' => Icons.two_wheeler_outlined,
  'ac' => Icons.ac_unit_outlined,
  'boiler' => Icons.hot_tub_outlined,
  'filter' => Icons.water_drop_outlined,
  'appliance' => Icons.home_repair_service_outlined,
  _ => Icons.build_outlined,
};

/// The type's label, title-cased to its strings key.
String maintenanceTypeLabel(BuildContext context, String type) =>
    maintenanceStrings(
      context,
      'type${type.isEmpty ? '' : type[0].toUpperCase()}${type.substring(1)}',
    );

/// "13 October 2026" for pickers and info lines.
String maintenanceFullDate(BuildContext context, DateTime date) {
  final persian = NexModuleStrings.persian(context);
  final month = maintenanceStrings(context, 'month${date.month.clamp(1, 12)}');
  final day = persian ? persianDigits('${date.day}') : '${date.day}';
  final year = persian ? persianDigits('${date.year}') : '${date.year}';
  return '$day $month $year';
}

/// A labelled switch row, 48dp.
class MaintenanceToggleRow extends StatelessWidget {
  const MaintenanceToggleRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(NexRadius.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: NexSpacing.xs),
        child: Row(
          children: [
            Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

/// Which unit an IRR amount is entered in.
enum IrrUnit { rial, toman }

/// The delete confirmation every editor shares: cancel first, the
/// destructive word in the error colour, one question.
Future<bool> confirmMaintenanceDelete(
  BuildContext context, {
  required String title,
  required String body,
}) async {
  final s = maintenanceStrings;
  final answer = await nexShowDialog<String>(
    context: context,
    builder: (dialogContext) => NexAlertDialog(
      title: Text(title),
      content: NexDialogBody(child: Text(body)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(s(dialogContext, 'cancel')),
        ),
        TextButton(
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(dialogContext).colorScheme.error,
          ),
          onPressed: () => Navigator.pop(dialogContext, 'delete'),
          child: Text(s(dialogContext, 'delete')),
        ),
      ],
    ),
  );
  return answer == 'delete';
}
