import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'controller.dart';
import 'maintenance_common.dart';
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

  /// Rows the person removed: their controllers are disposed only when the
  /// sheet closes, because the fields are still mounted until the rebuild
  /// after the removal — disposing at the tap could hand a disposed
  /// controller to a frame that has not rebuilt yet.
  final _retired = <_RateRow>[];
  bool _busy = false;
  bool _dirty = false;
  String? _error;

  @override
  void dispose() {
    for (final row in [..._rows, ..._retired]) {
      row.dispose();
    }
    _rows.clear();
    _retired.clear();
    super.dispose();
  }

  void _addExample() {
    setState(() {
      _dirty = true;
      _error = null;
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

  void _removeAt(int index) {
    setState(() {
      _retired.add(_rows.removeAt(index));
      _dirty = true;
      _error = null;
    });
  }

  Future<void> _save() async {
    if (_busy) return;
    final rates = <FuelRate>[];
    final names = <String>{};
    for (final row in _rows) {
      final name = row.name.text.trim();
      if (name.isEmpty) {
        setState(() => _error = maintenanceStrings(context, 'fuelRateBadName'));
        return;
      }
      if (name.length > 40) {
        setState(
          () => _error = maintenanceStrings(context, 'fuelRateNameLong'),
        );
        return;
      }
      // The quota view is by name: two rows with one name would count one
      // row's litres against the other's quota, so it is refused here.
      if (!names.add(name)) {
        setState(
          () => _error = maintenanceStrings(context, 'fuelRateDuplicate'),
        );
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
      if (mounted) {
        setState(() => _dirty = false);
        Navigator.pop(context);
      }
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
      // Rows the person touched are unsaved work: leaving asks, the way
      // every other editor in the module does, instead of losing them.
      canPop: !_busy && !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_busy) {
          unawaited(confirmMaintenanceDiscard(context));
        }
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
                          key: ObjectKey(_rows[i]),
                          index: i,
                          row: _rows[i],
                          onRemove: () => _removeAt(i),
                          onChanged: () => setState(() {
                            _error = null;
                            _dirty = true;
                            // "Example — check yours" is over once the person
                            // takes the row in hand: the values are theirs.
                            _rows[i].example = false;
                          }),
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
                // What destroys is red, as in every menu in the app.
                color: theme.colorScheme.error,
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
