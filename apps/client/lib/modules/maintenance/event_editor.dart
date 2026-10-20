import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'controller.dart';
import 'maintenance_common.dart';
import 'costs.dart';
import 'event_fields.dart';
import 'logic.dart';
import 'models.dart';
import 'strings.dart';
import 'units.dart';
import 'local_values.dart';
import 'editor_draft.dart';
import 'maintenance_undo.dart';

part 'event_editor_actions.dart';

/// Logs or edits a service: what was done, when, the optional cost,
/// the metre reading (with the correction question when it goes
/// backwards), the provider and notes. Deleting offers Undo; unsaved
/// work is guarded; a repeat prefills from the previous service.
Future<void> showEventEditor(
  BuildContext context, {
  required MaintenanceController controller,
  required MaintenanceAsset asset,
  ServiceEvent? existing,
  ServiceEvent? repeatOf,
}) => nexShowSheet(
  context: context,
  dismissible: false,
  swipeToClose: true,
  builder: (_) => EventEditorSheet(
    controller: controller,
    asset: asset,
    existing: existing,
    repeatOf: repeatOf,
  ),
);

class EventEditorSheet extends StatefulWidget {
  const EventEditorSheet({
    super.key,
    required this.controller,
    required this.asset,
    this.existing,
    this.repeatOf,
  });

  final MaintenanceController controller;
  final MaintenanceAsset asset;
  final ServiceEvent? existing;
  final ServiceEvent? repeatOf;

  @override
  State<EventEditorSheet> createState() => _EventEditorSheetState();
}

class _EventEditorSheetState extends State<EventEditorSheet> {
  late final ServiceEvent? _seed = widget.existing ?? widget.repeatOf;
  late DateTime _date = widget.existing?.date ?? DateTime.now();

  late final TextEditingController _task = TextEditingController(
    text: _seed?.task ?? '',
  );
  late final TextEditingController _cost = TextEditingController(
    text: () {
      final seed = _seed;
      if (seed == null ||
          seed.cost == null ||
          seed.cost! < 0 ||
          seed.cost! > costMax ||
          costCurrencyOf(seed.currency) == null) {
        return '';
      }
      return costMajorText(seed.cost!, costExponentOf(seed.currency));
    }(),
  );
  late final TextEditingController _meter = TextEditingController(
    text: widget.existing?.meterValid == true && widget.existing?.meter != null
        ? meterInputText(
            widget.existing!.meter!,
            scale: widget.existing!.meterScale,
          )
        : '',
  );
  late final TextEditingController _provider = TextEditingController(
    text: _seed?.provider ?? '',
  );
  late final TextEditingController _notes = TextEditingController(
    text: _seed?.notes ?? '',
  );

  late CostCurrency? _currency = _initialCurrency();
  late IrrUnit _irrUnit = IrrUnit.rial;

  late final MaintenanceEditorDraft _draft;
  late MeterKind _entryKind = widget.existing == null
      ? widget.asset.meterKind
      : eventMeterKind(widget.existing!);
  late DistanceUnit _entryUnit =
      widget.existing?.meterUnit ?? widget.asset.distanceUnit;
  late bool _dateConfirmed =
      widget.existing?.source == null ||
      LocalValues.stamp(widget.existing!.source!['date']) != null;
  @override
  void initState() {
    super.initState();
    _draft = MaintenanceEditorDraft(
      store: widget.controller.store,
      kind: 'event',
      existingId: widget.existing?.id,
      base:
          widget.existing?.source ??
          (widget.existing == null
              ? {'parentId': widget.asset.id}
              : widget.existing!.toBody()),
      target: widget.existing?.id ?? widget.controller.newEventId(),
      scope: widget.existing == null
          ? 'event:${widget.asset.id}:${widget.repeatOf == null ? 'new' : 'repeat:${widget.repeatOf!.id}:new'}'
          : null,
      fields: {
        'task': _task,
        'cost': _cost,
        'meter': _meter,
        'provider': _provider,
        'notes': _notes,
      },
      extra: () => {
        'parentId': widget.asset.id,
        'date': _date.toIso8601String(),
        'dateConfirmed': _dateConfirmed,
        'currency': _currency?.code,
        'irrUnit': _irrUnit.name,
        'meterKind': _entryKind.name,
        'unit': _entryUnit.name,
      },
      applyExtra: (b) {
        _date = maintenanceCalendar(b['date']) ?? _date;
        _dateConfirmed = b['dateConfirmed'] != false;
        _currency = costCurrencyOf(
          b['currency'] is String ? b['currency'] as String : null,
        );
        _irrUnit = b['irrUnit'] == 'toman' ? IrrUnit.toman : IrrUnit.rial;
        _entryKind = b['meterKind'] == 'hours'
            ? MeterKind.hours
            : b['meterKind'] == 'distance'
            ? MeterKind.distance
            : MeterKind.none;
        _entryUnit = b['unit'] == 'mi' ? DistanceUnit.mi : DistanceUnit.km;
        _dirty = true;
      },
      repaint: () {
        if (mounted) setState(() {});
      },
    );
    unawaited(_draft.load());
  }

  MaintenanceAsset get _meterContext => MaintenanceAsset(
    id: widget.asset.id,
    nickname: widget.asset.nickname,
    type: widget.asset.type,
    meterKind: _entryKind,
    distanceUnit: _entryUnit,
  );
  bool _saving = false;
  bool _dirty = false;
  bool _showErrors = false;

  CostCurrency? _initialCurrency() => costCurrencyOf(_seed?.currency);

  @override
  void dispose() {
    _draft.dispose();
    _task.dispose();
    _cost.dispose();
    _meter.dispose();
    _provider.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _markDirty() {
    setState(() => _dirty = true);
    _draft.changed();
  }

  void _paint(VoidCallback run) => setState(run);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = maintenanceStrings;
    final cost = _parsedCost;
    return PopScope(
      canPop: !_dirty && !_saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_saving) {
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
        busy: _saving,
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
              Row(
                children: [
                  Expanded(
                    child: Text(
                      s(
                        context,
                        widget.existing == null
                            ? 'newEventTitle'
                            : 'editEventTitle',
                      ),
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: s(context, 'cancel'),
                    onPressed: () => Navigator.maybePop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      NexAutoDirection(
                        controller: _task,
                        builder: (context, direction) => TextField(
                          key: const ValueKey('maintenance-task'),
                          controller: _task,
                          textDirection: direction,
                          autofocus: _task.text.isEmpty,
                          decoration: InputDecoration(
                            labelText: s(context, 'taskLabel'),
                            hintText: s(context, 'taskHint'),
                            errorText: _task.text.trim().isEmpty && _showErrors
                                ? s(context, 'taskEmpty')
                                : null,
                          ),
                          onChanged: (_) => _markDirty(),
                        ),
                      ),
                      const SizedBox(height: NexSpacing.md),
                      EventDateRow(
                        date: _date,
                        confirmed: _dateConfirmed,
                        onTap: () => unawaited(_pickDate()),
                      ),
                      const SizedBox(height: NexSpacing.md),
                      if (_entryKind != MeterKind.none)
                        EventMeterField(
                          controller: _meter,
                          asset: _meterContext,
                          invalid: _parsedMeter == -1,
                          onChanged: _markDirty,
                        ),

                      if (_showErrors &&
                          (!_dateConfirmed ||
                              dayOf(_date).isAfter(dayOf(DateTime.now()))))
                        Text(
                          maintenanceStrings(context, 'dateRequired'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      if (widget.repeatOf != null)
                        Text(
                          maintenanceStrings(context, 'repeatVerify'),
                          style: theme.textTheme.bodySmall,
                        ),
                      const SizedBox(height: NexSpacing.md),
                      EventCostFields(
                        controller: _cost,
                        currency: _currency,
                        irrUnit: _irrUnit,
                        error: _costErrorText(context, cost.error),
                        onChanged: _markDirty,
                        onCurrencyChanged: (currency) {
                          setState(() => _currency = currency);
                          _markDirty();
                        },
                        onIrrUnitChanged: (unit) {
                          final minor = _parsedCost.minor;
                          if (minor != null) {
                            _cost.text = costMajorText(
                              minor,
                              unit == IrrUnit.toman ? 3 : _currency!.exponent,
                            );
                          }
                          setState(() => _irrUnit = unit);
                          _markDirty();
                        },
                      ),
                      const SizedBox(height: NexSpacing.md),
                      NexAutoDirection(
                        controller: _provider,
                        builder: (context, direction) => TextField(
                          key: const ValueKey('maintenance-provider'),
                          controller: _provider,
                          textDirection: direction,
                          decoration: InputDecoration(
                            labelText: s(context, 'providerLabel'),
                            hintText: s(context, 'providerHint'),
                          ),
                          onChanged: (_) => _markDirty(),
                        ),
                      ),
                      const SizedBox(height: NexSpacing.md),
                      // The shared multiline editor: the platform's own
                      // per-paragraph direction on Android (ADR-037).
                      NexTextField(
                        key: const ValueKey('maintenance-event-notes'),
                        controller: _notes,
                        minLines: 2,
                        maxLines: 4,
                        decoration: InputDecoration(
                          labelText: s(context, 'notesLabelEvent'),
                          hintText: s(context, 'notesHintEvent'),
                        ),
                        onChanged: (_) => _markDirty(),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: NexSpacing.sm),
              FilledButton(
                key: const ValueKey('maintenance-event-save'),
                onPressed: _saving ? null : () => unawaited(_save()),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: Text(s(context, 'save')),
              ),
              if (widget.existing != null) ...[
                const SizedBox(height: NexSpacing.sm),
                TextButton(
                  key: const ValueKey('maintenance-event-delete'),
                  onPressed: _saving ? null : () => unawaited(_delete()),
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: Text(s(context, 'delete')),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String? _costErrorText(
    BuildContext context,
    CostAmountError? error,
  ) => switch (error) {
    null => null,
    CostAmountError.empty => null,
    CostAmountError.currencyRequired => maintenanceStrings(
      context,
      'currencyRequired',
    ),
    CostAmountError.zero => maintenanceStrings(context, 'costZero'),
    CostAmountError.notANumber => maintenanceStrings(context, 'errNotNumber'),
    CostAmountError.tooPrecise => maintenanceStrings(context, 'errTooPrecise'),
    CostAmountError.tooLarge => maintenanceStrings(context, 'errTooLarge'),
  };
}
