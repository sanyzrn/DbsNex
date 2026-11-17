part of 'medicine_screen.dart';

/// One medicine on the active list: the name as it was written, the
/// strength beside it, and the states worth reading on opening — stock,
/// expiry, refill — all from numbers the person wrote themselves.
/// One medicine on the active list: the name as it was written, the
/// strength beside it, and the states worth reading on opening — stock,
/// expiry, refill, whose it is and how long it lasts — all from numbers
/// the person wrote themselves.
class _MedicineRow extends StatelessWidget {
  const _MedicineRow({required this.record, required this.onOpen});

  final ModuleRecord record;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final strings = medicineStrings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final body = record.body;
    final name = MedicineModels.readString(body, 'name');
    final strength = MedicineModels.readString(body, 'strength');
    final packageUnit = MedicineModels.readString(body, 'package');
    final quantity = MedicineModels.readCount(body, 'quantity');
    final refillThreshold = MedicineModels.readCount(body, 'refillThreshold');
    final expiry = MedicineLogic.expiryOf(
      MedicineModels.readDate(body, 'expiresAt'),
      DateTime.now(),
    );
    final person = MedicineModels.readPerson(body);
    final doseUnits = MedicineModels.readCount(body, 'doseUnits');
    final daysLeft = MedicineLogic.runsOutInDays(
      quantity: quantity,
      doseUnits: doseUnits,
      schedule: MedicineSchedule.of(body),
    );
    final warnDays = MedicineModels.readWarnDays(body);
    final runoutWarn = MedicineLogic.runoutWarning(daysLeft, warnDays);

    final marks = <Widget>[
      if (quantity != null)
        Text(
          quantity == 0
              ? strings(context, 'quantityNone')
              : strings(context, 'quantityLeft', {
                  'count': quantity,
                  'unit': packageUnit.isEmpty
                      ? MedicineModels.readString(body, 'strength')
                      : packageUnit,
                }),
          style: theme.textTheme.bodySmall?.copyWith(
            color: MedicineLogic.needsRefill(quantity, refillThreshold)
                ? scheme.error
                : scheme.onSurfaceVariant,
          ),
        ),
      if (expiry.expired)
        Text(
          strings(context, 'expired'),
          style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
        )
      else if (expiry.soon)
        Text(
          strings(context, 'expiringSoon'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      if (MedicineLogic.needsRefill(quantity, refillThreshold) && quantity != 0)
        Text(
          strings(context, 'refillSoon'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      if (person.isNotEmpty)
        Text(
          strings(context, 'personFor', {'person': person}),
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      if (MedicineModels.readHardToFind(body))
        Text(
          strings(context, 'hardToFind'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      if (daysLeft != null && quantity != 0)
        Text(
          runoutWarn
              ? strings(context, 'startLooking')
              : medicineStrings(context, 'runsOutIn', {'count': daysLeft}),
          style: theme.textTheme.bodySmall?.copyWith(
            color: runoutWarn ? scheme.error : scheme.onSurfaceVariant,
          ),
        ),
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: NexSpacing.xs),
      child: ListTile(
        key: ValueKey('medicine-row-${record.id}'),
        onTap: onOpen,
        leading: NexIconTile(
          Icons.medication_outlined,
          color: NexHue.rose.of(theme.brightness),
        ),
        title: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium,
        ),
        subtitle: marks.isEmpty
            ? (strength.isEmpty ? null : Text(strength, maxLines: 1))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (strength.isNotEmpty) Text(strength, maxLines: 1),
                  Wrap(spacing: NexSpacing.sm, children: marks),
                ],
              ),
      ),
    );
  }
}

/// One archived medicine, one tap from coming back.
class _ArchivedRow extends StatelessWidget {
  const _ArchivedRow({
    required this.record,
    required this.onUnarchive,
    required this.onOpen,
  });

  final ModuleRecord record;
  final VoidCallback onUnarchive;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      key: ValueKey('medicine-archived-${record.id}'),
      onTap: onOpen,
      leading: NexIconTile(
        Icons.inventory_2_outlined,
        color: NexHue.slate.of(theme.brightness),
      ),
      title: Text(
        MedicineModels.readString(record.body, 'name'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
      ),
      trailing: TextButton(
        key: ValueKey('medicine-unarchive-${record.id}'),
        onPressed: onUnarchive,
        child: Text(medicineStrings(context, 'unarchive')),
      ),
    );
  }
}
