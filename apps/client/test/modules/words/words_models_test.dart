import 'package:flutter_test/flutter_test.dart';

import 'package:nex_client/modules/words/words_models.dart';

/// The card record: round-trips through the store's JSON, survives
/// half-empty and corrupt records, folds whitespace, warns on
/// duplication, and keeps its history capped.
void main() {
  WordCard example() => const WordCard(
    id: 'c1',
    headword: 'serendipity',
    language: 'English',
    meaning: 'یک یافتن خوش‌سُرپرست',
    example: 'The best things in my life came by serendipity.',
    note: 'from a podcast',
    tag: 'books',
    createdAtIso: '2026-10-01T10:00:00',
    step: 2,
    due: '2026-10-19',
    lapses: 1,
    reps: 4,
    lastReviewIso: '2026-10-12T09:00:00',
    log: [
      (at: '2026-10-02T09:00:00', grade: WordsGrade.good),
      (at: '2026-10-05T09:00:00', grade: WordsGrade.hard),
      (at: '2026-10-08T09:00:00', grade: WordsGrade.again),
      (at: '2026-10-12T09:00:00', grade: WordsGrade.good),
    ],
  );

  test('a card round-trips through record JSON unchanged', () {
    final back = WordCard.fromRecord('c1', example().toRecord());
    expect(back.id, 'c1');
    expect(back.headword, 'serendipity');
    expect(back.language, 'English');
    expect(back.meaning, 'یک یافتن خوش‌سُرپرست');
    expect(back.example, 'The best things in my life came by serendipity.');
    expect(back.note, 'from a podcast');
    expect(back.tag, 'books');
    expect(back.step, 2);
    expect(back.due, '2026-10-19');
    expect(back.lapses, 1);
    expect(back.reps, 4);
    expect(back.lastReviewIso, '2026-10-12T09:00:00');
    expect(back.log, hasLength(4));
    expect(back.log.last, (at: '2026-10-12T09:00:00', grade: WordsGrade.good));
    expect(back.paused, isFalse);
    expect(back.isNew, isFalse);
  });

  test('the record holds only what JSON holds', () {
    final record = example().toRecord();
    for (final value in record.values) {
      expect(
        value is String || value is num || value is bool || value is List,
        isTrue,
      );
    }
    for (final entry in record['log']! as List<Object?>) {
      expect(entry, isA<Map<String, Object?>>());
    }
  });

  test('an empty record reads as a brand-new card, never as a crash', () {
    final card = WordCard.fromRecord('x', const {});
    expect(card.headword, '');
    expect(card.step, 0);
    expect(card.due, '');
    expect(card.lapses, 0);
    expect(card.reps, 0);
    expect(card.log, isEmpty);
    expect(card.paused, isFalse);
    expect(card.isNew, isTrue);
  });

  test('old or nonsense fields default one at a time', () {
    final card = WordCard.fromRecord('x', {
      'headword': '  hello   world  ', // folded, not just trimmed
      'step': 99, // out of range → clamped to the ladder top
      'lapses': -3, // negative → zero
      'due': '2026-02-30', // a day that does not exist → not due
      'paused': 'yes', // not a bool → false
      'log': [
        'not a map',
        {'g': 'whatever', 'at': '2026-10-12T10:00:00'}, // unknown grade
        {'g': 'easy'}, // no timestamp → dropped
      ],
      'schema': 'one',
    });
    expect(card.headword, 'hello world');
    expect(card.step, 5);
    expect(card.lapses, 0);
    expect(card.due, '');
    expect(card.paused, isFalse);
    // The unreadable log entries are gone; the readable one stays.
    expect(card.log, hasLength(1));
    expect(card.log.single.grade, WordsGrade.good);
    expect(card.isNew, isFalse);
  });

  test('whitespace is folded, not merely trimmed', () {
    expect(
      foldWhitespace('  the  quick\tfox\njumped  '),
      'the quick fox jumped',
    );
    final card = WordCard.fromRecord('x', {
      'headword': '  multiple   spaces  ',
      'tag': ' book : something ',
    });
    expect(card.headword, 'multiple spaces');
    expect(card.tag, 'book : something');
  });

  group('duplication is a question, not a silent merge', () {
    final saved = example();

    test('the same word and language matches', () {
      final candidate = const WordCard(
        id: 'c2',
        headword: 'Serendipity ',
        language: 'english',
        createdAtIso: '2026-10-02T10:00:00',
      );
      expect(saved.sameWordAs(candidate), isTrue);
    });

    test('a different language is a different word', () {
      final candidate = WordCard.fromRecord(
        'c2',
        example().toRecord()..['language'] = 'French',
      );
      expect(saved.sameWordAs(candidate), isFalse);
    });

    test('a different headword is a different word', () {
      final candidate = WordCard.fromRecord(
        'c2',
        example().toRecord()..['headword'] = 'zephyr',
      );
      expect(saved.sameWordAs(candidate), isFalse);
    });

    test('a card never matches itself', () {
      expect(saved.sameWordAs(saved), isFalse);
    });
  });

  test('the log is capped when the record is rebuilt', () {
    final entries = <({String at, WordsGrade grade})>[
      for (var i = 0; i < 250; i++)
        (
          at: '2026-10-${((i % 28) + 1).toString().padLeft(2, '0')}T09:00:00',
          grade: WordsGrade.good,
        ),
    ];
    // A record written with an over-long log keeps its newest tail.
    final record = example().copyWith(log: entries).toRecord();
    final back = WordCard.fromRecord('c1', record);
    expect(back.log.length, WordCard.maxLog);
    expect(back.log.last.at, entries.last.at);
  });

  test('settings default to ten a day and survive their record', () {
    expect(const WordsSettings(newPerDay: 10).toRecord()['newPerDay'], 10);
    expect(WordsSettings.fromRecord(const {}).newPerDay, 10);
    expect(
      WordsSettings.fromRecord({'newPerDay': -5}).newPerDay,
      10, // corrupt negative settings keep the bounded default
    );
    expect(WordsSettings.fromRecord({'newPerDay': 'ten'}).newPerDay, 10);
  });
}
