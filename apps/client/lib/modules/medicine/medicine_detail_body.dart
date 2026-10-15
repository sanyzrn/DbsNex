part of 'medicine_detail.dart';

extension _MedicineDetailBody on _MedicineDetailSheetState {
  Widget _view(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadFailed || _body == null) {
      return _readError();
    }

    // A messenger of the sheet's own: a snackbar shown from inside this
    // sheet lands in the sheet rather than under it — and is not shown a
    // second time on the screen behind it.
    return ScaffoldMessenger(
      child: Builder(
        builder: (inner) {
          _sheetMessenger = ScaffoldMessenger.of(inner);
          return PopScope(
            canPop: !_busy,
            child: AbsorbPointer(absorbing: _busy, child: _sheet(inner)),
          );
        },
      ),
    );
  }

  Widget _sheet(BuildContext context) {
    final body = _body!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final strings = medicineStrings;
    final name = MedicineModels.readString(body, 'name');
    final strength = MedicineModels.readString(body, 'strength');

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(NexSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(name, style: theme.textTheme.headlineSmall),
                ),
                NexPopupMenuButton<String>(
                  key: const ValueKey('medicine-detail-menu'),
                  tooltip: strings(context, 'detailsTitle'),
                  onSelected: (value) => unawaited(_runAction(value)),
                  itemBuilder: (menuContext) => [
                    PopupMenuItem(
                      value: 'edit',
                      child: Text(AppLocalizations.of(menuContext).edit),
                    ),
                    if (MedicineModels.readArchived(body))
                      PopupMenuItem(
                        value: 'unarchive',
                        child: Text(medicineStrings(menuContext, 'unarchive')),
                      )
                    else
                      PopupMenuItem(
                        value: 'archive',
                        child: Text(medicineStrings(menuContext, 'archived')),
                      ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(AppLocalizations.of(menuContext).delete),
                    ),
                  ],
                ),
              ],
            ),
            if (strength.isNotEmpty)
              Text(strength, style: theme.textTheme.bodyLarge),
            const SizedBox(height: NexSpacing.md),
            MedicineInfoSection(body: body),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    key: const ValueKey('medicine-taken'),
                    onPressed: MedicineModels.readArchived(body)
                        ? null
                        : () => unawaited(_log(MedicineModels.taken)),
                    icon: const Icon(Icons.check_outlined),
                    label: Text(strings(context, 'taken')),
                  ),
                ),
                const SizedBox(width: NexSpacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    key: const ValueKey('medicine-skipped'),
                    onPressed: MedicineModels.readArchived(body)
                        ? null
                        : () => unawaited(_log(MedicineModels.skipped)),
                    icon: const Icon(Icons.remove_outlined),
                    label: Text(strings(context, 'skipped')),
                  ),
                ),
              ],
            ),
            const SizedBox(height: NexSpacing.lg),
            MedicineHistorySection(doses: _doses, onDelete: _deleteDose),
            const SizedBox(height: NexSpacing.md),
            Text(
              strings(context, 'safetyNote'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Runs the actions menu's choice.
  Future<void> _runAction(String value) async {
    switch (value) {
      case 'edit':
        await _edit();
      case 'archive':
        await _archive();
      case 'unarchive':
        await _unarchive();
      case 'delete':
        await _delete();
    }
  }

  /// Archives this medicine, with Undo. The sheet closes after, so the
  /// question is shown by the screen behind it.
  Future<void> _archive() async {
    if (_busy || _body == null) {
      return;
    }
    if (await MedicineDialogs.confirmArchive(
              context,
              medicineStrings,
              MedicineModels.readString(_body!, 'name'),
            ) !=
            true ||
        !mounted) {
      return;
    }
    await _work(() async {
      await LocalWrites.patch(
        widget.store,
        MedicineModels.medicine,
        widget.record.id,
        {'archived': true},
      );
      if (!mounted) {
        return;
      }
      final messenger = ScaffoldMessenger.of(context);
      final undo = AppLocalizations.of(context).undo;
      MedicineDialogs.offerUndo(
        messenger,
        medicineStrings(context, 'medicineArchived'),
        undo,
        () => LocalWrites.patch(
          widget.store,
          MedicineModels.medicine,
          widget.record.id,
          {'archived': false},
        ),
      );
      Navigator.of(context).pop();
    });
  }

  /// Brings this medicine back to the list.
  Future<void> _unarchive() async {
    await _work(() async {
      await LocalWrites.patch(
        widget.store,
        MedicineModels.medicine,
        widget.record.id,
        {'archived': false},
      );
      if (!mounted) {
        return;
      }

      Navigator.of(context).pop();
    });
  }

  /// Deletes this medicine and its dose history together, with one Undo
  /// that brings the whole set back exactly as it was. The sheet closes
  /// after, so the undo is offered by the screen behind it.
  Future<void> _delete() async {
    if (_busy || _body == null) {
      return;
    }
    if (await MedicineDialogs.confirmDelete(
              context,
              medicineStrings,
              MedicineModels.readString(_body ?? {}, 'name'),
            ) !=
            true ||
        !mounted) {
      return;
    }
    await _work(() async {
      final undo = await LocalWrites.delete(
        widget.store,
        MedicineModels.medicine,
        widget.record.id,
        children: MedicineModels.dose,
        parentField: 'medicineId',
      );
      if (!mounted) {
        return;
      }
      MedicineDialogs.offerUndo(
        ScaffoldMessenger.of(context),
        medicineStrings(context, 'medicineDeleted'),
        AppLocalizations.of(context).undo,
        undo,
      );
      Navigator.of(context).pop();
    });
  }
}
