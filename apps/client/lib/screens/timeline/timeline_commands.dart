part of '../timeline_screen.dart';

/// What the timeline can be asked to do from outside: open the capture
/// sheet, or delete a note with an undo. Split out of timeline_screen.dart
/// (REL-10).
extension TimelineCommands on TimelineScreenState {
  /// The capture sheet, open on [kind] — a note unless an entry point says
  /// otherwise (the widget's list button, the voice shortcut).
  Future<void> openCapture({CaptureKind kind = CaptureKind.note}) async {
    String? committed;
    var counted = false;
    // The three-second promise, timed the way a person lives it: from the
    // sheet opening to the note existing (W3.4).
    final opened = Stopwatch()..start();
    await nexShowSheet<void>(
      context: context,
      builder: (sheetContext) => CaptureSheet(
        services: widget.services,
        preferences: widget.preferences,
        initialKind: kind,
        onCommitted: (id) {
          committed = id;
          landedId = id;
          // Once a sheet: the words becoming a list as it closes are the
          // same capture, not a second one — and one capture is one buzz.
          // The first commit (the first keystroke, when the note first
          // exists — ADR-002) is the receipt's moment; the conversion that
          // follows on close keeps the same words, so it re-runs the
          // receipt flash without re-running the haptic that used to arrive
          // with it.
          if (!counted) {
            counted = true;
            NexMetrics.shared
              ..record(NexMetric.capture, opened.elapsed)
              ..markCapture();
            if (widget.preferences.haptics)
              unawaited(HapticFeedback.lightImpact());
          }
        },
        onRetracted: (id) {
          if (committed == id) committed = null;
        },
        onKeepVoice: (path, durationMs) =>
            unawaited(_keepVoice(path, durationMs)),
        // The page is read after the note exists, never before: a bookmark
        // is saved the moment you ask for it, and the title and description
        // are an improvement that arrives late or not at all.
        onLinkCaptured: (id, url) => unawaited(_readLink(id, url)),
        onCamera: () {
          Navigator.pop(sheetContext);
          unawaited(capturePhoto(ImageSource.camera));
        },
        onGallery: () {
          Navigator.pop(sheetContext);
          unawaited(capturePhoto(ImageSource.gallery));
        },
        onFile: () {
          Navigator.pop(sheetContext);
          unawaited(captureFile());
        },
      ),
    );
    unawaited(widget.services.refreshTimeline());
    // Once the sheet is closed, not at the first keystroke that created the
    // note: only then is there a whole note to compare.
    if (committed case final id?) unawaited(_offerThread(id));
  }

  /// What a flick of the + button starts: the capture sheet already on the
  /// kind, or the camera, the gallery or a file straight away.
  Future<void> runCaptureShortcut(CaptureShortcut shortcut) =>
      switch (shortcut) {
        CaptureShortcut.none => Future.value(),
        CaptureShortcut.voice => openCapture(kind: CaptureKind.voice),
        CaptureShortcut.checklist => openCapture(kind: CaptureKind.checklist),
        CaptureShortcut.link => openCapture(kind: CaptureKind.link),
        CaptureShortcut.camera => capturePhoto(ImageSource.camera),
        CaptureShortcut.gallery => capturePhoto(ImageSource.gallery),
        CaptureShortcut.file => captureFile(),
      };

  /// The post-capture offer on its own, for tests that cannot drive a
  /// capture sheet to its close.
  @visibleForTesting
  Future<void> offerThreadFor(String noteId) => _offerThread(noteId);

  Future<void> deleteWithUndo(Note note) async {
    final l10n = AppLocalizations.of(context);
    await widget.services.deleteNote(note.id);
    await widget.services.refreshTimeline();
    if (!mounted) return;
    // One buzz per delete, and it has already happened: the swipe's own
    // threshold thud — or the tap that chose Delete — is the whole
    // confirmation. The action and then the banner each added another:
    // three in a row for one delete, which reads as an error, not a receipt.
    nexShowBanner(
      context,
      message: l10n.noteDeleted,
      haptics: false,
      actionLabel: l10n.undo,
      onAction: () async {
        _tick();
        await widget.services.undelete(note.id);
        await widget.services.refreshTimeline();
      },
    );
  }

  /// Whether this touch belongs to closing an open card or menu rather than
  /// to what it landed on.
  ///
  /// The controls inside the list are made inert structurally — see
  /// [NexTapGuarded]. The capture button and the app bar are `Scaffold` slots
  /// that ask instead.
  bool _claimedByOverlay() => _guard.claim();

  /// The assistant, for the desktop rail (the phone holds the capture button).
  void showAssistant() => _openAssistant();

  /// A desktop rail section closed: catch up the way the dock does when its
  /// pages close — the timeline (Trash, Archive) and the brief (Recurring).
  Future<void> refreshAfterSection() async {
    await _refresh();
    await _model.loadCommitments();
  }

  /// What the desktop rail reads and drives: the tags the list is narrowed to.
  Set<String> get activeTagIds => _model.selectedTagIds;
  Listenable get filterChanges => _model;

  /// Shows only the notes with [tagId], or all of them if that is already the
  /// one on show.
  Future<void> showOnlyTag(String tagId) => _model.selectTags(
    _model.selectedTagIds.length == 1 && _model.selectedTagIds.contains(tagId)
        ? const {}
        : {tagId},
  );

  Future<void> clearFilterForRail() => _model.clearFilters();

  // Search and filter commands share the timeline's existing state.

  /// Brings the field in and puts the cursor in it.
  ///
  /// Tapping the field itself does this, and so does Ctrl+F — the field lives
  /// at the top of the list permanently now, so a dedicated AppBar icon for it
  /// pointed at something already on screen.
  Future<void> revealSearch() async {
    // Already searching with the cursor already in the field: this tap came
    // from the field itself — moving the caret, a paste, a second look — and
    // the search it would restart is the one already on screen. Re-running
    // it re-faded the results and re-billed the semantic round trip for a
    // query that never changed; the field's own edits debounce on their own.
    if (_searching && _searchFocus.hasFocus) {
      _searchFocus.requestFocus();
      return;
    }
    if (_scroll.hasClients && _scroll.offset > 0) {
      await _scroll.animateTo(
        0,
        duration: NexMotion.standard,
        curve: NexMotion.curve,
      );
    }
    if (!mounted) return;
    _rebuild(() {
      _searching = true;
      _selected.clear();
    });
    _fadeInBody();
    _searchStarted = Stopwatch()..start();
    // After the frame: with the field switched off it is not in the list
    // until this setState puts it there, and a focus request aimed at a node
    // no widget has attached yet is simply dropped.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    _searchFocus.requestFocus();
    unawaited(_search.run());
  }

  void _exitSearch() {
    // Left with words in the field: a search worth offering again.
    unawaited(widget.preferences.rememberSearch(_search.query.text));
    _searchStarted = null;
    _searchFocus.unfocus();
    _search.clear();
    _rebuild(() => _searching = false);
    _fadeInBody();
    // No scroll on the way out. Leaving search used to push the list back down
    // past the field to re-hide it; the field lives at the top now, so that
    // would just be the timeline jumping for no reason a user could name.
  }

  Future<void> _selectTags(Set<String> tagIds) async {
    _tick();
    await _model.selectTags(tagIds);
  }

  Future<void> _selectType(NoteType? type) async {
    _tick();
    await _model.selectType(type);
  }

  Future<void> _selectOnlyReminders(bool only) async {
    _tick();
    await _model.selectOnlyReminders(only);
  }

  void _tick() => nexTick();

  Future<void> _clearFilters() async {
    _tick();
    await _model.clearFilters();
  }
}
