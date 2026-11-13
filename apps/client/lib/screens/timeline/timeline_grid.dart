part of '../timeline_screen.dart';

/// The phone's grid view (2.6.27): the same days, pins and folds as the list,
/// each run laid out two tiles to a row instead of one card under another.
///
/// Swiping a tile does nothing — two tiles side by side leave no edge to
/// swipe from — so what a swipe does in the list is in the tile's hold menu,
/// which is the same menu the list's cards open.
extension _TimelineGrid on TimelineScreenState {
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
                    maxCrossAxisExtent: 260,
                    mainAxisExtent: height,
                    crossAxisSpacing: NexSpacing.sm,
                    mainAxisSpacing: NexSpacing.sm,
                  ),
                  itemCount: group.notes.length,
                  itemBuilder: (context, i) {
                    final note = group.notes[i];
                    return NexTapGuarded(
                      controller: _guard,
                      child: NoteContextMenu(
                        key: ValueKey('grid-menu-${note.id}'),
                        entriesBuilder: (menuContext, width) =>
                            _holdEntries(note, menuContext, width),
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
                    );
                  },
                ),
              ),
          ],
        ),
    ];
  }
}
