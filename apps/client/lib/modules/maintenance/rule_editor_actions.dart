part of 'rule_editor.dart';

extension _EditorActions on _RuleEditorSheetState {
  int? _parsedPositive(TextEditingController controller) {
    if (controller.text.trim().isEmpty) return null;
    if (identical(controller, _usage)) {
      final value = parseMeterInput(controller.text);
      return value == null || value <= 0 ? -1 : value;
    }
    final value = LocalValues.writtenCount(controller.text),
        max = _timeMode == TimeMode.months
            ? maxIntervalMonths
            : maxIntervalDays;
    return value == null || value <= 0 || value > max ? -1 : value;
  }

  Future<void> _save() async {
    if (_task.text.trim().isEmpty) {
      _paint(() => _showErrors = true);
      return;
    }
    final time = _parsedPositive(_time);
    final usage = _parsedPositive(_usage);
    if ((_useTime && time == null) ||
        (_useTime && time == -1) ||
        (_useUsage && usage == null) ||
        (_useUsage && usage == -1) ||
        (!_useTime && !_useUsage)) {
      _paint(() => _showErrors = true);
      return;
    }
    if (_saving) return;
    _paint(() => _saving = true);
    final rule = IntervalRule(
      id: _draft.recordId,
      assetId: widget.asset.id,
      meterScale: 1000,
      task: _task.text.trim(),
      days: _useTime && time != null && time > 0 && _timeMode == TimeMode.days
          ? time
          : null,
      months:
          _useTime && time != null && time > 0 && _timeMode == TimeMode.months
          ? time
          : null,
      meters:
          _useUsage &&
              usage != null &&
              usage > 0 &&
              _usageMode == UsageMode.distance
          ? usage
          : null,
      hours:
          _useUsage &&
              usage != null &&
              usage > 0 &&
              _usageMode == UsageMode.hours
          ? usage
          : null,
      meterUnit:
          _useUsage &&
              _usageMode == UsageMode.distance &&
              widget.asset.meterKind == MeterKind.distance
          ? _ruleUnit
          : null,
    );
    try {
      if (!await _draft.finish()) throw StateError('Draft flush failed');
      final groups = <String, List<String>>{
        'task': ['task'],
      };
      for (final key in ['days', 'months']) {
        groups[key] = ['time', 'timeMode', 'useTime'];
      }
      for (final key in ['meters', 'hours', 'meterUnit', 'meter_scale']) {
        groups[key] = ['usage', 'usageMode', 'useUsage', 'unit'];
      }
      await widget.controller.saveRule(
        rule,
        existing: widget.existing,
        editedKeys: widget.existing == null ? null : _draft.editedKeys(groups),
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

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null || _saving) return;
    final ok = await confirmMaintenanceDelete(
      context,
      title: maintenanceStrings(context, 'deleteRuleTitle'),
      body: maintenanceStrings(context, 'deleteRuleBody'),
    );
    if (!ok || !mounted) return;
    final messenger = ScaffoldMessenger.of(context),
        message = maintenanceStrings(context, 'deletedRule'),
        undo = maintenanceStrings(context, 'undo'),
        failure = maintenanceStrings(context, 'undoFailed');
    _paint(() => _saving = true);
    try {
      if (!await _draft.finish()) throw StateError('Draft flush failed');
      await widget.controller.deleteRule(existing.id);
      if (mounted) {
        Navigator.pop(context);
        MaintenanceUndo.offer(
          messenger,
          message: message,
          undoLabel: undo,
          failureMessage: failure,
          restore: () => widget.controller.restore(
            'rule',
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
