part of '../nex_preferences.dart';

/// How the library is browsed: collapsed groups, expanded cards, saved
/// searches, media sweeps.
mixin _LibraryPreferences on _PreferencesStore {
  /* ------------------------------------------------- Timeline date groups */

  /// Date groups the timeline is showing folded away.
  ///
  /// Stored by key rather than by index: "Last week" is a different set of
  /// notes tomorrow than it is today, and an index would fold whichever group
  /// happened to land in that position.
  Set<String> get collapsedTimelineGroups =>
      (_prefs.getStringList('timeline.collapsed') ?? const []).toSet();

  Future<void> setCollapsedTimelineGroups(Set<String> keys) async {
    await _prefs.setStringList('timeline.collapsed', keys.toList()..sort());
    notifyListeners();
  }

  /* ------------------------------------------------------- Expanded cards */

  /// Notes whose card shows all of itself instead of its first two lines.
  ///
  /// Here rather than on the note, and that is a decision worth the words. It
  /// is how a card is *drawn on this device*, not something true about the
  /// note — the same reason `pinnedAt` and `sortOrder` are documented as
  /// local-only and never synced. Keeping it here also means no migration, no
  /// new column for sync and merge to learn, and nothing for another device to
  /// disagree with about how tall a card should be.
  ///
  /// The cost is that it does not survive restoring the library on a new
  /// phone. A note that has to stay in view is one you are looking at now, so
  /// that is the right side to be wrong on.
  ///
  /// Held in memory rather than read back out of [_prefs] on every question,
  /// for the reason [_secureApiKeys] is: [isNoteExpanded] is asked once per
  /// card, inside the timeline's list builder, which is once per card per
  /// frame. Each of those calls used to copy the stored list and build a
  /// fresh `Set` from it — two allocations per card per frame, to answer a
  /// question about one string. The field beside it in the timeline
  /// (`_spentReminders`) carries a comment saying not to do this; this one
  /// did it anyway.
  ///
  /// It also only ever grows: nothing drops the id of a note that was later
  /// deleted for good. That is left alone deliberately — the entries are
  /// user-chosen and few (this is "keep *this* one open", not a default), and
  /// pruning them properly means a hook in the purge path down in the storage
  /// layer, which is a bigger change than one stale string per deleted note
  /// is worth.
  late final Set<String> _expandedNoteIds = <String>{
    ...?_prefs.getStringList('timeline.expanded'),
  };

  /// Unmodifiable: the only way in is [setNoteExpanded], which also persists.
  Set<String> get expandedNoteIds => Set.unmodifiable(_expandedNoteIds);

  bool isNoteExpanded(String id) => _expandedNoteIds.contains(id);

  Future<void> setNoteExpanded(String id, bool expanded) async {
    if (expanded ? !_expandedNoteIds.add(id) : !_expandedNoteIds.remove(id)) {
      return;
    }
    await _prefs.setStringList(
      'timeline.expanded',
      _expandedNoteIds.toList()..sort(),
    );
    notifyListeners();
  }

  /// Whether the orphaned-media sweep is due — see
  /// `NexServices.sweepOrphanMediaIfDue`.
  ///
  /// A bare timestamp rather than a policy object: there is one caller, it
  /// asks once per launch, and the question is only ever "has it been a day".
  bool mediaSweepDue(Duration interval) {
    final last = _prefs.getInt('media.last_sweep_at_ms');
    if (last == null) return true;
    final elapsed = DateTime.now().millisecondsSinceEpoch - last;
    return elapsed >= interval.inMilliseconds;
  }

  Future<void> markMediaSwept() => _prefs.setInt(
    'media.last_sweep_at_ms',
    DateTime.now().millisecondsSinceEpoch,
  );

  List<String> get savedSearches =>
      _prefs.getStringList('search.saved') ?? const [];

  Future<void> saveSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    final updated = <String>[
      trimmed,
      for (final saved in savedSearches)
        if (saved != trimmed) saved,
    ];
    await _prefs.setStringList(
      'search.saved',
      updated.take(NexPreferences.maxSavedSearches).toList(),
    );
    notifyListeners();
  }

  Future<void> removeSavedSearch(String query) async {
    final remaining = [
      for (final saved in savedSearches)
        if (saved != query) saved,
    ];
    await _prefs.setStringList('search.saved', remaining);
    notifyListeners();
  }
}
