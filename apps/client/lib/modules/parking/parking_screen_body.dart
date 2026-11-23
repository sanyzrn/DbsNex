part of 'parking_screen.dart';

extension _ParkingScreenBody on _ParkingScreenState {
  Widget _view(BuildContext context) {
    final strings = parkingStrings;
    final query = _query.text.trim();
    final searching = _searching && query.isNotEmpty;
    final active = _sessions
        .where((record) => ParkingLogic.isActive(record.body))
        .where(
          (record) =>
              !searching || ParkingLogic.matchesQuery(record.body, query),
        )
        .toList();
    final historyAll = ParkingLogic.historyOf(
      _sessions.map((record) => record.body),
    );
    final history = _sessions
        .where((record) => !ParkingLogic.isActive(record.body))
        .where(
          (record) =>
              !searching || ParkingLogic.matchesQuery(record.body, query),
        )
        .toList();
    final favourites = _places
        .where((record) => ParkingModels.isFavourite(record.body))
        .toList();
    final recentPlaces = _places
        .where((record) => !ParkingModels.isFavourite(record.body))
        .toList();

    int recentFirst(ModuleRecord a, ModuleRecord b) =>
        (ParkingModels.readDate(b.body, 'lastUsedAt') ?? DateTime(0)).compareTo(
          ParkingModels.readDate(a.body, 'lastUsedAt') ?? DateTime(0),
        );
    favourites.sort(recentFirst);
    recentPlaces.sort(recentFirst);
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
            key: const ValueKey('parking-park-details'),
            tooltip: strings(context, 'parkWithDetails'),
            icon: const Icon(Icons.add_location_alt_outlined),
            onPressed: _busy || _loading || _loadFailed
                ? null
                : () => unawaited(_newParking()),
          ),
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
                nexMenuItem(
                  value: 'clear',
                  icon: Icons.delete_sweep_outlined,
                  label: strings(menuContext, 'clearHistory'),
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
                    action: Column(
                      children: [
                        FilledButton.tonalIcon(
                          key: const ValueKey('parking-empty-add'),
                          onPressed: _busy || _loading || _loadFailed
                              ? null
                              : () => unawaited(_quickPark()),
                          icon: const Icon(Icons.local_parking_outlined),
                          label: Text(strings(context, 'parkNow')),
                        ),
                        TextButton.icon(
                          key: const ValueKey('parking-empty-details'),
                          onPressed: _busy || _loading || _loadFailed
                              ? null
                              : () => unawaited(_newParking()),
                          icon: const Icon(Icons.add_location_alt_outlined),
                          label: Text(strings(context, 'parkWithDetails')),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            )
          : _list(
              context,
              strings,
              active,
              history,
              searching,
              favourites,
              recentPlaces,
            ),
      // One primary action per page: with nothing yet it is the button in
      // the empty state, not a second one floating beside it.
      floatingActionButton:
          _loading || _loadFailed || (_sessions.isEmpty && _places.isEmpty)
          ? null
          : FloatingActionButton.extended(
              // No hero: a page's button never flies into another's (2.8.2).
              heroTag: null,
              key: const ValueKey('parking-fab'),
              onPressed: _busy ? null : () => unawaited(_quickPark()),
              label: Text(strings(context, 'parkNow')),
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
      child: NexSearchField(
        fieldKey: const ValueKey('parking-field-search'),
        controller: _query,
        labelText: strings(context, 'searchHint'),
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
    List<ModuleRecord> favourites,
    List<ModuleRecord> recentPlaces,
  ) => ListView(
    padding: const EdgeInsets.fromLTRB(
      NexSpacing.md,
      NexSpacing.sm,
      NexSpacing.md,
      NexSpacing.xl,
    ),
    children: [
      if (!searching) ...[
        NexModuleHero(
          key: const ValueKey('parking-hero'),
          moduleId: 'parking',
          icon: Icons.local_parking_outlined,
          eyebrow: strings(context, 'heroEyebrow'),
          headline: active.isEmpty
              ? strings(context, 'heroNone')
              : strings(context, 'heroParked', {'count': active.length}),
          caption: strings(context, 'heroCaption'),
        ),
        const SizedBox(height: NexSpacing.md),
      ],
      if (_searching && _queries.isNotEmpty) ...[
        NexShelfHeading(
          icon: Icons.manage_search,
          title: strings(context, 'searchHistory'),
        ),
        const SizedBox(height: NexSpacing.sm),
        Wrap(
          spacing: NexSpacing.sm,
          children: [
            for (final record in _queries.take(
              ParkingModels.searchHistoryLimit,
            ))
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
      if (!searching && favourites.isNotEmpty) ...[
        NexShelfHeading(
          icon: Icons.star_outline,
          title: strings(context, 'favouritePlaces'),
        ),
        const SizedBox(height: NexSpacing.sm),
        for (final place in favourites.take(6))
          ParkingPlaceRow(
            record: place,
            onTap: () => unawaited(_newParking(place)),
            onFavourite: (value) => unawaited(_toggleFavourite(place, value)),
          ),
        const SizedBox(height: NexSpacing.md),
      ],
      if (!searching && recentPlaces.isNotEmpty) ...[
        NexShelfHeading(
          icon: Icons.bookmark_outline,
          title: strings(context, 'recentPlaces'),
        ),
        const SizedBox(height: NexSpacing.sm),
        for (final place in recentPlaces.take(6))
          ParkingPlaceRow(
            record: place,
            onTap: () => unawaited(_newParking(place)),
            onFavourite: (value) => unawaited(_toggleFavourite(place, value)),
          ),
        const SizedBox(height: NexSpacing.md),
      ],
      if (!searching && _places.isNotEmpty) ...[
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: const ValueKey('parking-places-all'),
            onPressed: _busy ? null : () => unawaited(_openPlaces()),
            icon: const Icon(Icons.tune),
            label: Text(strings(context, 'allPlaces')),
          ),
        ),
        const SizedBox(height: NexSpacing.xs),
      ],
      if (history.isNotEmpty) ...[
        NexShelfHeading(
          icon: Icons.history,
          title: strings(context, 'history'),
        ),
        const SizedBox(height: NexSpacing.sm),
      ],
      if (searching && active.isEmpty && history.isEmpty)
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
