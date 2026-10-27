part of '../timeline_screen.dart';

/// The gap between the window's edge (and the rail) and the grid.
const _desktopGutter = 28.0;

/// The home screen in a wide window (`docs/27-desktop.md`): each day, or the
/// pinned notes, is a small label above a grid of cards, instead of the
/// phone's single column of rows.
extension _TimelineDesktop on TimelineScreenState {
  List<Widget> _desktopSlivers(List<_NoteGroup> groups, AppLocalizations l10n) {
    final strings = nexCardStrings(context);
    return [
      for (final group in groups)
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: _desktopGutter),
          sliver: SliverMainAxisGroup(
            slivers: [
              SliverToBoxAdapter(
                child: NexTapGuarded(
                  controller: _guard,
                  child: _GroupHeader(
                    compact: true,
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
                SliverGrid.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 340,
                    mainAxisExtent: NexDesktopNoteCard.height,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                  ),
                  itemCount: group.notes.length,
                  itemBuilder: (context, i) {
                    final note = group.notes[i];
                    return NexTapGuarded(
                      controller: _guard,
                      child: NoteContextMenu(
                        key: ValueKey('menu-${note.id}'),
                        entriesBuilder: (menuContext, width) =>
                            _holdEntries(note, menuContext, width),
                        child: NexDesktopNoteCard(
                          note: note,
                          strings: strings,
                          onTap: () => _tapNote(note),
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
              const SliverToBoxAdapter(child: SizedBox(height: NexSpacing.lg)),
            ],
          ),
        ),
    ];
  }
}
