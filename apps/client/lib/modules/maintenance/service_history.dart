import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'car_logic.dart';
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
  Iterable<ServiceEvent> events, {
  Iterable<FuelEntry> fuel = const [],
  Iterable<FuelRate> rates = const [],
  DateTime? now,
}) {
  final s = maintenanceStrings;
  final persian = NexModuleStrings.persian(context);
  final at = now ?? DateTime.now();
  final summary = fuelMonthSummary(
    fuel,
    at,
    solar: NexModuleCalendar.solarOf(context),
  );
  final lines = <String>[
    asset.nickname,
    [
      maintenanceTypeLabel(context, asset.type),
      if (asset.model?.isNotEmpty == true) asset.model!,
    ].join(' · '),
    if (asset.purchasedAt != null)
      '${s(context, 'purchasedLabel')}: ${fullDateLabel(context, asset.purchasedAt!)}',
    if (asset.insuranceExpiresAt != null)
      '${s(context, 'historyInsurance')}: ${fullDateLabel(context, asset.insuranceExpiresAt!)}',
    if (asset.inspectionExpiresAt != null)
      '${s(context, 'historyInspection')}: ${fullDateLabel(context, asset.inspectionExpiresAt!)}',
    '',
    s(context, 'historyHeading'),
  ];
  final done = events.where(serviceDateKnown).toList()..sort(compareServices);
  if (done.isEmpty) {
    lines.add(s(context, 'noServices'));
  }
  if (summary.litres > 0 || summary.priceRial > 0) {
    lines.add('');
    lines.add(s(context, 'historyFuel'));
    lines.add(
      '- ${s(context, 'historyFuelLine', {'litres': formatLitres(summary.litres, persian: persian), 'cost': formatToman(summary.priceRial, persian: persian)})}',
    );
    for (final rate in rates) {
      final used = summary.litresByRate[rate.name] ?? 0;
      if (used == 0) continue;
      // A rate with no quota shows what was bought at it, never a
      // meaningless division by zero.
      lines.add(
        rate.quota > 0
            ? '  ${rate.name}: ${formatLitres(used, persian: persian)} / ${formatLitres(rate.quota, persian: persian)}'
            : '  ${rate.name}: ${formatLitres(used, persian: persian)}',
      );
    }
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
