part of 'capture_sheet.dart';

/// The sheet's one settlement, for every way it can close: the last words
/// written, and a checklist or link box turned into its note, the draft the
/// words were on their way from removed.
extension _CaptureSettle on _CaptureSheetState {
  Future<bool> _settleOnce() async {
    await flush();
    final id = noteId;
    final text = _latestText;
    final kind = _kind;
    if (id == null || persisted != text) return true;
    try {
      final pending = _conversion;
      if (pending != null && (pending.text != text || pending.kind != kind)) {
        await widget.services.deleteNote(pending.note.id, refresh: false);
        await widget.services.purgeNote(pending.note.id);
        _conversion = null;
        _conversionKey = newUuidV7();
      }
    } catch (error) {
      unawaited(NexCrashLog.handled('capture.conversionCleanup', error));
      _fail();
      return false;
    }
    if (text.trim().isEmpty || kind == CaptureKind.note) return true;
    Note? made;
    try {
      made = _conversion?.note;
      if (made == null) {
        switch (kind) {
          case CaptureKind.checklist:
            final items = parseChecklist(text);
            if (items.isEmpty) return true;
            // Receipted, like a link conversion: a settle that was
            // interrupted after the commit must find the list it already
            // made when it is tried again, not make a second one.
            made = await widget.services.captureWrittenChecklist(
              _conversionKey,
              items,
            );
          case CaptureKind.link:
            if (writtenLink(text) == null) {
              // Not an address: the note it already is keeps it, and the
              // person is told why it is not a link.
              if (mounted) {
                nexShowBanner(
                  context,
                  message: AppLocalizations.of(context).linkKeptAsNote,
                  haptics: false,
                );
              }
              return true;
            }
            made = await widget.services.captureWrittenLink(
              _conversionKey,
              text,
            );
          case CaptureKind.note:
          case CaptureKind.voice:
            return true;
        }
      }
    } catch (error) {
      unawaited(NexCrashLog.handled('capture.convert', error));
      made = null;
    }
    if (made == null) {
      _fail();
      return false;
    }
    _conversion = (note: made, text: text, kind: kind);
    // Keep the source draft until both the reminder data and alarm transfer.
    // A draft that is already gone — removed from another window — has
    // nothing to transfer; the words still become their list or link rather
    // than stranding the sheet open over a note that no longer exists.
    try {
      final before = await widget.services.getById(id);
      if (before != null) {
        await widget.services.setDueAt(
          made.id,
          before.dueAt,
          repeat: before.dueRepeat,
          refresh: false,
        );
      }
    } catch (error) {
      unawaited(NexCrashLog.handled('capture.reminderTransfer', error));
      _fail();
      return false;
    }
    _conversion = null;
    // From here the sheet holds nothing: a flush that comes later — the
    // pop, `dispose` — must not write the note it is about to remove.
    debounce?.cancel();
    noteId = null;
    draft = null;
    persisted = '';
    _latestText = '';
    try {
      widget.services.captureJournal.complete(_draftId);
    } catch (_) {}
    // Removed outright, not sent to the trash: it was never a note of its
    // own, only these words on their way to being a list or a link. One
    // retry when the first delete is refused — the converted note is
    // already saved, and a draft left behind would put the same words on
    // the timeline twice.
    try {
      await widget.services.deleteNote(id, refresh: false);
      await widget.services.purgeNote(id);
    } catch (error) {
      unawaited(NexCrashLog.handled('capture.conversionDelete', error));
      try {
        await widget.services.deleteNote(id, refresh: false);
        await widget.services.purgeNote(id);
      } catch (_) {
        unawaited(NexServices.noteDiagnostic('conversion draft kept'));
      }
    }
    widget.onRetracted?.call(id);
    widget.onCommitted?.call(made.id);
    if (kind == CaptureKind.link && made.linkUrl != null) {
      widget.onLinkCaptured?.call(made.id, made.linkUrl!);
    }
    return true;
  }
}
