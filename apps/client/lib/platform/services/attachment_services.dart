part of '../nex_services.dart';

/// Files on a note after its own — `docs/14-attachments.md`.
///
/// A file is written under the media root first, flat and with its own
/// name, then put on the note; the media sweep collects one whose note
/// never took it (a capture that failed half way). Every change refreshes
/// the timeline, where a card shows how many files its note carries.
extension NexAttachmentServices on NexServices {
  Future<List<NoteAttachment>> attachmentsFor(String noteId) =>
      worker.attachmentsFor(noteId);

  /// Writes [bytes] under the media root and attaches the file to [noteId].
  Future<NoteAttachment?> attachBytes(
    String noteId,
    Uint8List bytes, {
    required AttachmentKind kind,
    required String extension,
    String? mimeType,
  }) async {
    final dest = p.join(
      mediaDir,
      'attach-${DateTime.now().microsecondsSinceEpoch}$extension',
    );
    await File(dest).writeAsBytes(bytes, flush: true);
    // Off the UI isolate: megabytes of pure-Dart SHA-256 (PERF-07).
    final hash = await compute(sha256OfBytes, bytes);
    return _attached(
      await worker.attachmentAdd(
        noteId,
        kind: kind,
        mediaUri: dest,
        mediaHash: hash,
        mimeType: mimeType,
      ),
    );
  }

  /// Copies the file at [source] under the media root and attaches it.
  Future<NoteAttachment?> attachFile(
    String noteId,
    String source, {
    required AttachmentKind kind,
    String? name,
    String? mimeType,
    int? durationMs,
  }) async {
    final extension = p.extension(source);
    final dest = p.join(
      mediaDir,
      'attach-${DateTime.now().microsecondsSinceEpoch}'
      '${RegExp(r'^\.[A-Za-z0-9]{1,10}$').hasMatch(extension) ? extension : ''}',
    );
    await File(source).copy(dest);
    final hash = await sha256OfFile(dest);
    if (hash == null) {
      await File(dest).delete();
      return null;
    }
    return _attached(
      await worker.attachmentAdd(
        noteId,
        kind: kind,
        mediaUri: dest,
        mediaHash: hash,
        name: name,
        mimeType: mimeType,
        durationMs: durationMs,
      ),
    );
  }

  /// Attaches a file already copied under the media root — a file shared
  /// into Nex along with others.
  Future<NoteAttachment?> attachStored(
    String noteId, {
    required String mediaUri,
    required String mediaHash,
    required AttachmentKind kind,
    String? name,
    String? mimeType,
  }) async => _attached(
    await worker.attachmentAdd(
      noteId,
      kind: kind,
      mediaUri: mediaUri,
      mediaHash: mediaHash,
      name: name,
      mimeType: mimeType,
    ),
  );

  Future<NoteAttachment?> _attached(NoteAttachment? attachment) async {
    if (attachment == null) return null;
    await refreshTimeline();
    // A photo's words are read, and a voice clip transcribed, the way a
    // photo or voice note's are: afterwards, in the background, and only
    // when that is switched on. Nobody
    // waits for it, so nobody is handed its failure; the next backfill
    // picks up what this missed.
    if (attachment.kind != AttachmentKind.file && !_closed) {
      unawaited(
        worker
            .attachmentReadText(attachment.id)
            .then<void>((_) {}, onError: (Object _) {}),
      );
    }
    return attachment;
  }

  Future<void> removeAttachment(String id) async {
    await worker.attachmentRemove(id);
    await refreshTimeline();
  }

  /// The Undo after [removeAttachment].
  Future<bool> restoreAttachment(String id) async {
    final restored = await worker.attachmentRestore(id);
    await refreshTimeline();
    return restored;
  }

  Future<void> reorderAttachments(String noteId, List<String> orderedIds) =>
      worker.attachmentReorder(noteId, orderedIds);

  /// The name a file attachment is shown and shared under.
  Future<void> renameAttachment(String id, String? name) =>
      worker.attachmentRename(id, name);

  /// Takes an attachment off its note and makes it a note of its own,
  /// read like any new note. The new note, or null.
  Future<Note?> detachAttachment(String id) async {
    final note = await worker.attachmentDetach(id);
    if (note != null) {
      scheduleEnrichment(note.id);
      await refreshTimeline();
    }
    return note;
  }

  /// Makes an attached photo the note's own photo, the old one attached in
  /// its place. The note is read again, since its picture changed.
  Future<bool> promoteAttachment(String noteId, String id) async {
    final done = await worker.attachmentPromote(id);
    if (done) {
      scheduleEnrichment(noteId);
      await refreshTimeline();
    }
    return done;
  }

  Future<void> setAttachmentCaption(String id, String? caption) =>
      worker.attachmentSetCaption(id, caption);
}
