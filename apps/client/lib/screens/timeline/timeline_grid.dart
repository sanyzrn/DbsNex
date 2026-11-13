part of '../timeline_screen.dart';

/// How many rows of a day fold with motion. Enough to fill any phone screen;
/// a longer day's remaining rows are below the screen while it moves.
const _gridFoldRows = 8;

/// The phone's grid view (2.6.27, reworked in 2.6.28): the same days, pins
/// and folds as the list, each day laid out as tiles — three to a row at the
/// compact card size, two at the others, more as the window widens
/// ([NexGridMetrics]).
///
/// Swiping a tile does nothing — tiles side by side leave no edge to swipe
/// from — so what a swipe does in the list is in the tile's hold menu, which
/// is the same menu the list's cards open.
extension _TimelineGrid on TimelineScreenState {
  /// How far down the grid the [index]th note starts, at least — the
  /// reveal's first jump, as `index * rowHeight` is the list's.
  double _gridOffsetEstimate(int index) {
    final metrics = NexGridMetrics.of(context);
    final width = MediaQuery.sizeOf(context).width - 2 * NexSpacing.md;
    final columns = metrics.columnsFor(width);
    final row = metrics.heightFor(context) + NexSpacing.sm;
    return (index ~/ columns) * row;
  }

  List<Widget> _gridSlivers(List<_NoteGroup> groups, AppLocalizations l10n) {
    final strings = nexCardStrings(context);
    final metrics = NexGridMetrics.of(context);
    final height = metrics.heightFor(context);
    const padding = EdgeInsets.fromLTRB(
      NexSpacing.md,
      NexSpacing.xs,
      NexSpacing.md,
      NexSpacing.sm,
    );
    return [
      for (final group in groups)
        SliverMainAxisGroup(
          slivers: [
            SliverToBoxAdapter(
              child: NexTapGuarded(
                controller: _guard,
                child: _GroupHeader(
                  label: group.label,
                  count: group.notes.length,
                  collapsed: _model.collapsedGroups.contains(group.key),
                  onToggle: () => unawaited(_toggleGroup(group.key)),
                  onAsk: AiChatSheet.availableFor(widget.preferences)
                      ? () => unawaited(_askAboutGroup(group))
                      : null,
                  onDelete: () => unawaited(_deleteGroup(group, l10n)),
                ),
              ),
            ),
            // A day folding or opening, by tap or by pinch: its first rows,
            // built at once, each folding a beat after the one above — the
            // list's fan, a row of tiles at a time. When the motion ends an
            // opened day becomes the lazy grid below; a closed one is gone.
            if (_closingGroups.contains(group.key) ||
                _openingGroups.contains(group.key))
              SliverPadding(
                padding: padding,
                sliver: SliverToBoxAdapter(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = metrics.columnsFor(constraints.maxWidth);
                      final rows = math.min(
                        _gridFoldRows,
                        (group.notes.length / columns).ceil(),
                      );
                      return Column(
                        children: [
                          for (var r = 0; r < rows; r++)
                            _FoldingRow(
                              key: ValueKey('grid-fold-${group.key}-$r'),
                              open: !_closingGroups.contains(group.key),
                              animateIn: _openingGroups.contains(group.key),
                              order: r,
                              child: Padding(
                                padding: EdgeInsets.only(
                                  bottom: r == rows - 1 ? 0 : NexSpacing.sm,
                                ),
                                child: SizedBox(
                                  height: height,
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      for (var c = 0; c < columns; c++) ...[
                                        if (c > 0)
                                          const SizedBox(width: NexSpacing.sm),
                                        Expanded(
                                          child:
                                              r * columns + c <
                                                  group.notes.length
                                              ? _gridTile(
                                                  group.notes[r * columns + c],
                                                  strings,
                                                  l10n,
                                                )
                                              : const SizedBox.shrink(),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              )
            else if (!_model.collapsedGroups.contains(group.key))
              SliverPadding(
                padding: padding,
                sliver: SliverLayoutBuilder(
                  builder: (context, constraints) => SliverGrid.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: metrics.columnsFor(
                        constraints.crossAxisExtent,
                      ),
                      mainAxisExtent: height,
                      crossAxisSpacing: NexSpacing.sm,
                      mainAxisSpacing: NexSpacing.sm,
                    ),
                    itemCount: group.notes.length,
                    itemBuilder: (context, i) =>
                        _gridTile(group.notes[i], strings, l10n),
                  ),
                ),
              ),
          ],
        ),
    ];
  }

  Widget _gridTile(Note note, NexCardStrings strings, AppLocalizations l10n) =>
      _DayMark(
        // The day passing under the filters, named as the list names it.
        label: _dayLabel(note, l10n),
        marks: _dayMarks,
        child: NexTapGuarded(
          controller: _guard,
          child: NoteContextMenu(
            key: ValueKey('grid-menu-${note.id}'),
            entriesBuilder: (menuContext, width) =>
                _holdEntries(note, menuContext, width),
            // The same two moments the list marks: a note asked for from
            // outside (a reminder, a widget row) is found by this anchor and
            // lit, and a note just captured lands with its receipt.
            child: NoteSpotlight(
              key: _spotlightId == note.id ? _spotlightAnchor : null,
              active: _spotlightId == note.id && _spotlightReady,
              insets: EdgeInsets.zero,
              radius: NexRadius.xl,
              onDone: () {
                if (mounted && _spotlightId == note.id) {
                  _rebuild(() => _spotlightId = null);
                }
              },
              child: CommitReceipt(
                key: ValueKey('grid-receipt-${note.id}'),
                active: landedId == note.id,
                // Off the rounded corners: the bar runs down the tile's
                // straight edge.
                insets: const EdgeInsets.symmetric(vertical: NexRadius.xl),
                onDone: () {
                  if (mounted && landedId == note.id) {
                    _rebuild(() => landedId = null);
                  }
                },
                child: NexNoteGridCard(
                  key: ValueKey('grid-${note.id}'),
                  note: note,
                  strings: strings,
                  onTap: () => _tapNote(note),
                  onLeadingTap: () => _pickNote(note),
                  selected: _selecting ? _selected.contains(note.id) : null,
                  ringing: widget.services.ringing.value.contains(note.id),
                ),
              ),
            ),
          ),
        ),
      );
}
