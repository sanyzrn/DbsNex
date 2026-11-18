import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'controller.dart';
import 'models.dart';
import 'strings.dart';
import 'units.dart';

/// The person's fuel rates and monthly quotas. Nothing here is fetched or
/// described as official: the labels and numbers are theirs, and example
/// values are marked as examples until they are checked and edited.
Future<void> showFuelRatesSheet(
  BuildContext context, {
  required MaintenanceController controller,
  required MaintenanceAsset asset,
}) => nexShowSheet(
  context: context,
  dismissible: false,
  swipeToClose: true,
  builder: (_) => FuelRatesSheet(controller: controller, asset: asset),
);

class _RateRow {
  _RateRow({
    this.id,
    required String name,
    required int quota,
    this.example = false,
  }) : name = TextEditingController(text: name),
       quota = TextEditingController(
         text: quota == 0 ? '' : meterInputText(quota, scale: FuelRate.scale),
       );

  String? id;
  final TextEditingController name;
  final TextEditingController quota;
  bool example;

  void dispose() {
    name.dispose();
    quota.dispose();
  }
}

class FuelRatesSheet extends StatefulWidget {
  const FuelRatesSheet({
    super.key,
    required this.controller,
    required this.asset,
  });

  final MaintenanceController controller;
  final MaintenanceAsset asset;

  @override
  State<FuelRatesSheet> createState() => _FuelRatesSheetState();
}

class _FuelRatesSheetState extends State<FuelRatesSheet> {
  late final List<_RateRow> _rows = [
    for (final rate in widget.controller.fuelRates.where(
      (r) => r.assetId == widget.asset.id,
    ))
      _RateRow(
        id: rate.id,
        name: rate.name,
        quota: rate.quota,
        example: rate.example,
      ),
  ];
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  void _addExample() {
    setState(() {
      if (_rows.isEmpty) {
        _rows.addAll([
          _RateRow(
            name: maintenanceStrings(context, 'fuelRateQuotaName'),
            quota: 60 * FuelRate.scale,
            example: true,
          ),
          _RateRow(
            name: maintenanceStrings(context, 'fuelRateFreeName'),
            quota: 0,
            example: true,
          ),
        ]);
      } else {
        _rows.add(
          _RateRow(
            name: maintenanceStrings(context, 'fuelRateFreeName'),
            quota: 0,
          ),
        );
      }
    });
  }

  Future<void> _save() async {
    if (_busy) return;
    final rates = <FuelRate>[];
    for (final row in _rows) {
      final name = row.name.text.trim();
      if (name.isEmpty) {
        setState(() => _error = maintenanceStrings(context, 'fuelRateBadName'));
        return;
      }
      final raw = row.quota.text.trim();
      final quota = raw.isEmpty ? 0 : parseMeterInput(raw);
      if (quota == null || quota > FuelRate.maxQuota) {
        setState(
          () => _error = maintenanceStrings(context, 'fuelRateBadQuota'),
        );
        return;
      }
      rates.add(
        FuelRate(
          id: row.id ?? 'rate-${widget.controller.store.newId()}',
          assetId: widget.asset.id,
          name: name,
          quota: quota,
          example: row.example,
        ),
      );
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.saveFuelRates(widget.asset.id, rates);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = maintenanceStrings(context, 'saveFailed');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = maintenanceStrings;
    final theme = Theme.of(context);
    return PopScope(
      canPop: !_busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop || _busy) return;
      },
      child: AbsorbPointer(
        absorbing: _busy,
        child: Padding(
          padding: EdgeInsets.only(
            left: NexSpacing.md,
            right: NexSpacing.md,
            top: NexSpacing.md,
            bottom: NexSpacing.md + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  s(context, 'fuelRateSheetTitle'),
                  style: theme.textTheme.titleLarge,
                ),
              ),
              const SizedBox(height: NexSpacing.xs),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  s(context, 'fuelRateNote'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: NexSpacing.md),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_rows.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: NexSpacing.md),
                          child: Text(
                            s(context, 'fuelRateEmpty'),
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      for (var i = 0; i < _rows.length; i++)
                        _RateFields(
                          key: ValueKey('maintenance-rate-row-$i'),
                          index: i,
                          row: _rows[i],
                          onRemove: () => setState(() {
                            _rows.removeAt(i).dispose();
                          }),
                          onChanged: () => setState(() => _error = null),
                        ),
                      const SizedBox(height: NexSpacing.sm),
                      Wrap(
                        spacing: NexSpacing.sm,
                        children: [
                          OutlinedButton.icon(
                            key: const ValueKey('maintenance-rate-add'),
                            onPressed: _addExample,
                            icon: const Icon(Icons.add),
                            label: Text(s(context, 'fuelRateAdd')),
                          ),
                          if (_rows.isEmpty)
                            TextButton(
                              key: const ValueKey('maintenance-rate-examples'),
                              onPressed: _addExample,
                              child: Text(s(context, 'fuelRateExamples')),
                            ),
                        ],
                      ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: NexSpacing.sm),
                          child: Text(
                            _error!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.error,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: NexSpacing.sm),
              FilledButton(
                key: const ValueKey('maintenance-rate-save'),
                onPressed: _busy ? null : () => unawaited(_save()),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: Text(s(context, 'fuelRateSave')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RateFields extends StatelessWidget {
  const _RateFields({
    super.key,
    required this.index,
    required this.row,
    required this.onRemove,
    required this.onChanged,
  });

  final int index;
  final _RateRow row;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final s = maintenanceStrings;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: NexSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: NexAutoDirection(
                  controller: row.name,
                  builder: (context, direction) => TextField(
                    key: ValueKey('maintenance-rate-name-$index'),
                    controller: row.name,
                    textDirection: direction,
                    decoration: InputDecoration(
                      labelText: s(context, 'fuelRateName'),
                    ),
                    onChanged: (_) => onChanged(),
                  ),
                ),
              ),
              IconButton(
                key: ValueKey('maintenance-rate-remove-$index'),
                tooltip: s(context, 'fuelRateRemove'),
                icon: const Icon(Icons.delete_outline),
                onPressed: onRemove,
              ),
            ],
          ),
          const SizedBox(height: NexSpacing.xs),
          TextField(
            key: ValueKey('maintenance-rate-quota-$index'),
            controller: row.quota,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              labelText: s(context, 'fuelRateQuota'),
              suffixText: s(context, 'fuelLitres'),
            ),
            onChanged: (_) => onChanged(),
          ),
          if (row.example)
            Padding(
              padding: const EdgeInsets.only(top: NexSpacing.xs),
              child: Text(
                s(context, 'fuelRateExample'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: NexHue.amber.of(theme.brightness),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
