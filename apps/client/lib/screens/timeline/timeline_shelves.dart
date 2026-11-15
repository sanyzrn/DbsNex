part of '../timeline_screen.dart';

/// The home arranged by kind or by tag (2.7.0): shelves instead of days.
///
/// Each shelf shows its newest few and ends in "See all", which narrows the
/// home to that shelf with the same filter the chips use — so the way back
/// is the way back from any filter: its chip, or Back. The headings carry a
/// mark of what they hold and the order is the reader's: a shelf's menu
/// moves it a step up or down, and the move is remembered.
extension _TimelineShelves on TimelineScreenState {
  /// What the rows are arranged by right now; null by day.
  _Arrange? _arrangeNow() {
    final by = widget.preferences.timelineArrangement;
    if (by == NexTimelineArrangement.time) return null;
    _model.ensureShelfCounts();
    return _Arrange(
      by: by,
      counts: _model.shelfCounts,
      tags: _model.filterTags,
      selectedTagIds: _model.selectedTagIds,
      onlyUntagged: _model.onlyUntagged,
      filtering: _model.filtering,
      order: widget.preferences.timelineShelfOrder(by),
    );
  }

  /// Fades the notes in when the list becomes a view of something else — a
  /// filter chip, "See all", the way back from it, another arrangement —
  /// as search fades its results in (2.7.1). It used to be a cut: one frame
  /// the shelves, the next a different list.
  ///
  /// Called before the rebuild that shows the new list, so the first frame
  /// of it is already the start of the fade. A note arriving, going or
  /// changing is not a new view and does not fade.
  void _fadeOnViewChange() {
    final view = [
      widget.preferences.timelineArrangement.name,
      widget.preferences.timelineGrid,
      _model.selectedType?.name,
      (_model.selectedTagIds.toList()..sort()).join(','),
      _model.onlyUntagged,
      _model.onlyReminders,
    ].join('|');
    final before = _rowsCache.view;
    _rowsCache.view = view;
    if (before != null && before != view && !_searching) _fadeInBody();
  }

  /// One heading, the same in the list, the grid and the desktop.
  Widget _groupHeading(
    _NoteGroup group,
    List<_NoteGroup> groups,
    AppLocalizations l10n, {
    bool compact = false,
  }) {
    final shelf = group.shelf;
    final movable = [
      for (final other in groups)
        if (other.shelf?.movable ?? false) other.key,
    ];
    final at = movable.indexOf(group.key);
    return _DayMark(
      // Known to the sticky day, so it does not repeat a heading that is
      // on screen beside it.
      heading: true,
      label: group.label,
      marks: _dayMarks,
      child: NexTapGuarded(
        controller: _guard,
        child: _GroupHeader(
          compact: compact,
          label: group.label,
          count: group.count,
          leading: _shelfMark(group),
          alwaysCount: shelf != null && shelf.kind != NexShelfKind.pinned,
          collapsed: _model.collapsedGroups.contains(group.key),
          onToggle: () => unawaited(_toggleGroup(group.key)),
          onAsk: AiChatSheet.availableFor(widget.preferences)
              ? () => unawaited(_askAboutGroup(group))
              : null,
          onDelete: group.complete
              ? () => unawaited(_deleteGroup(group, l10n))
              : null,
          onMoveUp: at > 0 ? () => _moveShelf(group, movable, -1) : null,
          onMoveDown: at >= 0 && at < movable.length - 1
              ? () => _moveShelf(group, movable, 1)
              : null,
        ),
      ),
    );
  }

  /// A shelf's mark: the kind's own icon in its own colour — the colour its
  /// cards are washed in — or the tag's dot, as the tag row draws it.
  Widget? _shelfMark(_NoteGroup group) {
    final shelf = group.shelf;
    if (shelf == null) return null;
    final scheme = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: switch (shelf.kind) {
        NexShelfKind.pinned => Icon(
          Icons.push_pin_outlined,
          size: 18,
          color: scheme.onSurfaceVariant,
        ),
        NexShelfKind.type => Icon(
          nexNoteTypeIcon(shelf.type!.wireName),
          size: 18,
          color: nexNoteTypeTint(shelf.type!.wireName, scheme),
        ),
        NexShelfKind.tag => Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: nexParseTagColor(shelf.tag?.color) ?? scheme.primary,
          ),
        ),
        NexShelfKind.untagged => Icon(
          Icons.label_off_outlined,
          size: 18,
          color: scheme.onSurfaceVariant,
        ),
      },
    );
  }

  /// The end of a shelf that holds more than it shows.
  Widget _shelfMore(_NoteGroup group, AppLocalizations l10n) {
    final shelf = group.shelf!;
    final theme = Theme.of(context);
    final label = shelf.exact
        ? l10n.shelfSeeAll(shelf.total)
        : l10n.shelfSeeAllUncounted;
    return NexTapGuarded(
      controller: _guard,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(
          NexSpacing.sm,
          NexSpacing.xs,
          NexSpacing.md,
          NexSpacing.xs,
        ),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: ValueKey('shelf-more-${group.key}'),
            onPressed: () => unawaited(_openShelf(shelf)),
            // Forward in the reading direction: the icon turns round in
            // Persian by itself.
            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
            iconAlignment: IconAlignment.end,
            label: Text(label),
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.primary,
              minimumSize: const Size(0, 48),
              padding: const EdgeInsets.symmetric(horizontal: NexSpacing.sm),
            ),
          ),
        ),
      ),
    );
  }

  /// "See all": the home narrowed to [shelf], with the chips' own filter.
  Future<void> _openShelf(NexShelf shelf) async {
    switch (shelf.kind) {
      case NexShelfKind.type:
        await _selectType(shelf.type);
      case NexShelfKind.tag:
        if (shelf.tag case final tag?) await _selectTags({tag.id});
      case NexShelfKind.untagged:
        _tick();
        await _model.selectUntagged(true);
      case NexShelfKind.pinned:
        return;
    }
    if (!mounted || !_scroll.hasClients) return;
    // The shelf was somewhere down the screen; as the whole list it starts
    // at the top. A jump, under the fade the new list comes in with — a
    // scroll would run back through notes that are no longer the list.
    _scroll.jumpTo(0);
  }

  /// Moves [group] a step among the [movable] shelves on screen.
  void _moveShelf(_NoteGroup group, List<String> movable, int step) {
    final by = widget.preferences.timelineArrangement;
    final next = nexMoveShelf(
      movable,
      widget.preferences.timelineShelfOrder(by),
      group.key,
      step,
    );
    nexBump();
    unawaited(widget.preferences.setTimelineShelfOrder(by, next));
    _rebuild(() {});
  }

  /// The heading a revealed note sits under on an arranged home, narrowing
  /// to its shelf first when the shelf shows only its newest few and the
  /// note is not among them. Null by day.
  Future<String?> _revealShelf(Note note) async {
    final arrange = _arrangeNow();
    if (arrange == null) return null;
    if (note.pinnedAt != null) return 'pinned';
    final shelves = nexArrangeShelves(
      _model.notes,
      by: arrange.by,
      counts: arrange.counts,
      tags: arrange.tags,
      selectedTagIds: arrange.selectedTagIds,
      onlyUntagged: arrange.onlyUntagged,
      filtering: arrange.filtering,
      order: arrange.order,
    );
    for (final shelf in shelves) {
      if (shelf.notes.any((n) => n.id == note.id)) return shelf.key;
    }
    if (arrange.by == NexTimelineArrangement.type) {
      await _model.selectType(note.type);
      return 'type:${note.type.wireName}';
    }
    final known = {for (final tag in _model.filterTags) tag.id};
    final tag =
        note.tags.where((t) => known.contains(t.id)).firstOrNull ??
        note.tags.firstOrNull;
    if (tag == null) {
      await _model.selectUntagged(true);
      return 'untagged';
    }
    await _model.selectTags({tag.id});
    return 'tag:${tag.id}';
  }
}
