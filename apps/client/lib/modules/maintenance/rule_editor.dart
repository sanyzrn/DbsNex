import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'controller.dart';
import 'maintenance_common.dart';
import 'models.dart';
import 'strings.dart';
import 'units.dart';
import 'local_values.dart';
import 'editor_draft.dart';
import 'maintenance_undo.dart';

part 'rule_editor_actions.dart';

/// Creates or edits one interval rule for one asset and task: every N
/// days or months (end-of-month convention documented in
/// `units.dart`), and/or every N kilometres, miles or hours in the
/// asset's own unit — with both, whichever comes first is due.
Future<void> showRuleEditor(
  BuildContext context, {
  required MaintenanceController controller,
  required MaintenanceAsset asset,
  IntervalRule? existing,
}) => nexShowSheet(
  context: context,
  dismissible: false,
  swipeToClose: true,
  builder: (_) =>
      RuleEditorSheet(controller: controller, asset: asset, existing: existing),
);

class RuleEditorSheet extends StatefulWidget {
  const RuleEditorSheet({
    super.key,
    required this.controller,
    required this.asset,
    this.existing,
  });

  final MaintenanceController controller;
  final MaintenanceAsset asset;
  final IntervalRule? existing;

  @override
  State<RuleEditorSheet> createState() => _RuleEditorSheetState();
}

class _RuleEditorSheetState extends State<RuleEditorSheet> {
  late final TextEditingController _task = TextEditingController(
    text: widget.existing?.task ?? '',
  );
  late final TextEditingController _time = TextEditingController(
    text: _initialTime(),
  );
  late final TextEditingController _usage = TextEditingController(
    text: widget.existing?.meters != null
        ? meterInputText(
            widget.existing!.meters!,
            scale: widget.existing!.meterScale,
          )
        : (widget.existing?.hours != null
              ? meterInputText(
                  widget.existing!.hours!,
                  scale: widget.existing!.meterScale,
                )
              : ''),
  );

  late TimeMode _timeMode = widget.existing?.months != null
      ? TimeMode.months
      : TimeMode.days;
  late UsageMode _usageMode = _initialUsageMode();

  late final MaintenanceEditorDraft _draft;
  late DistanceUnit _ruleUnit =
      widget.existing?.meterUnit ?? widget.asset.distanceUnit;
  bool _saving = false;
  bool _dirty = false;
  bool _showErrors = false;

  bool _useTime = true;
  bool _useUsage = false;

  @override
  void initState() {
    super.initState();
    _useTime =
        widget.existing?.days != null ||
        widget.existing?.months != null ||
        widget.existing == null;
    _useUsage =
        widget.existing?.meters != null || widget.existing?.hours != null;
    _draft = MaintenanceEditorDraft(
      store: widget.controller.store,
      kind: 'rule',
      existingId: widget.existing?.id,
      base:
          widget.existing?.source ??
          (widget.existing == null
              ? {'parentId': widget.asset.id}
              : widget.existing!.toBody()),
      target: widget.existing?.id ?? 'rule-${widget.controller.store.newId()}',
      scope: widget.existing == null ? 'rule:${widget.asset.id}:new' : null,
      fields: {'task': _task, 'time': _time, 'usage': _usage},
      extra: () => {
        'parentId': widget.asset.id,
        'timeMode': _timeMode.name,
        'usageMode': _usageMode.name,
        'useTime': _useTime,
        'useUsage': _useUsage,
        'unit': _ruleUnit.name,
      },
      applyExtra: (b) {
        _timeMode = b['timeMode'] == 'months' ? TimeMode.months : TimeMode.days;
        _usageMode = b['usageMode'] == 'hours'
            ? UsageMode.hours
            : UsageMode.distance;
        _useTime = b['useTime'] == true;
        _useUsage = b['useUsage'] == true;
        _ruleUnit = b['unit'] == 'mi' ? DistanceUnit.mi : DistanceUnit.km;
        _dirty = true;
      },
      repaint: () {
        if (mounted) setState(() {});
      },
    );
    unawaited(_draft.load());
  }

  String _initialTime() {
    final rule = widget.existing;
    if (rule == null) return '';
    if (rule.days != null) return '${rule.days}';
    if (rule.months != null) return '${rule.months}';
    return '';
  }

  UsageMode _initialUsageMode() {
    if (widget.existing?.meters != null) return UsageMode.distance;
    if (widget.existing?.hours != null) return UsageMode.hours;
    return widget.asset.meterKind == MeterKind.hours
        ? UsageMode.hours
        : UsageMode.distance;
  }

  @override
  void dispose() {
    _draft.dispose();
    _task.dispose();
    _time.dispose();
    _usage.dispose();
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
    final assetCountsDistance = widget.asset.meterKind == MeterKind.distance;
    final assetCountsHours = widget.asset.meterKind == MeterKind.hours;
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
                            ? 'newRuleTitle'
                            : 'editRuleTitle',
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
                          key: const ValueKey('maintenance-rule-task'),
                          controller: _task,
                          textDirection: direction,
                          autofocus: _task.text.isEmpty,
                          decoration: InputDecoration(
                            labelText: s(context, 'ruleTaskLabel'),
                            hintText: s(context, 'ruleTaskHint'),
                            errorText: _task.text.trim().isEmpty && _showErrors
                                ? s(context, 'ruleTaskEmpty')
                                : null,
                          ),
                          onChanged: (_) => _markDirty(),
                        ),
                      ),
                      const SizedBox(height: NexSpacing.md),
                      MaintenanceToggleRow(
                        label: s(context, 'everyLabel'),
                        value: _useTime,
                        onChanged: (value) {
                          setState(() => _useTime = value);
                          _markDirty();
                        },
                      ),
                      if (_useTime) ...[
                        SegmentedButton<TimeMode>(
                          key: const ValueKey('maintenance-timemode'),
                          segments: [
                            ButtonSegment(
                              value: TimeMode.days,
                              label: Text(s(context, 'timeModeDays')),
                            ),
                            ButtonSegment(
                              value: TimeMode.months,
                              label: Text(s(context, 'timeModeMonths')),
                            ),
                          ],
                          selected: {_timeMode},
                          onSelectionChanged: (set) => setState(() {
                            _timeMode = set.first;
                            _dirty = true;
                            _draft.changed();
                          }),
                        ),
                        const SizedBox(height: NexSpacing.xs),
                        TextField(
                          key: const ValueKey('maintenance-rule-time'),
                          controller: _time,
                          keyboardType: TextInputType.number,
                          textDirection: TextDirection.ltr,
                          decoration: InputDecoration(
                            suffixText: s(
                              context,
                              _timeMode == TimeMode.days
                                  ? 'daysUnit'
                                  : 'monthsUnit',
                            ),
                            errorText:
                                _showErrors &&
                                    (_parsedPositive(_time) == null ||
                                        _parsedPositive(_time) == -1)
                                ? s(context, 'invalidRule')
                                : null,
                          ),
                          onChanged: (_) => _markDirty(),
                        ),
                      ],
                      const SizedBox(height: NexSpacing.md),
                      if (assetCountsDistance || assetCountsHours)
                        MaintenanceToggleRow(
                          label: s(context, 'usageLabel'),
                          value: _useUsage,
                          onChanged: (value) {
                            setState(() {
                              _useUsage = value;
                              final fresh =
                                  widget.asset.meterKind == MeterKind.hours
                                  ? UsageMode.hours
                                  : UsageMode.distance;
                              if (value && fresh != _usageMode) {
                                _usageMode = fresh;
                                _usage.clear();
                              }
                            });
                            _markDirty();
                          },
                        )
                      else
                        Text(
                          s(context, 'usageNone'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      if (_useUsage &&
                          (assetCountsDistance || assetCountsHours)) ...[
                        TextField(
                          key: const ValueKey('maintenance-rule-usage'),
                          controller: _usage,
                          keyboardType: TextInputType.number,
                          textDirection: TextDirection.ltr,
                          decoration: InputDecoration(
                            suffixText: assetCountsHours
                                ? s(context, 'unitHours')
                                : s(
                                    context,
                                    _ruleUnit == DistanceUnit.km
                                        ? 'unitKm'
                                        : 'unitMi',
                                  ),
                            errorText:
                                _showErrors &&
                                    (_parsedPositive(_usage) == null ||
                                        _parsedPositive(_usage) == -1)
                                ? s(context, 'invalidRule')
                                : null,
                          ),
                          onChanged: (_) => _markDirty(),
                        ),
                        const SizedBox(height: NexSpacing.xs),
                        Text(
                          s(context, 'earliestNote'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (_showErrors)
                Text(
                  s(context, 'invalidRule'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              const SizedBox(height: NexSpacing.sm),
              FilledButton(
                key: const ValueKey('maintenance-rule-save'),
                onPressed: _saving ? null : () => unawaited(_save()),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: Text(s(context, 'save')),
              ),
              if (widget.existing != null) ...[
                const SizedBox(height: NexSpacing.sm),
                TextButton(
                  key: const ValueKey('maintenance-rule-delete'),
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
}

enum TimeMode { days, months }

enum UsageMode { distance, hours }
