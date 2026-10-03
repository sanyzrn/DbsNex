part of '../timeline_screen.dart';

/// What can be done to notes and groups on the timeline, and the sponsor card.
extension _TimelineNoteActions on TimelineScreenState {
  /// The non-destructive half of ADR-022's fixed action pair.
  /// Swipe-to-tag (FR-2.6).
  ///
  /// Offers the tags that exist rather than a bare text field, so tagging is
  /// picking from what you already use — the common case by a wide margin.
  ///
  /// Every tag, not [_model.filterTags]: that list only holds tags with at least one
  /// note left on them, so tagging the first note after clearing a library
  /// (or after every tagged note happened to be deleted) offered nothing.
  Future<void> _addTagTo(Note note) async {
    final all = await widget.services.listTags();
    if (!mounted) return;
    final choice = await TagPickerSheet.show(
      context,
      tags: all,
      alreadyOn: note.tags.map((t) => t.id).toSet(),
    );
    if (choice == null || !mounted) return;
    if (widget.preferences.haptics) HapticFeedback.lightImpact();
    await widget.services.addTag(
      noteId: note.id,
      name: choice.tag?.name ?? choice.name!,
      color: choice.color,
    );
    await widget.services.refreshTimeline();
    // A tag created here is new to the filter row too; without this it only
    // appeared after a restart.
    await _model.loadFilterTags();
  }

  /// The sponsor card, when there is one to show.
  ///
  /// Null on every path that means "nothing to show" — no file, an
  /// unparseable one, dates that have passed, another language, or one this
  /// person has already dismissed. Absence is silent by design: there is no
  /// placeholder and no error, because a card that failed to arrive and a
  /// day with no campaign are the same thing to the reader.
  ///
  /// Held back while searching or filtering: those are moments when somebody
  /// is looking for one specific note, and a card in the way of the answer is
  /// the worst possible time to ask for attention.
  Widget? _sponsorCard() {
    if (_searching || _model.filtering) return null;
    final sponsor = _sponsor.visible(
      languageCode: Localizations.localeOf(context).languageCode,
    );
    if (sponsor == null) return null;
    return SponsorCard(
      sponsor: sponsor,
      image: _sponsor.image,
      onOpen: () => unawaited(_openSponsor(sponsor)),
      onDismiss: _sponsor.dismissible
          ? () => unawaited(_dismissSponsor(sponsor))
          : null,
    );
  }

  Future<void> _openSponsor(NexSponsor sponsor) async {
    final url = sponsor.url;
    if (url == null) return;
    final uri = Uri.tryParse(url);
    // Only the two schemes a card has any business using. A file:// or
    // intent:// url in a document fetched from a server is not a link, it is
    // an attempt at something else.
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // No browser, or one that refused. Nothing to say about it.
    }
  }

  Future<void> _dismissSponsor(NexSponsor sponsor) async {
    if (widget.preferences.haptics) HapticFeedback.lightImpact();
    await _sponsor.dismiss(sponsor.id);
    if (mounted) _rebuild(() {});
  }

  /// Opens the assistant with one date run as its whole context.
  ///
  /// Same shape as asking about a single note, and for the same reason: the
  /// context is exactly what the question is about, so the answer is specific
  /// and the request is not carrying the rest of the library to get there.
  Future<void> _askAboutGroup(_NoteGroup group) async {
    await AiChatSheet.show(
      context,
      preferences: widget.preferences,
      services: widget.services,
      history: widget.preferences.chatHistory,
      scope: List.of(group.notes),
      scopeLabel: group.label,
    );
  }

  /// Deletes a whole date run, once, after asking.
  ///
  /// Confirmed rather than undone: a swipe deletes one note and an undo
  /// banner is the right weight for that, but a heading's menu can take a
  /// day's work away in one tap, and an undo that scrolls off screen is not
  /// a safety net for that much. The notes go to Trash either way, which the
  /// dialog says so nobody has to hope.
  Future<void> _deleteGroup(_NoteGroup group, AppLocalizations l10n) async {
    final notes = List.of(group.notes);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(group.label),
        content: NexDialogBody(child: Text(l10n.groupDeleteBody(notes.length))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (widget.preferences.haptics) HapticFeedback.mediumImpact();
    for (final note in notes) {
      await widget.services.deleteNote(note.id);
    }
    await widget.services.refreshTimeline();
    if (!mounted) return;
    nexShowBanner(
      context,
      message: l10n.groupDeleted(notes.length),
      haptics: widget.preferences.haptics,
    );
  }

  /// Runs whichever action an edge was bound to.
  ///
  /// Every one of these already existed behind the note detail sheet; a swipe
  /// is a second way to reach it, not a second implementation of it — which is
  /// why the reminder picker and the share path are shared functions rather
  /// than copies.
  /// The hold menu for [note]: the actions chosen in Settings, less any
  /// this particular note cannot do — no Open file on a text note, no
  /// Translate with nothing to translate or no provider to ask.
  /// Copy from the hold menu: [nexCopyTextOf], so a text or Markdown file
  /// copies its words rather than its name.
  Future<void> _copyNote(Note note) async {
    final text = await nexCopyTextOf(note);
    if (text != null) await Clipboard.setData(ClipboardData(text: text));
  }

  List<NoteMenuEntry> _holdEntries(Note note) {
    final prefs = widget.preferences;
    final l10n = AppLocalizations.of(context);
    final words = note.copyText ?? '';
    final expanded = prefs.isNoteExpanded(note.id);
    NoteMenuEntry? entry(NexHoldAction action) => switch (action) {
      NexHoldAction.select => NoteMenuEntry(
        action,
        () => _toggleSelected(note),
      ),
      NexHoldAction.pin => NoteMenuEntry(
        action,
        () => unawaited(_runSwipe(NexSwipeAction.pin, note)),
        label: note.pinnedAt != null ? l10n.unpin : null,
        icon: note.pinnedAt != null ? Icons.push_pin : null,
      ),
      NexHoldAction.copy =>
        words.isEmpty
            ? null
            : NoteMenuEntry(action, () => unawaited(_copyNote(note))),
      NexHoldAction.edit => NoteMenuEntry(
        action,
        () => unawaited(_openNote(note, edit: true)),
      ),
      NexHoldAction.remind => NoteMenuEntry(
        action,
        () => unawaited(_runSwipe(NexSwipeAction.remind, note)),
      ),
      NexHoldAction.share =>
        !nexCanShare
            ? null
            : NoteMenuEntry(
                action,
                () => unawaited(_runSwipe(NexSwipeAction.share, note)),
              ),
      NexHoldAction.addTag => NoteMenuEntry(
        action,
        () => unawaited(_addTagTo(note)),
      ),
      NexHoldAction.expand =>
        note.displayText == null && note.type != NoteType.checklist
            ? null
            : NoteMenuEntry(
                action,
                () => unawaited(
                  prefs
                      .setNoteExpanded(note.id, !expanded)
                      .then((_) => mounted ? _rebuild(() {}) : null),
                ),
                label: expanded ? l10n.collapseCard : null,
                icon: expanded ? Icons.unfold_less : null,
              ),
      NexHoldAction.open => NoteMenuEntry(
        action,
        () => unawaited(_openNote(note)),
      ),
      NexHoldAction.openFile =>
        note.mediaUri == null
            ? null
            : NoteMenuEntry(
                action,
                () => unawaited(
                  nexOpenFile(note.mediaUri!, mimeType: note.mimeType),
                ),
              ),
      NexHoldAction.openLink =>
        note.linkUrl == null
            ? null
            : NoteMenuEntry(
                action,
                () => unawaited(
                  launchUrl(
                    Uri.parse(note.linkUrl!),
                    mode: LaunchMode.externalApplication,
                  ).catchError((_) => false),
                ),
              ),
      NexHoldAction.convert =>
        note.type == NoteType.text ||
                (note.type == NoteType.file &&
                    NexTextImport.canConvert(
                      note.originalFilename ?? note.mediaUri,
                      mimeType: note.mimeType,
                    ))
            ? NoteMenuEntry(
                action,
                () => unawaited(_openNote(note, run: action)),
              )
            : null,
      NexHoldAction.ask =>
        !AiChatSheet.availableFor(prefs)
            ? null
            : NoteMenuEntry(
                action,
                () => unawaited(_runSwipe(NexSwipeAction.ask, note)),
              ),
      NexHoldAction.translate =>
        !TranslateSheet.availableFor(prefs) ||
                (note.displayText ?? words).trim().isEmpty
            ? null
            : NoteMenuEntry(
                action,
                () => unawaited(_openNote(note, run: action)),
              ),
      NexHoldAction.summarize =>
        !prefs.effectiveAiCapabilities.summarization ||
                !aiTextAvailableWith(prefs.aiProvider)
            ? null
            : NoteMenuEntry(
                action,
                () => unawaited(_openNote(note, run: action)),
              ),
      NexHoldAction.thread => NoteMenuEntry(
        action,
        () => unawaited(
          showThreadPicker(context, services: widget.services, noteId: note.id),
        ),
      ),
      NexHoldAction.caption || NexHoldAction.details => NoteMenuEntry(
        action,
        () => unawaited(_openNote(note, run: action)),
      ),
      NexHoldAction.delete => NoteMenuEntry(
        action,
        () => unawaited(deleteWithUndo(note)),
      ),
    };
    return [
      entry(NexHoldAction.select)!,
      for (final action in prefs.holdMenuActions)
        if (entry(action) case final value?) value,
    ];
  }

  Future<void> _runSwipe(NexSwipeAction action, Note note) async {
    final l10n = AppLocalizations.of(context);
    switch (action) {
      case NexSwipeAction.delete:
        await deleteWithUndo(note);
      case NexSwipeAction.addTag:
        await _addTagTo(note);
      case NexSwipeAction.pin:
        // A toggle, because the swipe is the same gesture either way and a
        // pin that could only ever be set would need a second route to undo.
        if (note.pinnedAt == null) {
          final pinned = await widget.services.pinNote(note.id);
          if (!pinned && mounted) {
            nexShowBanner(context, message: l10n.pinLimitReached);
          }
        } else {
          await widget.services.unpinNote(note.id);
        }
        await widget.services.refreshTimeline();
      case NexSwipeAction.remind:
        await nexPickReminder(
          context: context,
          services: widget.services,
          note: note,
        );
        await widget.services.refreshTimeline();
      case NexSwipeAction.share:
        if (!await nexShareNote(note) && mounted) {
          nexShowBanner(context, message: l10n.nothingToCopy);
        }
      case NexSwipeAction.ask:
        if (!mounted) return;
        // Same guard the detail sheet uses: a button that can only answer
        // "unavailable" is worse than no button, and an edge bound to this
        // with no provider configured is exactly that.
        if (!AiChatSheet.availableFor(widget.preferences)) {
          nexShowBanner(context, message: l10n.chatUnavailable);
          return;
        }
        await AiChatSheet.show(
          context,
          preferences: widget.preferences,
          services: widget.services,
          history: widget.preferences.chatHistory,
          focus: note,
        );
    }
  }

  /// A tap on a card, which means two different things depending on what the
  /// list already looked like.
  ///
  /// With a card swiped open, a tap anywhere — on the open card itself, or on
  /// any other one — used to both close it *and* open whatever was tapped,
  /// since the outer tap-to-close and the card's own tap handler both fired
  /// off the same touch. The first tap while something is open now only
  /// closes it; opening a note takes its own, second tap.
  void _tapNote(Note note) {
    if (_claimedByOverlay()) return;
    if (_selecting) return _toggleSelected(note);
    unawaited(_openNote(note));
  }

  /// One note by id, the way a card tap opens it.
  ///
  /// A Timeline widget row *is* a card, so tapping it lands on the same
  /// sheet. The lookup is the only thing the ordinary path does not need: a
  /// row that cold-started the app is asking for a note this screen has not
  /// loaded yet. When it is already here this is exactly a card tap, undo
  /// toast and all; when it is not, the sheet loads the note by id itself
  /// and the only thing missing is the undo a delete would have offered —
  /// which is honest, since there is nothing on this screen to undo it back
  /// into.
  Future<void> _openNoteById(String noteId) async {
    final known = _model.byId(noteId);
    if (known != null) return _openNote(known);
    await nexShowSheet<DetailResult>(
      context: context,
      builder: (_) => NoteDetailSheet(
        services: widget.services,
        preferences: widget.preferences,
        noteId: noteId,
      ),
    );
    await widget.services.refreshTimeline();
  }

  Future<void> _openNote(
    Note note, {
    bool edit = false,
    NexHoldAction? run,
  }) async {
    final result = await nexShowSheet<DetailResult>(
      context: context,
      rise: true,
      builder: (_) => NoteDetailSheet(
        editOnOpen: edit,
        runOnOpen: run,
        services: widget.services,
        preferences: widget.preferences,
        noteId: note.id,
      ),
    );
    if (result == DetailResult.deleted) await deleteWithUndo(note);
    await widget.services.refreshTimeline();
    // The sheet can create a tag; the filter row has to learn about it without
    // an app restart.
    await _model.loadFilterTags();
    if (_searching) await _search.run();
  }
}
