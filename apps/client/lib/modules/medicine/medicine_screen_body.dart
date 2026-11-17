part of 'medicine_screen.dart';

extension _MedicineScreenBody on _MedicineScreenState {
  Widget _view(BuildContext context) {
    final strings = medicineStrings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final now = DateTime.now();
    final active = _medicines
        .where((record) => !MedicineModels.readArchived(record.body))
        .toList();
    final archived = _medicines
        .where((record) => MedicineModels.readArchived(record.body))
        .toList();
    final people = <String>{
      for (final record in active)
        if (MedicineModels.readPerson(record.body).isNotEmpty)
          MedicineModels.readPerson(record.body),
    }.toList()..sort();
    final shown = _peopleFilter == null
        ? active
        : active
              .where(
                (record) =>
                    MedicineModels.readPerson(record.body) == _peopleFilter,
              )
              .toList();
    final todayCount = _todayCount(active, now);
    final expiringCount = _expiringCount(now);

    return Scaffold(
      appBar: NexAppBar(
        title: Text(strings(context, 'title')),
        actions: [
          IconButton(
            key: const ValueKey('medicine-today-button'),
            tooltip: strings(context, 'today'),
            onPressed: () => unawaited(_openToday()),
            icon: const Icon(Icons.today_outlined),
          ),
          NexPopupMenuButton<String>(
            key: const ValueKey('medicine-screen-menu'),
            tooltip: strings(context, 'detailsTitle'),
            onSelected: (value) => unawaited(_runMenu(value)),
            itemBuilder: (menuContext) => [
              nexMenuItem(
                value: 'expiry',
                icon: Icons.event_busy_outlined,
                label: medicineStrings(menuContext, 'expiryTitle'),
              ),
              nexMenuItem(
                value: 'secure',
                icon: _secure
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                label: medicineStrings(menuContext, 'secureMenu'),
              ),
            ],
          ),
        ],
      ),
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
                if (todayCount > 0) ...[
                  _summaryCard(
                    context,
                    cardKey: const ValueKey('medicine-today-card'),
                    icon: Icons.checklist_outlined,
                    message: strings(
                      context,
                      todayCount == 1 ? 'todayOne' : 'todayDoses',
                      {'count': todayCount},
                    ),
                    action: strings(context, 'openToday'),
                    onTap: () => unawaited(_openToday()),
                  ),
                  const SizedBox(height: NexSpacing.sm),
                ],
                if (expiringCount > 0) ...[
                  _summaryCard(
                    context,
                    cardKey: const ValueKey('medicine-expiry-card'),
                    icon: Icons.event_busy_outlined,
                    message: strings(
                      context,
                      expiringCount == 1 ? 'heroOneExpiry' : 'expiryCardCount',
                      {'count': expiringCount},
                    ),
                    action: strings(context, 'expiryCard'),
                    onTap: () => unawaited(_openExpiry()),
                    warn: true,
                  ),
                  const SizedBox(height: NexSpacing.sm),
                ],
                if (people.isNotEmpty) ...[
                  Wrap(
                    spacing: NexSpacing.sm,
                    runSpacing: NexSpacing.xs,
                    children: [
                      ChoiceChip(
                        key: const ValueKey('medicine-person-all'),
                        label: Text(strings(context, 'allPeople')),
                        selected: _peopleFilter == null,
                        onSelected: (_) => _paint(() => _peopleFilter = null),
                      ),
                      for (final person in people)
                        ChoiceChip(
                          key: ValueKey('medicine-person-$person'),
                          label: Text(person),
                          selected: _peopleFilter == person,
                          onSelected: (_) =>
                              _paint(() => _peopleFilter = person),
                        ),
                    ],
                  ),
                  const SizedBox(height: NexSpacing.sm),
                ],
                for (final record in shown)
                  _MedicineRow(
                    record: record,
                    onOpen: () => unawaited(_openDetail(record)),
                  ),
                if (shown.isEmpty && active.isNotEmpty)
                  Text(
                    strings(context, 'noMedicinesFor'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
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
              // No hero: a page's button never flies into another's (2.8.2).
              heroTag: null,
              key: const ValueKey('medicine-fab'),
              onPressed: _busy ? null : () => unawaited(_add()),
              label: Text(strings(context, 'addMedicine')),
              icon: const Icon(Icons.medication_outlined),
            ),
    );
  }

  /// How many routine moments today holds, across the medicines on the
  /// list. Counted from the person's own times and days; nothing medical.
  int _todayCount(List<ModuleRecord> active, DateTime now) {
    final start = DateTime(now.year, now.month, now.day);
    final end = DateTime(now.year, now.month, now.day, 23, 59, 59);
    var count = 0;
    for (final record in active) {
      final schedule = MedicineSchedule.of(record.body);
      if (!schedule.hasTimes) {
        continue;
      }
      count += schedule.occurrences(from: start, until: end).length;
    }
    return count;
  }

  /// How many dated things are expired or inside the next three months —
  /// each box's own date, and the single date older records carry.
  int _expiringCount(DateTime now) {
    final known = {for (final record in _medicines) record.id};
    var count = 0;
    for (final record in _medicines) {
      final legacy = MedicineModels.readDate(record.body, 'expiresAt');
      if (legacy == null) {
        continue;
      }
      final state = MedicineLogic.expiryBucket(legacy, now);
      if (state.expired || state.soon) {
        count++;
      }
    }
    for (final box in _boxes) {
      final day = MedicineModels.readDay(box.body, 'expiresAt');
      if (day == null ||
          !known.contains(MedicineModels.readString(box.body, 'medicineId'))) {
        continue;
      }
      final state = MedicineLogic.expiryBucket(day, now);
      if (state.expired || state.soon) {
        count++;
      }
    }
    return count;
  }

  /// One line of the cabinet with a fact and the way to it: what today
  /// holds, or what is running out of date.
  Widget _summaryCard(
    BuildContext context, {
    required Key cardKey,
    required IconData icon,
    required String message,
    required String action,
    required VoidCallback onTap,
    bool warn = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    // The action sits under the words rather than beside them: at twice the
    // text on a small phone, a row of both overflowed.
    return NexPanel(
      key: cardKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: warn ? scheme.error : scheme.primary),
              const SizedBox(width: NexSpacing.sm),
              Expanded(
                child: Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: warn ? scheme.error : null),
                ),
              ),
            ],
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(onPressed: onTap, child: Text(action)),
          ),
        ],
      ),
    );
  }
}
