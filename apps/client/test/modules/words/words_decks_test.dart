import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/words/words_batch_parse.dart';
import 'package:nex_client/modules/words/words_decks.dart';
import 'package:nex_client/modules/words/words_models.dart';
import 'package:nex_client/modules/words/words_screen.dart';
import 'package:nex_client/modules/words/words_store.dart';

import '../../support/nex_harness.dart';

/// 2.8.4: decks (and the separators a pasted list may use). A deck that is
/// removed takes no word with it, and a word can sit outside every deck.
void main() {
  late NexTestHarness harness;
  late NexModuleStore store;
  late WordsRepository repository;

  setUp(() async {
    harness = await NexTestHarness.create(name: 'words_decks_');
    store = NexModuleStore(harness.services, 'words');
    repository = WordsRepository(store);
  });

  tearDown(() => harness.dispose());

  Future<WordCard?> word(String headword, {String deckId = ''}) async {
    final card = await repository.newCard(
      headword: headword,
      language: 'English',
      meaning: 'meaning of $headword',
      deckId: deckId,
    );
    return await repository.saveCard(card) ? card : null;
  }

  group('decks', () {
    test('a deck is made once, whatever the case of its name', () async {
      final first = await repository.createDeck('  The Little   Prince ');
      final again = await repository.createDeck('the little prince');
      expect(first!.name, 'The Little Prince');
      expect(again!.id, first.id);
      expect(await repository.loadDecks(), hasLength(1));
    });

    test('an empty name makes nothing', () async {
      expect(await repository.createDeck('   '), isNull);
      expect(await repository.loadDecks(), isEmpty);
    });

    test('a deck is renamed without touching its words', () async {
      final deck = await repository.createDeck('Reading');
      final saved = await word('zephyr', deckId: deck!.id);
      expect(await repository.renameDeck(deck.id, 'Books'), isTrue);
      final decks = await repository.loadDecks();
      expect(decks.single.name, 'Books');
      final body = await store.get('card', saved!.id);
      expect(body!['deckId'], deck.id);
      expect(body['headword'], 'zephyr');
    });

    test('removing a deck keeps its words, without a deck', () async {
      final deck = await repository.createDeck('Reading');
      final inside = await word('zephyr', deckId: deck!.id);
      final outside = await word('harbor');
      expect(await repository.deleteDeck(deck.id), isTrue);
      expect(await repository.loadDecks(), isEmpty);
      expect((await store.get('card', inside!.id))!['deckId'], '');
      expect(
        (await store.get('card', inside.id))!['meaning'],
        'meaning of zephyr',
      );
      expect((await store.get('card', outside!.id))!['deckId'], '');
      expect(await repository.loadCards(), hasLength(2));
    });

    test('a word moves between decks with its history intact', () async {
      final deck = await repository.createDeck('Reading');
      final saved = await word('zephyr');
      final graded = await repository.answer(
        saved!,
        WordsGrade.good,
        store.newId(),
      );
      expect(graded.status, WordsAnswerStatus.saved);
      final before = (await store.get('card', saved.id))!;
      expect(await repository.setCardDeck(saved.id, deck!.id), isTrue);
      final after = (await store.get('card', saved.id))!;
      expect(after['deckId'], deck.id);
      for (final field in ['reps', 'step', 'due', 'lastReview', 'log']) {
        expect(after[field], before[field], reason: field);
      }
    });

    test('the helper counts and names what is in each deck', () async {
      final reading = await repository.createDeck('Reading');
      final saved = await word('zephyr', deckId: reading!.id);
      final loose = await word('harbor');
      final cards = await repository.loadCards();
      expect(wordsInDeck(cards, reading.id), 1);
      expect(wordsInDeck(cards, ''), 1);
      expect(wordsDeckName([reading], reading.id), 'Reading');
      expect(wordsDeckName([reading], 'gone'), isNull);
      expect(wordsDeckName([reading], ''), isNull);
      expect(
        sortDecks([
          const WordsDeck(id: 'b', name: 'travel'),
          const WordsDeck(id: 'a', name: 'Books'),
        ]).map((deck) => deck.name),
        ['Books', 'travel'],
      );
      expect(saved, isNotNull);
      expect(loose, isNotNull);
    });

    testWidgets('the home list narrows to a deck and back', (tester) async {
      final reading = await repository.createDeck('Reading');
      await word('zephyr', deckId: reading!.id);
      await word('harbor');
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: WordsScreen(store: store),
        ),
      );
      await tester.pumpAndSettle();
      // The newest word is the first row; the other one is further down
      // the list, past the fold of the test's window.
      expect(find.text('harbor'), findsOneWidget);

      await tester.tap(find.byKey(ValueKey('words-deck-chip-${reading.id}')));
      await tester.pumpAndSettle();
      // Only the deck's word is left, so it leads the list.
      expect(find.text('zephyr'), findsOneWidget);
      expect(find.text('harbor'), findsNothing);

      // The same chip again lets the whole collection back in.
      await tester.tap(find.byKey(ValueKey('words-deck-chip-${reading.id}')));
      await tester.pumpAndSettle();
      expect(find.text('harbor'), findsOneWidget);
    });
  });

  group('a pasted list', () {
    ({List<WordsBatchLine> entries, int duplicates}) parse(String text) =>
        parseWordsBatch(text);

    test('a Tab still separates the word from its meaning', () {
      final parsed = parse('zephyr\ta soft west wind');
      expect(parsed.entries.single.word, 'zephyr');
      expect(parsed.entries.single.meaning, 'a soft west wind');
    });

    test('a dash, a colon and an equal sign separate too', () {
      final parsed = parse(
        'zephyr - a soft west wind\n'
        'harbor: a sheltered port\n'
        'rest = to stop and be still',
      );
      expect(parsed.entries.map((e) => e.word), ['zephyr', 'harbor', 'rest']);
      expect(parsed.entries.map((e) => e.meaning), [
        'a soft west wind',
        'a sheltered port',
        'to stop and be still',
      ]);
    });

    test('an en dash or an em dash separates as well', () {
      final parsed = parse('zephyr – a soft wind\nharbor — a port');
      expect(parsed.entries.map((e) => e.meaning), ['a soft wind', 'a port']);
    });

    test('a hyphen inside a word is not a separator', () {
      final parsed = parse('well-being\nmother-in-law');
      expect(parsed.entries.map((e) => e.word), [
        'well-being',
        'mother-in-law',
      ]);
      expect(parsed.entries.every((e) => e.meaning.isEmpty), isTrue);
    });

    test('a colon inside a time or a link is not a separator', () {
      final parsed = parse('10:30\nhttps://example.com');
      expect(parsed.entries.map((e) => e.word), [
        '10:30',
        'https://example.com',
      ]);
    });

    test('the first separator wins, so a meaning keeps its own colons', () {
      final parsed = parse('harbor: a port: a safe place');
      expect(parsed.entries.single.word, 'harbor');
      expect(parsed.entries.single.meaning, 'a port: a safe place');
    });

    test('repeated and blank lines are counted, not added', () {
      final parsed = parse('zephyr - wind\n\nZEPHYR - wind again\nharbor');
      expect(parsed.entries.map((e) => e.word), ['zephyr', 'harbor']);
      expect(parsed.duplicates, 1);
    });
  });
}
