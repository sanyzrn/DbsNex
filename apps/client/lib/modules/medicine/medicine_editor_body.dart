part of 'medicine_editor.dart';

extension _MedicineEditorBody on _MedicineEditorSheetState {
  Widget _editorBody(BuildContext context) {
    final strings = medicineStrings;
    final theme = Theme.of(context);
    final timeShown = _time.text.trim();
    final timeBad =
        timeShown.isNotEmpty && (_addTime() == null || _timeOverflow);

    // The keyboard must not cover the save button: the module's own body
    // wrapper, because `NexSheetBody` is not part of the module API.
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_maybePop());
      },
      child: CheckpointFrame(
        session: _session,
        strings: strings,
        child: Padding(
          padding: EdgeInsets.only(bottom: viewInsets),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(NexSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings(
                    context,
                    widget.existing != null ? 'editMedicine' : 'addMedicine',
                  ),
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: NexSpacing.md),
                MedicineFields.line(
                  fieldKey: const ValueKey('medicine-field-name'),
                  controller: _name,
                  label: strings(context, 'name'),
                  hint: strings(context, 'nameHint'),
                  helper: _showErrors && _name.text.trim().isEmpty
                      ? strings(context, 'nameRequired')
                      : null,
                ),
                const SizedBox(height: NexSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: MedicineFields.line(
                        fieldKey: const ValueKey('medicine-field-strength'),
                        controller: _strength,
                        label: strings(context, 'strength'),
                        hint: strings(context, 'strengthHint'),
                      ),
                    ),
                    const SizedBox(width: NexSpacing.sm),
                    Expanded(
                      child: MedicineFields.line(
                        fieldKey: const ValueKey('medicine-field-package'),
                        controller: _packageUnit,
                        label: strings(context, 'packageUnit'),
                        hint: strings(context, 'packageHint'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: NexSpacing.sm),
                MedicineTextField(
                  key: const ValueKey('medicine-instructions'),
                  controller: _instructions,
                  hint: strings(context, 'instructionsHint'),
                ),
                const SizedBox(height: NexSpacing.lg),
                Text(
                  strings(context, 'times'),
                  style: theme.textTheme.titleSmall,
                ),
                Text(
                  strings(context, 'timesNote'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: NexSpacing.sm),
                if (_times.isNotEmpty)
                  MedicineTimeChips(
                    times: _times,
                    onRemoved: (time) {
                      _paint(() {
                        _times = _times.where((t) => t != time).toList();
                        _dirty = true;
                      });
                      _session.changed();
                    },
                  ),
                MedicineFields.line(
                  fieldKey: const ValueKey('medicine-field-time'),
                  controller: _time,
                  label: strings(context, 'times'),
                  hint: strings(context, 'timesHint'),
                  keyboard: TextInputType.datetime,
                  helper: _showErrors && timeBad
                      ? strings(
                          context,
                          _timeOverflow ? 'timeLimit' : 'badTime',
                          {'count': MedicineModels.timesLimit},
                        )
                      : null,
                  onSubmitted: _rememberTime,
                ),
                const SizedBox(height: NexSpacing.sm),
                MedicineFields.line(
                  fieldKey: const ValueKey('medicine-field-days'),
                  controller: _days,
                  label: strings(context, 'days'),
                  hint: strings(context, 'daysHint'),
                ),
                const SizedBox(height: NexSpacing.sm),
                MedicineTextField(
                  key: const ValueKey('medicine-purpose'),
                  controller: _purpose,
                  hint: strings(context, 'purposeHint'),
                ),
                const SizedBox(height: NexSpacing.lg),
                MedicineNumberFields(
                  quantity: _quantity,
                  doseUnits: _doseUnits,
                  refill: _refill,
                  expiry: _expiry,
                  showErrors: _showErrors,
                ),
                const SizedBox(height: NexSpacing.lg),
                Text(
                  strings(context, 'safetyNote'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: NexSpacing.md),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const ValueKey('medicine-save'),
                    onPressed: _session.busy ? null : _save,
                    child: Text(strings(context, 'save')),
                  ),
                ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    key: const ValueKey('medicine-keep-draft'),
                    onPressed: _session.busy ? null : _keepDraft,
                    child: Text(strings(context, 'keepDraft')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
