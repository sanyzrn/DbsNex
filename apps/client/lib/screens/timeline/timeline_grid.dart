part of '../timeline_screen.dart';

/// The phone's grid view (2.6.27): the same days, pins and folds as the list,
/// each run laid out two tiles to a row instead of one card under another.
///
/// Swiping a tile does nothing — two tiles side by side leave no edge to
/// swipe from — so what a swipe does in the list is in the tile's hold menu,
/// which is the same menu the list's cards open.
/// The widest a grid tile is drawn; the grid fits as many as this allows.
const _gridTileWidth = 260.0;

extension _TimelineGrid on TimelineScreenState {
  /// How far down the grid the [index]th note starts, at least — the
  /// reveal's first jump, as `index * rowHeight` is the list's.
  double _gridOffsetEstimate(int index) {
    final width = MediaQuery.sizeOf(context).width - 2 * NexSpacing.md;
    final columns = math.max(
      1,
      ((width + NexSpacing.sm) / (_gridTileWidth + NexSpacing.sm)).ceil(),
    );
    final row = NexNoteGridCard.heightFor(context) + NexSpacing.sm;
    return (index ~/ columns) * row;
  }

  List<Widget> _gridSlivers(List<_NoteGroup> groups, AppLocalizations l10n) {
    final strings = nexCardStrings(context);
    final height = NexNoteGridCard.heightFor(context);
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
            if (!_model.collapsedGroups.contains(group.key))
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  NexSpacing.md,
                  NexSpacing.xs,
                  NexSpacing.md,
                  NexSpacing.sm,
                ),
                sliver: SliverGrid.builder(
                  // Two on a phone; more as the window widens, each tile kept
                  // near the width it was drawn for.
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: _gridTileWidth,
                    mainAxisExtent: height,
                    crossAxisSpacing: NexSpacing.sm,
                    mainAxisSpacing: NexSpacing.sm,
                  ),
                  itemCount: group.notes.length,
                  itemBuilder: (context, i) {
                    final note = group.notes[i];
                    return _DayMark(
                      // The day passing under the filters, named as the
                      // list names it.
                      label: _dayLabel(note, l10n),
                      marks: _dayMarks,
                      child: NexTapGuarded(
                        controller: _guard,
                        child: NoteContextMenu(
                          key: ValueKey('grid-menu-${note.id}'),
                          entriesBuilder: (menuContext, width) =>
                              _holdEntries(note, menuContext, width),
                          // The same two moments the list marks: a note asked
                          // for from outside (a reminder, a widget row) is
                          // found by this anchor and lit, and a note just
                          // captured lands with its receipt.
                          child: NoteSpotlight(
                            key: _spotlightId == note.id
                                ? _spotlightAnchor
                                : null,
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
                              // Off the rounded corners: the bar runs down the
                              // tile's straight edge.
                              insets: const EdgeInsets.symmetric(
                                vertical: NexRadius.xl,
                              ),
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
                                selected: _selecting
                                    ? _selected.contains(note.id)
                                    : null,
                                ringing: widget.services.ringing.value.contains(
                                  note.id,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
    ];
  }
}
