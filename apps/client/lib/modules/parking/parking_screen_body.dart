part of 'parking_screen.dart';

extension _ParkingScreenBody on _ParkingScreenState {
  Widget _view(BuildContext context) {
    final strings = parkingStrings;
    final active = _sessions
        .where((record) => ParkingLogic.isActive(record.body))
        .toList();
    final historyAll = ParkingLogic.historyOf(
      _sessions.map((record) => record.body),
    );
    final query = _query.text.trim();
    final searching = _searching && query.isNotEmpty;
    final history = searching
        ? _sessions
              .where((record) => ParkingLogic.matchesQuery(record.body, query))
              .toList()
        : _sessions
              .where((record) => !ParkingLogic.isActive(record.body))
              .toList();

    history.sort(
      (a, b) => (ParkingModels.readDate(b.body, 'startedAt') ?? DateTime(0))
          .compareTo(
            ParkingModels.readDate(a.body, 'startedAt') ?? DateTime(0),
          ),
    );

    return Scaffold(
      appBar: NexAppBar(
        title: Text(strings(context, 'title')),
        actions: [
          IconButton(
            key: const ValueKey('parking-search'),
            tooltip: AppLocalizations.of(context).search,
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: () {
              _paint(() {
                _searching = !_searching;
                if (!_searching) _query.clear();
              });
            },
          ),
          if (historyAll.isNotEmpty)
            NexPopupMenuButton<String>(
              key: const ValueKey('parking-menu'),
              tooltip: strings(context, 'history'),
              onSelected: (_) => unawaited(_clearHistory()),
              itemBuilder: (menuContext) => [
                PopupMenuItem(
                  value: 'clear',
                  child: Text(strings(menuContext, 'clearHistory')),
                ),
              ],
            ),
        ],
        bottom: _searching ? _searchBar(strings) : null,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadFailed
          ? _readError()
          : _sessions.isEmpty && _places.isEmpty
          ? CustomScrollView(
              // The empty state stands centred when it fits, and scrolls
              // when large text makes it taller than the screen.
              slivers: [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: NexEmptyState(
                    key: const ValueKey('parking-empty'),
                    icon: Icons.local_parking_outlined,
                    message: strings(context, 'emptyMessage'),
                    // The empty state carries its own first action, not
                    // only the floating button below the fold.
                    action: FilledButton.tonalIcon(
                      key: const ValueKey('parking-empty-add'),
                      onPressed: _busy || _loading || _loadFailed
                          ? null
                          : () => unawaited(_newParking()),
                      icon: const Icon(Icons.local_parking_outlined),
                      label: Text(strings(context, 'parkedHere')),
                    ),
                  ),
                ),
              ],
            )
          : _list(context, strings, active, history, searching),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('parking-fab'),
        onPressed: _busy || _loading || _loadFailed
            ? null
            : () => unawaited(_newParking()),
        label: Text(strings(context, 'parkedHere')),
        icon: const Icon(Icons.local_parking_outlined),
      ),
    );
  }

  /// The search line that appears under the app bar while searching.
  PreferredSizeWidget _searchBar(NexModuleStrings strings) => PreferredSize(
    preferredSize: const Size.fromHeight(kToolbarHeight),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(
        NexSpacing.md,
        0,
        NexSpacing.md,
        NexSpacing.sm,
      ),
      child: ParkingFields.line(
        fieldKey: const ValueKey('parking-field-search'),
        controller: _query,
        label: strings(context, 'searchHint'),
        onSubmitted: (query) => unawaited(
          _work(
            () => ParkingWrites.rememberQuery(widget.store, _queries, query),
          ),
        ),
      ),
    ),
  );

  Widget _list(
    BuildContext context,
    NexModuleStrings strings,
    List<ModuleRecord> active,
    List<ModuleRecord> history,
    bool searching,
  ) => ListView(
    padding: const EdgeInsets.fromLTRB(
      NexSpacing.md,
      NexSpacing.sm,
      NexSpacing.md,
      NexSpacing.xl,
    ),
    children: [
      if (_searching && _queries.isNotEmpty) ...[
        NexShelfHeading(
          icon: Icons.manage_search,
          title: strings(context, 'searchHistory'),
        ),
        const SizedBox(height: NexSpacing.sm),
        Wrap(
          spacing: NexSpacing.sm,
          children: [
            for (final record in _queries.take(6))
              ActionChip(
                label: Text(ParkingModels.readString(record.body, 'query')),
                onPressed: () {
                  _paint(
                    () => _query.text = ParkingModels.readString(
                      record.body,
                      'query',
                    ),
                  );
                },
              ),
          ],
        ),
        const SizedBox(height: NexSpacing.md),
      ],
      if (!searching)
        for (final record in active)
          Padding(
            padding: const EdgeInsets.only(bottom: NexSpacing.md),
            child: ParkingActiveCard(
              key: ValueKey('parking-active-${record.id}'),
              store: widget.store,
              record: record,
              onFound: () => unawaited(_foundCar(record)),
              onEdit: () => unawaited(_editParking(record)),
            ),
          ),
      if (!searching && _places.isNotEmpty) ...[
        NexShelfHeading(
          icon: Icons.bookmark_outline,
          title: strings(context, 'recentPlaces'),
        ),
        const SizedBox(height: NexSpacing.sm),
        for (final place in _places.take(4))
          ParkingPlaceRow(
            record: place,
            onTap: () => unawaited(_newParking(place)),
          ),
        const SizedBox(height: NexSpacing.md),
      ],
      if (searching || history.isNotEmpty) ...[
        NexShelfHeading(
          icon: Icons.history,
          title: strings(context, 'history'),
        ),
        const SizedBox(height: NexSpacing.sm),
      ],
      if (searching && history.isEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: NexSpacing.md),
          child: Text(
            strings(context, 'noMatches', {'query': _query.text.trim()}),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      for (final record in history)
        ParkingHistoryRow(
          record: record,
          onTap: () => unawaited(
            Navigator.of(context).push(
              NexPageRoute(
                builder: (_) => ParkingDetailPage(
                  store: widget.store,
                  sessionId: record.id,
                ),
              ),
            ),
          ),
          onDelete: () => unawaited(_delete(record)),
        ),
    ],
  );
}
