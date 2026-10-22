part of '../nex_services.dart';

/// Tags, threads, recurring items, search, library maintenance, enrichment
/// and the timeline window. Split out of NexServices (REL-10).
extension NexLibraryServices on NexServices {
  Future<void> removeTag({required String noteId, required String tagId}) =>
      worker.removeTag(noteId: noteId, tagId: tagId);

  Future<Tag> createTag(String name, {String? color}) =>
      worker.createTag(name, color: color);

  Future<List<Tag>> listTags() => worker.listTags();

  Future<List<NoteThread>> threadsForNote(String noteId) =>
      worker.threadsForNote(noteId);

  Future<List<Note>> threadNotes(String threadId) =>
      worker.threadNotes(threadId);

  Future<NoteThread> createThread(
    String name, {
    List<String> noteIds = const [],
  }) => worker.createThread(name, noteIds: noteIds);

  Future<void> renameThread(String threadId, String name) =>
      worker.renameThread(threadId, name);

  Future<void> deleteThread(String threadId) => worker.deleteThread(threadId);

  Future<void> addToThread(String threadId, String noteId) =>
      worker.addToThread(threadId, noteId);

  Future<void> removeFromThread(String threadId, String noteId) =>
      worker.removeFromThread(threadId, noteId);

  /// Asked once, right after a capture lands. Never throws: a suggestion
  /// that could not be worked out is simply not offered.
  Future<ThreadSuggestion?> suggestThread(String noteId) async {
    try {
      return await worker.suggestThread(noteId);
    } catch (_) {
      return null;
    }
  }

  /// Writes it and moves its alarm to match.
  ///
  /// Both halves together, the way [setDueAt] does it for a note: a due date
  /// with no alarm behind it is a reminder that never arrives, and an alarm
  /// with no commitment behind it is one that cannot be cancelled.
  Future<NexCommitment> saveCommitment(NexCommitment commitment) async {
    final saved = await worker.saveCommitment(commitment);
    await reminders.scheduleCommitment(saved);
    return saved;
  }

  /// Met, and rolled forward to its next turn — alarm included.
  ///
  /// The reschedule is the whole reason this cannot be fire-and-forget: the
  /// due date has just moved, so the alarm standing behind the old one is now
  /// wrong. `scheduleCommitment` cancels before it schedules.
  Future<NexCommitment?> markCommitmentMet(String id, {DateTime? at}) async {
    final next = await worker.markCommitmentMet(id, at: at);
    if (next != null) await reminders.scheduleCommitment(next);
    return next;
  }

  Future<void> deleteCommitment(String id) async {
    await worker.deleteCommitment(id);
    await reminders.cancelCommitment(id);
  }

  Future<void> setTagColor({required String tagId, String? color}) =>
      worker.setTagColor(tagId: tagId, color: color);

  Future<List<Note>> search(SearchFilters filters) => worker.search(filters);

  Future<void> purgeDeletedBefore(DateTime cutoff) =>
      worker.purgeDeletedBefore(cutoff);

  Future<void> purgeNote(String id) => worker.purgeNote(id);

  Future<void> purgeAllDeleted() => worker.purgeAllDeleted();

  /// Clears attachment files no note points at any more, at most once a day.
  ///
  /// Purging a note deletes its file now, so from here on nothing is left
  /// behind. This is for what was left behind *before* that: every install
  /// upgrading from an earlier version carries the photos and recordings of
  /// every note it ever deleted for good, and no amount of deleting things
  /// correctly from now on will reach them. It also catches the rarer strays
  /// — a capture whose file was written and whose row then failed, or a purge
  /// whose unlink lost a race with a file handle.
  ///
  /// Throttled because it walks the media directory and stats every file in
  /// it: worth doing, not worth doing on every launch. Called away from the
  /// critical path — nothing waits on it, and a failure is not worth
  /// reporting, since the next sweep does the same work again.
  ///
  /// Returns how many files went, or zero when it was not due.
  Future<int> sweepOrphanMediaIfDue({
    Duration interval = const Duration(hours: 24),
  }) async {
    if (!_preferences.mediaSweepDue(interval)) return 0;
    // Marked before the walk, not after. A sweep that throws halfway has
    // still deleted whatever it deleted, and retrying it on every launch
    // because it never got to write a timestamp is how a background chore
    // turns into a launch cost.
    await _preferences.markMediaSwept();
    final notes = await worker.sweepOrphanMedia();
    return notes + await _sweepOrphanReceipts();
  }

  /// Receipt photos no Recurring item lists any more: taken off an item, or
  /// added in an editor that was then closed without saving. The same hour
  /// of grace as the note sweep, so one being added right now is left alone.
  Future<int> _sweepOrphanReceipts() async {
    final folder = Directory(p.join(mediaDir, 'recurring'));
    if (!folder.existsSync()) return 0;
    final kept = <String>{
      for (final item in await commitments())
        for (final relative
            in (item.details['receipts'] as List? ?? const [])
                .whereType<String>())
          p.normalize(p.join(mediaDir, relative)),
    };
    final cutoff = DateTime.now().subtract(const Duration(hours: 1));
    var removed = 0;
    for (final file in folder.listSync().whereType<File>()) {
      if (kept.contains(p.normalize(file.path))) continue;
      try {
        if (file.statSync().modified.isAfter(cutoff)) continue;
        file.deleteSync();
        removed++;
      } catch (_) {
        // Left for the next pass.
      }
    }
    return removed;
  }

  Future<List<TagUsage>> tagUsage() => worker.tagUsage();

  Future<void> renameTag(String id, String name) => worker.renameTag(id, name);

  Future<void> mergeTag({required String sourceId, required String targetId}) =>
      worker.mergeTag(sourceId: sourceId, targetId: targetId);

  Future<void> deleteTag(String id) => worker.deleteTag(id);

  Future<Note?> nearestMiss(String query) => worker.nearestMiss(query);

  /// What the library is made of, the offline model included.
  ///
  /// The model is measured here rather than in the repository: it lives in
  /// the app's support directory, which the database has no business knowing
  /// about, and it is also the single largest thing most installations will
  /// ever hold — a storage figure that quietly leaves out two gigabytes is
  /// worse than no figure at all, which is what made the old row useless.
  ///
  /// A failure to read that directory costs the breakdown one row rather than
  /// the whole screen: nothing about a storage figure is worth an error page.
  Future<StorageSnapshot> storage() async {
    final snapshot = await worker.storage(
      dbPath: dbPath,
      mediaDir: mediaDir,
      backupDir: backupDir,
    );
    try {
      return snapshot.withModels(await NexModelStore.totalInstalledBytes());
    } catch (_) {
      return snapshot;
    }
  }

  Future<bool> appendCaption(String noteId, String text) async {
    final saved = await worker.appendCaption(noteId, text);
    if (saved) {
      try {
        await refreshTimeline();
      } catch (_) {}
    }
    return saved;
  }

  Future<bool> replaceCaption(
    String noteId,
    String text, {
    required String? expectedCaption,
  }) async {
    final saved = await worker.replaceCaption(
      noteId,
      text,
      expectedCaption: expectedCaption,
    );
    if (saved) {
      try {
        await refreshTimeline();
      } catch (_) {}
    }
    return saved;
  }

  Future<String?> readMediaOnDemand(String noteId) async {
    final text = await worker.readMediaOnDemand(noteId);
    if (text != null) {
      try {
        await refreshTimeline();
      } catch (_) {}
    }
    return text;
  }

  Future<Summary?> summarizeOnDemand(String noteId) async {
    if (!_preferences.effectiveAiCapabilities.summarization) return null;
    if (!_manualLocalAi) return worker.summarizeOnDemand(noteId);
    final note = await worker.getById(noteId);
    final source = note?.aiSourceText;
    if (note == null || source == null || source.trim().isEmpty) return null;
    final adapter = CloudAIAdapter(
      config: const AiProviderConfig(),
      outputLanguage: _preferences.aiOutputLanguage,
    );
    try {
      final result = await adapter.summarize(note);
      final text = result?.text.trim() ?? '';
      if (!_manualLocalAi ||
          !_preferences.effectiveAiCapabilities.summarization ||
          text.isEmpty ||
          text == source.trim() ||
          text.length >= source.trim().length) {
        return null;
      }
      final saved = await worker.saveSummaryIfCurrent(noteId, source, text);
      if (!saved) return null;
      await refreshTimeline();
      return Summary(text: text);
    } catch (error) {
      unawaited(NexCrashLog.handled('ai.summarize.local', error));
      return null;
    } finally {
      adapter.close();
    }
  }

  /// Whether "Analyze video" belongs on [note] (2.1.7): a YouTube video, a
  /// provider that can watch one from its address, and summaries switched on
  /// — the result is kept as the note's summary.
  bool canAnalyzeVideo(Note note) =>
      _preferences.effectiveAiCapabilities.summarization &&
      CloudAIAdapter.watchesYouTube(_preferences.aiProvider) &&
      nexYouTubeWatchUrl(note.linkUrl) != null;

  /// Writes why an analysis was not kept in the local diagnostics log
  /// (2.1.10): the kind and the status code, never the address or the reply.
  void _logVideoFailure(NexVideoFailure failure, [int? status, Object? error]) {
    final detail = [
      failure.name,
      if (status != null) 'HTTP $status',
      if (error != null) error.runtimeType.toString(),
    ].join(' · ');
    unawaited(NexCrashLog.failed('video.analysis', detail));
  }

  /// Has the provider watch the YouTube video [noteId] links to, and keeps
  /// what it says as that note's summary — the page text of a YouTube link
  /// is a title and little else, so this is the summary worth having.
  ///
  /// When nothing is kept, the result says why (2.1.9): every failure used
  /// to read "private, age-restricted or too long", including a plan's
  /// limit, a timeout and an analysis that worked and then was not saved.
  Future<NexVideoAnalysis> analyzeVideo(String noteId) async {
    final note = await worker.getById(noteId);
    final url = note?.linkUrl;
    if (note == null || url == null || !canAnalyzeVideo(note)) {
      return const NexVideoAnalysis.failed(NexVideoFailure.unavailable);
    }
    final adapter = CloudAIAdapter(
      config: _preferences.aiProvider,
      outputLanguage: _preferences.aiOutputLanguage,
      client: nexVideoClientForTest,
    );
    try {
      final text = await adapter.analyzeYouTubeVideo(
        url,
        title: note.title ?? '',
        notes: [note.id],
      );
      if (text == null) {
        final status = adapter.lastFailureStatus;
        final detail = adapter.lastFailureMessage;
        final failure = switch (status) {
          null => NexVideoFailure.silent,
          402 || 429 => NexVideoFailure.limit,
          >= 500 => NexVideoFailure.unavailable,
          _ => NexVideoFailure.refused,
        };
        _logVideoFailure(failure, status);
        return NexVideoAnalysis.failed(failure, status: status, detail: detail);
      }
      // Kept against the link, not the note's words: what was watched is
      // the video, and a caption written or a page excerpt fetched in the
      // meantime does not make it any less that video's summary. It used to
      // be the words — and a link with none at all compared as '' against
      // null, so an analysis that worked was never kept.
      final now = await worker.getById(noteId);
      if (now == null || now.isDeleted || now.linkUrl != url) {
        _logVideoFailure(NexVideoFailure.changed);
        return const NexVideoAnalysis.failed(NexVideoFailure.changed);
      }
      final saved = await worker.saveSummaryIfCurrent(
        noteId,
        now.aiSourceText,
        text,
      );
      if (!saved) {
        _logVideoFailure(NexVideoFailure.changed);
        return const NexVideoAnalysis.failed(NexVideoFailure.changed);
      }
      await refreshTimeline();
      return NexVideoAnalysis.done(text);
    } on TimeoutException catch (error) {
      _logVideoFailure(NexVideoFailure.slow, null, error);
      return const NexVideoAnalysis.failed(NexVideoFailure.slow);
    } catch (error) {
      _logVideoFailure(NexVideoFailure.unavailable, null, error);
      return const NexVideoAnalysis.failed(NexVideoFailure.unavailable);
    } finally {
      adapter.close();
    }
  }

  /// What the profile's portrait is counted from: the newest 2,000 notes,
  /// years of most libraries and a quick read for any.
  Future<List<Note>> portraitNotes() => worker.timeline(limit: 2000);

  /// Whether a written portrait can be asked for: a model to write it.
  bool get portraitWritable =>
      _preferences.aiEnabled && aiTextAvailableWith(_preferences.aiProvider);

  /// Writes the profile's portrait from a sample of the notes and keeps it
  /// (2.1.7). Asked for by the person, never in the background. Null when
  /// nothing usable came back; the portrait already kept stays then.
  Future<NexPortrait?> writePortrait() async {
    if (!portraitWritable) return null;
    final notes = await portraitNotes();
    final stats = nexWritingStats(notes);
    final source = nexPortraitSource(notes);
    if (source.ids.isEmpty) return null;
    final adapter = CloudAIAdapter(
      config: _preferences.aiProvider,
      outputLanguage: _preferences.aiOutputLanguage,
    );
    try {
      final portrait = await adapter.writePortrait(
        source.text,
        facts: nexWritingFacts(stats),
        basedOn: source.ids.length,
        notes: source.ids,
      );
      if (portrait != null) await _preferences.setProfilePortrait(portrait);
      return portrait;
    } catch (error) {
      unawaited(NexCrashLog.handled('ai.portrait', error));
      return null;
    } finally {
      adapter.close();
    }
  }

  Future<List<SemanticHit>> relatedNotes(String noteId, {int limit = 5}) =>
      nexRelatedNotesAvailable
      ? worker.relatedNotes(noteId, limit: limit)
      : Future.value(const []);

  Future<List<SemanticHit>> semanticSearch(String query, {int limit = 20}) =>
      worker.semanticSearch(query, limit: limit);

  /// Keyword and meaning search as one ranked list (W2.2). Slower than
  /// [search] by one embedding request, so callers show [search] first.
  Future<List<Note>> fusedSearch(SearchFilters filters) =>
      worker.fusedSearch(filters);

  Future<void> refreshTimeline() async {
    if (_closed || _timelineController.isClosed) return;
    _timelineReads++;
    final notes = await worker.timeline(limit: _timelineWindow);
    // A restore/restart may have closed this graph while the worker's
    // response was in flight. Its old snapshot has no listeners to update.
    if (_closed || _timelineController.isClosed) return;
    _lastTimeline = notes;
    _timelineController.add(notes);
  }

  /// How many notes the timeline stream currently carries.
  int get timelineWindow => _timelineWindow;

  /// Shrinks the window back to its first page, without a database read, once
  /// the reader is near the top again. Until then a deep scroll made every
  /// capture, edit and sync re-read — and the screen re-group — all of it.
  ///
  /// Only worth doing when the window has grown by a real margin; a few extra
  /// rows are not worth a rebuild. A page being fetched at the old depth is
  /// dropped (see [_loadMoreTimelinePage]).
  void trimTimelineWindow() {
    if (_closed || _timelineController.isClosed) return;
    if (_timelineWindow <= NexServices.timelineBaseWindow + 100) return;
    final last = _lastTimeline;
    if (last == null) return;
    _timelineWindow = NexServices.timelineBaseWindow;
    _timelineReads++;
    final head = List<Note>.unmodifiable(last.take(_timelineWindow));
    _lastTimeline = head;
    _timelineController.add(head);
  }

  Future<List<Note>> loadMore({required int offset, int limit = 50}) =>
      worker.loadMore(offset: offset, limit: limit);

  /// The scroll-to-bottom half of pagination: fetches the page past the
  /// current window with [loadMore], and — only if that page was not empty —
  /// grows the window and reloads through the same [refreshTimeline] every
  /// other mutation uses, so the result is the one canonical ordering rather
  /// than a hand-appended list that could drift from it.
  ///
  /// Returns false once a fetch turns up nothing to add, so the caller —
  /// [TimelineScreenState] — knows to stop asking until something changes.
  ///
  /// The page is appended rather than the window re-read (PERF-03): a
  /// re-read cost the whole window each time, so scrolling deep into a
  /// large library got slower with every page — about a second and a half a
  /// page at five thousand notes. The order is stable between changes, so
  /// appending is the same list; when anything was re-read while the page
  /// was being fetched, the full read stays the answer.
  Future<bool> loadMoreTimeline({int by = 50}) {
    final active = _timelinePage;
    if (active != null) return active;
    final work = _loadMoreTimelinePage(by: by);
    _timelinePage = work;
    return work.whenComplete(() {
      if (identical(_timelinePage, work)) _timelinePage = null;
    });
  }

  Future<bool> _loadMoreTimelinePage({required int by}) async {
    if (_closed) return false;
    final base = _lastTimeline;
    final reads = _timelineReads;
    final offset = _timelineWindow;
    final more = await worker.loadMore(offset: offset, limit: by);
    if (more.isEmpty) return false;
    // The window was trimmed while this page was coming: it belongs to a
    // depth nobody is at any more.
    if (_closed || _timelineWindow != offset) return true;
    _timelineWindow += more.length;
    if (base != null && reads == _timelineReads && base.length == offset) {
      final seen = {for (final note in base) note.id};
      final next = List<Note>.unmodifiable([
        ...base,
        for (final note in more)
          if (seen.add(note.id)) note,
      ]);
      _lastTimeline = next;
      if (!_closed) _timelineController.add(next);
      return true;
    }
    await refreshTimeline();
    return true;
  }
}

/// What "Analyze video" talks through in a test; null in the app, which
/// opens its own connection for each analysis.
@visibleForTesting
http.Client? nexVideoClientForTest;

/// Why "Analyze video" kept nothing (2.1.9).
enum NexVideoFailure {
  /// The plan's limit, usually a long video on a free plan (402, 429).
  limit,

  /// No answer within [CloudAIAdapter.videoTimeout].
  slow,

  /// The provider said no, with its reason: a private or age-restricted
  /// video, one too long for the model, a model that cannot watch.
  refused,

  /// An answer with nothing in it about the video.
  silent,

  /// The note was deleted or its link changed while the video was watched.
  changed,

  /// No connection, a server error, or nothing to analyse.
  unavailable,
}

/// What "Analyze video" came to: the analysis kept as the summary, or why
/// not, with the provider's status and words when it gave them.
class NexVideoAnalysis {
  const NexVideoAnalysis.done(String this.text)
    : failure = null,
      status = null,
      detail = null;

  const NexVideoAnalysis.failed(
    NexVideoFailure this.failure, {
    this.status,
    this.detail,
  }) : text = null;

  final String? text;
  final NexVideoFailure? failure;
  final int? status;
  final String? detail;
}
