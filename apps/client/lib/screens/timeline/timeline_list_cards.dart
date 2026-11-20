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

    final tileRow = NexNoteGridCard.heightFor(context) + insets;
    if (widget.preferences.expandedNoteIds.isEmpty) return index * tileRow;
    var expanded = 0;
    for (var i = 0; i < index; i++) {
      final note = _model.notes[i];
      if (widget.preferences.isNoteExpanded(note.id) && !_wideTileOnly(note)) {
        expanded++;
      }
    }
    return (index - expanded) * tileRow + expanded * listRow;
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
        child: SizedBox(
          height: NexNoteGridCard.heightFor(context),
          width: double.infinity,
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
                ? _ListVoicePreview(note: note, strings: strings)
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

class _ListVoicePreview extends StatelessWidget {
  const _ListVoicePreview({required this.note, required this.strings});

  final Note note;
  final NexCardStrings strings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = note.title?.trim();
    final leading = title?.isNotEmpty == true ? title : note.originalFilename;
    final caption = NexMarkdownText.preview(note.caption ?? '').trim();
    final transcript = NexMarkdownText.preview(note.transcriptText ?? '')
        .trim();
    final hasCaption = caption.isNotEmpty && caption != leading;
    final hasTranscript =
        transcript.isNotEmpty && transcript != caption && transcript != leading;
    const captionShare = 4;
    final small = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Column(
      key: const ValueKey('card-voice'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (leading?.isNotEmpty == true)
          NexTextSurface.line(leading!, style: theme.textTheme.bodyLarge),
        if (hasCaption)
          NexTextSurface(
            caption,
            maxLines: hasTranscript ? captionShare : nexCardExpandedMaxLines,
            style: small,
          ),
        SizedBox(
          height: nexMinTapTarget,
          child: NexCardVoice(
            note: note,
            tint: nexNoteWash(note.type.wireName, theme.colorScheme).tint,
            height: nexMinTapTarget,
            durationLabel: strings.durationLabel ?? nexDefaultDurationLabel,
            playLabel: strings.playLabel ?? 'Play',
            pauseLabel: strings.pauseLabel ?? 'Pause',
          ),
        ),
        if (hasTranscript)
          NexTextSurface(
            transcript,
            maxLines: nexCardExpandedMaxLines - (hasCaption ? captionShare : 0),
            style: small,
          ),
      ],
    );
  }
}
