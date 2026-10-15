import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'controller.dart';
import 'maintenance_common.dart';
import 'models.dart';
import 'strings.dart';
import 'units.dart';
import 'editor_draft.dart';

part 'asset_editor_actions.dart';

/// Creates or edits an asset: name, type, model, purchase date, what
/// it counts and in which unit, notes. Switching a distance unit
/// offers an explicit, exact conversion of existing readings and
/// rules — never a silent relabelling — and guards unsaved work on
/// the way out.
Future<void> showAssetEditor(
  BuildContext context, {
  required MaintenanceController controller,
  MaintenanceAsset? existing,
}) => nexShowSheet(
  context: context,
  dismissible: false,
  swipeToClose: true,
  builder: (_) => AssetEditorSheet(controller: controller, existing: existing),
);

class AssetEditorSheet extends StatefulWidget {
  const AssetEditorSheet({super.key, required this.controller, this.existing});

  final MaintenanceController controller;
  final MaintenanceAsset? existing;

  @override
  State<AssetEditorSheet> createState() => _AssetEditorSheetState();
}

class _AssetEditorSheetState extends State<AssetEditorSheet> {
  late String _type = widget.existing?.type ?? 'car';
  late MeterKind _meterKind = widget.existing?.meterKind ?? MeterKind.none;
  late DistanceUnit _distanceUnit =
      widget.existing?.distanceUnit ?? DistanceUnit.km;
  late DateTime? _purchased = widget.existing?.purchasedAt;

  late final TextEditingController _nickname = TextEditingController(
    text: widget.existing?.nickname ?? '',
  );
  late final TextEditingController _model = TextEditingController(
    text: widget.existing?.model ?? '',
  );
  late final TextEditingController _notes = TextEditingController(
    text: widget.existing?.notes ?? '',
  );

  late final MaintenanceEditorDraft _draft;
  bool _convertHistory = false, _choosingUnit = false;
  late bool _purchasedConfirmed =
      widget.existing?.source?['purchasedAt'] == null ||
      maintenanceCalendar(widget.existing!.source!['purchasedAt']) != null;
  @override
  void initState() {
    super.initState();
    _draft = MaintenanceEditorDraft(
      store: widget.controller.store,
      kind: 'asset',
      existingId: widget.existing?.id,
      base: widget.existing?.source ?? widget.existing?.toBody(),
      target: widget.existing?.id ?? widget.controller.newAssetId(),
      fields: {'nickname': _nickname, 'model': _model, 'notes': _notes},
      extra: () => {
        'type': _type,
        'meterKind': _meterKind.name,
        'unit': _distanceUnit.name,
        'purchased': _purchased?.toIso8601String(),
        'purchasedConfirmed': _purchasedConfirmed,
        'convertHistory': _convertHistory,
      },
      applyExtra: (b) {
        if (b['type'] is String && assetTypeIds.contains(b['type'])) {
          _type = b['type'] as String;
        }
        _meterKind = b['meterKind'] == 'distance'
            ? MeterKind.distance
            : b['meterKind'] == 'hours'
            ? MeterKind.hours
            : MeterKind.none;
        _distanceUnit = b['unit'] == 'mi' ? DistanceUnit.mi : DistanceUnit.km;
        _purchased = maintenanceCalendar(b['purchased']);
        _purchasedConfirmed = b['purchasedConfirmed'] != false;
        _convertHistory = b['convertHistory'] == true;
        _dirty = true;
      },
      repaint: () {
        if (mounted) setState(() {});
      },
    );
    unawaited(_draft.load());
  }

  bool _saving = false;
  bool _dirty = false;
  bool _showErrors = false;

  @override
  void dispose() {
    _draft.dispose();
    _nickname.dispose();
    _model.dispose();
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
    return PopScope(
      canPop: !_dirty && !_saving && !_choosingUnit,
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
        busy: _saving || _choosingUnit,
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
                            ? 'newAssetTitle'
                            : 'editAssetTitle',
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
                        controller: _nickname,
                        builder: (context, direction) => TextField(
                          key: const ValueKey('maintenance-nickname'),
                          controller: _nickname,
                          textDirection: direction,
                          autofocus: widget.existing == null,
                          decoration: InputDecoration(
                            labelText: s(context, 'nicknameLabel'),
                            hintText: s(context, 'nicknameHint'),
                            errorText:
                                _nickname.text.trim().isEmpty && _showErrors
                                ? s(context, 'nicknameEmpty')
                                : null,
                          ),
                          onChanged: (_) => _markDirty(),
                        ),
                      ),
                      const SizedBox(height: NexSpacing.md),
                      Text(
                        s(context, 'typeLabel'),
                        style: theme.textTheme.labelLarge,
                      ),
                      const SizedBox(height: NexSpacing.xs),
                      Wrap(
                        spacing: NexSpacing.sm,
                        runSpacing: NexSpacing.xs,
                        children: [
                          for (final type in assetTypeIds)
                            MaintenanceTypePill(
                              type: type,
                              selected: type == _type,
                              onTap: () {
                                setState(() => _type = type);
                                _markDirty();
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: NexSpacing.md),
                      NexAutoDirection(
                        controller: _model,
                        builder: (context, direction) => TextField(
                          key: const ValueKey('maintenance-model'),
                          controller: _model,
                          textDirection: direction,
                          decoration: InputDecoration(
                            labelText: s(context, 'modelLabel'),
                            hintText: s(context, 'modelHint'),
                          ),
                          onChanged: (_) => _markDirty(),
                        ),
                      ),
                      const SizedBox(height: NexSpacing.md),
                      InkWell(
                        key: const ValueKey('maintenance-purchased'),
                        onTap: () => unawaited(_pickDate()),
                        borderRadius: BorderRadius.circular(NexRadius.md),
                        child: InputDecorator(
                          decoration: InputDecoration(
                            labelText: s(context, 'purchasedLabel'),
                            contentPadding:
                                const EdgeInsetsDirectional.symmetric(
                                  horizontal: NexSpacing.md,
                                  vertical: NexSpacing.md,
                                ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _purchased == null
                                      ? s(context, 'purchasedUnset')
                                      : maintenanceFullDate(
                                          context,
                                          _purchased!,
                                        ),
                                ),
                              ),
                              const Icon(
                                Icons.calendar_today_outlined,
                                size: 20,
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_purchased != null ||
                          widget.existing?.source?['purchasedAt'] != null)
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _purchased = null;
                              _purchasedConfirmed = true;
                            });
                            _markDirty();
                          },
                          child: Text(s(context, 'clearDate')),
                        ),
                      if (!_purchasedConfirmed && _showErrors)
                        Text(
                          s(context, 'assetDateRequired'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      Text(
                        s(context, 'gregorian'),
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: NexSpacing.md),
                      Text(
                        s(context, 'meterKindLabel'),
                        style: theme.textTheme.labelLarge,
                      ),
                      const SizedBox(height: NexSpacing.xs),
                      Wrap(
                        key: const ValueKey('maintenance-meterkind'),
                        spacing: NexSpacing.sm,
                        runSpacing: NexSpacing.sm,
                        children: [
                          for (final kind in MeterKind.values)
                            MaintenanceTypePill(
                              type: kind.name,
                              label: s(
                                context,
                                kind == MeterKind.none
                                    ? 'meterKindNone'
                                    : kind == MeterKind.distance
                                    ? 'meterKindDistance'
                                    : 'meterKindHours',
                              ),
                              selected: _meterKind == kind,
                              onTap: () {
                                setState(() => _meterKind = kind);
                                _markDirty();
                              },
                            ),
                        ],
                      ),
                      if (_meterKind == MeterKind.distance) ...[
                        const SizedBox(height: NexSpacing.md),
                        Wrap(
                          key: const ValueKey('maintenance-distanceunit'),
                          spacing: NexSpacing.sm,
                          runSpacing: NexSpacing.sm,
                          children: [
                            for (final unit in DistanceUnit.values)
                              MaintenanceTypePill(
                                type: unit.name,
                                label: s(
                                  context,
                                  unit == DistanceUnit.km
                                      ? 'unitKmLabel'
                                      : 'unitMiLabel',
                                ),
                                selected: _distanceUnit == unit,
                                onTap: () => unawaited(_changeUnit(unit)),
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: NexSpacing.md),
                      // Single-line: a module cannot import the platform's
                      // multi-line NexTextField (see the README's Platform
                      // requests); direction follows the script typed.
                      NexAutoDirection(
                        controller: _notes,
                        builder: (context, direction) => TextField(
                          key: const ValueKey('maintenance-notes'),
                          controller: _notes,
                          textDirection: direction,
                          decoration: InputDecoration(
                            labelText: s(context, 'notesLabel'),
                            hintText: s(context, 'notesHint'),
                          ),
                          maxLines: 1,
                          onChanged: (_) => _markDirty(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: NexSpacing.sm),
              FilledButton(
                key: const ValueKey('maintenance-asset-save'),
                onPressed: _saving ? null : () => unawaited(_save()),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: Text(s(context, 'save')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
