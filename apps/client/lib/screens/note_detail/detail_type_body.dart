part of '../note_detail_sheet.dart';

/// What the sheet shows for the note's own type — the list, the link, the
/// text, the player, the picture or the file — and, for anything but text,
/// its caption. Split out of the sheet's build (REL-10).
extension _DetailTypeBody on _NoteDetailSheetState {
  List<Widget> _typeBody(
    BuildContext context,
    Note note,
    AppLocalizations l10n,
  ) => [
    if (note.type == NoteType.checklist)
      // The one place a checklist is interactive. On the card it
      // is a picture of a list; here it is the list.
      _ChecklistBody(
        items: note.checklistItems,
        onToggle: (index) => unawaited(_toggleItem(index)),
      )
    else if (note.type == NoteType.link)
      _LinkBody(note: note, onOpen: _openLink)
    else if (note.type == NoteType.text)
      FoldedNote(
        text: note.content ?? '',
        onTapLink: _openHref,
        onCopyCode: (code) => unawaited(_copyCodeSpan(context, code)),
      )
    else if (note.type == NoteType.voice) ...[
      if (_steady == null)
        Text(
          l10n.voiceDuration(((note.durationMs ?? 0) / 1000).ceil()),
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      if (_steady != null) ...[
        const SizedBox(height: NexSpacing.sm),
        _VoicePlayerControls(
          path: note.mediaUri,
          steady: _steady!,
          position: _position,
          duration: _duration > Duration.zero
              ? _duration
              : Duration(milliseconds: note.durationMs ?? 0),
        ),
      ],
      if (note.transcriptText == null)
        Text(
          l10n.voiceSearchHint,
          style: Theme.of(context).textTheme.bodySmall,
        ),
    ] else if (note.type == NoteType.photo) ...[
      if (note.mediaUri != null && File(note.mediaUri!).existsSync()) ...[
        GestureDetector(
          onTap: () => unawaited(_openGallery(note, at: note.mediaUri!)),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(NexRadius.md),
            child: Image.file(
              File(note.mediaUri!),
              semanticLabel: l10n.photo,
              fit: BoxFit.contain,
              height: 220,
              width: double.infinity,
              cacheWidth: _imageCacheWidth(context),
              // A photo whose file has gone — deleted
              // underneath an open sheet — draws nothing
              // rather than reporting an error.
              errorBuilder: (_, _, _) => const SizedBox(height: 220),
            ),
          ),
        ),
        const SizedBox(height: NexSpacing.sm),
        Text(l10n.tapToExpand, style: Theme.of(context).textTheme.bodySmall),
      ] else
        Text(
          l10n.mediaUnavailable,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
    ] else ...[
      // File — same sheet, ADR-008 display fields. Tapping the row
      // hands it to the OS, so the note behaves like the same file
      // does in a file manager.
      InkWell(
        onTap: _openExternally,
        borderRadius: BorderRadius.circular(NexRadius.lg),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: NexSpacing.sm,
            horizontal: NexSpacing.xs,
          ),
          child: Row(
            children: [
              Icon(
                Icons.insert_drive_file_outlined,
                color: Theme.of(context).colorScheme.secondary,
              ),
              const SizedBox(width: NexSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      note.content?.trim().isNotEmpty == true
                          ? note.content!
                          : (note.mediaUri != null
                                ? p.basename(note.mediaUri!)
                                : l10n.file),
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    if (note.mediaUri != null &&
                        File(note.mediaUri!).existsSync())
                      Text(
                        [
                          nexDigits(
                            nexFormatBytes(File(note.mediaUri!).lengthSync()),
                            persian:
                                Localizations.localeOf(context).languageCode ==
                                'fa',
                          ),
                          if (note.mimeType != null) note.mimeType!,
                        ].join(' · '),
                        textDirection: TextDirection.ltr,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.secondary,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: l10n.revealInFolder,
                onPressed: _copyPath,
                icon: const Icon(Icons.folder_outlined, size: 18),
                color: Theme.of(context).colorScheme.secondary,
              ),
              Icon(
                Icons.open_in_new,
                size: 18,
                color: Theme.of(context).colorScheme.secondary,
              ),
            ],
          ),
        ),
      ),
      // A file shown rather than merely listed. The note
      // itself only ever held the filename — the content is in
      // a file on disk — so this is the one place in the app
      // that reads a note's media back.
      if (note.mediaUri != null)
        _FileBody(
          path: note.mediaUri!,
          kind: NexFileKinds.of(path: note.mediaUri, mimeType: note.mimeType),
          player: _steady,
          position: _position,
          duration: _duration,
          onOpen: _openExternally,
        ),
    ],
    if (note.type != NoteType.text) ...[
      const SizedBox(height: NexSpacing.md),
      Text(l10n.caption, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: NexSpacing.xs),
      if (note.caption != null && note.caption!.trim().isNotEmpty)
        // The caption editor offers the same bold, italic and
        // link actions as a text note's, so a caption that
        // used them is drawn the way a text note's body is.
        nexLooksLikeMarkdown(note.caption!)
            ? SelectionArea(
                contextMenuBuilder: nexSelectionMenu,
                child: NexMarkdown(
                  note.caption!,
                  selectable: false,
                  onTapLink: _openHref,
                  onCopyCode: (code) => unawaited(_copyCodeSpan(context, code)),
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              )
            : NexTextSurface(
                note.caption!,
                style: Theme.of(context).textTheme.bodyLarge,
                selectable: true,
              )
      else
        Text(
          l10n.noCaption,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.secondary,
          ),
        ),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton(
          onPressed: _editCaption,
          child: Text(
            note.caption == null || note.caption!.trim().isEmpty
                ? l10n.addCaption
                : l10n.editCaption,
          ),
        ),
      ),
    ],
  ];
}
