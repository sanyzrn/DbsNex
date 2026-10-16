part of 'db_worker.dart';

/// The calling side of [NexDbWorker]: every [NexDb] call, sent to the
/// worker isolate and answered there. Split out of `db_worker.dart` to keep
/// it readable (REL-10); the worker side — what each command does — stays
/// there.
mixin _DbClient implements NexDb {
  Future<T> _send<T>(_DbCommand command, [Map<String, Object?> args]);

  /* ------------------------------------------------------------- reading */

  @override
  Future<List<Note>> timeline({
    int limit = 200,
    int offset = 0,
    String? tagId,
  }) => _send<List<Note>>(_DbCommand.timeline, {
    'limit': limit,
    'offset': offset,
    'tagId': tagId,
  });

  @override
  Future<List<Note>> loadMore({required int offset, int limit = 50}) =>
      _send<List<Note>>(_DbCommand.loadMore, {
        'limit': limit,
        'offset': offset,
      });

  @override
  Future<List<Note>> search(SearchFilters filters) =>
      _send<List<Note>>(_DbCommand.search, {'filters': filters});

  @override
  Future<Note?> getById(String id) =>
      _send<Note?>(_DbCommand.getById, {'id': id});

  /* ------------------------------------------------------------ capturing */

  @override
  Future<Note?> captureText(String content) =>
      _send<Note?>(_DbCommand.captureText, {'content': content});

  @override
  Future<Note?> captureShared(Map<String, String> payload) =>
      _send<Note?>(_DbCommand.captureShared, {'payload': payload});

  @override
  Future<Note?> capturedFor(String requestId) =>
      _send<Note?>(_DbCommand.capturedFor, {'requestId': requestId});

  @override
  Future<Note?> captureChecklist(List<ChecklistItem> items) =>
      _send<Note?>(_DbCommand.captureChecklist, {
        // Sent as the on-disk text rather than as objects: the isolate port
        // takes primitives, and formatChecklist is already the one place that
        // knows the format.
        'body': formatChecklist(items),
      });

  @override
  Future<int> importNotes(String path, {required String mediaDir}) =>
      _send<int>(_DbCommand.importNotes, {'path': path, 'mediaDir': mediaDir});

  @override
  Future<Note?> captureLink(String url) =>
      _send<Note?>(_DbCommand.captureLink, {'url': url});

  @override
  Future<Note> captureVoice({
    required String mediaUri,
    required String mediaHash,
    required int durationMs,
  }) => _send<Note>(_DbCommand.captureVoice, {
    'mediaUri': mediaUri,
    'mediaHash': mediaHash,
    'durationMs': durationMs,
  });

  @override
  Future<Note> capturePhoto({
    required String mediaUri,
    required String mediaHash,
  }) => _send<Note>(_DbCommand.capturePhoto, {
    'mediaUri': mediaUri,
    'mediaHash': mediaHash,
  });

  @override
  Future<Note> captureFile({
    required String mediaUri,
    required String mediaHash,
    String? originalFilename,
    String? mimeType,
  }) => _send<Note>(_DbCommand.captureFile, {
    'mediaUri': mediaUri,
    'mediaHash': mediaHash,
    'originalFilename': originalFilename,
    'mimeType': mimeType,
  });

  /* ------------------------------------------------------------- mutating */

  @override
  Future<void> updateNote(String id, String content) =>
      _send<void>(_DbCommand.updateNote, {'id': id, 'content': content});

  @override
  Future<void> convertMarkdown(
    String id,
    String text,
    String? uri,
    String? hash,
  ) => _send<void>(_DbCommand.convertMarkdown, {
    'id': id,
    'text': text,
    'uri': uri,
    'hash': hash,
  });

  @override
  Future<void> updateImageMedia(String id, String mediaUri, String mediaHash) =>
      _send<void>(_DbCommand.updateImageMedia, {
        'id': id,
        'mediaUri': mediaUri,
        'mediaHash': mediaHash,
      });

  @override
  Future<void> deleteNote(String id) =>
      _send<void>(_DbCommand.deleteNote, {'id': id});

  @override
  Future<void> undelete(String id) =>
      _send<void>(_DbCommand.undelete, {'id': id});

  @override
  Future<bool> appendCaption(String id, String text) =>
      _send<bool>(_DbCommand.appendCaption, {'id': id, 'text': text});

  @override
  Future<bool> replaceCaption(
    String id,
    String text, {
    required String? expectedCaption,
  }) => _send<bool>(_DbCommand.replaceCaption, {
    'id': id,
    'text': text,
    'expectedCaption': expectedCaption,
  });

  @override
  Future<void> setCaption(String id, String caption) =>
      _send<void>(_DbCommand.setCaption, {'id': id, 'caption': caption});

  @override
  Future<void> setTitle(String id, String? title) =>
      _send<void>(_DbCommand.setTitle, {'id': id, 'title': title});

  @override
  Future<void> setSummaryText(String id, String text) =>
      _send<void>(_DbCommand.setSummaryText, {'id': id, 'text': text});

  @override
  Future<void> setLinkMetadata(String id, {String? title, String? excerpt}) =>
      _send<void>(_DbCommand.setLinkMetadata, {
        'id': id,
        'title': title,
        'excerpt': excerpt,
      });

  @override
  Future<void> toggleChecklistItem(String id, int index) =>
      _send<void>(_DbCommand.toggleChecklistItem, {'id': id, 'index': index});

  @override
  Future<bool> pinNote(String id) =>
      _send<bool>(_DbCommand.pinNote, {'id': id});

  @override
  Future<void> unpinNote(String id) =>
      _send<void>(_DbCommand.unpinNote, {'id': id});

  @override
  Future<int> pinnedNoteCount() => _send<int>(_DbCommand.pinnedNoteCount);

  /* ----------------------------------------------------------------- tags */

  @override
  Future<Tag> addTag({
    required String noteId,
    required String name,
    String? color,
  }) => _send<Tag>(_DbCommand.addTag, {
    'noteId': noteId,
    'name': name,
    'color': color,
  });

  @override
  Future<void> removeTag({required String noteId, required String tagId}) =>
      _send<void>(_DbCommand.removeTag, {'noteId': noteId, 'tagId': tagId});

  @override
  Future<Tag> createTag(String name, {String? color}) =>
      _send<Tag>(_DbCommand.createTag, {'name': name, 'color': color});

  @override
  Future<List<Tag>> listTags() => _send<List<Tag>>(_DbCommand.listTags);

  @override
  Future<List<NexCommitment>> listCommitments() =>
      _send<List<NexCommitment>>(_DbCommand.listCommitments);

  @override
  Future<NexCommitment> saveCommitment(NexCommitment commitment) =>
      _send<NexCommitment>(_DbCommand.saveCommitment, {
        'commitment': commitment,
      });

  @override
  Future<NexCommitment?> markCommitmentMet(String id, {DateTime? at}) =>
      _send<NexCommitment?>(_DbCommand.markCommitmentMet, {'id': id, 'at': at});

  @override
  Future<void> deleteCommitment(String id) =>
      _send<void>(_DbCommand.deleteCommitment, {'id': id});

  @override
  Future<List<CyclePeriod>> cyclePeriods() =>
      _send<List<CyclePeriod>>(_DbCommand.cyclePeriods);

  @override
  Future<CyclePeriod> cycleStartPeriod(DateTime day, {int closeAfter = 5}) =>
      _send<CyclePeriod>(_DbCommand.cycleStartPeriod, {
        'day': day.toIso8601String(),
        'closeAfter': closeAfter,
      });

  @override
  Future<void> cycleEndPeriod(String id, DateTime day) => _send<void>(
    _DbCommand.cycleEndPeriod,
    {'id': id, 'day': day.toIso8601String()},
  );

  @override
  Future<void> cycleUpdatePeriod(String id, DateTime start, DateTime? end) =>
      _send<void>(_DbCommand.cycleUpdatePeriod, {
        'id': id,
        'start': start.toIso8601String(),
        'end': end?.toIso8601String(),
      });

  @override
  Future<void> cycleDeletePeriod(String id) =>
      _send<void>(_DbCommand.cycleDeletePeriod, {'id': id});

  @override
  Future<List<CycleDayLog>> cycleDays(DateTime from, DateTime to) =>
      _send<List<CycleDayLog>>(_DbCommand.cycleDays, {
        'from': from.toIso8601String(),
        'to': to.toIso8601String(),
      });

  @override
  Future<void> cycleSaveDay(CycleDayLog log) =>
      _send<void>(_DbCommand.cycleSaveDay, {'log': log});

  @override
  Future<void> cycleDeleteAll() => _send<void>(_DbCommand.cycleDeleteAll);

  @override
  Future<ScheduledNote?> scheduleNote(String noteId, DateTime releaseAt) =>
      _send<ScheduledNote?>(_DbCommand.scheduleNote, {
        'noteId': noteId,
        'releaseAt': releaseAt.toUtc().toIso8601String(),
      });

  @override
  Future<List<ScheduledNote>> scheduledNotes() =>
      _send<List<ScheduledNote>>(_DbCommand.scheduledNotes);

  @override
  Future<List<Note>> releaseDueNotes(DateTime now) => _send<List<Note>>(
    _DbCommand.releaseDueNotes,
    {'now': now.toUtc().toIso8601String()},
  );

  @override
  Future<Note?> releaseScheduledNow(String id, DateTime now) => _send<Note?>(
    _DbCommand.releaseScheduledNow,
    {'id': id, 'now': now.toUtc().toIso8601String()},
  );

  @override
  Future<bool> rescheduleNote(String id, DateTime releaseAt) => _send<bool>(
    _DbCommand.rescheduleNote,
    {'id': id, 'releaseAt': releaseAt.toUtc().toIso8601String()},
  );

  @override
  Future<void> discardScheduled(String id) =>
      _send<void>(_DbCommand.discardScheduled, {'id': id});

  @override
  Future<List<NoteThread>> listThreads() =>
      _send<List<NoteThread>>(_DbCommand.listThreads);

  @override
  Future<List<NoteThread>> threadsForNote(String noteId) =>
      _send<List<NoteThread>>(_DbCommand.threadsForNote, {'noteId': noteId});

  @override
  Future<List<Note>> threadNotes(String threadId) =>
      _send<List<Note>>(_DbCommand.threadNotes, {'threadId': threadId});

  @override
  Future<NoteThread> createThread(
    String name, {
    List<String> noteIds = const [],
  }) => _send<NoteThread>(_DbCommand.createThread, {
    'name': name,
    'noteIds': noteIds,
  });

  @override
  Future<void> renameThread(String threadId, String name) => _send<void>(
    _DbCommand.renameThread,
    {'threadId': threadId, 'name': name},
  );

  @override
  Future<void> deleteThread(String threadId) =>
      _send<void>(_DbCommand.deleteThread, {'threadId': threadId});

  @override
  Future<void> addToThread(String threadId, String noteId) => _send<void>(
    _DbCommand.addToThread,
    {'threadId': threadId, 'noteId': noteId},
  );

  @override
  Future<void> removeFromThread(String threadId, String noteId) => _send<void>(
    _DbCommand.removeFromThread,
    {'threadId': threadId, 'noteId': noteId},
  );

  @override
  Future<ThreadSuggestion?> suggestThread(String noteId) =>
      _send<ThreadSuggestion?>(_DbCommand.suggestThread, {'noteId': noteId});

  @override
  Future<void> setTagColor({required String tagId, String? color}) =>
      _send<void>(_DbCommand.setTagColor, {'tagId': tagId, 'color': color});

  /* ------------------------------------------------------ backup / export */

  @override
  Future<void> setDueAt(
    String noteId,
    DateTime? when, {
    NoteRepeat repeat = NoteRepeat.once,
  }) => _send<void>(_DbCommand.setDueAt, {
    'noteId': noteId,
    'when': when?.toUtc().toIso8601String(),
    'repeat': repeat.wireName,
  });

  @override
  Future<List<Note>> upcomingReminders({int limit = 200}) =>
      _send<List<Note>>(_DbCommand.upcomingReminders, {'limit': limit});

  @override
  Future<void> backup(String backupDir, {required String mediaDir}) {
    final previous = _backupTask ?? Future<void>.value();
    return _backupTask = previous
        .catchError((Object _) {})
        .then((_) => _createBackup(backupDir, mediaDir));
  }

  Future<void>? _backupTask;

  Future<void> _createBackup(String backupDir, String mediaDir) async {
    final snapshotPath = await _send<String>(_DbCommand.backup, {
      'dir': backupDir,
    });
    try {
      await Isolate.run(
        () => NexBackupArchive.createFromSnapshot(
          snapshotPath: snapshotPath,
          mediaDir: mediaDir,
          backupDir: backupDir,
          compact: true,
        ),
      );
    } finally {
      final snapshot = File(snapshotPath);
      if (await snapshot.exists()) await snapshot.delete();
    }
  }

  @override
  Future<String> exportArchive({
    required String outputPath,
    required String mediaRoot,
  }) => _send<String>(_DbCommand.exportArchive, {
    'outputPath': outputPath,
    'mediaRoot': mediaRoot,
  });

  @override
  Future<ImportResult> importArchive({
    required String archivePath,
    required String mediaRoot,
  }) => _send<ImportResult>(_DbCommand.importArchive, {
    'archivePath': archivePath,
    'mediaRoot': mediaRoot,
  });

  /* --------------------------------------------------- library maintenance */

  @override
  Future<List<Note>> deletedNotes({int limit = 200}) =>
      _send<List<Note>>(_DbCommand.deletedNotes, {'limit': limit});

  @override
  Future<void> purgeDeletedBefore(DateTime cutoff) =>
      _send<void>(_DbCommand.purgeDeletedBefore, {'cutoff': cutoff});

  @override
  Future<int> sweepOrphanMedia() => _send<int>(_DbCommand.sweepOrphanMedia);

  @override
  Future<void> purgeNote(String id) =>
      _send<void>(_DbCommand.purgeNote, {'id': id});

  @override
  Future<void> purgeAllDeleted() => _send<void>(_DbCommand.purgeAllDeleted);

  @override
  Future<List<TagUsage>> tagUsage() =>
      _send<List<TagUsage>>(_DbCommand.tagUsage);

  @override
  Future<void> renameTag(String id, String name) =>
      _send<void>(_DbCommand.renameTag, {'id': id, 'name': name});

  @override
  Future<void> mergeTag({required String sourceId, required String targetId}) =>
      _send<void>(_DbCommand.mergeTag, {
        'sourceId': sourceId,
        'targetId': targetId,
      });

  @override
  Future<void> deleteTag(String id) =>
      _send<void>(_DbCommand.deleteTag, {'id': id});

  @override
  Future<Note?> nearestMiss(String query) =>
      _send<Note?>(_DbCommand.nearestMiss, {'query': query});

  @override
  Future<StorageSnapshot> storage({
    required String dbPath,
    required String mediaDir,
    required String backupDir,
  }) => _send<StorageSnapshot>(_DbCommand.storage, {
    'dbPath': dbPath,
    'mediaDir': mediaDir,
    'backupDir': backupDir,
  });

  /* ----------------------------------------------------------- enrichment */

  @override
  Future<String?> readMediaOnDemand(String noteId) =>
      _send<String?>(_DbCommand.readMediaOnDemand, {'noteId': noteId});

  @override
  Future<void> enrichNote(String noteId) =>
      _send<void>(_DbCommand.enrichNote, {'noteId': noteId});

  @override
  Future<int> backfillEnrichment({int limit = 25}) =>
      _send<int>(_DbCommand.backfillEnrichment, {'limit': limit});

  @override
  Future<int> backfillEmbeddings({int limit = 25}) =>
      _send<int>(_DbCommand.backfillEmbeddings, {'limit': limit});

  @override
  Future<List<TagSuggestion>> suggestTags(String noteId) =>
      _send<List<TagSuggestion>>(_DbCommand.suggestTags, {'noteId': noteId});

  @override
  Future<Summary?> summarizeOnDemand(String noteId) =>
      _send<Summary?>(_DbCommand.summarize, {'noteId': noteId});

  @override
  Future<List<SemanticHit>> relatedNotes(String noteId, {int limit = 5}) =>
      _send<List<SemanticHit>>(_DbCommand.relatedNotes, {
        'noteId': noteId,
        'limit': limit,
      });

  @override
  Future<List<Note>> fusedSearch(SearchFilters filters) =>
      _send<List<Note>>(_DbCommand.fusedSearch, {'filters': filters});

  @override
  Future<List<SemanticHit>> semanticSearch(String query, {int limit = 20}) =>
      _send<List<SemanticHit>>(_DbCommand.semanticSearch, {
        'query': query,
        'limit': limit,
      });

  @override
  Future<void> setAiProvider(Map<String, String> config) =>
      _send<void>(_DbCommand.setAiProvider, {'config': config});

  @override
  Future<void> setLocalEmbedder(String? modelPath) =>
      _send<void>(_DbCommand.setLocalEmbedder, {'modelPath': modelPath});

  @override
  Future<void> setAiCapabilities(AiCapabilities capabilities) =>
      _send<void>(_DbCommand.setAiCapabilities, {'capabilities': capabilities});

  /// One sync cycle.
  ///
  /// SyncClient needs the concrete repository — the outbox surface the port
  /// deliberately withholds — so it is built here, inside the isolate that owns
  /// it, rather than on the UI isolate where it has nothing to talk to.
  @override
  Future<SyncResult> sync({required String baseUrl, String? bearerToken}) =>
      _send<SyncResult>(_DbCommand.sync, {
        'baseUrl': baseUrl,
        'bearerToken': bearerToken,
      });
}
