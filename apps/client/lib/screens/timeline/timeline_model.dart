import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:nex_core/nex_core.dart';

import '../../platform/nex_preferences.dart';
import '../../platform/nex_services.dart';

/// What the timeline model last notified about, so a listener can skip work
/// a change does not concern.
///
/// The model is one `ChangeNotifier` for things a screen consumes very
/// differently: a notes change rebuilds the cards, while a filter-row or
/// commitments change is the row's and the brief's own business. The kind is
/// set immediately before each notification and read by listeners that run
/// synchronously inside it.
enum TimelineChange { notes, tags, commitments, folds, shelves }

/// What the timeline shows, apart from how it shows it (W4.2).
///
/// The notes as the stream last delivered them, the filters narrowing them,
/// the window's paging, the date groups folded away and the recurring items
/// the brief reads. The screen listens and rebuilds; everything here can be
/// driven and checked without a widget.
class TimelineModel extends ChangeNotifier {
  TimelineModel({required this.services, required this.preferences})
    : _collapsedGroups = preferences.collapsedTimelineGroups;

  final NexServices services;
  final NexPreferences preferences;

  StreamSubscription<List<Note>>? _subscription;
  bool _disposed = false;

  /// Everything the timeline stream last delivered, before filters.
  ///
  /// **Null means "not known yet"**, which is a different thing from "empty".
  /// This was `const []` at field initialisation while `build` ran immediately
  /// and the first read resolved later, so the first frame of *every* cold
  /// launch satisfied the empty condition and flashed the full-screen
  /// onboarding copy — marketing text, in front of a user with a library.
  ///
  /// It also used to hold only the filtered list, so the next stream event —
  /// which a capture triggers — replaced it with the unfiltered one while the
  /// filter chips still claimed to be active.
  List<Note>? get all => _all;
  List<Note>? _all;

  /// [all], narrowed by the filters.
  List<Note> get notes => _notes;
  List<Note> _notes = const [];

  /// The first timeline read threw and there is nothing to show instead.
  /// Only ever true while [all] is null: once data is on screen, a failed
  /// reload keeps the data it failed to replace.
  bool get loadFailed => _loadFailed;
  bool _loadFailed = false;

  /// The tags the filter row offers.
  ///
  /// Built from usage counts rather than the bare tag list: a tag nothing is
  /// tagged with anymore (its last note deleted, or created and never used)
  /// was still showing up as a pill that filtered to an empty list.
  List<Tag> get filterTags => _filterTags;
  List<Tag> _filterTags = const [];

  /// Live note counts from the same tag-usage query that powers the pills.
  Map<String, int> get filterTagCounts => _filterTagCounts;
  Map<String, int> _filterTagCounts = const {};

  /// Every tag the timeline is being narrowed to. Empty is "All".
  ///
  /// A set, because one pill could only ever answer "notes tagged work", and
  /// the question people actually have is "notes tagged work or home". They
  /// are OR-ed, not AND-ed: a note usually carries one of the tags somebody
  /// is thinking about, rarely all of them, and an AND across two tags is
  /// almost always empty.
  Set<String> get selectedTagIds => _selectedTagIds;
  Set<String> _selectedTagIds = const {};
  bool get onlyUntagged => _onlyUntagged;
  bool _onlyUntagged = false;
  bool _hasUntagged = false;
  bool get hasUntagged => _hasUntagged;

  NoteType? get selectedType => _selectedType;
  NoteType? _selectedType;

  /// Show only notes with a reminder still ahead of them.
  ///
  /// A state, not a type, which is why it is its own field rather than a
  /// seventh entry in [selectedType]: a note is a photo *and* has a reminder,
  /// and a filter that made you choose between those two facts would be
  /// answering a question nobody asked. It layers on top of both other
  /// filters, the same way they layer on each other.
  ///
  /// "Still ahead" comes for free: a reminder that has rung and been seen is
  /// retired by [retireSpentReminders], so a note that still carries a
  /// `dueAt` is a note with something coming.
  bool get onlyReminders => _onlyReminders;
  bool _onlyReminders = false;

  bool get filtering =>
      _selectedTagIds.isNotEmpty ||
      _onlyUntagged ||
      _selectedType != null ||
      _onlyReminders;

  /// Date groups the user has folded away, by their stable key.
  ///
  /// Persisted rather than kept for the session: someone who collapses "Last
  /// month" has said something about how they want the list to look, and
  /// having it spring open on the next launch means saying it again every day.
  Set<String> get collapsedGroups => _collapsedGroups;
  Set<String> _collapsedGroups;

  /// Whole-timeline counts for an arranged home's shelves (2.7.0) — see
  /// `timelineShelfCounts`. Null until read, and never read while the home
  /// is arranged by day.
  Map<String, int>? get shelfCounts => _shelfCounts;
  Map<String, int>? _shelfCounts;
  Future<void>? _shelfFlight;
  bool _shelfAgain = false;

  /// Reads [shelfCounts] when the home is arranged by kind or tag.
  ///
  /// Coalesced like [loadFilterTags], but a call that lands mid-read asks
  /// for one more read after it: the read in flight may have started before
  /// the write that prompted this call.
  Future<void> loadShelfCounts() {
    if (preferences.timelineArrangement == NexTimelineArrangement.time) {
      return Future.value();
    }
    final pending = _shelfFlight;
    if (pending != null) {
      _shelfAgain = true;
      return pending;
    }
    final flight = _readShelfCounts().whenComplete(() {
      _shelfFlight = null;
      if (_shelfAgain && !_disposed) {
        _shelfAgain = false;
        unawaited(loadShelfCounts());
      }
    });
    _shelfFlight = flight;
    return flight;
  }

  /// The first read after the home is arranged by kind or tag — once, not
  /// again on every build while a read is out or after one failed.
  void ensureShelfCounts() {
    if (_shelfCounts != null || _shelfFlight != null || _shelfTried) return;
    _shelfTried = true;
    unawaited(loadShelfCounts());
  }

  bool _shelfTried = false;

  Future<void> _readShelfCounts() async {
    try {
      final counts = await services.worker.timelineShelfCounts();
      if (_disposed || mapEquals(counts, _shelfCounts)) return;
      _shelfCounts = Map.unmodifiable(counts);
      _notifyOf(TimelineChange.shelves);
    } on Object {
      // Without counts a shelf says "See all" rather than how many: true,
      // only less exact.
    }
  }

  /// The recurring items, for the brief and the recap.
  List<NexCommitment> get commitments => _commitments;
  List<NexCommitment> _commitments = const [];

  // The meaning of "met today" changes at local midnight without a DB write.
  String? _commitmentsDayKey;

  /// Guards against firing a second [NexServices.loadMoreTimeline] while one
  /// is still in flight, and against firing one at all once a fetch has come
  /// back empty — a finger held past the bottom during the overscroll bounce
  /// delivers a scroll notification per frame, not one per gesture.
  bool _loadingMore = false;
  bool _exhausted = false;

  /// What the last notification was about — set by [_notifyOf] immediately
  /// before notifying, read by listeners that run inside that notification.
  TimelineChange get lastChange => _lastChange;
  TimelineChange _lastChange = TimelineChange.notes;

  /// Notifies with what changed. Listeners that run synchronously inside the
  /// notification can ask and skip the work a change does not concern; a
  /// listener that arrives between notifications sees the most recent kind,
  /// which is the only one it can still react to.
  void _notifyOf(TimelineChange change) {
    _lastChange = change;
    notifyListeners();
  }

  /// The note with [id] among those delivered, if it is one of them.
  Note? byId(String id) => _all?.where((n) => n.id == id).firstOrNull;

  /// Follows the timeline stream. [onDelivered] runs after each delivery has
  /// been taken in, for what the screen does on top of showing it.
  void listen(
    void Function(List<Note> delivered) onDelivered, {
    VoidCallback? onUnchanged,
  }) {
    _subscription = services.timelineStream.listen((value) {
      if (_disposed) return;
      _loadFailed = false;
      // Suppress an identical note snapshot without hiding a newly cached
      // recap written by another service (which has its own callback).
      if (!_take(value)) {
        onUnchanged?.call();
        return;
      }
      // A capture or a delete can change whether there is more to load —
      // most obviously a capture, past a window an earlier scroll had
      // already exhausted. Re-arming here costs one wasted fetch on the next
      // scroll-to-bottom when it turns out nothing changed; leaving it stuck
      // costs a note nobody can ever scroll to.
      _exhausted = false;
      // The filter row is fed by a separate query. Creating or deleting a tag
      // anywhere in the app left the row showing the old set until the next
      // cold launch — which is exactly the "I had to restart it" report.
      // Every mutation path already refreshes the timeline, so this is the
      // one place that has to notice.
      unawaited(loadFilterTags());
      unawaited(loadShelfCounts());
      onDelivered(value);
    });
  }

  /// The first read. Returns what it read, or null when it failed.
  ///
  /// A read that never comes back used to look identical to one still
  /// coming: skeletons for as long as the app was open, with nothing to tap.
  /// When there is nothing on screen yet the failure *is* the state; once
  /// data is showing, keep it — a reload that fails must not blank the
  /// screen it failed on.
  Future<List<Note>?> load() async {
    try {
      final loaded = await services.timeline(limit: 200);
      if (_disposed) return null;
      _loadFailed = false;
      _take(loaded);
      unawaited(loadShelfCounts());
      return loaded;
    } on Object {
      if (_disposed) return null;
      _loadFailed = _all == null;
      _notifyOf(TimelineChange.notes);
      return null;
    }
  }

  /// Clears a failed first read's state and tries it again.
  Future<List<Note>?> retry() {
    _loadFailed = false;
    _notifyOf(TimelineChange.notes);
    return load();
  }

  Future<void>? _filterTagsFlight;

  /// The filter row's tags and counts, as one shared query.
  ///
  /// Coalesced: the stream listener, the first read, the search sheet and a
  /// manual pull all ask for the same two queries, often within the same few
  /// milliseconds — a burst of captures firing the stream once each used to
  /// read the tags once each too. While one read is in flight, later callers
  /// join it rather than queue behind it.
  Future<void> loadFilterTags() {
    final pending = _filterTagsFlight;
    if (pending != null) return pending;
    final flight = _readFilterTags().whenComplete(() {
      _filterTagsFlight = null;
    });
    _filterTagsFlight = flight;
    return flight;
  }

  Future<void> _readFilterTags() async {
    final loaded = await services.tagUsage(timelineOnly: true);
    final hasUntagged = await services.worker.hasUntaggedTimelineNotes();
    if (_disposed) return;
    final tags = [
      for (final usage in loaded)
        if (usage.count > 0) usage.tag,
    ];
    final counts = {
      for (final usage in loaded)
        if (usage.count > 0) usage.tag.id: usage.count,
    };
    // Tag queries often return the same labels and counts. Do not rebuild
    // the entire home screen just to display an identical filter row.
    if (_sameTags(_filterTags, tags) &&
        mapEquals(_filterTagCounts, counts) &&
        _hasUntagged == hasUntagged) {
      return;
    }
    _filterTags = tags;
    _filterTagCounts = counts;
    _hasUntagged = hasUntagged;
    if (!hasUntagged && _onlyUntagged) {
      _onlyUntagged = false;
      await _applyFilters();
    } else {
      _notifyOf(TimelineChange.tags);
    }
  }

  Future<void> loadCommitments({DateTime? now}) async {
    try {
      final all = await services.commitments();
      if (_disposed) return;
      final dayKey = nexDayKey(now ?? DateTime.now());
      // Returning from Settings or Recurring should not repaint every card
      // when neither the commitments nor their local-day meaning changed.
      if (_commitmentsDayKey == dayKey && _sameCommitments(_commitments, all)) {
        return;
      }
      _commitmentsDayKey = dayKey;
      _commitments = all;
      _notifyOf(TimelineChange.commitments);
    } catch (_) {
      // A brief without them is still a brief.
    }
  }

  Future<void> selectTags(Set<String> tagIds) {
    _onlyUntagged = false;
    _selectedTagIds = Set.unmodifiable(tagIds);
    return _applyFilters();
  }

  Future<void> selectType(NoteType? type) {
    _selectedType = type;
    return _applyFilters();
  }

  Future<void> selectOnlyReminders(bool only) {
    _onlyReminders = only;
    return _applyFilters();
  }

  Future<void> clearFilters() {
    _onlyUntagged = false;
    _selectedTagIds = const {};
    _selectedType = null;
    _onlyReminders = false;
    return _applyFilters();
  }

  Future<void> selectUntagged(bool selected) {
    _onlyUntagged = selected;
    if (selected) _selectedTagIds = const {};
    return _applyFilters();
  }

  /// Grows the timeline window when the list is close to its end.
  ///
  /// The result reaches [notes] through the same stream subscription every
  /// other mutation already goes through, so there is nothing to do here
  /// with what comes back beyond remembering whether it was empty.
  void loadMore() {
    if (_loadingMore || _exhausted) return;
    _loadingMore = true;
    unawaited(
      services
          .loadMoreTimeline()
          .then((more) => _exhausted = !more)
          .whenComplete(() => _loadingMore = false),
    );
  }

  /// Back near the top of a list that was scrolled deep: lets the service drop
  /// the depth it kept, so later changes read one page again.
  void trimWindow() {
    if (services.timelineWindow <= NexServices.timelineBaseWindow + 100) return;
    services.trimTimelineWindow();
    _exhausted = false;
  }

  Future<bool> ensureLoaded(String noteId) async {
    if (_all == null) await load();
    if (byId(noteId) != null) return true;
    final note = await services.worker.getById(noteId);
    if (note == null || note.deletedAt != null) return false;
    // Reuse the service’s full window after a filter or first-read snapshot.
    // An exhausted page must not hide rows that were already loaded earlier.
    await services.refreshTimeline();
    if (_disposed) return false;
    while (!_disposed && byId(noteId) == null) {
      final more = await services.loadMoreTimeline();
      if (!more) return byId(noteId) != null;
    }
    return !_disposed;
  }

  /// Folds away or opens up date groups, and remembers it.
  void setCollapsedGroups(Set<String> keys) {
    _collapsedGroups = keys;
    _notifyOf(TimelineChange.folds);
    unawaited(preferences.setCollapsedTimelineGroups(keys));
  }

  /// Clears one-off reminders that have already rung.
  ///
  /// A reminder is a thing to be reminded of, and once it has happened it is
  /// finished. It used to be kept on the note for ever and merely hidden from
  /// the card by a set of ids recorded here — so the note still carried a
  /// reminder, the detail sheet still offered to remove it, and removing it
  /// by hand was the only way to be rid of it. That was the report, three
  /// times: the trace stays on the item.
  ///
  /// The screen calls this on the way out rather than the moment a reminder
  /// lapses, so it gets exactly one more showing — a reminder that vanished
  /// while being read would be a reminder you never saw.
  ///
  /// A repeating one is never spent: its stored time is in the past by design
  /// after the first firing, and it is still going to ring again. Only a
  /// one-off can be finished with.
  Future<void> retireSpentReminders() async {
    final now = DateTime.now().toUtc();
    final spent = [
      for (final note in _all ?? const <Note>[])
        if (note.dueRepeat == NoteRepeat.once)
          if (note.dueAt case final due?)
            if (!due.isAfter(now)) note.id,
    ];
    if (spent.isEmpty) return;
    var cleared = false;
    for (final id in spent) {
      // Re-read before clearing. [all] is a snapshot, and the most likely way
      // to reach this code is by opening the note — which is also the most
      // likely place to push the reminder forward. Deleting a time the reader
      // has just chosen, because a list from a moment ago still said it had
      // lapsed, is the one mistake this must not make.
      final current = await services.getById(id);
      if (current == null) continue;
      if (current.dueRepeat != NoteRepeat.once) continue;
      final due = current.dueAt;
      if (due == null || due.isAfter(DateTime.now().toUtc())) continue;
      // The time goes; a notification it left in the shade stays.
      await services.retireDue(id);
      cleared = true;
    }
    if (cleared) await services.refreshTimeline();
  }

  // Filters only narrow the already-loaded timeline window. Re-reading the
  // same database rows did not change [_all], so [_take] suppressed its
  // notification even when [_notes] changed. The chip then showed the new
  // selection while the cards still showed the previous one until an
  // unrelated rebuild — especially confusing during rapid tag taps.
  // Update both in the same turn, notify exactly once, and let the normal
  // timeline stream keep the window fresh when underlying notes change.
  Future<void> _applyFilters() {
    if (!_disposed) {
      _notes = visible(_all ?? const <Note>[]);
      _notifyOf(TimelineChange.notes);
    }
    return Future<void>.value();
  }

  /// Returns true when the *entire* timeline snapshot actually changed.
  ///
  /// Comparing the unfiltered window matters: notes hidden by a tag/type
  /// filter still contribute to the smart summary and reminder state.
  /// A changed hidden note must reach the summary even when cards stay put.
  bool _take(List<Note> delivered) {
    final changed = _all == null || !_sameNotes(_all!, delivered);
    _all = delivered;
    _notes = visible(delivered);
    if (changed) _notifyOf(TimelineChange.notes);
    return changed;
  }

  /// FR-4.5: the content-type filter layers on top of the tag filter — it is
  /// not a separate mode, so both selections resolve into one view.
  @visibleForTesting
  List<Note> visible(List<Note> source) {
    final tagIds = _selectedTagIds;
    final type = _selectedType;
    return source.where((note) {
      if (_onlyReminders && note.dueAt == null) return false;
      if (type != null && note.type != type) return false;
      if (_onlyUntagged && note.tags.isNotEmpty) return false;
      if (tagIds.isNotEmpty && !note.tags.any((t) => tagIds.contains(t.id))) {
        return false;
      }
      return true;
    }).toList();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  /// A refreshed DB snapshot contains new Note objects even if no data moved.
  /// Keep no-op navigation from rebuilding the cards, filter row, and recap.
  static bool _sameNotes(List<Note> before, List<Note> after) {
    if (before.length != after.length) return false;
    for (var i = 0; i < before.length; i++) {
      if (!_sameNote(before[i], after[i])) return false;
    }
    return true;
  }

  static bool _sameNote(Note a, Note b) {
    if (identical(a, b)) return true;
    // AI summary, transcription, and OCR updates do NOT necessarily bump
    // updatedAt/rev, so those fields must be compared explicitly.
    // The same applies to local-only reminder, pin and urgency metadata.
    return a.id == b.id &&
        a.type == b.type &&
        a.rev == b.rev &&
        a.updatedAt == b.updatedAt &&
        a.createdAt == b.createdAt &&
        a.deletedAt == b.deletedAt &&
        a.content == b.content &&
        a.caption == b.caption &&
        a.title == b.title &&
        a.linkExcerpt == b.linkExcerpt &&
        a.transcriptText == b.transcriptText &&
        a.ocrText == b.ocrText &&
        a.summaryText == b.summaryText &&
        a.mediaUri == b.mediaUri &&
        a.mediaHash == b.mediaHash &&
        a.durationMs == b.durationMs &&
        a.mimeType == b.mimeType &&
        a.pinnedAt == b.pinnedAt &&
        a.isUrgent == b.isUrgent &&
        a.setAsideAt == b.setAsideAt &&
        a.setAsideUntil == b.setAsideUntil &&
        a.dueAt == b.dueAt &&
        a.dueRepeat == b.dueRepeat &&
        a.sortOrder == b.sortOrder &&
        a.attachmentCount == b.attachmentCount &&
        _sameTags(a.tags, b.tags);
    // syncState is intentionally omitted: there is no card-level sync badge.
  }

  static bool _sameTags(List<Tag> before, List<Tag> after) {
    if (before.length != after.length) return false;
    for (var i = 0; i < before.length; i++) {
      if (before[i].id != after[i].id ||
          before[i].name != after[i].name ||
          before[i].color != after[i].color) {
        return false;
      }
    }
    return true;
  }

  static bool _sameCommitments(List<NexCommitment> a, List<NexCommitment> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_sameCommitment(a[i], b[i])) return false;
    }
    return true;
  }

  static bool _sameCommitment(NexCommitment a, NexCommitment b) {
    if (identical(a, b)) return true;
    // Not all save paths bump rev/updatedAt. Compare every persisted field,
    // including nested details such as recurrence, cost and history.
    return a.id == b.id &&
        a.rev == b.rev &&
        a.createdAt == b.createdAt &&
        a.updatedAt == b.updatedAt &&
        a.title == b.title &&
        a.cadence == b.cadence &&
        a.every == b.every &&
        a.dueAt == b.dueAt &&
        a.lead == b.lead &&
        a.windowStart == b.windowStart &&
        a.windowEnd == b.windowEnd &&
        a.lastMetAt == b.lastMetAt &&
        a.metToday == b.metToday &&
        a.metTodayOn == b.metTodayOn &&
        a.paused == b.paused &&
        a.notify == b.notify &&
        _sameDetails(a.details, b.details);
  }

  // JSON-compatible details can contain nested maps and history lists.
  // A shallow mapEquals would hide edits inside an existing history entry.
  static bool _sameDetails(Object? a, Object? b) {
    if (identical(a, b)) return true;
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final key in a.keys) {
        if (!b.containsKey(key) || !_sameDetails(a[key], b[key])) return false;
      }
      return true;
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_sameDetails(a[i], b[i])) return false;
      }
      return true;
    }
    return a == b;
  }
}
