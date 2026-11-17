import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/words/words_models.dart';
import 'package:nex_client/modules/words/words_practice.dart';

/// 2.8.4: practice that teaches. Forgiving matching, choices drawn from the
/// same deck, the daily goal and the week — all plain functions, so each
/// rule is held on its own.
void main() {
  WordCard card(
    String id, {
    String headword = 'resilient',
    String meaning = 'able to recover',
    String deckId = '',
    String due = '',
    int step = 0,
    int reps = 0,
    String language = 'English',
    List<({String at, WordsGrade grade})> log = const [],
    bool paused = false,
  }) => WordCard.fromRecord(id, {
    'schema': 2,
    'headword': headword,
    'language': language,
    'meaning': meaning,
    'createdAt': '2026-11-01T09:00:00',
    'step': step,
    'reps': reps,
    if (due.isNotEmpty) 'due': due,
    'paused': paused,
    'deckId': deckId,
    'log': [
      for (final entry in log) {'at': entry.at, 'g': entry.grade.name},
    ],
  });

  group('forgiving matching', () {
    test('case, spacing and punctuation do not matter', () {
      expect(
        wordsAnswerMatches('  Able   To Recover. ', 'able to recover'),
        isTrue,
      );
      expect(wordsAnswerMatches('able-to-recover', 'able to recover'), isTrue);
    });

    test('the Persian and Arabic forms of ی and ک are one letter', () {
      // «کتاب» typed with the Arabic kaf, «سازی» with the Arabic yeh.
      expect(wordsAnswerMatches('كتاب', 'کتاب'), isTrue);
      expect(wordsAnswerMatches('سازي', 'سازی'), isTrue);
    });

    test('harakat and the zero-width non-joiner are forgiven', () {
      expect(wordsAnswerMatches('میروم', 'می‌روم'), isTrue);
      expect(wordsAnswerMatches('كَتَبَ', 'کتب'), isTrue);
    });

    test('Persian and Arabic digits read as the same digits', () {
      expect(wordsAnswerMatches('۳', '3'), isTrue);
      expect(wordsAnswerMatches('٢', '۲'), isTrue);
    });

    test('any sense of a multi-line meaning is right', () {
      const meaning = 'a happy accident\nluck that finds you';
      expect(wordsAnswerMatches('luck that finds you', meaning), isTrue);
      expect(wordsAnswerMatches('A HAPPY ACCIDENT', meaning), isTrue);
      expect(wordsAnswerMatches('luck', meaning), isFalse);
    });

    test('an empty answer is never right', () {
      expect(wordsAnswerMatches('   ', 'able to recover'), isFalse);
      expect(wordsAnswerMatches('', ''), isFalse);
    });

    test('the prompt and the answer swap with the direction', () {
      final due = card('a', meaning: 'تاب‌آور');
      expect(wordsPromptOf(due, reverse: false), 'resilient');
      expect(wordsAnswerOf(due, reverse: false), 'تاب‌آور');
      expect(wordsPromptOf(due, reverse: true), 'تاب‌آور');
      expect(wordsAnswerOf(due, reverse: true), 'resilient');
    });

    test('a card with no meaning always asks forward', () {
      final blank = card('b', meaning: '');
      expect(wordsPromptOf(blank, reverse: true), 'resilient');
      expect(wordsChoices(blank, [blank], reverse: false), isEmpty);
    });
  });

  group('choices', () {
    final mine = card('mine', meaning: 'able to recover', deckId: 'book');
    final sameDeck = [
      card('d1', headword: 'serene', meaning: 'calm', deckId: 'book'),
      card(
        'd2',
        headword: 'frugal',
        meaning: 'careful with money',
        deckId: 'book',
      ),
      card('d3', headword: 'terse', meaning: 'short in speech', deckId: 'book'),
      card(
        'd4',
        headword: 'vivid',
        meaning: 'bright and clear',
        deckId: 'book',
      ),
    ];
    final elsewhere = [
      card('o1', headword: 'lucid', meaning: 'easy to follow', deckId: 'trip'),
    ];

    test('the right answer is there, once, with wrong ones beside it', () {
      final choices = wordsChoices(mine, [
        ...sameDeck,
        ...elsewhere,
      ], reverse: false);
      expect(choices, hasLength(4));
      expect(choices.where((c) => c == 'able to recover'), hasLength(1));
      expect(choices.toSet(), hasLength(4));
    });

    test('wrong choices come from the same deck first', () {
      final choices = wordsChoices(mine, [
        ...sameDeck,
        ...elsewhere,
      ], reverse: false);
      final fromOther = choices.where((c) => c == 'easy to follow');
      expect(fromOther, isEmpty);
    });

    test('a deck with too few words borrows from the rest', () {
      final choices = wordsChoices(mine, [
        sameDeck.first,
        ...elsewhere,
      ], reverse: false);
      expect(choices, hasLength(3));
      expect(choices, contains('easy to follow'));
    });

    test('the same card shows the same choices every time', () {
      final pool = [...sameDeck, ...elsewhere];
      expect(
        wordsChoices(mine, pool, reverse: false, salt: 2),
        wordsChoices(mine, pool, reverse: false, salt: 2),
      );
    });

    test('asked backwards the choices are words, not meanings', () {
      final choices = wordsChoices(mine, sameDeck, reverse: true);
      expect(choices, contains('resilient'));
      expect(choices, contains('serene'));
      expect(choices, isNot(contains('calm')));
    });

    test('a paused word is never offered as a wrong choice', () {
      final choices = wordsChoices(mine, [
        card('p', headword: 'hidden', meaning: 'x', paused: true),
      ], reverse: false);
      expect(choices, ['able to recover']);
    });
  });

  group('the daily goal and the week', () {
    final today = DateTime(2026, 11, 17, 12);
    List<({String at, WordsGrade grade})> logOn(
      DateTime when,
      List<WordsGrade> grades,
    ) => [
      for (final grade in grades)
        (
          at: DateTime(
            when.year,
            when.month,
            when.day,
            9,
            grades.indexOf(grade),
          ).toIso8601String(),
          grade: grade,
        ),
    ];

    test('answers are counted by the local day they were given', () {
      final cards = [
        card(
          'a',
          reps: 3,
          log: logOn(today, [WordsGrade.good, WordsGrade.again]),
        ),
        card(
          'b',
          reps: 1,
          log: logOn(today.subtract(const Duration(days: 1)), [
            WordsGrade.good,
          ]),
        ),
      ];
      expect(wordsReviewsOn(cards, '2026-11-17'), 2);
      expect(wordsReviewsOn(cards, '2026-11-16'), 1);
      expect(wordsReviewsOn(cards, '2026-11-01'), 0);
    });

    test('a week is seven days ending today, oldest first', () {
      final cards = [
        card(
          'a',
          reps: 2,
          log: logOn(today, [WordsGrade.good, WordsGrade.again]),
        ),
        card(
          'b',
          reps: 1,
          log: logOn(today.subtract(const Duration(days: 6)), [
            WordsGrade.hard,
          ]),
        ),
        card(
          'c',
          reps: 1,
          log: logOn(today.subtract(const Duration(days: 8)), [
            WordsGrade.good,
          ]),
        ),
      ];
      final week = wordsWeek(cards, today);
      expect(week, hasLength(7));
      expect(week.first.iso, '2026-11-11');
      expect(week.last.iso, '2026-11-17');
      expect(week.last.reviews, 2);
      expect(week.last.again, 1);
      expect(week.fold(0, (sum, day) => sum + day.reviews), 3);
      // The answer from eight days ago is in no bar of this week.
      expect(week.every((day) => day.iso != '2026-11-09'), isTrue);
    });

    test('the summary counts learned, due and paused honestly', () {
      final cards = [
        card(
          'learned',
          step: 5,
          reps: 9,
          due: '2026-12-01',
          log: logOn(today, [WordsGrade.easy]),
        ),
        card(
          'due',
          step: 2,
          reps: 4,
          due: '2026-11-16',
          log: logOn(today, [WordsGrade.again]),
        ),
        card('later', step: 1, reps: 2, due: '2026-11-25'),
        card('paused', step: 3, reps: 2, due: '2026-11-01', paused: true),
        card('new'),
      ];
      final summary = wordsProgressSummary(
        cards,
        todayIso: '2026-11-17',
        today: today,
      );
      expect(summary.total, 5);
      expect(summary.learned, 1);
      // The overdue card counts as due; the paused and the new ones do not,
      // and neither does one due later in the month.
      expect(summary.due, 1);
      expect(summary.paused, 1);
      expect(summary.reviews, 2);
      expect(summary.again, 1);
    });

    test('an empty collection is a calm zero, not a division by zero', () {
      final summary = wordsProgressSummary(
        const [],
        todayIso: '2026-11-17',
        today: today,
      );
      expect(summary.total, 0);
      expect(summary.learned, 0);
      expect(summary.due, 0);
      expect(summary.reviews, 0);
      expect(wordsWeek(const [], today), hasLength(7));
    });
  });
}
