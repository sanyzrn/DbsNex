part of '../nex_services.dart';

extension _NexBriefServices on NexServices {
  Future<HabitsBrief> _readHabitsForBrief() async {
    await applyHabitActions();
    if (!_preferences.briefHabitsAllowed) {
      return HabitsBrief.empty;
    }
    final day = NexPreferences.daySummaryDateKey(DateTime.now());
    if (_habitBriefDay != day) _habitBrief = null;
    _habitBriefDay = day;
    return _habitBrief ??=
        HabitsBrief.read(
          NexModuleStore(this, 'habits'),
          DateTime.now(),
        ).catchError((Object error) {
          _habitBrief = null;
          return HabitsBrief.empty;
        });
  }

  /// The notes the brief chooses from: the library's own candidate set —
  /// everything that can be waiting, plus the newest ordinary prose —
  /// whatever the timeline window happens to carry. See
  /// `NoteRepository.listBriefCandidates`.
  ///
  /// Refreshed on each brief pass rather than cached: unlike the habits,
  /// whose day-shaped state changes only through a write that already
  /// invalidates the cache, a note gains or loses a reminder through the
  /// ordinary note paths this call rides along with.
  ///
  /// A failed read is an empty list, not a failed brief: the timeline window
  /// still carries everything recent, which is what the brief falls back to.
  Future<List<Note>> _readBriefCandidates() async {
    try {
      return await worker.briefCandidates();
    } catch (_) {
      return const [];
    }
  }

  /// Which of the brief's candidates the library's own embeddings call one
  /// subject — grouping beyond shared words, read locally, nothing sent
  /// anywhere. A failed read is no pairs, not a failed brief: words and tags
  /// still group what they always did.
  Future<List<({String a, String b})>> _readBriefSemanticPairs(
    List<String> noteIds,
  ) async {
    try {
      final pairs = await worker.briefSemanticPairs(noteIds);
      return [for (final pair in pairs) (a: pair.a, b: pair.b)];
    } catch (_) {
      return const [];
    }
  }
}
