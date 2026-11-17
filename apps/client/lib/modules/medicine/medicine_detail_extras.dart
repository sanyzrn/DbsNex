part of 'medicine_detail.dart';

/// The parts of one medicine's sheet that were added with the upgrade:
/// the person's own "hard to find" note, the reminders that follow the
/// routine, the boxes with their expiry days, and where it was found.
extension _MedicineDetailExtras on _MedicineDetailSheetState {
  Widget _hardToFindRow(BuildContext context, Map<String, Object?> body) {
    final archived = MedicineModels.readArchived(body);
    return SwitchListTile(
      key: const ValueKey('medicine-hard-to-find-toggle'),
      contentPadding: EdgeInsets.zero,
      value: MedicineModels.readHardToFind(body),
      onChanged: archived || _busy
          ? null
          : (value) => unawaited(_toggleHardToFind(value)),
      title: Text(medicineStrings(context, 'hardToFind')),
      subtitle: Text(medicineStrings(context, 'hardToFindNote')),
    );
  }

  /// A routine with times is reminded by the schedule itself; a medicine
  /// without one keeps the shared one-time control it has always had.
  Widget _reminderBlock(BuildContext context, Map<String, Object?> body) {
    if (MedicineModels.readArchived(body)) {
      return const SizedBox.shrink();
    }
    final schedule = MedicineSchedule.of(body);
    if (!schedule.hasTimes) {
      final person = MedicineModels.readPerson(body);
      return NexModuleReminderControl(
        store: widget.store,
        sourceKind: MedicineModels.medicine,
        sourceId: widget.record.id,
        body: medicineStrings(context, 'reminderBodySingle', {
          'person': person.isEmpty ? medicineStrings(context, 'me') : person,
        }),
      );
    }
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: NexSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.notifications_active_outlined,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: NexSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  medicineStrings(context, 'scheduleReminders'),
                  style: theme.textTheme.bodyMedium,
                ),
                Text(
                  medicineStrings(context, 'scheduleRemindersBody'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (!widget.store.remindersEnabled)
                  Text(
                    medicineStrings(context, 'remindersOff'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _boxesAndPlaces(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      MedicineBoxSection(
        boxes: _boxes,
        onAdd: () => unawaited(_addBox()),
        onDelete: (box) => unawaited(_deleteBox(box)),
      ),
      MedicinePlaceSection(
        sources: _sources,
        onAdd: () => unawaited(_addPlace()),
        onDelete: (source) => unawaited(_deletePlace(source)),
      ),
    ],
  );

  Future<void> _toggleHardToFind(bool value) async {
    await _work(
      () => LocalWrites.patch(
        widget.store,
        MedicineModels.medicine,
        widget.record.id,
        {'hardToFind': value},
      ),
    );
  }

  Future<void> _addBox() async {
    if (_busy || _loadFailed) {
      return;
    }
    final saved = await nexShowSheet<bool>(
      context: context,
      dismissible: false,
      swipeToClose: true,
      builder: (_) =>
          MedicineBoxSheet(store: widget.store, medicineId: widget.record.id),
    );
    if (saved == true && mounted) {
      NexBannerHost.of(context)
          ?.show(message: medicineStrings(context, 'boxSaved'));
    }
  }

  Future<void> _deleteBox(ModuleRecord box) async {
    await _work(() async {
      final undo = await MedicineRepository.deleteBox(widget.store, box.id);
      if (!mounted) {
        return;
      }
      MedicineDialogs.offerUndo(
        _messenger(),
        medicineStrings(context, 'boxDeleted'),
        AppLocalizations.of(context).undo,
        undo,
      );
    });
  }

  Future<void> _addPlace() async {
    if (_busy || _loadFailed) {
      return;
    }
    final saved = await nexShowSheet<bool>(
      context: context,
      dismissible: false,
      swipeToClose: true,
      builder: (_) =>
          MedicinePlaceSheet(store: widget.store, medicineId: widget.record.id),
    );
    if (saved == true && mounted) {
      NexBannerHost.of(context)
          ?.show(message: medicineStrings(context, 'placeSaved'));
    }
  }

  Future<void> _deletePlace(ModuleRecord source) async {
    await _work(() async {
      final undo = await MedicineRepository.deleteSource(
        widget.store,
        source.id,
      );
      if (!mounted) {
        return;
      }
      MedicineDialogs.offerUndo(
        _messenger(),
        medicineStrings(context, 'placeDeleted'),
        AppLocalizations.of(context).undo,
        undo,
      );
    });
  }
}
