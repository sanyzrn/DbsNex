part of 'medicine_today_page.dart';

/// One routine moment as the Today page draws it.
extension _MedicineTodayRows on _MedicineTodayPageState {
  Widget _slotRow(
    BuildContext context,
    _DoseSlot slot, {
    required NexModuleStrings strings,
  }) {
    final theme = Theme.of(context);
    final body = slot.medicine.body;
    final name = MedicineModels.readString(body, 'name');
    final person = MedicineModels.readPerson(body);
    final log = slot.log;
    final action = log == null
        ? ''
        : MedicineModels.readString(log.body, 'action');
    final loggedTime = log == null
        ? null
        : MedicineModels.readDate(log.body, 'at')?.toLocal();
    final status = log == null
        ? strings(context, 'noRecord')
        : strings(
            context,
            action == MedicineModels.taken ? 'loggedTaken' : 'loggedSkipped',
            {'time': MedicineFields.hm(context, loggedTime ?? slot.at)},
          );

    return Padding(
      padding: const EdgeInsets.only(bottom: NexSpacing.sm),
      child: NexPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              key: ValueKey(
                'medicine-today-${slot.day}-${slot.medicine.id}-${slot.time}',
              ),
              onTap: () => unawaited(_open(slot.medicine)),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: theme.textTheme.titleMedium),
                        Text(
                          [
                            MedicineFields.digits(context, slot.time),
                            if (person.isNotEmpty) person,
                            status,
                          ].join(' · '),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: log == null
                                ? theme.colorScheme.onSurfaceVariant
                                : theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: NexSpacing.sm),
            if (log == null)
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      key: ValueKey(
                        'medicine-today-taken-${slot.day}-${slot.medicine.id}-${slot.time}',
                      ),
                      onPressed: _busy
                          ? null
                          : () => unawaited(_log(slot, MedicineModels.taken)),
                      icon: const Icon(Icons.check_outlined),
                      label: Text(strings(context, 'taken')),
                    ),
                  ),
                  const SizedBox(width: NexSpacing.sm),
                  Expanded(
                    child: OutlinedButton.icon(
                      key: ValueKey(
                        'medicine-today-skipped-${slot.day}-${slot.medicine.id}-${slot.time}',
                      ),
                      onPressed: _busy
                          ? null
                          : () => unawaited(_log(slot, MedicineModels.skipped)),
                      icon: const Icon(Icons.remove_outlined),
                      label: Text(strings(context, 'skipped')),
                    ),
                  ),
                ],
              )
            else
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton.icon(
                  key: ValueKey(
                    'medicine-today-correct-${slot.day}-${slot.medicine.id}-${slot.time}',
                  ),
                  onPressed: _busy ? null : () => unawaited(_correct(slot)),
                  icon: const Icon(Icons.undo),
                  label: Text(AppLocalizations.of(context).delete),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
