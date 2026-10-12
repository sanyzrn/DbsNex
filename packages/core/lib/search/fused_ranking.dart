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
/// most similar first) give one list in two tiers:
///
/// 1. **The notes that contain the words**, in the keyword order. A note
///    that has what was typed is the surest answer there is, and it stays
///    where the first, instant results put it: the list no longer jumps when
///    the meaning search answers a moment later.
/// 2. **Then the notes found only by meaning**, best first, and only a few
///    of them ([meaningOnlyWithWords] under keyword results,
///    [meaningOnlyAlone] when the words found nothing).
///
/// This replaced reciprocal-rank fusion of the two lists. RRF scores a
/// list's first place the same whichever list it is in, so a note that
/// merely resembled the query sat level with the best keyword match and
/// above every keyword match after it — and a meaning search answers for
/// every query, near or not, so the notes that actually held the words were
/// pushed down the list by ones that did not (the owner's report, 1.99.80).
///
/// Within a tier, two small nudges settle near-ties, each worth a place or
/// two and never more:
///
/// - **Recency.** Of two equally good matches, the newer is more likely the
///   one being looked for; the nudge halves every [recencyHalfLife].
/// - **Type.** A query that names a kind of note — "photo", "voice", "لینک" —
///   without the `type:` filter prefers that kind instead of requiring it.
///   Pinned notes get the same small preference.
class FusedRanking {
  const FusedRanking._();

  /// The rank constant: large enough that rank 1 and rank 2 are not worlds
  /// apart, so the nudges below can settle a near-tie between them.
  static const k = 60;

  /// Sized against the gap between neighbouring places at the top
  /// (1/61 − 1/62 ≈ 0.00026): a few places at most. It used to be 0.004,
  /// worth ten places, and a newer note with one passing mention climbed
  /// over older notes that were about the query.
  static const recencyWeight = 0.0008;
  static const recencyHalfLife = Duration(days: 60);
  static const typeWeight = 0.003;
  static const pinnedWeight = 0.0005;

  /// How many notes found only by meaning follow the keyword results.
  static const meaningOnlyWithWords = 5;

  /// And how many make the list when the words found nothing.
  static const meaningOnlyAlone = 12;

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
    final named = typesNamedIn(query);
    final halfLifeDays = recencyHalfLife.inHours / 24;

    // One tier: its own order, nudged.
    List<String> rank(List<String> ids) {
      final scores = <String, double>{};
      final seen = <String, int>{};
      for (var i = 0; i < ids.length; i++) {
        final id = ids[i];
        if (!facts.containsKey(id) || scores.containsKey(id)) continue;
        final fact = facts[id]!;
        final ageDays = now.difference(fact.createdAt).inHours / 24;
        var score = 1 / (k + i + 1);
        score +=
            recencyWeight *
            math.pow(0.5, ageDays < 0 ? 0 : ageDays / halfLifeDays);
        if (named.contains(fact.type)) score += typeWeight;
        if (fact.pinned) score += pinnedWeight;
        scores[id] = score;
        seen[id] = i;
      }
      return scores.keys.toList()..sort((a, b) {
        final byScore = scores[b]!.compareTo(scores[a]!);
        if (byScore != 0) return byScore;
        final byDate = facts[b]!.createdAt.compareTo(facts[a]!.createdAt);
        if (byDate != 0) return byDate;
        return seen[a]!.compareTo(seen[b]!);
      });
    }

    final byWords = rank(keyword);
    final found = byWords.toSet();
    final byMeaning = rank([
      for (final id in semantic)
        if (!found.contains(id)) id,
    ]).take(byWords.isEmpty ? meaningOnlyAlone : meaningOnlyWithWords);
    return [...byWords, ...byMeaning];
  }
}
