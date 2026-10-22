part of 'db_worker.dart';

/// The worker side of [NexDbWorker]: the library's repositories, opened in
/// the worker isolate, and what each command does with them. Split out of
/// `db_worker.dart` to keep it readable (REL-10).
class _Worker {
  _Worker(this.boot, this.db) {
    repo = SqliteNoteRepository(db, localDeviceId: boot.deviceId);
    capture = CaptureService(repo, deviceId: boot.deviceId);
    tags = TagService(repo);
    search = SearchService(repo);
    maintenance = LibraryMaintenance(repo, mediaRoot: boot.mediaDir);
    commitments = SqliteCommitmentRepository(db, localDeviceId: boot.deviceId);
    threads = SqliteThreadRepository(db, repo, localDeviceId: boot.deviceId);
    scheduled = SqliteScheduledNoteRepository(db, repo);
    cycle = SqliteCycleRepository(db);
    modules = SqliteModuleRecordRepository(db);
    attachments = SqliteAttachmentRepository(
      repo,
      localDeviceId: boot.deviceId,
    );
    enrichment = EnrichmentService(
      repo: repo,
      adapter: boot.adapter,
      capabilities: boot.capabilities,
      disclose: (noteId, send) => NexDisclosureLog.about(send, notes: [noteId]),
    );
    if (boot.adapter case final CloudAIAdapter initial) _cloudAdapter = initial;
  }

  final _WorkerBoot boot;
  final NexDatabase db;
  late final SqliteNoteRepository repo;
  late final CaptureService capture;
  late final TagService tags;
  late final SearchService search;
  late final LibraryMaintenance maintenance;
  late final SqliteCommitmentRepository commitments;
  late final SqliteThreadRepository threads;
  late final SqliteScheduledNoteRepository scheduled;
  late final SqliteCycleRepository cycle;
  late final SqliteModuleRecordRepository modules;
  late final SqliteAttachmentRepository attachments;
  late final EnrichmentService enrichment;

  /// Text in attached photos, each request logged with its note.
  late final attachmentText = AttachmentTextReader(
    attachments,
    enrichment,
    disclose: (noteId, read) => NexDisclosureLog.about(read, notes: [noteId]),
  );

  AiProviderConfig? provider;
  CloudAIAdapter? _cloudAdapter;
  var localSearch = false;

  // What decides the library's vector space between them: the provider
  // last configured, and whether the on-device search model is in use.
  // Either message can arrive first, so each one re-decides from both.
  void settleEmbeddingSpace() {
    final space = nexEmbeddingSpaceFor(
      provider: provider,
      localSearch: localSearch,
    );
    if (space != null) repo.setEmbeddingSpace(space);
  }

  Future<Object?> dispatch(_DbRequest message) async {
    Object? arg(String key) => message.args[key];

    // The handler is asynchronous because several operations are:
    // exportArchive and storage return Futures, and a Future cannot cross a
    // SendPort — the previous synchronous handler sent the Future itself and
    // the awaiting side hung or cast-failed.
    return switch (message.command) {
      _DbCommand.timeline || _DbCommand.loadMore => search.timeline(
        limit: arg('limit')! as int,
        offset: arg('offset')! as int,
        tagId: arg('tagId') as String?,
      ),
      _DbCommand.search => search.search(arg('filters')! as SearchFilters),
      _DbCommand.getById => repo.getById(arg('id')! as String),
      _DbCommand.captureShared => repo.captureShared(
        Map<String, String>.from(arg('payload')! as Map),
      ),
      _DbCommand.capturedFor => repo.capturedFor(arg('requestId')! as String),
      _DbCommand.captureText => capture.submitTextCapture(
        arg('content')! as String,
      ),
      _DbCommand.captureChecklist => capture.submitChecklistCapture(
        parseChecklist(arg('body')! as String),
      ),
      // Read *and* written inside the isolate. Unzipping a Takeout
      // export, writing its photos out and inserting a few thousand rows
      // are all long enough to drop frames, and the point of this worker
      // is that none of it happens on the thread drawing the screen.
      // One transaction (DATA-02): an import that failed part-way left
      // half its notes behind, and the retry duplicated them.
      _DbCommand.importNotes => db.db.together(
        () => NexDbWorker._importNotes(
          capture,
          File(arg('path')! as String),
          Directory(arg('mediaDir')! as String),
        ),
      ),
      _DbCommand.captureLink => capture.submitLinkCapture(
        arg('url')! as String,
      ),
      _DbCommand.captureVoice => capture.submitVoiceCapture(
        mediaUri: arg('mediaUri')! as String,
        mediaHash: arg('mediaHash')! as String,
        durationMs: arg('durationMs')! as int,
      ),
      _DbCommand.capturePhoto => capture.submitPhotoCapture(
        mediaUri: arg('mediaUri')! as String,
        mediaHash: arg('mediaHash')! as String,
      ),
      _DbCommand.captureFile => capture.submitFileCapture(
        mediaUri: arg('mediaUri')! as String,
        mediaHash: arg('mediaHash')! as String,
        originalFilename: arg('originalFilename') as String?,
        mimeType: arg('mimeType') as String?,
      ),
      _DbCommand.updateNote => NexDbWorker._voided(
        () =>
            repo.updateContent(arg('id')! as String, arg('content')! as String),
      ),
      _DbCommand.convertMarkdown => NexDbWorker._voided(
        () => repo.convertMarkdown(
          arg('id')! as String,
          arg('text')! as String,
          arg('uri') as String?,
          arg('hash') as String?,
        ),
      ),
      _DbCommand.updateImageMedia => NexDbWorker._voided(
        () => repo.updateImageMedia(
          arg('id')! as String,
          arg('mediaUri')! as String,
          arg('mediaHash')! as String,
        ),
      ),
      _DbCommand.deleteNote => NexDbWorker._voided(
        () => repo.softDelete(arg('id')! as String),
      ),
      _DbCommand.undelete => NexDbWorker._voided(
        () => repo.undelete(arg('id')! as String),
      ),
      _DbCommand.appendCaption => repo.appendCaption(
        arg('id')! as String,
        arg('text')! as String,
      ),
      _DbCommand.replaceCaption => repo.replaceCaption(
        arg('id')! as String,
        arg('text')! as String,
        expectedCaption: arg('expectedCaption') as String?,
      ),
      _DbCommand.setCaption => NexDbWorker._voided(
        () => repo.setCaption(arg('id')! as String, arg('caption')! as String),
      ),
      _DbCommand.setTitle => NexDbWorker._voided(
        () => repo.setTitle(arg('id')! as String, arg('title') as String?),
      ),
      _DbCommand.saveSummaryIfCurrent => () {
        final id = arg('id')! as String;
        final note = repo.getById(id);
        if (note == null || note.aiSourceText != arg('source')) return false;
        repo.setSummaryText(id, arg('text')! as String);
        return true;
      }(),
      _DbCommand.setSummaryText => NexDbWorker._voided(
        () => repo.setSummaryText(arg('id')! as String, arg('text')! as String),
      ),
      _DbCommand.setLinkMetadata => NexDbWorker._voided(
        () => repo.setLinkMetadata(
          arg('id')! as String,
          title: arg('title') as String?,
          excerpt: arg('excerpt') as String?,
        ),
      ),
      _DbCommand.toggleChecklistItem => NexDbWorker._voided(
        () => repo.toggleChecklistItem(
          arg('id')! as String,
          arg('index')! as int,
        ),
      ),
      _DbCommand.pinNote => repo.pinNote(arg('id')! as String),
      _DbCommand.unpinNote => NexDbWorker._voided(
        () => repo.unpinNote(arg('id')! as String),
      ),
      _DbCommand.pinnedNoteCount => repo.pinnedNoteCount(),
      _DbCommand.setAside => repo.setAside(
        arg('id')! as String,
        until: switch (arg('until')) {
          final String iso => DateTime.parse(iso),
          _ => null,
        },
      ),
      _DbCommand.bringBack => NexDbWorker._voided(
        () => repo.bringBack(arg('id')! as String),
      ),
      _DbCommand.listSetAside => repo.listSetAside(),
      _DbCommand.setAsideCount => repo.setAsideCount(),
      _DbCommand.releaseDueSetAside => repo.releaseDueSetAside(),
      _DbCommand.addTag => tags.addTag(
        noteId: arg('noteId')! as String,
        name: arg('name')! as String,
        color: arg('color') as String?,
      ),
      _DbCommand.removeTag => NexDbWorker._voided(
        () => tags.removeTag(
          noteId: arg('noteId')! as String,
          tagId: arg('tagId')! as String,
        ),
      ),
      _DbCommand.createTag => repo.upsertTag(
        name: arg('name')! as String,
        color: arg('color') as String?,
      ),
      _DbCommand.listTags => tags.listTags(),
      _DbCommand.listCommitments => commitments.list(),
      _DbCommand.saveCommitment => commitments.save(
        arg('commitment')! as NexCommitment,
      ),
      _DbCommand.markCommitmentMet => commitments.markMet(
        arg('id')! as String,
        at: arg('at') as DateTime?,
      ),
      _DbCommand.deleteCommitment => NexDbWorker._voided(
        () => commitments.delete(arg('id')! as String),
      ),
      _DbCommand.cyclePeriods => cycle.periods(),
      _DbCommand.cycleStartPeriod => cycle.startPeriod(
        DateTime.parse(arg('day')! as String),
        closeAfter: arg('closeAfter')! as int,
      ),
      _DbCommand.cycleEndPeriod => NexDbWorker._voided(
        () => cycle.endPeriod(
          arg('id')! as String,
          DateTime.parse(arg('day')! as String),
        ),
      ),
      _DbCommand.cycleUpdatePeriod => NexDbWorker._voided(
        () => cycle.updatePeriod(
          arg('id')! as String,
          DateTime.parse(arg('start')! as String),
          switch (arg('end')) {
            final String end => DateTime.parse(end),
            _ => null,
          },
        ),
      ),
      _DbCommand.cycleDeletePeriod => NexDbWorker._voided(
        () => cycle.deletePeriod(arg('id')! as String),
      ),
      _DbCommand.cycleDays => cycle.days(
        DateTime.parse(arg('from')! as String),
        DateTime.parse(arg('to')! as String),
      ),
      _DbCommand.cycleSaveDay => NexDbWorker._voided(
        () => cycle.saveDay(arg('log')! as CycleDayLog),
      ),
      _DbCommand.cycleDeleteAll => NexDbWorker._voided(cycle.deleteAll),
      _DbCommand.attachmentsFor ||
      _DbCommand.attachmentAdd ||
      _DbCommand.attachmentUpdateImage ||
      _DbCommand.attachmentRemove ||
      _DbCommand.attachmentRestore ||
      _DbCommand.attachmentReorder ||
      _DbCommand.attachmentSetCaption ||
      _DbCommand.attachmentRename ||
      _DbCommand.attachmentDetach ||
      _DbCommand.attachmentPromote ||
      _DbCommand.attachmentSetOcr => _attachmentCommand(
        attachments,
        message.command,
        arg,
      ),
      _DbCommand.moduleRecords ||
      _DbCommand.moduleRecord ||
      _DbCommand.modulePut ||
      _DbCommand.moduleDelete ||
      _DbCommand.moduleDeleteAll => _moduleCommand(
        modules,
        message.command,
        arg,
      ),
      _DbCommand.scheduleNote => scheduled.schedule(
        arg('noteId')! as String,
        DateTime.parse(arg('releaseAt')! as String),
      ),
      _DbCommand.scheduledNotes => scheduled.pending(),
      _DbCommand.releaseDueNotes => scheduled.releaseDue(
        DateTime.parse(arg('now')! as String),
      ),
      _DbCommand.releaseScheduledNow => scheduled.releaseNow(
        arg('id')! as String,
        DateTime.parse(arg('now')! as String),
      ),
      _DbCommand.rescheduleNote => scheduled.reschedule(
        arg('id')! as String,
        DateTime.parse(arg('releaseAt')! as String),
      ),
      _DbCommand.discardScheduled => NexDbWorker._voided(
        () => scheduled.discard(arg('id')! as String),
      ),
      _DbCommand.listThreads => threads.list(),
      _DbCommand.threadsForNote => threads.forNote(arg('noteId')! as String),
      _DbCommand.threadNotes => threads.notes(arg('threadId')! as String),
      _DbCommand.createThread => threads.create(
        arg('name')! as String,
        noteIds: List<String>.from(arg('noteIds')! as List),
      ),
      _DbCommand.renameThread => NexDbWorker._voided(
        () =>
            threads.rename(arg('threadId')! as String, arg('name')! as String),
      ),
      _DbCommand.deleteThread => NexDbWorker._voided(
        () => threads.delete(arg('threadId')! as String),
      ),
      _DbCommand.addToThread => NexDbWorker._voided(
        () => threads.add(arg('threadId')! as String, arg('noteId')! as String),
      ),
      _DbCommand.removeFromThread => NexDbWorker._voided(
        () => threads.remove(
          arg('threadId')! as String,
          arg('noteId')! as String,
        ),
      ),
      _DbCommand.suggestThread => threads.suggest(arg('noteId')! as String),
      _DbCommand.setTagColor => NexDbWorker._voided(
        () => tags.setColor(
          tagId: arg('tagId')! as String,
          color: arg('color') as String?,
        ),
      ),
      // `when` is a pattern guard keyword, so the variable it would
      // otherwise be named cannot be spelled here.
      _DbCommand.setDueAt => NexDbWorker._voided(() {
        final at = arg('when');
        repo.setDueAt(
          arg('noteId')! as String,
          at is String ? DateTime.parse(at) : null,
          repeat: NoteRepeat.fromWire(arg('repeat') as String?),
        );
      }),
      _DbCommand.upcomingReminders => repo.listUpcomingReminders(
        limit: arg('limit')! as int,
      ),
      _DbCommand.backup => repo.backupSnapshot(arg('dir')! as String).path,
      _DbCommand.exportArchive => (await repo.exportArchive(
        outputPath: arg('outputPath')! as String,
        mediaRoot: arg('mediaRoot')! as String,
      )).path,
      _DbCommand.importArchive => await repo.importArchive(
        archiveFile: File(arg('archivePath')! as String),
        mediaRoot: arg('mediaRoot')! as String,
      ),
      _DbCommand.deletedNotes => maintenance.deletedNotes(
        limit: arg('limit')! as int,
      ),
      _DbCommand.purgeDeletedBefore => NexDbWorker._voided(
        () => maintenance.purgeDeletedBefore(arg('cutoff')! as DateTime),
      ),
      _DbCommand.sweepOrphanMedia => maintenance.sweepOrphanMedia(),
      _DbCommand.purgeNote => NexDbWorker._voided(
        () => maintenance.purgeNote(arg('id')! as String),
      ),
      _DbCommand.purgeAllDeleted => NexDbWorker._voided(
        maintenance.purgeAllDeleted,
      ),
      _DbCommand.tagUsage => maintenance.tagUsage(),
      _DbCommand.renameTag => NexDbWorker._voided(
        () =>
            maintenance.renameTag(arg('id')! as String, arg('name')! as String),
      ),
      _DbCommand.mergeTag => NexDbWorker._voided(
        () => maintenance.mergeTag(
          sourceId: arg('sourceId')! as String,
          targetId: arg('targetId')! as String,
        ),
      ),
      _DbCommand.deleteTag => NexDbWorker._voided(
        () => maintenance.deleteTag(arg('id')! as String),
      ),
      _DbCommand.nearestMiss => maintenance.nearestMiss(
        arg('query')! as String,
      ),
      _DbCommand.storage => await maintenance.storage(
        arg('dbPath')! as String,
        arg('mediaDir')! as String,
        arg('backupDir')! as String,
      ),
      _DbCommand.readMediaOnDemand => await NexDisclosureLog.about(
        () => enrichment.readMediaOnDemand(arg('noteId')! as String),
        notes: [arg('noteId')! as String],
      ),
      _DbCommand.enrichNote => await NexDisclosureLog.about(
        () => enrichment.enrichNote(arg('noteId')! as String),
        notes: [arg('noteId')! as String],
      ).then<Object?>((_) => null),
      _DbCommand.backfillEnrichment => await enrichment.backfill(
        limit: arg('limit')! as int,
      ),
      _DbCommand.attachmentReadText => await attachmentText.read(
        arg('id')! as String,
        refresh: arg('refresh') == true,
      ),
      _DbCommand.backfillEmbeddings => await enrichment.backfillEmbeddings(
        limit: arg('limit')! as int,
      ),
      _DbCommand.suggestTags => await enrichment.suggestTags(
        arg('noteId')! as String,
      ),
      _DbCommand.summarize => await enrichment.summarizeOnDemand(
        arg('noteId')! as String,
      ),
      _DbCommand.relatedNotes => await enrichment.relatedNotes(
        arg('noteId')! as String,
        limit: arg('limit')! as int,
      ),
      _DbCommand.semanticSearch => await enrichment.semanticSearch(
        arg('query')! as String,
        limit: arg('limit')! as int,
      ),
      _DbCommand.fusedSearch => await NexDbWorker._fusedSearch(
        repo,
        enrichment,
        arg('filters')! as SearchFilters,
      ),
      _DbCommand.setAiCapabilities => NexDbWorker._voided(
        () => enrichment.updateCapabilities(
          arg('capabilities')! as AiCapabilities,
        ),
      ),
      _DbCommand.setAiProvider => NexDbWorker._voided(() {
        final raw = (arg('config')! as Map).cast<String, String>();
        final config = AiProviderConfig.fromMap(raw);
        // No provider, or an incomplete one, falls back to the local
        // heuristics rather than to nothing: tag hints keep working.
        final previous = _cloudAdapter;
        _cloudAdapter = config.isUsable
            ? CloudAIAdapter(
                config: config,
                outputLanguage: AiOutputLanguage.fromWire(
                  raw['outputLanguage'],
                ),
              )
            : null;
        enrichment.updateAdapter(_cloudAdapter ?? const OnDeviceAIAdapter());
        // Retires after pending response bodies finish, so a provider change
        // neither leaks its client nor aborts an already requested read.
        previous?.retire();
        // A vector is only comparable to vectors from the same model and
        // the same endpoint. Swap either and every stored embedding becomes
        // a number from a different space — which `_cosine` will still
        // score, truncating to the shorter of the two, and hand back a
        // confident similarity that means nothing. Equal dimensions are the
        // dangerous case, because nothing about the result looks wrong.
        //
        // Only when the new provider can actually embed. Turning AI off
        // makes the config unusable, and that must not be read as a change
        // of space: switching off and on again would otherwise throw away
        // every vector in the library for nothing.
        provider = config;
        settleEmbeddingSpace();
      }),
      _DbCommand.setLocalEmbedder => NexDbWorker._voided(() {
        final path = arg('modelPath') as String?;
        enrichment.updateEmbedder(path == null ? null : NexLocalEmbedder(path));
        localSearch = path != null;
        settleEmbeddingSpace();
      }),
      _DbCommand.sync => await () async {
        final client = SyncClient(
          baseUrl: arg('baseUrl')! as String,
          deviceId: boot.deviceId,
          repo: repo,
          bearerToken: arg('bearerToken') as String?,
        );
        try {
          return await client.sync();
        } finally {
          client.close();
        }
      }(),
      _DbCommand.close => NexDbWorker._voided(() {
        _cloudAdapter?.close();
        _cloudAdapter = null;
      }),
    };
  }
}
