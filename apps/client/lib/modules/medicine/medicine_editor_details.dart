part of 'medicine_editor.dart';

/// The optional half of the form: what the person wrote in their own
/// words, the routine and the numbers. It opens by itself for a saved
/// medicine, a resumed draft, or a refused save.
extension _MedicineEditorDetails on _MedicineEditorSheetState {
  Widget _detailsFields(BuildContext context) {
    final strings = medicineStrings;
    final theme = Theme.of(context);
    final timeShown = _time.text.trim();
    final timeBad =
        timeShown.isNotEmpty && (_addTime() == null || _timeOverflow);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: NexSpacing.sm),
        MedicineTextField(
          key: const ValueKey('medicine-instructions'),
          controller: _instructions,
          hint: strings(context, 'instructionsHint'),
        ),
        const SizedBox(height: NexSpacing.lg),
        Text(
          strings(context, 'scheduleLabel'),
          style: theme.textTheme.titleSmall,
        ),
        Text(strings(context, 'scheduleNote'), style: muted),
        const SizedBox(height: NexSpacing.sm),
        MedicineWeekdayPicker(selected: _weekdays, onToggle: _toggleWeekday),
        const SizedBox(height: NexSpacing.sm),
        MedicineFields.number(
          fieldKey: const ValueKey('medicine-field-every'),
          controller: _every,
          label: strings(context, 'everyDays'),
          hint: strings(context, 'everyDaysHint'),
          helper: _showErrors && _badEveryDays
              ? strings(context, 'badEveryDays')
              : strings(context, 'everyDaysHint'),
        ),
        const SizedBox(height: NexSpacing.sm),
        NexModuleDateEntry(
          controller: _start,
          child: MedicineFields.line(
            fieldKey: const ValueKey('medicine-field-start'),
            controller: _start,
            label: strings(context, 'startsOn'),
            hint: strings(context, 'dateHint'),
            keyboard: TextInputType.datetime,
            helper: _showErrors && _badStart
                ? strings(context, 'badDate')
                : strings(context, 'startsOnNote'),
          ),
        ),
        const SizedBox(height: NexSpacing.sm),
        NexModuleDateEntry(
          controller: _end,
          child: MedicineFields.line(
            fieldKey: const ValueKey('medicine-field-end'),
            controller: _end,
            label: strings(context, 'endsOn'),
            hint: strings(context, 'dateHint'),
            keyboard: TextInputType.datetime,
            helper: _showErrors && _badEnd
                ? strings(context, 'badDate')
                : _showErrors && _badScheduleOrder
                ? strings(context, 'badDateOrder')
                : strings(context, 'endsOnNote'),
          ),
        ),
        const SizedBox(height: NexSpacing.sm),
        MedicineFields.number(
          fieldKey: const ValueKey('medicine-field-warn'),
          controller: _warn,
          label: strings(context, 'warnDays'),
          hint: strings(context, 'quantityHint'),
          helper: _showErrors && _badWarnDays
              ? strings(context, 'badWarnDays')
              : strings(context, 'warnDaysNote'),
        ),
        SwitchListTile(
          key: const ValueKey('medicine-hard-to-find'),
          contentPadding: EdgeInsets.zero,
          value: _hardToFind,
          onChanged: _setHardToFind,
          title: Text(strings(context, 'hardToFind')),
          subtitle: Text(strings(context, 'hardToFindNote')),
        ),
        const SizedBox(height: NexSpacing.lg),
        Text(strings(context, 'times'), style: theme.textTheme.titleSmall),
        Text(strings(context, 'timesNote'), style: muted),
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
              ? strings(context, _timeOverflow ? 'timeLimit' : 'badTime', {
                  'count': MedicineModels.timesLimit,
                })
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
      ],
    );
  }
}
