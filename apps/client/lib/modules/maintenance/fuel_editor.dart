import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'car_logic.dart';
import 'controller.dart';
import 'editor_draft.dart';
import 'event_fields.dart';
import 'maintenance_common.dart';
import 'maintenance_undo.dart';
import 'models.dart';
import 'strings.dart';
import 'units.dart';

/// Logs or edits one fill-up: the date, the litres, what was paid in tomans
/// (stored exactly as rials) and which of the person's own rates it was
/// bought at. Deleting offers Undo.
Future<void> showFuelEditor(
  BuildContext context, {
  required MaintenanceController controller,
  required MaintenanceAsset asset,
  FuelEntry? existing,
}) => nexShowSheet(
  context: context,
  dismissible: false,
  swipeToClose: true,
  builder: (_) =>
      FuelEditorSheet(controller: controller, asset: asset, existing: existing),
);

class FuelEditorSheet extends StatefulWidget {
  const FuelEditorSheet({
    super.key,
    required this.controller,
    required this.asset,
    this.existing,
  });

  final MaintenanceController controller;
  final MaintenanceAsset asset;
  final FuelEntry? existing;

  @override
  State<FuelEditorSheet> createState() => _FuelEditorSheetState();
}

class _FuelEditorSheetState extends State<FuelEditorSheet> {
  late DateTime _date = widget.existing?.date ?? dayOf(DateTime.now());
  late final _litres = TextEditingController(
    text: widget.existing == null
        ? ''
        : meterInputText(widget.existing!.litres, scale: FuelEntry.scale),
  );
  late final _price = NexMoneyController(
    text: widget.existing == null
        ? ''
        : formatToman(
            widget.existing!.priceRial,
            persian: false,
          ).replaceAll(',', ''),
  );
  late final _notes = TextEditingController(text: widget.existing?.notes ?? '');
  late String? _rate = widget.existing?.rate;
  late final MaintenanceEditorDraft _draft;
  bool _busy = false, _dirty = false, _errors = false;

  List<FuelRate> get _rates {
    final rates = widget.controller.fuelRates
        .where((r) => r.assetId == widget.asset.id)
        .toList();
    // The quota rate first, then by name: the order does not depend on
    // which record happened to be written last.
    rates.sort((a, b) {
      final quota = b.quota.compareTo(a.quota);
      return quota != 0 ? quota : a.name.compareTo(b.name);
    });
    return rates;
  }

  @override
  void initState() {
    super.initState();
    _rate ??= _rates.isEmpty ? null : _rates.first.name;
    _draft = MaintenanceEditorDraft(
      store: widget.controller.store,
      kind: 'fuel',
      existingId: widget.existing?.id,
      base:
          widget.existing?.source ??
          (widget.existing == null
              ? {'parentId': widget.asset.id}
              : widget.existing!.toBody()),
      target: widget.existing?.id ?? widget.controller.newFuelId(),
      scope: widget.existing == null ? 'fuel:${widget.asset.id}:new' : null,
      fields: {'litres': _litres, 'price': _price, 'notes': _notes},
      extra: () => {
        'parentId': widget.asset.id,
        'date': _date.toIso8601String(),
        'rate': _rate,
      },
      applyExtra: (b) {
        _date = maintenanceCalendar(b['date']) ?? _date;
        _rate = b['rate'] is String ? b['rate'] as String : _rate;
        _dirty = true;
      },
      repaint: () {
        if (mounted) setState(() {});
      },
    );
    unawaited(_draft.load());
  }

  @override
  void dispose() {
    _draft.dispose();
    _litres.dispose();
    _price.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _markDirty() {
    setState(() => _dirty = true);
    _draft.changed();
  }

  Future<void> _pickDate() async {
    final picked = await nexPickModuleDate(
      context,
      initial: _date,
      first: DateTime(_date.year - 10),
      last: DateTime.now(),
    );
    if (picked == null || !mounted) return;
    setState(() => _date = dayOf(picked));
    _markDirty();
  }

  Future<void> _save() async {
    if (_busy) return;
    final litres = parseMeterInput(_litres.text);
    final price = rialFromTomanInput(_price.text);
    final rate = _rate;
    if (litres == null ||
        litres <= 0 ||
        litres > FuelEntry.maxLitres ||
        price == null ||
        rate == null ||
        rate.isEmpty) {
      setState(() => _errors = true);
      return;
    }
    setState(() => _busy = true);
    try {
      if (!await _draft.finish()) throw StateError('Draft flush failed');
      final entry = FuelEntry(
        id: _draft.recordId,
        assetId: widget.asset.id,
        date: _date,
        litres: litres,
        priceRial: price,
        rate: rate,
        notes: _notes.text,
      );
      await widget.controller.saveFuel(entry, draftId: _draft.draftId);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      _draft.resume();
      _draft.writeFailed = true;
      if (mounted) maintenanceWriteFailure(context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null || _busy) return;
    final s = maintenanceStrings;
    final approved = await confirmMaintenanceDelete(
      context,
      title: s(context, 'fuelEntryDeleteTitle'),
      body: s(context, 'fuelEntryDeleteBody'),
    );
    if (!approved || !mounted) return;
    final messenger = NexBannerHost.of(context);
    final message = s(context, 'fuelDeleted');
    final undo = s(context, 'undo');
    final failure = s(context, 'undoFailed');
    try {
      await widget.controller.deleteFuel(existing.id);
      if (mounted) {
        Navigator.pop(context);
        MaintenanceUndo.offer(
          messenger,
          message: message,
          undoLabel: undo,
          failureMessage: failure,
          restore: () => widget.controller.restore(
            'fuel',
            existing.id,
            parentId: existing.assetId,
          ),
        );
      }
    } catch (_) {
      if (mounted) maintenanceWriteFailure(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = maintenanceStrings;
    final theme = Theme.of(context);
    final rates = _rates;
    return PopScope(
      canPop: !_dirty && !_busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_busy) {
          unawaited(
            confirmMaintenanceDiscard(
              context,
              discard: _draft.draft.clear,
              keepDraft: _draft.finish,
            ),
          );
        }
      },
      child: MaintenanceDraftFrame(
        session: _draft,
        busy: _busy,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            NexSpacing.md,
            0,
            NexSpacing.md,
            NexSpacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  s(
                    context,
                    widget.existing == null
                        ? 'fuelEntryTitle'
                        : 'fuelEditTitle',
                  ),
                  style: theme.textTheme.titleLarge,
                ),
              ),
              const SizedBox(height: NexSpacing.md),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      EventDateRow(date: _date, onTap: _pickDate),
                      const SizedBox(height: NexSpacing.md),
                      TextField(
                        key: const ValueKey('maintenance-fuel-litres'),
                        controller: _litres,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        textDirection: TextDirection.ltr,
                        decoration: InputDecoration(
                          labelText: s(context, 'fuelLitres'),
                          errorText:
                              _errors && parseMeterInput(_litres.text) == null
                              ? s(context, 'fuelBadLitres')
                              : null,
                        ),
                        onChanged: (_) => _markDirty(),
                      ),
                      const SizedBox(height: NexSpacing.md),
                      TextField(
                        key: const ValueKey('maintenance-fuel-price'),
                        controller: _price,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        textDirection: TextDirection.ltr,
                        decoration: InputDecoration(
                          labelText: s(context, 'fuelPrice'),
                          hintText: s(context, 'fuelPriceHint'),
                          errorText:
                              _errors && rialFromTomanInput(_price.text) == null
                              ? s(context, 'fuelBadPrice')
                              : null,
                        ),
                        onChanged: (_) => _markDirty(),
                      ),
                      const SizedBox(height: NexSpacing.md),
                      Text(
                        s(context, 'fuelRateLabel'),
                        style: theme.textTheme.labelLarge,
                      ),
                      const SizedBox(height: NexSpacing.xs),
                      if (rates.isEmpty)
                        Text(
                          s(context, 'fuelRateRequired'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        )
                      else
                        Wrap(
                          spacing: NexSpacing.sm,
                          runSpacing: NexSpacing.xs,
                          children: [
                            for (final rate in rates)
                              ChoiceChip(
                                key: ValueKey(
                                  'maintenance-fuel-rate-${rate.name}',
                                ),
                                label: Text(rate.name),
                                selected: _rate == rate.name,
                                onSelected: (_) {
                                  setState(() => _rate = rate.name);
                                  _markDirty();
                                },
                              ),
                          ],
                        ),
                      const SizedBox(height: NexSpacing.md),
                      NexTextField(
                        key: const ValueKey('maintenance-fuel-notes'),
                        controller: _notes,
                        minLines: 2,
                        maxLines: 3,
                        decoration: InputDecoration(
                          labelText: s(context, 'fuelNotesLabel'),
                          hintText: s(context, 'fuelNotesHint'),
                        ),
                        onChanged: (_) => _markDirty(),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: NexSpacing.sm),
              FilledButton(
                key: const ValueKey('maintenance-fuel-save'),
                onPressed: _busy ? null : () => unawaited(_save()),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: Text(s(context, 'fuelSave')),
              ),
              if (widget.existing != null)
                TextButton(
                  key: const ValueKey('maintenance-fuel-delete'),
                  onPressed: _busy ? null : () => unawaited(_delete()),
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: Text(s(context, 'delete')),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
