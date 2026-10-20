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
      appBar: NexAppBar(title: Text(strings(context, 'title'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadFailed
          ? _readError()
          : _medicines.isEmpty
          // Scrolled rather than overflowing: at 2× text the empty state
          // is taller than a small phone. The ConstrainedBox keeps it
          // vertically centered when it does fit.
          ? LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: NexEmptyState(
                    key: const ValueKey('medicine-empty'),
                    icon: Icons.medication_outlined,
                    message: strings(context, 'emptyMessage'),
                    // The empty state carries its own first action, not only
                    // the floating button below it.
                    action: FilledButton.tonalIcon(
                      key: const ValueKey('medicine-empty-add'),
                      onPressed: () => unawaited(_add()),
                      icon: const Icon(Icons.medication_outlined),
                      label: Text(strings(context, 'addMedicine')),
                      // Material's default caps a filled button at 40 px
                      // tall, which a 2× text scale cannot fit into; let it
                      // grow with the words instead of clipping them.
                      style: const ButtonStyle(
                        maximumSize: WidgetStatePropertyAll<Size?>(
                          Size(double.infinity, double.infinity),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                NexSpacing.md,
                NexSpacing.sm,
                NexSpacing.md,
                NexSpacing.xl,
              ),
              children: [
                NexModuleHero(
                  key: const ValueKey('medicine-hero'),
                  moduleId: 'medicine',
                  icon: Icons.medication_outlined,
                  eyebrow: strings(context, 'heroEyebrow'),
                  headline: nexDigits(
                    strings(
                      context,
                      active.length == 1 ? 'heroOne' : 'heroCount',
                      {'count': active.length},
                    ),
                    persian: NexModuleStrings.persian(context),
                  ),
                  caption: strings(context, 'heroCaption'),
                ),
                const SizedBox(height: NexSpacing.md),
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
      floatingActionButton: _loading || _loadFailed || _medicines.isEmpty
          ? null
          : FloatingActionButton.extended(
              key: const ValueKey('medicine-fab'),
              onPressed: _busy ? null : () => unawaited(_add()),
              label: Text(strings(context, 'addMedicine')),
              icon: const Icon(Icons.medication_outlined),
            ),
    );
  }
}
