import 'dart:async';
import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';
import 'controller.dart';
import 'models.dart';
import 'logic.dart';
import 'units.dart';
import 'strings.dart';
import 'editor_draft.dart';
import 'maintenance_common.dart';

Future<void> showReadingEditor(
  BuildContext context, {
  required MaintenanceController controller,
  required MaintenanceAsset asset,
}) => nexShowSheet(
  context: context,
  dismissible: false,
  swipeToClose: true,
  builder: (_) => ReadingEditor(controller: controller, asset: asset),
);

class ReadingEditor extends StatefulWidget {
  const ReadingEditor({
    super.key,
    required this.controller,
    required this.asset,
  });
  final MaintenanceController controller;
  final MaintenanceAsset asset;
  @override
  State<ReadingEditor> createState() => _ReadingEditorState();
}

class _ReadingEditorState extends State<ReadingEditor> {
  final _value = TextEditingController();
  late final MaintenanceEditorDraft _draft;
  late MeterKind _kind = widget.asset.meterKind;
  late DistanceUnit _unit = widget.asset.distanceUnit;
  bool _busy = false, _dirty = false, _errors = false;
  @override
  void initState() {
    super.initState();
    _draft = MaintenanceEditorDraft(
      store: widget.controller.store,
      kind: 'reading',
      scope: 'reading:${widget.asset.id}:new',
      base: {'parentId': widget.asset.id},
      fields: {'value': _value},
      extra: () => {
        'parentId': widget.asset.id,
        'kind': _kind.name,
        'unit': _unit.name,
      },
      applyExtra: (b) {
        _kind = b['kind'] == 'hours' ? MeterKind.hours : MeterKind.distance;
        _unit = b['unit'] == 'mi' ? DistanceUnit.mi : DistanceUnit.km;
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
    _value.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    final value = parseMeterInput(_value.text);
    if (value == null) {
      setState(() => _errors = true);
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.controller.load();
      if (widget.controller.readFailed) throw StateError('Read failed');
      if (!mounted) return;
      final inputAsset = MaintenanceAsset(
        id: widget.asset.id,
        nickname: widget.asset.nickname,
        type: widget.asset.type,
        meterKind: _kind,
        distanceUnit: _unit,
      );
      final previous = latestEnteredMeter(
        inputAsset,
        widget.controller.events,
        widget.controller.readings,
        DateTime.now(),
      );
      var corrected = false;
      if (previous != null && value < previous.value) {
        final answer = await nexShowDialog<bool>(
          context: context,
          builder: (dialog) => AlertDialog(
            title: Text(maintenanceStrings(dialog, 'readingCorrection')),
            content: NexDialogBody(
              child: Text(maintenanceStrings(dialog, 'readingCorrectionBody')),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog, false),
                child: Text(maintenanceStrings(dialog, 'keepEditing')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialog, true),
                child: Text(maintenanceStrings(dialog, 'keepIt')),
              ),
            ],
          ),
        );
        if (answer != true || !mounted) return;
        corrected = true;
      }
      if (!await _draft.finish()) throw StateError('Draft flush failed');
      final entry = MaintenanceReading(
        id: _draft.recordId,
        assetId: widget.asset.id,
        value: value,
        kind: _kind,
        unit: _kind == MeterKind.distance ? _unit : null,
        at: DateTime.now().toUtc(),
        corrected: corrected,
      );
      await widget.controller.saveReading(entry, draftId: _draft.draftId);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      _draft.resume();
      _draft.writeFailed = true;
      if (mounted) maintenanceWriteFailure(context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = maintenanceStrings;
    final unit = s(
      context,
      _kind == MeterKind.hours
          ? 'unitHours'
          : _unit == DistanceUnit.km
          ? 'unitKm'
          : 'unitMi',
    );
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
          padding: const EdgeInsets.all(NexSpacing.md),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  s(context, 'readingTitle'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: IconButton(
                    tooltip: s(context, 'cancel'),
                    icon: const Icon(Icons.close),
                    onPressed: _busy ? null : () => Navigator.maybePop(context),
                  ),
                ),
                const SizedBox(height: NexSpacing.md),
                TextField(
                  key: const ValueKey('maintenance-current-meter'),
                  controller: _value,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(
                    labelText: s(context, 'readingValue'),
                    suffixText: unit,
                    errorText: _errors && parseMeterInput(_value.text) == null
                        ? s(context, 'readingInvalid')
                        : null,
                  ),
                  onChanged: (_) {
                    setState(() => _dirty = true);
                    _draft.changed();
                  },
                ),
                const SizedBox(height: NexSpacing.sm),
                Text(
                  s(context, 'readingNote'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: NexSpacing.md),
                FilledButton(
                  key: const ValueKey('maintenance-reading-save'),
                  onPressed: _busy ? null : () => unawaited(_save()),
                  child: Text(s(context, 'save')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
