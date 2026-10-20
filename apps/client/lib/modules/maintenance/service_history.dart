import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'costs.dart';
import 'logic.dart';
import 'maintenance_common.dart';
import 'maintenance_widgets.dart';
import 'models.dart';
import 'strings.dart';
import 'units.dart';

/// An asset's service history as plain text for a repairer or a buyer:
/// the asset, then each service newest first — date, what was done, who did
/// it, the reading and the cost, as the person entered them. A cost shows in
/// its own currency and is never converted or added up across currencies.
String serviceHistoryText(
  BuildContext context,
  MaintenanceAsset asset,
  Iterable<ServiceEvent> events,
) {
  final s = maintenanceStrings;
  final persian = NexModuleStrings.persian(context);
  final lines = <String>[
    asset.nickname,
    [
      maintenanceTypeLabel(context, asset.type),
      if (asset.model?.isNotEmpty == true) asset.model!,
    ].join(' · '),
    if (asset.purchasedAt != null)
      '${s(context, 'purchasedLabel')}: ${fullDateLabel(context, asset.purchasedAt!)}',
    '',
    s(context, 'historyHeading'),
  ];
  final done = events.where(serviceDateKnown).toList()..sort(compareServices);
  if (done.isEmpty) {
    lines.add(s(context, 'noServices'));
  }
  for (final event in done) {
    final parts = <String>[
      fullDateLabel(context, event.date),
      event.task.trim(),
      if (event.provider?.trim().isNotEmpty == true) event.provider!.trim(),
    ];
    final meter = event.meter;
    if (meter != null && event.meterValid) {
      final unit = eventMeterKind(event) == MeterKind.hours
          ? s(context, 'unitHours')
          : s(
              context,
              meterUnitLabelKey(event.meterUnit ?? asset.distanceUnit),
            );
      parts.add(
        '${formatMeterValue(meter, scale: event.meterScale, persian: persian)} $unit',
      );
    }
    final cost = event.cost, code = event.currency;
    if (cost != null && code != null) {
      parts.add(
        '${formatCostNumber(cost, costExponentOf(code), persian: persian)} $code',
      );
    }
    lines.add('- ${parts.join(' · ')}');
    if (event.notes?.trim().isNotEmpty == true) {
      lines.add('  ${event.notes!.trim()}');
    }
  }
  return lines.join('\n');
}
