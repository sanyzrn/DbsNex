part of 'capture_sheet.dart';

extension _CaptureSheetWrites on _CaptureSheetState {
  /// Adds a reminder after the first draft is saved, without blocking capture.
  /// A converted checklist or link inherits that reminder on settlement.
  Future<void> _remind() async {
    await draft;
    // What has been typed since the first keystroke, so a reminder set here
    // is on the note as it now reads. `updateContent` never touches `due_at`
    // and `setDueAt` never touches the content, so the order of these two
    // writes does not matter.
    await flush();
    final id = noteId;
    if (id == null) return;
    final note = await widget.services.getById(id);
    if (note == null) return;
    if (!mounted) return;
    await nexPickReminder(
      context: context,
      services: widget.services,
      note: note,
    );
    final saved = await widget.services.getById(id);
    if (!mounted) return;
    _set(() => hasReminder = saved?.dueAt != null);
  }

  /// The held Send: the note being written arrives later instead of now.
  ///
  /// It is already a note by now (no Save button, ADR-002), so this hands
  /// that note to [NexServices.scheduleNote], which takes it back out of the
  /// library until its time — and then the sheet closes with nothing left
  /// behind to write: the draft is forgotten, not flushed, or the close
  /// would put the words straight back on the timeline. A note only: what
  /// waits is words, and it comes back as the note they were.

  Future<void> _schedule() async {
    if (_scheduling || _closing || controller.text.trim().isEmpty) return;
    if (_shown != CaptureKind.note) return;
    if (widget.preferences.haptics) unawaited(HapticFeedback.mediumImpact());
    _scheduling = true;
    try {
      await flush();
      final id = noteId;
      if (id == null ||
          persisted != _latestText ||
          _wireContent(_latestText) != _persistedWire ||
          !mounted) {
        return;
      }
      final when = await nexPickScheduleTime(
        context: context,
        services: widget.services,
      );
      if (when == null || !mounted) return;
      // Typed while the picker was up — the field is still live under it.
      await flush();
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      final scheduled = await widget.services.scheduleNote(id, when.toUtc());
      if (!mounted) return;
      if (scheduled == null) {
        _fail(l10n.scheduleFailed);
        return;
      }
      unawaited(widget.preferences.markScheduleUsed());
      // Forgotten rather than flushed: see above.
      debounce?.cancel();
      noteId = null;
      _latestText = '';
      persisted = '';
      _persistedWire = '';
      draft = null;
      widget.services.captureJournal.complete(_draftId);
      nexShowBanner(
        context,
        message: l10n.scheduleSet(nexUntilLabel(l10n, when)),
        kind: NexBannerKind.done,
      );
      _set(() => _allowClose = true);
      nexDismissKeyboard(context);
      if (mounted) Navigator.pop(context);
    } finally {
      _scheduling = false;
    }
  }

  /// Leaves for the camera, the gallery or a file, with what was written
  /// kept first, in its kind.
  Future<void> _leaveFor(VoidCallback launch) async {
    if (_closing) return;
    _set(() => _closing = true);
    if (_voiceOn) await _stopVoice(keep: true);
    final settled = await _settle();
    if (!mounted) return;
    if (!settled || !_matchesStored) {
      _settling = null;
      _set(() => _closing = false);
      return;
    }
    _set(() => _allowClose = true);
    nexDismissKeyboard(context);
    if (!mounted) return;
    launch();
  }
}
