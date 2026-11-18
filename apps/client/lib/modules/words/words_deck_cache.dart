/// A deck of cards, parsed once per record rather than once per read.
///
/// Every path into Word by Word — the review screen, the module's `dues` on
/// the home screen, the pinned glance, the reminder's re-arm on every launch
/// and every return — reads the whole deck and parses every record, and for
/// a deck of a thousand cards that parse is the better part of a hundred
/// milliseconds of UI-isolate work, on a phone, per resume. The records
/// themselves are unchanged almost all of those times: a deck in review
/// changes one card per answer.
///
/// The cache is keyed by record id and validated by the record's
/// `updated_at` stamp, which the storage layer rewrites on every save — a
/// record's body cannot change without its stamp moving, so the stamp is a
/// sufficient witness that a card parsed from it is still that record. A
/// deleted card's entry simply stops being named and is reaped by the next
/// full pass; nothing needs an invalidation hook.
library;

import 'package:nex_client/modules/module_api.dart';

import 'words_models.dart';

/// How many parsed cards are kept. Decks live far below this; the bound is
/// for a cache that must never grow with the number of distinct records ever
/// seen — only with the deck.
const _wordsDeckCacheLimit = 4096;

final _parsed = <String, ({int stamp, WordCard card})>{};

/// The cards of [records], parsed only for those whose stamp moved since the
/// last time they were parsed here.
///
/// The returned cards are shared, not copies: [WordCard] is immutable, and
/// the whole point is that an unchanged record's parse is not paid twice.
List<WordCard> wordsCardsFromRecords(List<ModuleRecord> records) {
  if (records.length > _wordsDeckCacheLimit) {
    // A deck past the bound is parsed in full without caching this pass,
    // rather than half-cached; decks live far below it, and one rule beats
    // an eviction policy nobody can exercise.
    return [for (final r in records) WordCard.fromRecord(r.id, r.body)];
  }
  final out = <WordCard>[];
  var misses = 0;
  for (final record in records) {
    final stamp = record.updatedAt.toUtc().microsecondsSinceEpoch;
    final cached = _parsed[record.id];
    if (cached != null && cached.stamp == stamp) {
      out.add(cached.card);
      continue;
    }
    final card = WordCard.fromRecord(record.id, record.body);
    _parsed[record.id] = (stamp: stamp, card: card);
    out.add(card);
    misses++;
  }
  // A pass that parsed nothing means the deck is fully cached; anything the
  // cache holds beyond the deck's own ids is a deleted record's leftover,
  // and this is the cheap moment (nothing else to do) to take it out.
  if (misses == 0 && _parsed.length > records.length) {
    final living = {for (final r in records) r.id};
    _parsed.removeWhere((id, _) => !living.contains(id));
  }
  return out;
}

/// The cache as it stands — for tests, to prove what was and was not
/// re-parsed. Nothing outside the words module's own suite should read it.
Map<String, ({int stamp, WordCard card})> get debugWordsDeckCache => _parsed;
