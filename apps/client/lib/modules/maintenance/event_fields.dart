import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'costs.dart';
import 'maintenance_common.dart';
import 'maintenance_undo.dart';
import 'controller.dart';
import 'models.dart';
import 'units.dart';
import 'editor_draft.dart';
import 'strings.dart';

/// The event editor's cost pieces: the amount field with the currency
/// picker row and the rial/toman choice, and the backwards-reading
/// question. The words come from the strings like everything else.

/// The cost section of the service editor: the amount, and — once a
/// currency is chosen — the picker row and the IRR unit toggle. An
/// unset cost is simply absent; a zero says to leave it empty.
class EventCostFields extends StatelessWidget {
  const EventCostFields({
    super.key,
    required this.controller,
    required this.currency,
    required this.irrUnit,
    required this.error,
    required this.onChanged,
    required this.onCurrencyChanged,
    required this.onIrrUnitChanged,
  });

  final TextEditingController controller;
  final CostCurrency? currency;
  final IrrUnit irrUnit;
  final String? error;
  final VoidCallback onChanged;
  final ValueChanged<CostCurrency?> onCurrencyChanged;
  final ValueChanged<IrrUnit> onIrrUnitChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = maintenanceStrings;
    final currency = this.currency;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const ValueKey('maintenance-cost'),
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(
            labelText: s(context, 'costLabel'),
            hintText: s(context, 'costHint'),
            suffixText: currency?.code,
            errorText: error,
          ),
          onChanged: (_) => onChanged(),
        ),
        if (currency != null) ...[
          const SizedBox(height: NexSpacing.md),
          MaintenanceCurrencyRow(
            currency: currency,
            onChanged: onCurrencyChanged,
          ),
          if (currency.code == 'IRR') ...[
            const SizedBox(height: NexSpacing.xs),
            SegmentedButton<IrrUnit>(
              segments: [
                ButtonSegment(
                  value: IrrUnit.rial,
                  label: Text(s(context, 'rialUnit')),
                ),
                ButtonSegment(
                  value: IrrUnit.toman,
                  label: Text(s(context, 'tomanUnit')),
                ),
              ],
              selected: {irrUnit},
              onSelectionChanged: (set) => onIrrUnitChanged(set.first),
            ),
            Text(
              s(context, 'tomanHint'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ] else
          Padding(
            padding: const EdgeInsetsDirectional.only(top: NexSpacing.xs),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                key: const ValueKey('maintenance-pick-currency'),
                onPressed: () => unawaited(
                  pickMaintenanceCurrency(context).then((value) {
                    if (value != null) onCurrencyChanged(value);
                  }),
                ),
                child: Text(s(context, 'currencyLabel')),
              ),
            ),
          ),
      ],
    );
  }
}

/// Opens the currency picker sheet for a service cost.
class MaintenanceCurrencyRow extends StatelessWidget {
  const MaintenanceCurrencyRow({
    super.key,
    required this.currency,
    required this.onChanged,
  });

  final CostCurrency currency;
  final ValueChanged<CostCurrency> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: const ValueKey('maintenance-currency'),
      onTap: () => unawaited(
        pickMaintenanceCurrency(context, selected: currency).then((picked) {
          if (picked != null) onChanged(picked);
        }),
      ),
      borderRadius: BorderRadius.circular(NexRadius.md),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: maintenanceStrings(context, 'currencyLabel'),
          contentPadding: const EdgeInsetsDirectional.symmetric(
            horizontal: NexSpacing.md,
            vertical: NexSpacing.md,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${currency.code} · ${maintenanceStrings(context, 'currency-${currency.code}')}',
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.start,
              ),
            ),
            Icon(
              Directionality.of(context) == TextDirection.rtl
                  ? Icons.chevron_left
                  : Icons.chevron_right,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

/// The correction question: a reading lower than the last one in this
/// unit. The answer keeps the history complete either way — a
/// correction is a fact, not a mistake to reject.
Future<bool> confirmBackwardsMeter(
  BuildContext context, {
  required String unitWord,
  required int latest,
  int scale = 1,
}) async {
  final s = maintenanceStrings;
  final persian = NexModuleStrings.persian(context);
  final answer = await nexShowDialog<String>(
    context: context,
    builder: (dialogContext) => NexAlertDialog(
      title: Text(s(dialogContext, 'backwardsTitle')),
      content: NexDialogBody(
        child: Text(
          s(dialogContext, 'backwardsBody', {
            'unit': unitWord,
            'last': formatMeterValue(latest, scale: scale, persian: persian),
          }),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, 'keep'),
          child: Text(s(dialogContext, 'keepIt')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, 'edit'),
          child: Text(s(dialogContext, 'keepEditing')),
        ),
      ],
    ),
  );
  return answer == 'keep';
}

/// The metre reading field, labelled for what the asset counts.
class EventMeterField extends StatelessWidget {
  const EventMeterField({
    super.key,
    required this.controller,
    required this.asset,
    required this.invalid,
    required this.onChanged,
  });

  final TextEditingController controller;
  final MaintenanceAsset asset;
  final bool invalid;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final s = maintenanceStrings;
    final countsHours = asset.meterKind == MeterKind.hours;
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: NexSpacing.md),
      child: TextField(
        key: const ValueKey('maintenance-meter'),
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textDirection: TextDirection.ltr,
        decoration: InputDecoration(
          labelText: s(context, countsHours ? 'hoursMeterLabel' : 'meterLabel'),
          hintText: s(context, 'meterHint'),
          suffixText: countsHours
              ? s(context, 'unitHours')
              : s(
                  context,
                  asset.distanceUnit == DistanceUnit.km ? 'unitKm' : 'unitMi',
                ),
          errorText: invalid ? s(context, 'errNotNumber') : null,
        ),
        onChanged: (_) => onChanged(),
      ),
    );
  }
}

/// The service date row, opening the platform's Gregorian picker (a
/// Jalali picker is a platform request — see the README).
class EventDateRow extends StatelessWidget {
  const EventDateRow({
    super.key,
    required this.date,
    required this.onTap,
    this.confirmed = true,
  });

  final DateTime date;
  final bool confirmed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = maintenanceStrings;
    return InkWell(
      key: const ValueKey('maintenance-event-date'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(NexRadius.md),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: s(context, 'dateLabel'),
          contentPadding: const EdgeInsetsDirectional.symmetric(
            horizontal: NexSpacing.md,
            vertical: NexSpacing.md,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                confirmed
                    ? nexModuleDateLabel(context, date)
                    : s(context, 'dateRequired'),
              ),
            ),
            const Icon(Icons.calendar_today_outlined, size: 20),
          ],
        ),
      ),
    );
  }
}

/// The delete flow of a service event: confirm, delete, close the
/// editor, offer Undo that rewrites exactly the record that was
/// there. The words and the messenger are captured before the sheet
/// pops, so nothing crosses an async gap.
Future<void> deleteServiceEvent(
  BuildContext context, {
  required MaintenanceController controller,
  ServiceEvent? existing,
  bool saving = false,
  ValueChanged<bool>? onSaving,
}) async {
  if (existing == null || saving) return;
  final s = maintenanceStrings;
  final answer = await confirmMaintenanceDelete(
    context,
    title: s(context, 'deleteEventTitle'),
    body: s(context, 'deleteEventBody'),
  );
  if (answer != true || !context.mounted) return;
  onSaving?.call(true);
  final messenger = ScaffoldMessenger.of(context);
  final message = s(context, 'deletedEvent');
  final undoLabel = s(context, 'undo');
  try {
    await controller.deleteEvent(existing.id);
    if (context.mounted) {
      Navigator.pop(context);
      MaintenanceUndo.offer(
        messenger,
        message: message,
        undoLabel: undoLabel,
        failureMessage: s(context, 'undoFailed'),
        restore: () => controller.restore(
          'event',
          existing.id,
          parentId: existing.assetId,
        ),
      );
    }
  } catch (_) {
    if (context.mounted) maintenanceWriteFailure(context);
  } finally {
    onSaving?.call(false);
  }
}

Future<CostCurrency?> pickMaintenanceCurrency(
  BuildContext context, {
  CostCurrency? selected,
}) => nexShowSheet<CostCurrency>(
  context: context,
  builder: (sheet) => ListView(
    shrinkWrap: true,
    padding: const EdgeInsets.all(NexSpacing.md),
    children: [
      Text(
        maintenanceStrings(sheet, 'currencyLabel'),
        style: Theme.of(sheet).textTheme.titleLarge,
      ),
      for (final currency in costCurrencies)
        ListTile(
          title: Text(currency.code, textDirection: TextDirection.ltr),
          subtitle: Text(
            maintenanceStrings(sheet, 'currency-${currency.code}'),
          ),
          trailing: currency.code == selected?.code
              ? const Icon(Icons.check)
              : null,
          onTap: () => Navigator.pop(sheet, currency),
        ),
    ],
  ),
);
