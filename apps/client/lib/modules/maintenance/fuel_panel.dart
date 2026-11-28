import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'car_logic.dart';
import 'controller.dart';
import 'fuel_editor.dart';
import 'fuel_rates_sheet.dart';
import 'maintenance_widgets.dart';
import 'models.dart';
import 'strings.dart';
import 'units.dart';

/// The car's fuel: this month's litres and cost, the quota left at each of
/// the person's rates, and the fill-ups themselves. The month is the
/// person's month — Jalali for a solar reader — and every number comes from
/// the log, never from a fetched price.
class FuelPanel extends StatelessWidget {
  const FuelPanel({
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
    final theme = Theme.of(context);
    final persian = NexModuleStrings.persian(context);
    final solar = NexModuleCalendar.solarOf(context);
    final rates = controller.fuelRates
        .where((r) => r.assetId == asset.id)
        .toList();
    // The quota rate first, then by name, regardless of write order.
    rates.sort((a, b) {
      final quota = b.quota.compareTo(a.quota);
      return quota != 0 ? quota : a.name.compareTo(b.name);
    });
    final entries = controller.fuel.where((e) => e.assetId == asset.id).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final summary = fuelMonthSummary(entries, now, solar: solar);
    final monthEntries = entries
        .where((e) => CarLogic.inMonth(e.date, now, solar: solar))
        .toList();
    return NexPanel(
      key: const ValueKey('maintenance-fuel-panel'),
      title: s(context, 'fuelTitle'),
      icon: Icons.local_gas_station_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            s(context, 'fuelThisMonth'),
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            s(context, 'fuelMonthTotal', {
              'litres': formatLitres(summary.litres, persian: persian),
              'cost': formatToman(summary.priceRial, persian: persian),
            }),
            style: theme.textTheme.titleMedium,
          ),
          if (rates.isNotEmpty) ...[
            const SizedBox(height: NexSpacing.sm),
            for (final rate in rates)
              _QuotaLine(
                rate: rate,
                used: summary.litresByRate[rate.name] ?? 0,
              ),
          ],
          const SizedBox(height: NexSpacing.sm),
          Wrap(
            spacing: NexSpacing.sm,
            runSpacing: NexSpacing.xs,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('maintenance-fuel-add'),
                onPressed: asset.archived
                    ? null
                    : () => unawaited(
                        showFuelEditor(
                          context,
                          controller: controller,
                          asset: asset,
                        ),
                      ),
                icon: const Icon(Icons.add),
                label: Text(s(context, 'fuelAdd')),
              ),
              TextButton.icon(
                key: const ValueKey('maintenance-fuel-rates'),
                onPressed: asset.archived
                    ? null
                    : () => unawaited(
                        showFuelRatesSheet(
                          context,
                          controller: controller,
                          asset: asset,
                        ),
                      ),
                icon: const Icon(Icons.tune_outlined),
                label: Text(s(context, 'fuelRates')),
              ),
            ],
          ),
          const SizedBox(height: NexSpacing.xs),
          if (monthEntries.isEmpty)
            Text(
              s(context, 'fuelEmpty'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            for (final entry in monthEntries)
              _FuelRow(
                entry: entry,
                onTap: () => unawaited(
                  showFuelEditor(
                    context,
                    controller: controller,
                    asset: asset,
                    existing: entry,
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _QuotaLine extends StatelessWidget {
  const _QuotaLine({required this.rate, required this.used});

  final FuelRate rate;
  final int used;

  @override
  Widget build(BuildContext context) {
    final s = maintenanceStrings;
    final theme = Theme.of(context);
    final persian = NexModuleStrings.persian(context);
    final left = rate.quota - used;
    final over = rate.quota > 0 && left < 0;
    final String text;
    if (rate.quota == 0) {
      text = used > 0
          ? s(context, 'fuelQuotaNoneUsed', {
              'used': formatLitres(used, persian: persian),
            })
          : s(context, 'fuelNoQuota');
    } else {
      text = left >= 0
          ? s(context, 'fuelQuotaLeft', {
              'used': formatLitres(used, persian: persian),
              'quota': formatLitres(rate.quota, persian: persian),
            })
          : s(context, 'fuelOverQuota', {
              'n': formatLitres(-left, persian: persian),
            });
    }
    return Padding(
      padding: const EdgeInsets.only(top: NexSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  // An untouched example still says so, so the quota is
                  // never mistaken for the person's own number.
                  rate.example
                      ? '${rate.name} · ${s(context, 'fuelExampleTag')}'
                      : rate.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              Text(
                text,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: over
                      ? theme.colorScheme.error
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          if (rate.quota > 0)
            // The same calm bar a rule's standing uses, at the quota's
            // own pace; it turns the error colour once the month is over.
            Padding(
              padding: const EdgeInsets.only(top: NexSpacing.xs),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(NexRadius.xs),
                child: LinearProgressIndicator(
                  value: (used / rate.quota).clamp(0.0, 1.0),
                  minHeight: 4,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation(
                    over
                        ? theme.colorScheme.error
                        : NexHue.amber.of(theme.brightness),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FuelRow extends StatelessWidget {
  const _FuelRow({required this.entry, required this.onTap});

  final FuelEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = maintenanceStrings;
    final theme = Theme.of(context);
    final persian = NexModuleStrings.persian(context);
    // What one litre cost in this fill-up, said by the person's own two
    // numbers — never fetched, never guessed. Milli-tomans per litre:
    // price in rials × 100 (milli-tomans) × 1000 (per thousandth of a
    // litre) ÷ litres in thousandths. A price beyond any real fill-up is
    // left unsaid rather than risked through the multiplication.
    final perLitre =
        entry.priceRial > 0 &&
            entry.priceRial < 1000000000000 &&
            entry.litres > 0
        ? s(context, 'fuelPerLitre', {
            'price': formatMeterValue(
              entry.priceRial * 100000 ~/ entry.litres,
              persian: persian,
            ),
          })
        : null;
    return InkWell(
      key: ValueKey('maintenance-fuel-${entry.id}'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: NexSpacing.xs),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${formatLitres(entry.litres, persian: persian)} ${s(context, 'fuelLitres')} · ${entry.rate}',
                    style: theme.textTheme.bodyMedium,
                  ),
                  Text(
                    fullDateLabel(context, entry.date),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${formatToman(entry.priceRial, persian: persian)} ${s(context, 'fuelPriceUnit')}',
                  style: theme.textTheme.bodyMedium,
                ),
                if (perLitre != null)
                  Text(
                    perLitre,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
