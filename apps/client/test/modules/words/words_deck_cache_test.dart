import 'package:flutter_test/flutter_test.dart';
import 'package:nex_data/nex_data.dart' show ModuleRecord;
import 'package:nex_client/modules/words/words_deck_cache.dart';

/// The deck parse cache: an unchanged record's card is parsed once, a record
/// whose stamp moved is parsed again, and nothing the deck no longer names
/// is kept. These pin the property the resume path leans on — a deck that
/// did not change costs no parse — without which every launch and every
/// return would re-parse the whole deck for nothing.
void main() {
  ModuleRecord record(
    String id, {
    Map<String, Object?> body = const {},
    DateTime? updatedAt,
  }) => ModuleRecord(
    module: 'words',
    kind: 'card',
    id: id,
    body: {
      'schema': 2,
      'headword': id,
      'language': 'English',
      'meaning': 'meaning of $id',
      'createdAt': '2026-10-01T09:00:00',
      ...body,
    },
    updatedAt: updatedAt ?? DateTime.utc(2026, 11, 1, 9),
  );

  setUp(() {
    // The cache is a module-level store, like the deck it serves: each test
    // starts with it empty so one test's deck is not another's cache.
    debugWordsDeckCache.clear();
  });

  test('an unchanged deck is not re-parsed', () {
    final records = [
      for (var i = 0; i < 50; i++) record('c$i', body: {'step': i % 5}),
    ];
    final first = wordsCardsFromRecords(records);
    expect(first.length, 50);
    final second = wordsCardsFromRecords(records);
    // The same card objects, not fresh parses of the same records.
    for (var i = 0; i < first.length; i++) {
      expect(identical(first[i], second[i]), isTrue, reason: 'card $i');
    }
  });

  test('a record whose stamp moved is parsed again', () {
    final base = record('moved', body: {'headword': 'before'});
    final before = wordsCardsFromRecords([base]).single;
    expect(before.headword, 'before');
    final edited = record(
      'moved',
      body: {'headword': 'after'},
      // Saved: a new stamp, the way the storage layer writes one on every put.
      updatedAt: DateTime.utc(2026, 11, 2, 10),
    );
    final after = wordsCardsFromRecords([edited]).single;
    expect(after.headword, 'after');
    expect(identical(before, after), isFalse);
    // And it is the new one that stands cached now.
    final again = wordsCardsFromRecords([edited]).single;
    expect(identical(after, again), isTrue);
  });

  test('a record that only changed order is not re-parsed', () {
    final records = [record('a'), record('b'), record('c')];
    final first = wordsCardsFromRecords(records);
    // Newest-first reshuffles on every save; the deck's contents did not.
    final reordered = [records[2], records[0], records[1]];
    final second = wordsCardsFromRecords(reordered);
    expect(second.map((c) => c.id), ['c', 'a', 'b']);
    expect(identical(first[0], second[1]), isTrue);
    expect(identical(first[1], second[2]), isTrue);
    expect(identical(first[2], second[0]), isTrue);
  });

  test('a deleted record\'s cache entry is reaped on a clean pass', () {
    final records = [record('stay'), record('go')];
    wordsCardsFromRecords(records);
    expect(debugWordsDeckCache.containsKey('go'), isTrue);
    final remaining = wordsCardsFromRecords([record('stay')]);
    expect(remaining.single.id, 'stay');
    // Nothing was parsed (the survivor is cached) and the dead id is gone.
    expect(debugWordsDeckCache.containsKey('go'), isFalse);
    expect(debugWordsDeckCache.length, 1);
  });

  test('a deck past the bound parses without caching', () {
    final records = [
      for (var i = 0; i < 4097; i++) record('big$i'),
    ];
    final first = wordsCardsFromRecords(records);
    expect(first.length, 4097);
    expect(debugWordsDeckCache, isEmpty);
    final second = wordsCardsFromRecords(records);
    expect(second.length, 4097);
    // Distinct parses, not a shared cache that was promised not to grow.
    expect(identical(first.first, second.first), isFalse);
  });
}
