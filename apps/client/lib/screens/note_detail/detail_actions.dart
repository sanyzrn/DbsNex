part of '../note_detail_sheet.dart';

/// What can be done to the note from its sheet: copy, share, open, edit,
/// remind, tag, pin.
extension _DetailActions on _NoteDetailSheetState {
  Future<void> _pickThreads(String noteId) async {
    await showThreadPicker(context, services: widget.services, noteId: noteId);
    await _reload();
  }

  Future<void> _openThread(NoteThread thread) async {
    await Navigator.push(
      context,
      NexPageRoute<void>(
        builder: (_) => ThreadScreen(
          services: widget.services,
          preferences: widget.preferences,
          thread: thread,
        ),
      ),
    );
    await _reload();
  }

  /// The text the main copy action hands to the clipboard: whatever
  /// [Note.displayText] shows on screen, so the button copies what the user
  /// is actually looking at — a caption once there is one, not the
  /// transcript/OCR text underneath it. That text keeps its own small copy
  /// icon in the AI panel (see [_copyDerivedText]).
  String? _copyableText(Note note) => note.displayText;

  /// The note's own words, wherever they live.
  ///
  /// [Note.displayText] prefers a caption the user wrote, which is the right
  /// answer for the card and the wrong one here: a photo captioned "receipt"
  /// with a page of Persian read out of it has a page worth translating and a
  /// one-word caption that is not.
  String _translatableText(Note note) {
    for (final candidate in [
      note.content,
      note.transcriptText,
      note.ocrText,
      note.displayText,
    ]) {
      final text = candidate?.trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  void _toast(String message) {
    nexShowBanner(context, message: message);
  }

  Future<void> _copyText() async {
    final note = _note;
    if (note == null) return;
    final l10n = AppLocalizations.of(context);
    final text = _copyableText(note);
    if (text == null) {
      _toast(l10n.nothingToCopy);
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    _toast(l10n.copied);
  }

  /// Copies one of the AI panel's own texts — a transcript, an OCR read, a
  /// summary — rather than [_copyableText]'s fallback chain, which is the
  /// note's own content first and would copy the wrong thing here.
  Future<void> _copyDerivedText(String text) async {
    final l10n = AppLocalizations.of(context);
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    _toast(l10n.copied);
  }

  Future<void> _copyPath() async {
    final note = _note;
    final uri = note?.mediaUri;
    if (uri == null) return;
    final l10n = AppLocalizations.of(context);
    await Clipboard.setData(ClipboardData(text: uri));
    if (!mounted) return;
    _toast(l10n.copied);
  }

  /// Hands the note's media to the OS, exactly as a file manager would: the
  /// default handler opens it, or the system asks which app should.
  Future<void> _openExternally() async {
    final note = _note;
    final uri = note?.mediaUri;
    if (uri == null) return;
    final l10n = AppLocalizations.of(context);
    if (!File(uri).existsSync()) {
      _toast(l10n.mediaUnavailable);
      return;
    }
    final result = await nexOpenFile(uri, mimeType: note?.mimeType);
    if (!mounted) return;
    if (result != FileOpenOutcome.opened) _toast(l10n.cannotOpen);
  }

  Future<void> _editImage() async {
    final note = _note;
    final source = note?.mediaUri;
    if (note == null || source == null) return;
    try {
      final original = await File(source).readAsBytes();
      if (!mounted) return;
      final edited = await Navigator.of(context).push<Uint8List>(
        NexPageRoute(
          swipeBackEnabled: false,
          builder: (_) => PhotoCropScreen(
            image: original,
            drafts: widget.preferences?.editorDrafts,
            draftKey: 'photo-${note.id}',
          ),
        ),
      );
      if (edited == null || !mounted) return;
      final encoded = await compute(encodeEditedPhoto, (
        bytes: edited,
        wasJpeg:
            original.length > 2 && original[0] == 0xff && original[1] == 0xd8,
      ));
      // Never overwrite the original. A failed database write must not leave
      // the note pointing at bytes that changed underneath it.
      final dest = p.join(
        widget.services.mediaDir,
        'edited-${DateTime.now().microsecondsSinceEpoch}${photoExtension(encoded)}',
      );
      final file = File(dest);
      await file.writeAsBytes(encoded, flush: true);
      // An exception can follow a committed write (lost worker response or
      // failed refresh). Leave cleanup to reference-aware media maintenance.
      await widget.services.updateImageMedia(
        note.id,
        dest,
        sha256OfBytes(encoded),
      );
      widget.preferences?.editorDrafts?.clear('photo-${note.id}-crop');
      widget.preferences?.editorDrafts?.clear('photo-${note.id}-annotation');
      await _reload();
    } catch (_) {
      if (mounted) {
        nexShowBanner(
          context,
          message: AppLocalizations.of(context).editPhotoFailed,
          kind: NexBannerKind.failed,
        );
      }
    }
  }

  /// Opens a link note in whatever handles the web on this device.
  ///
  /// `externalApplication` rather than an in-app view: a bookmark is a
  /// promise to hand you back to the page, and a stripped-down web view
  /// without your session, your extensions or your history is not that page.
  Future<void> _openLink() async {
    final url = _note?.linkUrl;
    if (url == null) return;
    final l10n = AppLocalizations.of(context);
    final opened = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    ).catchError((Object _) => false);
    if (!mounted) return;
    if (!opened) _toast(l10n.cannotOpen);
  }

  /// Ticks one line of a checklist and re-reads the note.
  ///
  /// Straight through to the repository, which rewrites the note's content —
  /// there is no local list being edited here, so nothing can drift out of
  /// step with what is stored.
  Future<void> _toggleItem(int index) async {
    final note = _note;
    if (note == null) return;
    await widget.services.toggleChecklistItem(note.id, index);
    await _reload();
  }

  /// The note's optional headline. Empty clears it, so the one control both
  /// names a note and un-names it.
  /// Shares the media itself for a file, photo or voice note, and the body for
  /// a text note — sharing a text note as a zero-byte attachment would be
  /// useless to whatever receives it.
  Future<void> _share() async {
    final note = _note;
    if (note == null) return;
    final l10n = AppLocalizations.of(context);
    if (!await nexShareNote(note) && mounted) _toast(l10n.nothingToCopy);
  }

  Future<void> _convertMarkdown() async {
    final note = _note;
    if (note == null || _convertingMarkdown) return;
    _rebuild(() => _convertingMarkdown = true);
    try {
      await widget.services.convertMarkdown(note);
      await _reload();
    } catch (_) {
      if (mounted) {
        nexShowBanner(
          context,
          message: AppLocalizations.of(context).markdownConvertFailed,
        );
      }
    } finally {
      if (mounted) _rebuild(() => _convertingMarkdown = false);
    }
  }

  Future<void> _editContent() async {
    final note = _note;
    final preferences = widget.preferences;
    if (note == null || note.type != NoteType.text) return;
    if (preferences == null) return;
    final value = await NoteEditorSheet.show(
      context,
      initial: note.content ?? '',
      draftKey: 'note-${note.id}',
      preferences: preferences,
    );
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return;
    if (trimmed == note.content) {
      preferences.editorDrafts?.clear('note-${note.id}');
      return;
    }
    await widget.services.updateNote(note.id, trimmed);
    preferences.editorDrafts?.clear('note-${note.id}');
    await widget.services.refreshTimeline();
    await _reload();
  }

  /// Editing a checklist: the same sheet it was written in, seeded.
  ///
  /// There was no way to fix a typo, add the thing you forgot, or drop a line
  /// — a checklist could be ticked and nothing else. Reusing the capture
  /// sheet rather than building a row-per-item editor is what makes all three
  /// of those the same gesture: it is a field of lines, so adding is Enter
  /// and removing is deleting the line.
  ///
  /// The ticks come back across by [restoreTicks]: the editor carries text
  /// and nothing else, and saving what it returns as-is would untick the
  /// whole list.
  Future<void> _editChecklist() async {
    final note = _note;
    final preferences = widget.preferences;
    if (note == null || note.type != NoteType.checklist) return;
    if (preferences == null) return;
    final before = note.checklistItems;
    final edited = await nexShowSheet<List<ChecklistItem>>(
      context: context,
      dismissible: false,
      swipeToClose: true,
      builder: (_) => ChecklistCaptureSheet(
        preferences: preferences,
        initial: before,
        draftKey: 'checklist-${note.id}',
      ),
    );
    if (edited == null) return;
    final content = formatChecklist(restoreTicks(edited, before));
    if (content == note.content) {
      preferences.editorDrafts?.clear('checklist-${note.id}');
      return;
    }
    await widget.services.updateNote(note.id, content);
    preferences.editorDrafts?.clear('checklist-${note.id}');
    await widget.services.refreshTimeline();
    await _reload();
  }

  /// The reminder menu: four times someone actually means, and a picker.
  ///
  /// Quick choices rather than a date picker first. "Tomorrow morning" is
  /// what people say, and making them assemble it out of a calendar and a
  /// clock to say it is the reason reminder features go unused.
  Future<void> _pickReminder() async {
    final note = _note;
    if (note == null) return;
    // The picker itself lives in `reminder_picker.dart`: a swipe on the
    // timeline opens the same sheet, and two copies of a date-and-permission
    // flow is two places for it to drift.
    if (await nexPickReminder(
      context: context,
      services: widget.services,
      note: note,
    )) {
      await _reload();
    }
  }

  Future<void> _showDetails() async {
    final note = _note;
    if (note == null) return;
    final l10n = AppLocalizations.of(context);
    final uri = note.mediaUri;
    final file = uri == null ? null : File(uri);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.details),
        content: NexDialogBody(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DetailRow(label: l10n.noteType(note.type.wireName), value: ''),
              _DetailRow(
                label: l10n.created,
                value: _formatTimestamp(note.createdAt),
              ),
              _DetailRow(
                label: l10n.updated,
                value: _formatTimestamp(note.updatedAt),
              ),
              if (note.tags.isNotEmpty)
                _DetailRow(
                  label: l10n.tags,
                  value: note.tags.map((t) => t.name).join('، '),
                ),
              if (file != null && file.existsSync())
                _DetailRow(
                  label: l10n.size,
                  value: nexDigits(
                    nexFormatBytes(file.lengthSync()),
                    persian:
                        Localizations.localeOf(context).languageCode == 'fa',
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime value) => nexDisplayDate(
    value,
    solar: widget.services.solarCalendar,
    persian: Localizations.localeOf(context).languageCode == 'fa',
    time: true,
    seconds: true,
  );

  /// Tagging a note.
  ///
  /// The dialog used to offer five hardcoded starter names and a colour grid,
  /// and no way to reach the tags the user had actually made — so the one list
  /// it needed to show was the one list it did not have.
  Future<void> _addTag() async {
    final note = _note;
    final all = await widget.services.listTags();
    if (!mounted) return;
    final choice = await TagPickerSheet.show(
      context,
      tags: all,
      alreadyOn: note?.tags.map((t) => t.id).toSet() ?? const {},
    );
    if (choice == null || !mounted) return;
    await widget.services.addTag(
      noteId: widget.noteId,
      name: choice.tag?.name ?? choice.name!,
      color: choice.color,
    );
    await widget.services.refreshTimeline();
    await _reload();
  }

  /// Shows this note's card in full on the timeline, or puts it back to two
  /// lines.
  ///
  /// Stored per device rather than on the note — see
  /// [NexPreferences.expandedNoteIds] for why.
  Future<void> _toggleExpanded(String noteId) async {
    final preferences = widget.preferences;
    if (preferences == null) return;
    await preferences.setNoteExpanded(
      noteId,
      !preferences.isNoteExpanded(noteId),
    );
    if (mounted) _rebuild(() {});
  }

  Future<void> _togglePin() async {
    final note = _note;
    if (note == null) return;
    if (note.pinnedAt != null) {
      await widget.services.unpinNote(note.id);
    } else {
      await widget.services.pinNote(note.id);
    }
    await widget.services.refreshTimeline();
    await _reload();
  }

  Future<void> _editCaption() async {
    final note = _note;
    if (note == null || note.type == NoteType.text) return;
    final preferences = widget.preferences;
    if (preferences == null) return;
    final value = await NoteEditorSheet.show(
      context,
      initial: note.caption ?? '',
      preferences: preferences,
      draftKey: 'caption-${note.id}',
      allowEmpty: true,
    );
    if (value == null) return;
    await widget.services.setCaption(widget.noteId, value);
    preferences.editorDrafts?.clear('caption-${note.id}');
    await widget.services.refreshTimeline();
    await _reload();
  }
}
