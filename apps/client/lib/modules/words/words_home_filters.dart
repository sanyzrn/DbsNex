part of 'words_screen.dart';

/// The search box, the deck chips, the status chips and the tags: one
/// band of the home page, kept beside the page it belongs to.
extension _HomeFilters on _WordsScreenState {
  Widget _searchAndFilters(BuildContext context, ThemeData theme) {
    final strings = wordsStrings;
    final tags =
        _cards
            .map((card) => card.tag)
            .where((tag) => tag.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NexSearchField(
          fieldKey: const ValueKey('words-search'),
          controller: _search,
          hintText: strings(context, 'searchHint'),
          onChanged: (value) => _paint(() => _query = value.trim()),
        ),
        // Decks first, on their own line, when there are any: a deck is
        // the coarser cut, and it was hidden off the end of the status row.
        if (_decks.isNotEmpty) ...[
          const SizedBox(height: NexSpacing.sm),
          SingleChildScrollView(
            key: const ValueKey('words-deck-filters'),
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final deck in _decks) ...[
                  FilterChip(
                    key: ValueKey('words-deck-chip-${deck.id}'),
                    avatar: const Icon(Icons.folder_outlined, size: 16),
                    label: Text(deck.name),
                    selected: _deckFilter == deck.id,
                    showCheckmark: false,
                    onSelected: (_) => _paint(
                      () =>
                          _deckFilter = _deckFilter == deck.id ? null : deck.id,
                    ),
                  ),
                  const SizedBox(width: NexSpacing.xs + 2),
                ],
                if (_cards.any((card) => card.deckId.isEmpty))
                  FilterChip(
                    key: const ValueKey('words-deck-chip-none'),
                    avatar: const Icon(Icons.folder_off_outlined, size: 16),
                    label: Text(strings(context, 'deckNone')),
                    selected: _deckFilter == '',
                    showCheckmark: false,
                    onSelected: (_) => _paint(
                      () => _deckFilter = _deckFilter == '' ? null : '',
                    ),
                  ),
                const SizedBox(width: NexSpacing.xs + 2),
                ActionChip(
                  key: const ValueKey('words-decks-manage'),
                  avatar: const Icon(
                    Icons.create_new_folder_outlined,
                    size: 16,
                  ),
                  label: Text(strings(context, 'decksTitle')),
                  onPressed: _manageDecks,
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: NexSpacing.sm),
        // One row that scrolls sideways, statuses then tags: two wrapped
        // rows of chips used to break apart at odd places (2.4.0).
        SingleChildScrollView(
          key: const ValueKey('words-filters'),
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final entry in [
                (_StatusFilter.all, 'filterAll'),
                (_StatusFilter.newWords, 'filterNew'),
                (_StatusFilter.due, 'filterDue'),
                (_StatusFilter.learned, 'filterLearned'),
                (_StatusFilter.paused, 'filterPaused'),
              ]) ...[
                ChoiceChip(
                  key: ValueKey('words-filter-${entry.$2}'),
                  label: Text(strings(context, entry.$2)),
                  selected: _filter == entry.$1,
                  showCheckmark: false,
                  onSelected: (_) => _paint(() => _filter = entry.$1),
                ),
                const SizedBox(width: NexSpacing.xs + 2),
              ],
              if (tags.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: NexSpacing.xs,
                  ),
                  child: SizedBox(
                    height: 24,
                    child: VerticalDivider(
                      width: 1,
                      color: theme.colorScheme.outlineVariant,
                    ),
                  ),
                ),
              for (final tag in _showAllTags ? tags : tags.take(8)) ...[
                const SizedBox(width: NexSpacing.xs + 2),
                FilterChip(
                  avatar: const Icon(Icons.sell_outlined, size: 16),
                  label: Text(tag),
                  selected: _tagFilter == tag,
                  showCheckmark: false,
                  onSelected: (_) =>
                      _paint(() => _tagFilter = _tagFilter == tag ? null : tag),
                ),
              ],
            ],
          ),
        ),
        if (tags.length > 8)
          TextButton(
            onPressed: () => _paint(() => _showAllTags = !_showAllTags),
            child: Text(
              strings(context, _showAllTags ? 'tagsLess' : 'tagsAll', {
                'count': tags.length,
              }),
            ),
          ),
        if (_tagFilter != null ||
            _deckFilter != null ||
            _filter != _StatusFilter.all ||
            _query.isNotEmpty)
          TextButton(
            key: const ValueKey('words-clear-filters'),
            onPressed: () {
              _search.clear();
              _paint(() {
                _tagFilter = null;
                _deckFilter = null;
                _filter = _StatusFilter.all;
                _query = '';
              });
            },
            child: Text(strings(context, 'clearFilters')),
          ),
        const SizedBox(height: NexSpacing.md),
      ],
    );
  }
}
