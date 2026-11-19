part of '../timeline_screen.dart';

extension _TimelineListCards on TimelineScreenState {
  NoteCard _listCard(
    Note note,
    NexCardStrings strings, {
    bool interactive = true,
  }) {
    final density = NexCardDensity.of(context);
    final large = density == NexCardDensity.readable;
    final expanded = widget.preferences.isNoteExpanded(note.id);
    final playable = NexCardVoicePreview.fits(note, density);
    final media = large
        ? switch (nexTileBackdropOf(note, collages: false)) {
            NexTileBackdrop.photo => _ListPhotoPreview(path: note.mediaUri!),
            NexTileBackdrop.pdf => _ListPdfPreview(path: note.mediaUri!),
            _ => null,
          }
        : null;
    final selected = interactive && _selecting
        ? _selected.contains(note.id)
        : null;
    return NoteCard(
      note: note,
      strings: strings,
      timelinePreview: true,
      mediaPreview: media,
      expanded: expanded,
      selected: selected,
      previewOverride: playable
          ? (large || expanded) && note.mediaUri!.isNotEmpty
                ? _ListVoicePreview(
                    note: note,
                    strings: strings,
                    expanded: expanded,
                  )
                : NexCardVoicePreview(note: note, strings: strings)
          : NexCardLinkPreview.fits(note)
          ? large
                ? _ListLinkPreview(note: note)
                : NexCardLinkPreview(note: note)
          : null,
      onTap: interactive ? () => _tapNote(note) : null,
      onLeadingTap: interactive ? () => _pickNote(note) : null,
      onToggleChecklistItem:
          interactive &&
              selected == null &&
              large &&
              note.type == NoteType.checklist
          ? (index) =>
                unawaited(widget.services.toggleChecklistItem(note.id, index))
          : null,
      ringing: interactive && widget.services.ringing.value.contains(note.id),
    );
  }
}

class _ListVoicePreview extends StatelessWidget {
  const _ListVoicePreview({
    required this.note,
    required this.strings,
    required this.expanded,
  });

  final Note note;
  final NexCardStrings strings;
  final bool expanded;

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
            maxLines: !expanded
                ? 2
                : hasTranscript
                ? captionShare
                : nexCardExpandedMaxLines,
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
            maxLines: expanded
                ? nexCardExpandedMaxLines - (hasCaption ? captionShare : 0)
                : 2,
            style: small,
          ),
      ],
    );
  }
}

class _ListLinkPreview extends StatelessWidget {
  const _ListLinkPreview({required this.note});

  final Note note;

  @override
  Widget build(BuildContext context) {
    final link = NexCardLinkPreview(note: note);
    final excerpt = NexMarkdownText.preview(note.linkExcerpt ?? '').trim();
    if (excerpt.isEmpty || excerpt == note.displayText?.trim()) return link;
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        link,
        NexTextSurface(
          excerpt,
          maxLines: 2,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _ListPhotoPreview extends StatelessWidget {
  const _ListPhotoPreview({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final height = (constraints.maxWidth / 2.3).clamp(88.0, 166.0);
      final ratio = MediaQuery.devicePixelRatioOf(context);
      final image = ResizeImage(
        FileImage(File(path)),
        width: (constraints.maxWidth * ratio).round().clamp(1, 720),
        height: (height * ratio * 2).round().clamp(1, 840),
        policy: ResizeImagePolicy.fit,
      );
      return SizedBox(
        key: const ValueKey('list-photo-preview'),
        height: height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(NexRadius.md),
          child: Image(
            image: image,
            fit: BoxFit.cover,
            excludeFromSemantics: true,
            errorBuilder: (context, _, _) => ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainer,
              child: const Icon(Icons.image_not_supported_outlined),
            ),
          ),
        ),
      );
    },
  );
}

class _ListPdfPreview extends StatelessWidget {
  const _ListPdfPreview({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final known = NexTilePreviews.knownPage(path);
    if (known != null) return _preview(context, known.page);
    return FutureBuilder<NexTilePage?>(
      future: NexTilePreviews.page(path),
      builder: (context, snapshot) => _preview(context, snapshot.data),
    );
  }

  Widget _preview(BuildContext context, NexTilePage? page) {
    final theme = Theme.of(context);
    const width = 72.0;
    const height = 90.0;
    return Row(
      key: const ValueKey('list-pdf-preview'),
      children: [
        SizedBox(
          width: width,
          height: height,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(NexRadius.sm),
            child: ColoredBox(
              color: theme.colorScheme.surface,
              child: page == null
                  ? Icon(
                      Icons.picture_as_pdf_outlined,
                      color: theme.colorScheme.onSurfaceVariant,
                    )
                  : Image.memory(
                      page.bytes,
                      cacheWidth:
                          (width * MediaQuery.devicePixelRatioOf(context))
                              .round(),
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      excludeFromSemantics: true,
                      errorBuilder: (_, _, _) =>
                          const Icon(Icons.picture_as_pdf_outlined),
                    ),
            ),
          ),
        ),
        if (page != null) ...[
          const SizedBox(width: NexSpacing.sm),
          Expanded(
            child: Text(
              AppLocalizations.of(context).tilePdfPages(page.pages),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
