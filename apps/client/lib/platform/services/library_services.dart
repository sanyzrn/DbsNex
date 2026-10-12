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

  Future<Summary?> summarizeOnDemand(String noteId) =>
      worker.summarizeOnDemand(noteId);

  Future<List<SemanticHit>> relatedNotes(String noteId, {int limit = 5}) =>
      worker.relatedNotes(noteId, limit: limit);

  Future<List<SemanticHit>> semanticSearch(String query, {int limit = 20}) =>
      worker.semanticSearch(query, limit: limit);

  /// Keyword and meaning search as one ranked list (W2.2). Slower than
  /// [search] by one embedding request, so callers show [search] first.
  Future<List<Note>> fusedSearch(SearchFilters filters) =>
      worker.fusedSearch(filters);

  Future<void> refreshTimeline() async {
    if (_closed) return;
    _timelineReads++;
    final notes = await worker.timeline(limit: _timelineWindow);
    _lastTimeline = notes;
    _timelineController.add(notes);
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
  Future<bool> loadMoreTimeline({int by = 50}) async {
    if (_closed) return false;
    final base = _lastTimeline;
    final reads = _timelineReads;
    final offset = _timelineWindow;
    final more = await worker.loadMore(offset: offset, limit: by);
    if (more.isEmpty) return false;
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
