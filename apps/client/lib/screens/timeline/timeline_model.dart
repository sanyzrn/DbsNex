import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:nex_core/nex_core.dart';

import '../../platform/nex_preferences.dart';
import '../../platform/nex_services.dart';

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

  /// Every tag the timeline is being narrowed to. Empty is "All".
  ///
  /// A set, because one pill could only ever answer "notes tagged work", and
  /// the question people actually have is "notes tagged work or home". They
  /// are OR-ed, not AND-ed: a note usually carries one of the tags somebody
  /// is thinking about, rarely all of them, and an AND across two tags is
  /// almost always empty.
  Set<String> get selectedTagIds => _selectedTagIds;
  Set<String> _selectedTagIds = const {};

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
      _selectedTagIds.isNotEmpty || _selectedType != null || _onlyReminders;

  /// Date groups the user has folded away, by their stable key.
  ///
  /// Persisted rather than kept for the session: someone who collapses "Last
  /// month" has said something about how they want the list to look, and
  /// having it spring open on the next launch means saying it again every day.
  Set<String> get collapsedGroups => _collapsedGroups;
  Set<String> _collapsedGroups;

  /// The recurring items, for the brief and the recap.
  List<NexCommitment> get commitments => _commitments;
  List<NexCommitment> _commitments = const [];

  /// Guards against firing a second [NexServices.loadMoreTimeline] while one
  /// is still in flight, and against firing one at all once a fetch has come
  /// back empty — a finger held past the bottom during the overscroll bounce
  /// delivers a scroll notification per frame, not one per gesture.
  bool _loadingMore = false;
  bool _exhausted = false;

  /// The note with [id] among those delivered, if it is one of them.
  Note? byId(String id) => _all?.where((n) => n.id == id).firstOrNull;

  /// Follows the timeline stream. [onDelivered] runs after each delivery has
  /// been taken in, for what the screen does on top of showing it.
  void listen(void Function(List<Note> delivered) onDelivered) {
    _subscription = services.timelineStream.listen((value) {
      if (_disposed) return;
      _loadFailed = false;
      _take(value);
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
      return loaded;
    } on Object {
      if (_disposed) return null;
      _loadFailed = _all == null;
      notifyListeners();
      return null;
    }
  }

  /// Clears a failed first read's state and tries it again.
  Future<List<Note>?> retry() {
    _loadFailed = false;
    notifyListeners();
    return load();
  }

  Future<void> loadFilterTags() async {
    final loaded = await services.tagUsage();
    if (_disposed) return;
    _filterTags = [
      for (final usage in loaded)
        if (usage.count > 0) usage.tag,
    ];
    notifyListeners();
  }

  Future<void> loadCommitments() async {
    try {
      final all = await services.commitments();
      if (_disposed) return;
      _commitments = all;
      notifyListeners();
    } catch (_) {
      // A brief without them is still a brief.
    }
  }

  Future<void> selectTags(Set<String> tagIds) {
    _selectedTagIds = tagIds;
    notifyListeners();
    return _applyFilters();
  }

  Future<void> selectType(NoteType? type) {
    _selectedType = type;
    notifyListeners();
    return _applyFilters();
  }

  Future<void> selectOnlyReminders(bool only) {
    _onlyReminders = only;
    notifyListeners();
    return _applyFilters();
  }

  Future<void> clearFilters() {
    _selectedTagIds = const {};
    _selectedType = null;
    _onlyReminders = false;
    notifyListeners();
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

  /// Folds away or opens up date groups, and remembers it.
  void setCollapsedGroups(Set<String> keys) {
    _collapsedGroups = keys;
    notifyListeners();
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
      // Null clears the repeat alongside the time, and cancels the alarm the
      // OS is still holding for it.
      await services.setDueAt(id, null);
      cleared = true;
    }
    if (cleared) await services.refreshTimeline();
  }

  Future<void> _applyFilters() async {
    final loaded = await services.timeline(limit: 200);
    if (_disposed) return;
    _take(loaded);
  }

  void _take(List<Note> delivered) {
    _all = delivered;
    _notes = visible(delivered);
    notifyListeners();
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
}
