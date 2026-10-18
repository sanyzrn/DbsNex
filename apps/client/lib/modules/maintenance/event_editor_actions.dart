part of 'event_editor.dart';

extension _EditorActions on _EventEditorSheetState {
  CostAmountResult get _parsedCost {
    final currency = _currency;
    if (_cost.text.trim().isEmpty) {
      return (minor: null, error: null);
    }
    if (currency == null) {
      return (minor: null, error: CostAmountError.currencyRequired);
    }
    return currency.code == 'IRR' && _irrUnit == IrrUnit.toman
        ? parseTomanCost(_cost.text)
        : parseCostAmount(_cost.text, currency);
  }

  int? get _parsedMeter {
    if (_meter.text.trim().isEmpty || _entryKind == MeterKind.none) return null;
    return parseMeterInput(_meter.text) ?? -1;
  }

  Future<void> _pickDate() async {
    final today = DateTime.now();
    final candidate = !_dateConfirmed || dayOf(_date).isAfter(dayOf(today))
        ? today
        : _date;
    final picked = await nexPickModuleDate(
      context,
      initial: candidate,
      first: DateTime(1),
      last: dayOf(today),
    );
    if (picked == null || !mounted) return;
    _paint(() {
      _date = picked;
      _dateConfirmed = true;
    });
    _markDirty();
  }

  /// A reading lower than the asset's latest in this unit is a
  /// correction, not a mistake to reject: the question is asked, the
  /// history stays complete either way.
  Future<bool> _confirmBackwards(int reading) async {
    if (!meterGoesBackwards(
      widget.controller.events,
      widget.asset.id,
      _entryUnit,
      reading,
      excludingEventId: widget.existing?.id,
      at: _date,
      kind: _entryKind,
      scale: 1000,
    )) {
      return true;
    }
    return confirmBackwardsMeter(
      context,
      unitWord: maintenanceStrings(
        context,
        _entryKind == MeterKind.hours
            ? 'unitHours'
            : _entryUnit == DistanceUnit.km
            ? 'unitKm'
            : 'unitMi',
      ),
      latest: _latestMeterInUnit(),
      scale: 1000,
    );
  }

  int _latestMeterInUnit() {
    final list =
        widget.controller.events
            .where(
              (e) =>
                  e.assetId == widget.asset.id &&
                  e.id != widget.existing?.id &&
                  validEventMeter(e) &&
                  eventMeterKind(e) == _entryKind,
            )
            .toList()
          ..sort(compareServices);
    if (list.isEmpty) return 0;
    return _entryKind == MeterKind.hours
        ? list.first.meterMilli!
        : convertMilli(
            list.first.meterMilli!,
            list.first.meterUnit!,
            _entryUnit,
          );
  }

  Future<void> _save() async {
    if (_saving) return;
    final cost = _parsedCost, meter = _parsedMeter;
    if (_task.text.trim().isEmpty ||
        cost.error != null ||
        meter == -1 ||
        !_dateConfirmed ||
        dayOf(_date).isAfter(dayOf(DateTime.now()))) {
      _paint(() => _showErrors = true);
      return;
    }
    _paint(() => _saving = true);
    try {
      await widget.controller.load();
      if (widget.controller.readFailed) throw StateError('Read failed');
      if (!mounted) return;
      if (meter != null && !await _confirmBackwards(meter)) return;
      if (!mounted) return;
      if (!await _draft.finish()) throw StateError('Draft flush failed');
      final event = _buildEvent(
        id: _draft.recordId,
        cost: cost.minor,
        meter: meter,
      );
      final groups = <String, List<String>>{
        'task': ['task'],
        'date': ['date', 'dateConfirmed'],
        'provider': ['provider'],
        'notes': ['notes'],
      };
      for (final key in [
        'cost',
        'currency',
        'currency_code',
        'currency_exponent',
      ]) {
        groups[key] = ['cost', 'currency', 'irrUnit'];
      }
      for (final key in ['meter', 'meter_scale', 'meter_kind', 'meterUnit']) {
        groups[key] = ['meter', 'meterKind', 'unit'];
      }
      final keys = _draft.editedKeys(groups);
      await widget.controller.saveEvent(
        event,
        existing: widget.existing,
        editedKeys: widget.existing == null ? null : keys,
        draftId: _draft.draftId,
      );
      if (mounted) Navigator.pop(context);
    } catch (_) {
      _draft.resume();
      _draft.writeFailed = true;
      if (mounted) maintenanceWriteFailure(context);
    } finally {
      if (mounted) _paint(() => _saving = false);
    }
  }

  ServiceEvent _buildEvent({required String id, int? cost, int? meter}) =>
      ServiceEvent(
        id: id,
        assetId: widget.asset.id,
        date: _date,
        task: _task.text.trim(),
        cost: cost,
        currency: cost == null ? null : _currency!.code,
        meter: meter,
        meterScale: 1000,
        meterKind: _entryKind,
        meterUnit: meter == null
            ? null
            : _entryKind == MeterKind.hours
            ? null
            : _entryUnit,
        provider: _provider.text.trim().isEmpty ? null : _provider.text.trim(),
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      );

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null || _saving) return;
    final confirmed = await confirmMaintenanceDelete(
      context,
      title: maintenanceStrings(context, 'deleteEventTitle'),
      body: maintenanceStrings(context, 'deleteEventBody'),
    );
    if (!confirmed || !mounted) return;
    final messenger = ScaffoldMessenger.of(context),
        message = maintenanceStrings(context, 'deletedEvent'),
        undo = maintenanceStrings(context, 'undo'),
        failure = maintenanceStrings(context, 'undoFailed');
    _paint(() => _saving = true);
    try {
      if (!await _draft.finish()) throw StateError('Draft flush failed');
      await widget.controller.deleteEvent(existing.id);
      if (mounted) {
        Navigator.pop(context);
        MaintenanceUndo.offer(
          messenger,
          message: message,
          undoLabel: undo,
          failureMessage: failure,
          restore: () => widget.controller.restore(
            'event',
            existing.id,
            parentId: widget.asset.id,
          ),
        );
      }
    } catch (_) {
      _draft.resume();
      _draft.writeFailed = true;
      if (mounted) maintenanceWriteFailure(context);
    } finally {
      if (mounted) _paint(() => _saving = false);
    }
  }
}
