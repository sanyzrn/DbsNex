import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';

import 'nex_services.dart';

/// The date windows the filter sheet offers. Presets rather than a calendar:
/// every fielded request for "find that thing" is about recency, and a
/// two-handle date picker is a form for a query that used to be one tap.
enum NoteDatePreset {
  any,
  today,
  last7Days,
  last30Days;

  DateTimeRange? resolve(DateTime now) => switch (this) {
    any => null,
    today => DateTimeRange(
      start: DateTime(now.year, now.month, now.day),
      end: now,
    ),
    last7Days => DateTimeRange(
      start: DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(const Duration(days: 6)),
      end: now,
    ),
    last30Days => DateTimeRange(
      start: DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(const Duration(days: 29)),
      end: now,
    ),
  };
}

/// Everything a search needs to run, independent of where it is shown.
///
/// Search used to live entirely inside a full-screen route, which is why
/// putting a query field on the timeline would have meant a second copy of the
/// debounce, the stale-response guard and the nearest-miss lookup. This is the
/// one copy.
class NoteSearchController extends ChangeNotifier {
  NoteSearchController({required this.services});

  final NexServices services;

  final query = TextEditingController();
  final tags = <String>{};
  final types = <NoteType>{};
  DateTimeRange? range;

  List<Note> results = const [];
  List<Tag> allTags = const [];

  /// The closest thing the user did write, when nothing matched.
  Note? nearest;

  /// The results that no word of the query matched — found by meaning and
  /// fused into [results] (W2.2). Empty whenever semantic search is off or
  /// unconfigured. Kept so the list can say why such a note is there.
  Set<String> meaningOnly = const {};

  /// Null until the first search resolves, so "no results" and "not searched
  /// yet" are different states rather than the same empty list.
  bool get hasRun => _hasRun;
  bool _hasRun = false;

  /// Why the last search did not run, or null if it ran.
  ///
  /// A thrown search used to leave `run()` before `_hasRun` was ever set, and
  /// the results area shows skeletons for as long as that is false — so the
  /// one visible consequence of a failed search was three placeholder cards,
  /// for ever. "Search keeps loading" is a worse report than "search failed",
  /// because there is nothing in it to act on.
  ///
  /// The reason is kept rather than dropped, on the same principle the
  /// reminders follow, even though the results area shows only the plain
  /// sentence: a database error is not something the reader can act on, and
  /// the retry beside it is.
  String? get failure => _failure;
  String? _failure;

  Timer? _debounce;

  /// Guards against an older query resolving after a newer one and overwriting
  /// it — the classic search race.
  int _request = 0;

  int get activeFilterCount =>
      tags.length + types.length + (range == null ? 0 : 1);

  /// The preset the current [range] came from, if it still matches one.
  /// A null range is "any time".
  NoteDatePreset get datePreset {
    if (range == null) return NoteDatePreset.any;
    final now = DateTime.now();
    for (final preset in NoteDatePreset.values) {
      final resolved = preset.resolve(now);
      if (resolved == null) continue;
      if (_sameDay(resolved.start, range!.start) &&
          _sameDay(resolved.end, range!.end)) {
        return preset;
      }
    }
    return NoteDatePreset.any;
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Toggles one tag in the filter set and re-runs the search.
  void toggleTag(String tagId) {
    if (!tags.add(tagId)) tags.remove(tagId);
    schedule();
  }

  /// Toggles one note type in the filter set and re-runs the search.
  void toggleType(NoteType type) {
    if (!types.add(type)) types.remove(type);
    schedule();
  }

  /// Sets the date window from a preset and re-runs the search.
  void setDatePreset(NoteDatePreset preset) {
    range = preset.resolve(DateTime.now());
    schedule();
  }

  /// Drops every chip filter at once. The typed query is left alone — it is
  /// what the field shows, and clearing text the user typed is not a filter
  /// operation.
  void clearFilters() {
    if (activeFilterCount == 0) return;
    tags.clear();
    types.clear();
    range = null;
    schedule();
  }

  /// Stands in for a `tag:` nobody has ever used.
  ///
  /// An id that matches nothing, rather than dropping the term: searching for
  /// a tag that does not exist has no results, and silently ignoring it would
  /// show every note instead — the opposite of what was asked for.
  static const _noSuchTag = '\u0000no-such-tag';

  String? _tagIdNamed(String name) {
    final wanted = name.trim().toLowerCase();
    for (final tag in allTags) {
      if (tag.name.toLowerCase() == wanted) return tag.id;
    }
    return null;
  }

  Future<void> loadTags() async {
    allTags = await services.listTags();
    notifyListeners();
  }

  /// Coalesces keystrokes. Without it every character is a database round trip.
  void schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), run);
  }

  Future<void> run() async {
    final current = ++_request;
    // `tag:` and `type:` typed into the box mean the same as the chips above
    // it, and combine with them rather than replacing them: someone who has
    // tapped a tag and then types `type:link` wants both.
    final typed = parseSearchQuery(query.text);
    final typedTagIds = <String>[
      for (final name in typed.tagNames)
        if (_tagIdNamed(name) case final id?) id else _noSuchTag,
    ];
    final filters = SearchFilters(
      query: typed.text,
      tagIds: {...tags, ...typedTagIds}.toList(),
      types: {...types, ...typed.types}.toList(),
      createdFrom: range?.start,
      createdTo: range?.end.add(const Duration(days: 1)),
    );
    final trimmed = typed.text.trim();
    try {
      // Keyword matches first, ranked: they come straight from the local
      // index, so they are on screen while the meaning search is still
      // asking the provider for the query's embedding.
      final found = await services.search(filters);
      if (current != _request) return;
      // Shown now unless there is nothing to show yet: "nothing matches"
      // flashing up before the meaning search answers would be wrong half
      // the time.
      if (found.isNotEmpty || trimmed.isEmpty) {
        results = found;
        meaningOnly = const {};
        nearest = null;
        _failure = null;
        _hasRun = true;
        notifyListeners();
      }

      if (trimmed.isEmpty) return;
      // Then one list: the same matches fused with what means the same
      // thing (W2.2). Without a provider this is the keyword ranking again,
      // and nothing on screen moves.
      List<Note> fused;
      try {
        fused = await services.fusedSearch(filters);
      } catch (_) {
        fused = found;
      }
      if (current != _request) return;
      final byWord = {for (final note in found) note.id};
      _failure = null;
      nearest = null;
      results = fused;
      meaningOnly = {
        for (final note in fused)
          if (!byWord.contains(note.id)) note.id,
      };
      if (fused.isEmpty) {
        final close = await services.nearestMiss(trimmed);
        if (current != _request) return;
        nearest = close;
      }
    } catch (error) {
      // A newer query is already in flight and will report for itself; an
      // older one's failure is not news.
      if (current != _request) return;
      results = const [];
      nearest = null;
      meaningOnly = const {};
      _failure = '$error';
    }
    // Either way the search has now been *attempted*, which is what stops the
    // skeletons. Reached only by the paths that did not return early above.
    _hasRun = true;
    notifyListeners();
  }

  /// Back to a blank search, without disposing anything.
  void clear() {
    _debounce?.cancel();
    query.clear();
    tags.clear();
    types.clear();
    range = null;
    results = const [];
    nearest = null;
    meaningOnly = const {};
    _hasRun = false;
    _failure = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    query.dispose();
    super.dispose();
  }
}
