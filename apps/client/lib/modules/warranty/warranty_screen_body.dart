part of 'warranty_screen.dart';

extension _WarrantyScreenBody on _WarrantyScreenState {
  Widget _view(BuildContext context) {
    final strings = warrantyStrings;
    final query = _query.text.trim();
    final active = _warranties
        .where((r) => !WarrantyModels.readArchived(r.body))
        .toList();
    final visible = (query.isEmpty
        ? active
        : active
              .where((r) => WarrantyLogic.matchesQuery(r.body, query))
              .toList());
    final sorted = _sortSoonest
        ? WarrantyLogic.soonestEndFirst(visible)
        : visible;

    return Scaffold(
      appBar: NexAppBar(
        title: Text(strings(context, 'title')),
        actions: [
          IconButton(
            key: const ValueKey('warranty-sort'),
            tooltip: strings(context, 'sortSoonest'),
            icon: Icon(_sortSoonest ? Icons.sort : Icons.low_priority_outlined),
            onPressed: () => _paint(() => _sortSoonest = !_sortSoonest),
          ),
          IconButton(
            key: const ValueKey('warranty-search'),
            tooltip: AppLocalizations.of(context).search,
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: () {
              _paint(() {
                _searching = !_searching;
                if (!_searching) _query.clear();
              });
            },
          ),
        ],
        bottom: _searching
            ? PreferredSize(
                preferredSize: const Size.fromHeight(kToolbarHeight),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    NexSpacing.md,
                    0,
                    NexSpacing.md,
                    NexSpacing.sm,
                  ),
                  child: WarrantyFieldsLine(
                    controller: _query,
                    label: strings(context, 'searchHint'),
                  ),
                ),
              )
            : null,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadFailed
          ? _readError()
          : _warranties.isEmpty
          // Scrolled rather than overflowing: at 2× text the empty state
          // is taller than a small phone. The ConstrainedBox keeps it
          // vertically centered when it does fit.
          ? LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: NexEmptyState(
                    key: const ValueKey('warranty-empty'),
                    icon: Icons.verified_outlined,
                    message: strings(context, 'emptyMessage'),
                    // The empty state carries its own first action, not only
                    // the floating button below it.
                    action: FilledButton.tonalIcon(
                      key: const ValueKey('warranty-empty-add'),
                      onPressed: _busy || _loading || _loadFailed
                          ? null
                          : () => unawaited(_add()),
                      icon: const Icon(Icons.add_outlined),
                      label: Text(strings(context, 'add')),
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
          : _list(context, strings, sorted, query),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('warranty-fab'),
        onPressed: _busy || _loading || _loadFailed
            ? null
            : () => unawaited(_add()),
        label: Text(strings(context, 'add')),
        icon: const Icon(Icons.add_outlined),
      ),
    );
  }

  Widget _list(
    BuildContext context,
    NexModuleStrings strings,
    List<ModuleRecord> visible,
    String query,
  ) {
    final now = DateTime.now();
    final covered = <ModuleRecord>[];
    final expiring = <ModuleRecord>[];
    final expired = <ModuleRecord>[];
    final unknown = <ModuleRecord>[];
    for (final record in visible) {
      final end = WarrantyModels.readDate(record.body, 'coverageEnd');
      if (end == null) {
        unknown.add(record);
        continue;
      }
      final status = WarrantyLogic.statusOf(end, now);
      if (status.expired) {
        expired.add(record);
      } else if (status.expiring) {
        expiring.add(record);
      } else {
        covered.add(record);
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        NexSpacing.md,
        NexSpacing.sm,
        NexSpacing.md,
        NexSpacing.xl,
      ),
      children: [
        if (unknown.isNotEmpty)
          WarrantySection(
            icon: Icons.help_outline,
            title: strings(context, 'unknownDate'),
            records: unknown,
            onOpen: _openDetail,
          ),
        if (covered.isNotEmpty)
          WarrantySection(
            key: const ValueKey('warranty-section-active'),
            icon: Icons.verified_outlined,
            title: strings(context, 'active'),
            records: covered,
            onOpen: _openDetail,
          ),
        if (expiring.isNotEmpty)
          WarrantySection(
            key: const ValueKey('warranty-section-expiring'),
            icon: Icons.schedule_outlined,
            title: strings(context, 'expiring'),
            records: expiring,
            onOpen: _openDetail,
          ),
        if (expired.isNotEmpty) ...[
          NexShelfHeading(
            icon: Icons.event_busy_outlined,
            title: strings(context, 'expired'),
          ),
          const SizedBox(height: NexSpacing.sm),
          for (final record in expired)
            WarrantyRow(
              key: ValueKey('warranty-row-${record.id}'),
              record: record,
              onOpen: () => unawaited(_openDetail(record)),
            ),
        ],
        if (query.isEmpty && _archived().isNotEmpty) ...[
          const SizedBox(height: NexSpacing.md),
          Center(
            child: TextButton.icon(
              key: const ValueKey('warranty-archived-toggle'),
              onPressed: () {
                _paint(() => _showArchived = !_showArchived);
              },
              icon: Icon(_showArchived ? Icons.expand_less : Icons.expand_more),
              label: Text(
                strings(
                  context,
                  _showArchived ? 'hideArchived' : 'showArchived',
                ),
              ),
            ),
          ),
          if (_showArchived)
            for (final record in _archived())
              WarrantyArchivedRow(
                key: ValueKey('warranty-archived-${record.id}'),
                record: record,
                onUnarchive: () => unawaited(_unarchive(record)),
                onOpen: () => unawaited(_openDetail(record)),
              ),
        ],
        if (query.isNotEmpty && visible.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: NexSpacing.md),
            child: Text(
              strings(context, 'noResults'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }

  List<ModuleRecord> _archived() =>
      _warranties.where((r) => WarrantyModels.readArchived(r.body)).toList();

  Future<void> _unarchive(ModuleRecord record) async {
    await _work(
      () => LocalWrites.patch(
        widget.store,
        WarrantyModels.warranty,
        record.id,
        {'archived': false},
      ),
    );
  }
}
