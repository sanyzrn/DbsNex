part of '../timeline_screen.dart';

extension _TimelineListCards on TimelineScreenState {
  bool _wideTileOnly(Note note) =>
      note.type == NoteType.link ||
      nexTileBackdropOf(note) != NexTileBackdrop.none;

  bool _usesWideListTile(Note note) =>
      NexCardDensity.of(context) == NexCardDensity.readable &&
      (!widget.preferences.isNoteExpanded(note.id) || _wideTileOnly(note));

  double _listOffsetEstimate(int index) {
    final insets = nexCardInsetsFor(context).vertical;
    final listRow = nexCardHeightFor(context, timelinePreview: true) + insets;
    if (NexCardDensity.of(context) != NexCardDensity.readable ||
        NexDesktopScope.isDesktop(context)) {
      return index * listRow;
    }

    final metrics = NexGridMetrics.of(context);
    // A lower bound even if every row is a one-line note or a media
    // preview fails. Revealing a distant note never lays out its predecessors.
    return index * (metrics.disc + metrics.padding * 2 + insets);
  }

  Widget _listCard(
    Note note,
    NexCardStrings strings, {
    bool interactive = true,
  }) {
    final density = NexCardDensity.of(context);
    final expanded = widget.preferences.isNoteExpanded(note.id);
    final selected = interactive && _selecting
        ? _selected.contains(note.id)
        : null;
    final ringing =
        interactive && widget.services.ringing.value.contains(note.id);
    final onTap = interactive ? () => _tapNote(note) : null;
    final onPick = interactive ? () => _pickNote(note) : null;
    if (_usesWideListTile(note)) {
      return Padding(
        padding: nexCardInsetsFor(context),
        child: LayoutBuilder(
          builder: (_, constraints) => NexNoteGridCard(
            key: ValueKey('list-wide-${note.id}'),
            note: note,
            strings: strings,
            onTap: onTap,
            onLeadingTap: onPick,
            selected: selected,
            ringing: ringing,
            photos: _tilePhotos,
            previewWidth: constraints.maxWidth,
            onToggleItem:
                interactive && !_selecting && note.type == NoteType.checklist
                ? (index) => unawaited(
                    widget.services.toggleChecklistItem(note.id, index),
                  )
                : null,
          ),
        ),
      );
    }

    final playable = NexCardVoicePreview.fits(note, density);
    return NoteCard(
      note: note,
      strings: strings,
      timelinePreview: true,
      expanded: expanded,
      selected: selected,
      previewOverride: playable
          ? expanded && note.mediaUri!.isNotEmpty
                ? NexListVoicePreview(
                    note: note,
                    strings: strings,
                    expanded: true,
                  )
                : NexCardVoicePreview(note: note, strings: strings)
          : NexCardLinkPreview.fits(note)
          ? NexCardLinkPreview(note: note)
          : null,
      onTap: onTap,
      onLeadingTap: onPick,
      ringing: ringing,
    );
  }
}
