part of 'medicine_screen.dart';

extension _MedicineScreenBody on _MedicineScreenState {
  Widget _view(BuildContext context) {
    final strings = medicineStrings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final active = _medicines
        .where((record) => !MedicineModels.readArchived(record.body))
        .toList();
    final archived = _medicines
        .where((record) => MedicineModels.readArchived(record.body))
        .toList();

    return Scaffold(
      appBar: AppBar(title: Text(strings(context, 'title'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadFailed
          ? _readError()
          : _medicines.isEmpty
          ? NexEmptyState(
              key: const ValueKey('medicine-empty'),
              icon: Icons.medication_outlined,
              message: strings(context, 'emptyMessage'),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                NexSpacing.md,
                NexSpacing.sm,
                NexSpacing.md,
                NexSpacing.xl,
              ),
              children: [
                for (final record in active)
                  _MedicineRow(
                    record: record,
                    onOpen: () => unawaited(_openDetail(record)),
                  ),
                if (archived.isNotEmpty) ...[
                  const SizedBox(height: NexSpacing.md),
                  Center(
                    child: TextButton.icon(
                      key: const ValueKey('medicine-archived-toggle'),
                      onPressed: () {
                        _paint(() => _showArchived = !_showArchived);
                      },
                      icon: Icon(
                        _showArchived ? Icons.expand_less : Icons.expand_more,
                      ),
                      label: Text(
                        strings(
                          context,
                          _showArchived ? 'hideArchived' : 'showArchived',
                        ),
                      ),
                    ),
                  ),
                  if (_showArchived)
                    for (final record in archived)
                      _ArchivedRow(
                        record: record,
                        onUnarchive: () => unawaited(_unarchive(record)),
                        onOpen: () => unawaited(_openDetail(record)),
                      ),
                ],
                Padding(
                  padding: const EdgeInsets.only(top: NexSpacing.md),
                  child: Text(
                    strings(context, 'safetyNote'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('medicine-fab'),
        onPressed: _busy || _loading || _loadFailed
            ? null
            : () => unawaited(_add()),
        label: Text(strings(context, 'addMedicine')),
        icon: const Icon(Icons.medication_outlined),
      ),
    );
  }
}
