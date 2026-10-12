import 'package:nex_core/nex_core.dart';
import 'package:test/test.dart';

/// W2.2: one list from keyword and meaning search.
void main() {
  final now = DateTime.utc(2026, 9, 30);
  FusionFacts fact({
    int daysAgo = 0,
    NoteType type = NoteType.text,
    bool pinned = false,
  }) => FusionFacts(
    createdAt: now.subtract(Duration(days: daysAgo)),
    type: type,
    pinned: pinned,
  );

  test('the notes with the words come first, in their order, then meaning', () {
    final ranked = FusedRanking.fuse(
      keyword: ['a', 'b'],
      semantic: ['c', 'b'],
      facts: {'a': fact(), 'b': fact(), 'c': fact()},
      now: now,
    );
    // `c` resembles the query more than `a` does, by the meaning search's
    // account; `a` has the words, and words win.
    expect(ranked, ['a', 'b', 'c']);
  });

  test('only a few notes found by meaning alone join the list', () {
    final meaning = [for (var i = 0; i < 30; i++) 'm$i'];
    final facts = {'a': fact(), for (final id in meaning) id: fact()};
    final withWords = FusedRanking.fuse(
      keyword: ['a'],
      semantic: meaning,
      facts: facts,
      now: now,
    );
    expect(withWords.first, 'a');
    expect(withWords, hasLength(1 + FusedRanking.meaningOnlyWithWords));
    expect(withWords.skip(1).take(2), ['m0', 'm1'], reason: 'best first');

    final alone = FusedRanking.fuse(
      keyword: const [],
      semantic: meaning,
      facts: facts,
      now: now,
    );
    expect(alone, hasLength(FusedRanking.meaningOnlyAlone));
  });

  test('a newer note moves a place or two, never ten', () {
    final ranked = FusedRanking.fuse(
      keyword: [for (var i = 0; i < 10; i++) 'x$i', 'new'],
      semantic: const [],
      facts: {
        for (var i = 0; i < 10; i++) 'x$i': fact(daysAgo: 400),
        'new': fact(),
      },
      now: now,
    );
    expect(ranked.indexOf('new'), greaterThan(6));
    expect(ranked.first, 'x0');
  });

  test('recency only settles near-ties; it never lifts a weak match', () {
    final close = FusedRanking.fuse(
      keyword: ['old', 'new'],
      semantic: const [],
      facts: {'old': fact(daysAgo: 400), 'new': fact()},
      now: now,
    );
    expect(close, ['new', 'old']);

    final far = FusedRanking.fuse(
      keyword: ['old', for (var i = 0; i < 30; i++) 'x$i', 'new'],
      semantic: const [],
      facts: {
        'old': fact(daysAgo: 400),
        'new': fact(),
        for (var i = 0; i < 30; i++) 'x$i': fact(daysAgo: 400),
      },
      now: now,
    );
    expect(far.first, 'old');
  });

  test('naming a kind of note prefers it, in either language', () {
    expect(FusedRanking.typesNamedIn('receipt photo'), {NoteType.photo});
    expect(FusedRanking.typesNamedIn('عکس رسید'), {NoteType.photo});
    final ranked = FusedRanking.fuse(
      keyword: ['text', 'photo'],
      semantic: const [],
      facts: {
        'text': fact(),
        'photo': fact(type: NoteType.photo),
      },
      now: now,
      query: 'receipt photo',
    );
    expect(ranked.first, 'photo');
  });

  test('ids the filters removed are dropped', () {
    expect(
      FusedRanking.fuse(
        keyword: ['kept'],
        semantic: ['gone'],
        facts: {'kept': fact()},
        now: now,
      ),
      ['kept'],
    );
  });
}
