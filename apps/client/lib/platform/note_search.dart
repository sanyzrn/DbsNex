import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';

import 'nex_services.dart';

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

  /// Notes with no keyword overlap at all, surfaced by meaning instead —
  /// only ever populated once keyword search has already come up empty, and
  /// silently empty itself whenever semantic search is off or unconfigured
  /// (see [NexServices.semanticSearch]).
  List<Note> semanticResults = const [];

  /// Null until the first search resolves, so "no results" and "not searched
  /// yet" are different states rather than the same empty list.
  bool get hasRun => _hasRun;
  bool _hasRun = false;

  Timer? _debounce;

  /// Guards against an older query resolving after a newer one and overwriting
  /// it — the classic search race.
  int _request = 0;

  int get activeFilterCount =>
      tags.length + types.length + (range == null ? 0 : 1);

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
    final found = await services.search(
      SearchFilters(
        query: query.text,
        tagIds: tags.toList(),
        types: types.toList(),
        createdFrom: range?.start,
        createdTo: range?.end.add(const Duration(days: 1)),
      ),
    );
    final trimmed = query.text.trim();
    Note? close;
    List<Note> semantic = const [];
    if (found.isEmpty && trimmed.isNotEmpty) {
      final widened = await Future.wait([
        services.nearestMiss(trimmed),
        _semanticMatches(trimmed),
      ]);
      close = widened[0] as Note?;
      semantic = (widened[1] as List<Note>)
          .where((note) => note.id != close?.id)
          .toList();
    }
    if (current != _request) return;
    results = found;
    nearest = close;
    semanticResults = semantic;
    _hasRun = true;
    notifyListeners();
  }

  /// Notes ranked by embedding similarity, resolved from ids to full [Note]s
  /// here so the widget layer never has to cross the isolate boundary itself.
  Future<List<Note>> _semanticMatches(String query) async {
    final hits = await services.semanticSearch(query, limit: 5);
    final notes = <Note>[];
    for (final hit in hits) {
      final note = await services.getById(hit.noteId);
      if (note != null) notes.add(note);
    }
    return notes;
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
    semanticResults = const [];
    _hasRun = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    query.dispose();
    super.dispose();
  }
}
