import 'dart:math' as math;

import '../models/note.dart';

/// What the ranking needs to know about a note beyond whether it matched.
class FusionFacts {
  const FusionFacts({
    required this.createdAt,
    required this.type,
    this.pinned = false,
  });

  final DateTime createdAt;
  final NoteType type;
  final bool pinned;
}

/// One ranked list from the two ways Nex finds a note (W2.2).
///
/// Keyword search (FTS5, best match first) and meaning search (embeddings,
/// most similar first) used to be two separate answers: the second only
/// appeared when the first found nothing. They are now fused with
/// reciprocal-rank fusion — each list gives a note `1 / (k + rank)`, and a
/// note both lists found gets both — which needs no calibration between a
/// BM25 score and a cosine, only their orders.
///
/// Two small nudges follow, each worth a few places near the top and never
/// enough to lift a weak match over a strong one:
///
/// - **Recency.** Of two equally good matches, the newer is more likely the
///   one being looked for; the nudge halves every [recencyHalfLife].
/// - **Type.** A query that names a kind of note — "photo", "voice", "لینک" —
///   without the `type:` filter prefers that kind instead of requiring it.
///   Pinned notes get the same small preference.
class FusedRanking {
  const FusedRanking._();

  /// The standard RRF constant: large enough that rank 1 and rank 2 are not
  /// worlds apart, small enough that the top of a list still leads.
  static const k = 60;

  static const recencyWeight = 0.004;
  static const recencyHalfLife = Duration(days: 60);
  static const typeWeight = 0.003;
  static const pinnedWeight = 0.002;

  static const _typeWords = <NoteType, List<String>>{
    NoteType.photo: ['photo', 'photos', 'picture', 'image', 'عکس', 'تصویر'],
    NoteType.voice: ['voice', 'audio', 'recording', 'صدا', 'صوتی', 'ضبط'],
    NoteType.link: ['link', 'links', 'url', 'لینک', 'پیوند'],
    NoteType.file: ['file', 'files', 'document', 'pdf', 'فایل', 'سند'],
    NoteType.checklist: ['checklist', 'todo', 'list', 'چک‌لیست', 'فهرست'],
  };

  /// The note types [query] names in words.
  static Set<NoteType> typesNamedIn(String query) {
    final words = query
        .toLowerCase()
        .split(RegExp(r'[\s,.;:!?،؛]+'))
        .where((w) => w.isNotEmpty)
        .toSet();
    return {
      for (final entry in _typeWords.entries)
        if (entry.value.any(words.contains)) entry.key,
    };
  }

  /// [keyword] and [semantic] as ids, best first; [facts] for every id in
  /// either. Returns ids, best first. Ids missing from [facts] are dropped:
  /// they are notes the filters or a deletion already excluded.
  static List<String> fuse({
    required List<String> keyword,
    required List<String> semantic,
    required Map<String, FusionFacts> facts,
    required DateTime now,
    String query = '',
  }) {
    final scores = <String, double>{};
    // Where each note first appeared, keyword list first: the last word on a
    // tie, so equal scores keep the order the lists gave them rather than
    // whatever an unstable sort leaves.
    final seen = <String, int>{};
    void add(List<String> ranked) {
      for (var i = 0; i < ranked.length; i++) {
        final id = ranked[i];
        if (!facts.containsKey(id)) continue;
        scores[id] = (scores[id] ?? 0) + 1 / (k + i + 1);
        seen.putIfAbsent(id, () => seen.length);
      }
    }

    add(keyword);
    add(semantic);
    final named = typesNamedIn(query);
    final halfLifeDays = recencyHalfLife.inHours / 24;
    for (final id in scores.keys.toList()) {
      final fact = facts[id]!;
      final ageDays = now.difference(fact.createdAt).inHours / 24;
      var score = scores[id]!;
      score +=
          recencyWeight *
          math.pow(0.5, ageDays < 0 ? 0 : ageDays / halfLifeDays);
      if (named.contains(fact.type)) score += typeWeight;
      if (fact.pinned) score += pinnedWeight;
      scores[id] = score;
    }
    final ordered = scores.keys.toList()
      ..sort((a, b) {
        final byScore = scores[b]!.compareTo(scores[a]!);
        if (byScore != 0) return byScore;
        final byDate = facts[b]!.createdAt.compareTo(facts[a]!.createdAt);
        if (byDate != 0) return byDate;
        return seen[a]!.compareTo(seen[b]!);
      });
    return ordered;
  }
}
