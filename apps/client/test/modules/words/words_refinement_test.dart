import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/words/words_batch_parse.dart';
import 'package:nex_client/modules/words/words_models.dart';
import 'package:nex_client/modules/words/words_practice.dart';
import 'package:nex_client/modules/words/words_review_page.dart';
import 'package:nex_client/modules/words/words_scheduler.dart';
import 'package:nex_client/modules/words/words_screen.dart';
import 'package:nex_client/modules/words/words_share.dart';
import 'package:nex_client/modules/words/words_store.dart';

import '../../support/nex_harness.dart';

/// The refinement pass: a Persian-aware search, sessions that stay inside
/// the deck the person narrowed to, a skip that means «later», a practice
/// mode that is remembered, the daily goal chosen from the app, one word
/// shared as text — and the settings of an older version still opening.
void main() {
  WordCard card(
    String id,
    String headword, {
    String language = 'English',
    String meaning = '',
    String example = '',
    String note = '',
    String tag = '',
  }) => WordCard(
    id: id,
    headword: headword,
    language: language,
    meaning: meaning,
    example: example,
    note: note,
    tag: tag,
    createdAtIso: '2026-10-01T10:00:00',
  );

  group('search reads the way a Persian reader types', () {
    test('the Arabic and Persian forms of ی and ک are one letter', () {
      final entry = card('1', 'كتاب', language: 'عربي', meaning: 'book');
      expect(wordsMatchesQuery(entry, 'کتاب'), isTrue);
      expect(wordsMatchesQuery(entry, 'كتاب'), isTrue);
    });

    test('a space where the half-space belongs still finds the word', () {
      final entry = card('1', 'میروم', language: 'فارسی', meaning: 'می روم');
      expect(wordsMatchesQuery(entry, 'می روم'), isTrue);
      expect(wordsMatchesQuery(entry, 'می\u200cروم'), isTrue);
    });

    test('harakat and Persian digits are folded', () {
      final entry = card(
        '1',
        'كتابِ من',
        language: 'فارسی',
        meaning: 'صفحه ۱۲',
      );
      expect(wordsMatchesQuery(entry, 'کتاب من'), isTrue);
      expect(wordsMatchesQuery(entry, 'صفحه 12'), isTrue);
      expect(wordsMatchesQuery(entry, 'صفحه ۱۲'), isTrue);
    });

    test('case and punctuation are folded; every field is searched', () {
      final entry = card(
        '1',
        'Resilient',
        meaning: 'Able to recover.',
        note: 'from the first chapter',
        tag: 'Reading',
      );
      expect(wordsMatchesQuery(entry, 'resilient'), isTrue);
      expect(wordsMatchesQuery(entry, 'RECOVER'), isTrue);
      expect(wordsMatchesQuery(entry, 'first chapter'), isTrue);
      expect(wordsMatchesQuery(entry, 'reading'), isTrue);
      expect(wordsMatchesQuery(entry, 'nothing of the sort'), isFalse);
    });

    test('an empty query matches everything', () {
      expect(wordsMatchesQuery(card('1', 'lantern'), '   '), isTrue);
    });
  });

  group('a pasted list takes the language already in use', () {
    test('the most common language wins, with its own spelling', () {
      final cards = [
        card('1', 'a', language: 'English'),
        card('2', 'ب', language: 'فارسی'),
        card('3', 'پ', language: 'فارسی'),
        card('4', 'c', language: ''),
      ];
      expect(wordsSuggestedLanguage(cards), 'فارسی');
      expect(wordsSuggestedLanguage(const []), 'English');
    });
  });

  group('one word as text', () {
    test('word, meaning, example, note and where it belongs', () {
      final entry = card(
        '1',
        'lantern',
        meaning: 'a light to carry',
        example: 'The lantern swayed.',
        note: 'from chapter one',
        tag: 'books',
      );
      expect(
        wordsShareText(entry, deckName: 'The Little Prince'),
        'lantern — a light to carry\nThe lantern swayed.\n'
        'from chapter one\nEnglish · books · The Little Prince',
      );
    });

    test('a word without a meaning or a deck is still a line of text', () {
      expect(wordsShareText(card('1', 'zephyr', language: '')), 'zephyr');
    });
  });

  group('settings', () {
    test('an older record reads with flashcards and the word first', () {
      final settings = WordsSettings.fromRecord({
        'schema': 2,
        'newPerDay': 20,
        'sessionLimit': 40,
      });
      expect(settings.exercise, WordsSettings.defaultExercise);
      expect(settings.reverse, isFalse);
      expect(settings.goalPerDay, WordsSettings.defaultGoalPerDay);
    });

    test('an unknown practice mode falls back instead of failing', () {
      final settings = WordsSettings.fromRecord({'exercise': 'telepathy'});
      expect(settings.exercise, WordsSettings.defaultExercise);
    });

    test('the practice mode and direction round-trip', () {
      const settings = WordsSettings(
        newPerDay: 10,
        exercise: 'choose',
        reverse: true,
      );
      final back = WordsSettings.fromRecord(settings.toRecord());
      expect(back.exercise, 'choose');
      expect(back.reverse, isTrue);
    });
  });

  group('a session inside a deck', () {
    late NexTestHarness harness;
    late NexModuleStore store;
    late WordsRepository repository;
    setUp(() async {
      harness = await NexTestHarness.create(name: 'words_refine_');
      store = NexModuleStore(harness.services, 'words');
      repository = WordsRepository(store);
      await store.put('deck', 'd1', {
        'schema': 1,
        'name': 'The Little Prince',
        'createdAt': '2026-10-01T10:00:00',
      });
      await store.put('deck', 'd2', {
        'schema': 1,
        'name': 'Course',
        'createdAt': '2026-10-01T10:00:00',
      });
    });
    tearDown(() => harness.dispose());

    String day(int offset) {
      final now = DateTime.now();
      final value = DateTime(now.year, now.month, now.day + offset);
      return isoDay(value);
    }

    Map<String, Object?> reviewed(String id, String headword, String deck) => {
      'schema': 2,
      'headword': headword,
      'language': 'English',
      'meaning': 'meaning of $headword',
      'createdAt': '2026-10-01T10:00:00',
      'due': day(-1),
      'reps': 1,
      'lastReview': '2026-10-01T09:00:00',
      'log': [
        {'at': '2026-10-01T09:00:00', 'g': 'good'},
      ],
      'deckId': deck,
    };

    test('only the deck\'s cards are due, and the words outside decks '
        'have a session of their own', () async {
      await store.put('card', 'in1', reviewed('in1', 'alpha', 'd1'));
      await store.put('card', 'in2', reviewed('in2', 'beta', 'd2'));
      await store.put('card', 'free', reviewed('free', 'gamma', ''));
      final scoped = await repository.loadSession(deckId: 'd1');
      expect(scoped.due.map((c) => c.id), ['in1']);
      final outside = await repository.loadSession(deckId: '');
      expect(outside.due.map((c) => c.id), ['free']);
      final all = await repository.loadSession();
      expect(all.due.map((c) => c.id).toSet(), {'in1', 'in2', 'free'});
    });

    test('a deck cannot introduce more words than the day allows', () async {
      await repository.updateSettings(newPerDay: 1);
      // One word was introduced today in another deck.
      final introduced = DateTime.now().toIso8601String();
      await store.put('card', 'spent', {
        'schema': 2,
        'headword': 'spent',
        'language': 'English',
        'meaning': 'already counted',
        'createdAt': '2026-10-01T10:00:00',
        'due': day(3),
        'reps': 1,
        'introducedOn': day(0),
        'lastReview': introduced,
        'log': [
          {'at': introduced, 'g': 'good'},
        ],
        'deckId': 'd2',
      });
      await store.put('card', 'fresh', {
        'schema': 2,
        'headword': 'fresh',
        'language': 'English',
        'meaning': 'not met yet',
        'createdAt': '2026-10-02T10:00:00',
        'deckId': 'd1',
      });
      final session = await repository.loadSession(deckId: 'd1');
      expect(session.fresh, isEmpty);
      // Without the scoped count the deck would have introduced it again.
      expect(
        buildSession(
          cards: await repository.loadCards(),
          todayIso: day(0),
          newPerDay: 1,
        ).fresh,
        isEmpty,
      );
    });
  });

  group('on screen', () {
    late NexTestHarness harness;
    setUp(() async {
      harness = await NexTestHarness.create(name: 'words_refine_ui_');
    });
    tearDown(() => harness.dispose());

    NexModuleStore store() => NexModuleStore(harness.services, 'words');

    Widget host(Widget home, {Locale locale = const Locale('en')}) =>
        MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: home,
        );

    String day(int offset) {
      final now = DateTime.now();
      return isoDay(DateTime(now.year, now.month, now.day + offset));
    }

    Map<String, Object?> due(String headword, {String deck = ''}) => {
      'schema': 2,
      'headword': headword,
      'language': 'English',
      'meaning': 'meaning of $headword',
      'createdAt': '2026-10-01T10:00:00',
      'due': day(-1),
      'reps': 1,
      'lastReview': '2026-10-01T09:00:00',
      'log': [
        {'at': '2026-10-01T09:00:00', 'g': 'good'},
      ],
      'deckId': deck,
    };

    testWidgets('the deck a person narrowed to is the deck reviewed', (
      tester,
    ) async {
      final inner = store();
      await inner.put('deck', 'd1', {
        'schema': 1,
        'name': 'The Little Prince',
        'createdAt': '2026-10-01T10:00:00',
      });
      await inner.put('card', 'in', due('inside', deck: 'd1'));
      await inner.put('card', 'out', due('outside'));

      await tester.pumpWidget(host(WordsScreen(store: inner)));
      await tester.pumpAndSettle();
      expect(find.text('2 due now · 0 new today'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('words-deck-chip-d1')));
      await tester.pumpAndSettle();
      expect(find.text('1 due now · 0 new today'), findsOneWidget);
      expect(find.text('outside'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('words-start-review')));
      await tester.pumpAndSettle();
      expect(find.text('Review · The Little Prince'), findsOneWidget);
      expect(find.text('inside'), findsOneWidget);
      expect(find.text('1 of 1'), findsOneWidget);
    });

    testWidgets('a skipped card comes back before the sitting ends', (
      tester,
    ) async {
      final inner = store();
      await inner.put('card', 'a', due('alpha'));
      await inner.put('card', 'b', due('beta'));
      await tester.pumpWidget(host(WordsReviewPage(store: inner)));
      await tester.pumpAndSettle();
      expect(find.text('alpha'), findsOneWidget);

      // The first skip defers it to the end of the sitting…
      await tester.tap(find.byKey(const ValueKey('words-review-skip')));
      await tester.pumpAndSettle();
      expect(find.text('beta'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('words-review-skip')));
      await tester.pumpAndSettle();
      expect(find.text('alpha'), findsOneWidget);

      // …and answering both ends the session with both counted.
      await tester.tap(find.byKey(const ValueKey('words-review-card')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('words-answer-good')));
      await tester.pumpAndSettle();
      expect(find.text('beta'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('words-review-card')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('words-answer-good')));
      await tester.pumpAndSettle();
      expect(
        find.text('That is the session — 2 cards reviewed.'),
        findsOneWidget,
      );
    });

    testWidgets('a skipped card skipped again is counted, not dropped', (
      tester,
    ) async {
      final inner = store();
      await inner.put('card', 'a', due('alpha'));
      await tester.pumpWidget(host(WordsReviewPage(store: inner)));
      await tester.pumpAndSettle();
      // The only card, skipped: there is nowhere to defer it to, so it is
      // let go — and said, rather than vanishing.
      await tester.tap(find.byKey(const ValueKey('words-review-skip')));
      await tester.pumpAndSettle();
      expect(find.text('No cards were reviewed this time.'), findsOneWidget);
      expect(find.text('1 left for next time'), findsOneWidget);
      // Nothing was graded: the card still has its one earlier review.
      expect((await inner.get('card', 'a'))!['log'], hasLength(1));
    });

    testWidgets('an empty sitting says so instead of counting zero', (
      tester,
    ) async {
      await tester.pumpWidget(host(WordsReviewPage(store: store())));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Nothing to review right now. Words come back on their own days.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('0 cards'), findsNothing);
    });

    testWidgets('the practice mode and direction are remembered', (
      tester,
    ) async {
      final inner = store();
      await inner.put('card', 'a', due('alpha'));
      await tester.pumpWidget(host(WordsReviewPage(store: inner)));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('words-exercise')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('words-exercise-type')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('words-typed-answer')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('words-review-reverse')));
      await tester.pumpAndSettle();
      // Both writes are best-effort in the page; give the database its
      // real moment before reading the settings back.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      final saved = await tester.runAsync(
        () => WordsRepository(inner).loadSettings(),
      );
      expect(saved!.exercise, 'type');
      expect(saved.reverse, isTrue);
    });

    testWidgets('the daily goal is chosen in the review settings', (
      tester,
    ) async {
      final inner = store();
      await inner.put('card', 'a', due('alpha'));
      await tester.pumpWidget(host(WordsScreen(store: inner)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('words-review-settings')));
      await tester.pumpAndSettle();
      expect(find.text('0/10 today'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('words-goal-pick')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('words-goal-20')));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();
      expect(find.text('0/20 today'), findsOneWidget);
      final saved = await tester.runAsync(
        () => WordsRepository(inner).loadSettings(),
      );
      expect(saved!.goalPerDay, 20);
    });

    testWidgets('removing the deck clears the filter that named it', (
      tester,
    ) async {
      final inner = store();
      final repository = WordsRepository(inner);
      final deck = await tester.runAsync(() => repository.createDeck('Trip'));
      await inner.put('card', 'a', due('alpha', deck: deck!.id));
      await tester.pumpWidget(host(WordsScreen(store: inner)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('words-deck-chip-${deck.id}')));
      await tester.pumpAndSettle();
      expect(find.text('1 due now · 0 new today'), findsOneWidget);

      await tester.runAsync(() => repository.deleteDeck(deck.id));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();
      // The chip is gone with the deck, and the list is not left empty by
      // a filter no one can see or clear.
      expect(find.byKey(ValueKey('words-deck-chip-${deck.id}')), findsNothing);
      expect(find.text('alpha'), findsOneWidget);
      expect(find.text('1 due now · 0 new today'), findsOneWidget);
    });

    testWidgets('a saved word can be shared as text', (tester) async {
      final inner = store();
      await inner.put('card', 'a', due('alpha'));
      await tester.pumpWidget(host(WordsScreen(store: inner)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('words-card-a')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('words-card-share')), findsOneWidget);
    });
  });
}
