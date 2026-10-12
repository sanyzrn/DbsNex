part of '../timeline_screen.dart';

/// What the timeline can be asked to do from outside: open the capture
/// sheet, or delete a note with an undo. Split out of timeline_screen.dart
/// (REL-10).
extension TimelineCommands on TimelineScreenState {
  Future<void> openCapture() async {
    String? committed;
    // The three-second promise, timed the way a person lives it: from the
    // sheet opening to the note existing (W3.4).
    final opened = Stopwatch()..start();
    await nexShowSheet<void>(
      context: context,
      builder: (sheetContext) => CaptureSheet(
        services: widget.services,
        preferences: widget.preferences,
        onCommitted: (id) {
          committed = id;
          landedId = id;
          NexMetrics.shared
            ..record(NexMetric.capture, opened.elapsed)
            ..markCapture();
          if (widget.preferences.haptics) HapticFeedback.lightImpact();
        },
        onVoice: () {
          Navigator.pop(sheetContext);
          captureVoice();
        },
        onCamera: () {
          Navigator.pop(sheetContext);
          capturePhoto(ImageSource.camera);
        },
        onGallery: () {
          Navigator.pop(sheetContext);
          capturePhoto(ImageSource.gallery);
        },
        onFile: () {
          Navigator.pop(sheetContext);
          captureFile();
        },
        onChecklist: () {
          Navigator.pop(sheetContext);
          unawaited(captureChecklist());
        },
        onLink: () {
          Navigator.pop(sheetContext);
          unawaited(captureLink());
        },
      ),
    );
    widget.services.refreshTimeline();
    // Once the sheet is closed, not at the first keystroke that created the
    // note: only then is there a whole note to compare.
    if (committed case final id?) unawaited(_offerThread(id));
  }

  /// The post-capture offer on its own, for tests that cannot drive a
  /// capture sheet to its close.
  @visibleForTesting
  Future<void> offerThreadFor(String noteId) => _offerThread(noteId);

  Future<void> deleteWithUndo(Note note) async {
    final l10n = AppLocalizations.of(context);
    if (widget.preferences.haptics) HapticFeedback.mediumImpact();
    await widget.services.deleteNote(note.id);
    await widget.services.refreshTimeline();
    if (!mounted) return;
    nexShowBanner(
      context,
      message: l10n.noteDeleted,
      haptics: widget.preferences.haptics,
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
}
