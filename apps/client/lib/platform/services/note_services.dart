part of '../nex_services.dart';

/// Writing notes: capture, edits, deletion, reminders on notes. Split out of
/// NexServices (REL-10).
extension NexNoteServices on NexServices {
  Future<Note?> captureText(String content) => worker.captureText(content);

  Future<Note?> captureDraft(String id, String text) => worker.captureShared({
    'requestId': 'draft-$id',
    'type': 'shared_text',
    'text': text,
  });

  Future<void> recoverCaptureDrafts() async {
    for (final draft in captureJournal.pending().toList()) {
      try {
        final note = await captureDraft(draft.id, draft.text);
        // A journal write can fail while the database write of the same
        // text succeeds; a journal older than the note would then wind the
        // note back to a stale snapshot (DATA-05). The newer one wins.
        final behind = note != null && note.updatedAt.isAfter(draft.at);
        if (note != null && !behind) {
          if (draft.text.isEmpty) {
            await worker.deleteNote(note.id);
          } else if (note.content != draft.text) {
            await worker.updateNote(note.id, draft.text);
          }
        }
        captureJournal.complete(draft.id);
      } catch (_) {
        // Retry next launch without blocking the already-saved library.
      }
    }
  }

  Future<Note?> captureChecklist(List<ChecklistItem> items) =>
      worker.captureChecklist(items);

  Future<Note?> captureLink(String url) => worker.captureLink(url);

  /// What was written in the capture sheet's link box, as a link note: the
  /// address, with a line around it as its caption — read by `writtenLink`. Null when [text] is not one link.
  ///
  /// Keyed by [draftId], so a sheet that is closed two ways at once still
  /// makes one note.
  Future<Note?> captureWrittenLink(String draftId, String text) async {
    final link = writtenLink(text);
    if (link == null) return null;
    return worker.captureShared({
      'requestId': 'link-$draftId',
      'type': 'shared_text',
      // A bare address goes as the address it was read as, scheme and all,
      // so the share's own reading finds it.
      'text': link.words == null ? link.url : text,
    });
  }

  /// Imports another app's export, and answers how many notes landed.
  Future<int> importNotes(String path) =>
      worker.importNotes(path, mediaDir: mediaDir);

  /// Keeps the recordings the app died in the middle of (DATA-04).
  ///
  /// A `.recording` file is a memo that never reached Keep — the process
  /// was killed, or crashed, with the person still talking. Its frames are
  /// whole up to the last second written, so it is kept as a voice note
  /// like any other, with the length it actually has. One still being
  /// written (touched in the last two minutes — another window of the app
  /// may be recording) is left alone.
  Future<int> recoverVoiceRecordings({DateTime? now}) async {
    final dir = Directory(mediaDir);
    if (!dir.existsSync()) return 0;
    final idle = (now ?? DateTime.now()).subtract(const Duration(minutes: 2));
    var kept = 0;
    for (final entity in dir.listSync(followLinks: false)) {
      if (entity is! File ||
          !p.basename(entity.path).startsWith('voice-') ||
          !entity.path.endsWith(NexVoiceSpool.extension)) {
        continue;
      }
      try {
        if (entity.lastModifiedSync().isAfter(idle)) continue;
        final durationMs = NexVoiceSpool.adtsDurationMs(
          await entity.readAsBytes(),
        );
        final saved = await NexVoiceSpool.finish(entity.path);
        if (saved == null) continue;
        final note = await captureVoice(
          mediaUri: saved,
          mediaHash: (await sha256OfFile(saved))!,
          durationMs: durationMs,
        );
        scheduleEnrichment(note.id);
        kept++;
      } catch (error) {
        unawaited(
          NexServices.noteDiagnostic('voice recovery: ${error.runtimeType}'),
        );
      }
    }
    if (kept > 0) {
      unawaited(NexServices.noteDiagnostic('voice recovered: $kept'));
    }
    return kept;
  }

  Future<Note> captureVoice({
    required String mediaUri,
    required String mediaHash,
    required int durationMs,
  }) => worker.captureVoice(
    mediaUri: mediaUri,
    mediaHash: mediaHash,
    durationMs: durationMs,
  );

  Future<Note> capturePhoto({
    required String mediaUri,
    required String mediaHash,
  }) => worker.capturePhoto(mediaUri: mediaUri, mediaHash: mediaHash);

  Future<Note> captureFile({
    required String mediaUri,
    required String mediaHash,
    String? originalFilename,
    String? mimeType,
  }) => worker.captureFile(
    mediaUri: mediaUri,
    mediaHash: mediaHash,
    originalFilename: originalFilename,
    mimeType: mimeType,
  );

  Future<void> updateNote(String id, String content) async {
    await worker.updateNote(id, content);
    // The pending notification carries the note's text, baked in when it was
    // scheduled. An edit that did not re-schedule left a reminder whose
    // notification said something the note had already stopped saying until
    // the next launch happened to rebuild it. The alarm instant is unchanged;
    // only its payload is refreshed.
    try {
      final note = await worker.getById(id);
      if (note != null && note.dueAt != null) {
        await reminders.schedule(note);
      }
    } catch (_) {}
    await refreshTimeline();
  }

  Future<void> convertMarkdown(Note note) async {
    if (note.type == NoteType.text) {
      final text = note.content ?? '';
      final bytes = utf8.encode(text);
      final target = File(p.join(mediaDir, '${newUuidV7()}.md'));
      final staging = File('${target.path}.partial');
      await staging.writeAsBytes(bytes, flush: true);
      await staging.rename(target.path);
      // Retain the file if the worker's response is lost after COMMIT.
      // Library maintenance later removes genuinely unreferenced media.
      await worker.convertMarkdown(
        note.id,
        text,
        target.path,
        sha256.convert(bytes).toString(),
      );
    } else {
      // Any file the app can read words out of — Markdown, plain text, a
      // Word or OpenDocument file, RTF, HTML — becomes a text note. Never the
      // other way round: a note only ever becomes Markdown (above).
      final source = File(note.mediaUri!);
      if (await source.length() > NexTextImport.maxBytes) {
        throw StateError('File exceeds ${NexTextImport.maxBytes} bytes');
      }
      final text = await NexTextImport.extract(
        await source.readAsBytes(),
        note.originalFilename ?? note.mediaUri!,
      );
      if (text == null) throw StateError('No readable text');
      await worker.convertMarkdown(note.id, text, null, null);
    }
    try {
      final fresh = await worker.getById(note.id);
      if (fresh != null && fresh.dueAt != null) await reminders.schedule(fresh);
      await refreshTimeline();
    } catch (_) {
      /* Conversion is already durable. */
    }
  }

  Future<void> updateImageMedia(
    String id,
    String mediaUri,
    String mediaHash,
  ) async {
    await worker.updateImageMedia(id, mediaUri, mediaHash);
    scheduleEnrichment(id);
    // The media change is already committed. A failed list refresh must never
    // be reported as a failed save: the caller would then delete the new file.
    try {
      await refreshTimeline();
    } catch (_) {}
  }

  /// Soft-deletes a note and cancels whatever alarm it still had pending.
  ///
  /// The alarm used to survive the note: the OS keeps its own schedule, the
  /// library is only consulted to rebuild, and nothing in the delete path
  /// told the scheduler anything — so a deleted note's reminder still fired,
  /// tapped through to nothing, and the plugin's boot receiver re-armed it
  /// again at every reboot. Cancelling here is what makes the library the
  /// record it claims to be: if the note is not in it, no alarm exists.
  Future<void> deleteNote(String id) async {
    await worker.deleteNote(id);
    // Best-effort: the row is already soft-deleted, so a failure here must
    // not roll the visible state back; the next reconcile would catch it.
    try {
      await reminders.cancel(id);
    } catch (_) {}
    await refreshTimeline();
  }

  /// Undoes a soft delete, and re-arms the note's alarm if it has one.
  Future<void> undelete(String id) async {
    await worker.undelete(id);
    // The delete path cancelled the alarm (as it must). Restoring the note
    // without restoring its reminder would make delete lose data — the one
    // thing an undo is not allowed to do. A past-due one-off stays quiet,
    // matching [NexReminders.schedule]'s own rule for missed reminders.
    try {
      final note = await worker.getById(id);
      if (note != null && note.dueAt != null) {
        await reminders.schedule(note);
      }
    } catch (_) {}
    await refreshTimeline();
  }

  /// Sets or clears when a note should come back up, and moves the alarm to
  /// match. Both halves or neither: a due date with no alarm behind it is a
  /// reminder that never arrives, and an alarm with no due date is one that
  /// cannot be seen or cancelled.
  Future<void> setDueAt(
    String id,
    DateTime? when, {
    NoteRepeat repeat = NoteRepeat.once,
  }) async {
    await worker.setDueAt(id, when, repeat: repeat);
    final note = await worker.getById(id);
    if (note == null) return;
    if (when == null) {
      await reminders.cancel(id);
    } else {
      await reminders.schedule(note);
    }
    await refreshTimeline();
  }
}
