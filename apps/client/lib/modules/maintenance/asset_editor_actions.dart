part of 'asset_editor.dart';

extension _EditorActions on _AssetEditorSheetState {
  Future<void> _pickDate() async {
    final candidate = _purchased ?? DateTime.now();
    final picked = await nexShowDialog<DateTime>(
      context: context,
      builder: (_) => DatePickerDialog(
        initialDate: candidate.year > 2100 ? DateTime(2100, 12, 31) : candidate,
        firstDate: DateTime(1),
        lastDate: DateTime(2100, 12, 31),
      ),
    );
    if (picked == null || !mounted) return;
    _paint(() {
      _purchased = picked;
      _purchasedConfirmed = true;
    });
    _markDirty();
  }

  /// Changing the unit asks: convert the history exactly, or keep it
  /// as entered? Either way nothing is relabelled silently.
  Future<void> _changeUnit(DistanceUnit unit) async {
    if (unit == _distanceUnit || _saving || _choosingUnit) return;
    _paint(() => _choosingUnit = true);
    try {
      final old = widget.existing;
      var convert = false;
      if (old != null && unit != old.distanceUnit) {
        final answer = await nexShowDialog<String>(
          context: context,
          builder: (dialog) => NexAlertDialog(
            title: Text(maintenanceStrings(dialog, 'convertUnitTitle')),
            content: NexDialogBody(
              child: Text(
                maintenanceStrings(dialog, 'convertUnitBody', {
                  'from': maintenanceStrings(
                    dialog,
                    old.distanceUnit == DistanceUnit.km ? 'kmFull' : 'miFull',
                  ),
                  'to': maintenanceStrings(
                    dialog,
                    unit == DistanceUnit.km ? 'kmFull' : 'miFull',
                  ),
                }),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog),
                child: Text(maintenanceStrings(dialog, 'cancel')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialog, 'keep'),
                child: Text(maintenanceStrings(dialog, 'keepOriginal')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialog, 'convert'),
                child: Text(maintenanceStrings(dialog, 'convert')),
              ),
            ],
          ),
        );
        if (answer == null || !mounted) return;
        convert = answer == 'convert';
      }
      if (mounted) {
        _paint(() {
          _distanceUnit = unit;
          _convertHistory = convert;
        });
        _markDirty();
      }
    } finally {
      if (mounted) _paint(() => _choosingUnit = false);
    }
  }

  Future<void> _save() async {
    if (_saving || _choosingUnit) return;
    if (_nickname.text.trim().isEmpty || !_purchasedConfirmed) {
      _paint(() => _showErrors = true);
      return;
    }
    _paint(() => _saving = true);
    try {
      if (!await _draft.finish()) throw StateError('Draft flush failed');
      final asset = MaintenanceAsset(
        id: _draft.recordId,
        nickname: _nickname.text.trim(),
        type: _type,
        model: _model.text.trim().isEmpty ? null : _model.text.trim(),
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        purchasedAt: _purchased,
        meterKind: _meterKind,
        distanceUnit: _distanceUnit,
        archived: widget.existing?.archived ?? false,
      );
      final keys = _draft.editedKeys({
        'nickname': ['nickname'],
        'type': ['type'],
        'model': ['model'],
        'notes': ['notes'],
        'purchasedAt': ['purchased', 'purchasedConfirmed'],
        'meterKind': ['meterKind'],
        'distanceUnit': ['unit'],
      });
      await widget.controller.saveAsset(
        asset,
        existing: widget.existing,
        convertHistory: _convertHistory,
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
}
