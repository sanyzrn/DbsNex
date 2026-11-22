part of '../timeline_screen.dart';

/// The phone's grid view (2.6.27, reworked in 2.6.28): the same days, pins
/// and folds as the list, each day laid out as tiles — three to a row at the
/// compact card size, two at the others, more as the window widens
/// ([NexGridMetrics]).
///
/// Swiping a tile does nothing — tiles side by side leave no edge to swipe
/// from — so what a swipe does in the list is in the tile's hold menu, which
/// is the same menu the list's cards open.
extension _TimelineGrid on TimelineScreenState {
  /// Where a collage tile's other pictures come from.
  NexTilePhotos get _tilePhotos =>
      (note) => _tilePhotosOf(widget.services, note);

  /// How far down the grid the [index]th note starts, at least — the
  /// reveal's first jump, as `index * rowHeight` is the list's.
  double _gridOffsetEstimate(int index) {
    final metrics = NexGridMetrics.of(context);
    final width = MediaQuery.sizeOf(context).width - 2 * NexSpacing.md;
    final columns = metrics.columnsFor(width);
    final row = metrics.minimumHeightFor(context) + NexSpacing.sm;
    return (index ~/ columns) * row;
  }

  NexGridRows _adaptiveGridRows(_NoteGroup group, NexGridRowSizing sizing) {
    final known = _gridRowLayouts[group.notes];
    if (known != null && known.matches(sizing)) return known;
    return _gridRowLayouts[group.notes] = NexGridRows(group.notes, sizing);
  }

  List<Widget> _gridSlivers(List<_NoteGroup> groups, AppLocalizations l10n) {
    final strings = nexCardStrings(context);
    final metrics = NexGridMetrics.of(context);
    final height = metrics.heightFor(context);
    final sizing = metrics.hasAdaptiveRows
        ? NexGridRowSizing.of(context, strings, previous: _gridRowSizing)
        : null;
    _gridRowSizing = sizing;
    NexGridRows? adaptiveRows(_NoteGroup group) =>
        sizing == null ? null : _adaptiveGridRows(group, sizing);
    const padding = EdgeInsets.fromLTRB(
      NexSpacing.md,
      NexSpacing.xs,
      NexSpacing.md,
      NexSpacing.sm,
    );
    return [
      for (final group in groups)
        _GroupSliver(
          key: ValueKey(group.key),
          screen: this,
          group: group,
          folds: _groupFoldPulse,
          heading: () => _groupHeading(group, groups, l10n),
          body: () => SliverMainAxisGroup(
            slivers: [
              if (group.notes.isNotEmpty)
                SliverPadding(
                  padding: padding,
                  sliver: SliverGrid.builder(
                    gridDelegate: NexGridColumnsDelegate(
                      metrics: metrics,
                      mainAxisExtent: height,
                      rows: adaptiveRows(group),
                    ),
                    itemCount: group.notes.length,
                    itemBuilder: (context, i) =>
                        _gridTile(group.notes[i], strings, l10n, group),
                  ),
                ),
              if (!group.complete)
                SliverToBoxAdapter(child: _shelfMore(group, l10n)),
            ],
          ),
        ),
    ];
  }

  Widget _gridTile(
    Note note,
    NexCardStrings strings,
    AppLocalizations l10n,
    _NoteGroup group,
  ) => _DayMark(
    // The day passing under the filters, named as the list names it —
    // or, arranged, the shelf.
    label: group.shelf != null ? group.label : _dayLabel(note, l10n),
    marks: _dayMarks,
    child: NexTapGuarded(
      controller: _guard,
      child: NoteContextMenu(
        key: ValueKey('grid-menu-${note.id}'),
        entriesBuilder: (menuContext, width) =>
            _holdEntries(note, menuContext, width),
        onHold: _selecting ? () => _pickNote(note) : null,
        // The same two moments the list marks: a note asked for from
        // outside (a reminder, a widget row) is found by this anchor and
        // lit, and a note just captured lands with its receipt.
        child: NoteSpotlight(
          key: _spotlightId == note.id && !group.echoes.contains(note.id)
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
            // Off the rounded corners: the bar runs down the tile's
            // straight edge.
            insets: const EdgeInsets.symmetric(vertical: NexRadius.xl),
            onDone: () {
              if (mounted && landedId == note.id) {
                _rebuild(() => landedId = null);
              }
            },
            child: _pickShield(
              note,
              NexNoteGridCard(
                key: ValueKey('grid-${note.id}'),
                note: note,
                strings: strings,
                onTap: () => _tapNote(note),
                onLeadingTap: () => _pickNote(note),
                selected: _selecting ? _selected.contains(note.id) : null,
                ringing: widget.services.ringing.value.contains(note.id),
                photos: _tilePhotos,
                // Ticked where it is seen (2.8.2); not while notes are being
                // picked, when a touch on a tile picks it.
                onToggleItem: _selecting
                    ? null
                    : (index) => unawaited(
                        widget.services.toggleChecklistItem(note.id, index),
                      ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// A photo note's other pictures, for its collage tile: the photo
/// attachments' files, in their order (2.8.2).
Future<List<String>> _tilePhotosOf(NexServices services, Note note) async {
  final attached = await services.attachmentsFor(note.id);
  return [
    for (final a in attached)
      if (a.deletedAt == null &&
          (a.kind == AttachmentKind.photo ||
              (a.mimeType?.startsWith('image/') ?? false)))
        a.mediaUri,
  ];
}
