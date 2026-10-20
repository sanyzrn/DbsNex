import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/words/words_batch_parse.dart';
import 'package:nex_client/modules/words/words_models.dart';
import 'package:nex_client/modules/words/words_screen.dart';

import '../../support/nex_harness.dart';

WordCard card(String word, String meaning) => WordCard(
  id: word,
  headword: word,
  language: 'English',
  meaning: meaning,
  createdAtIso: '2026-10-01T10:00:00',
);

void main() {
  group('the copied list is the paste box\'s own format', () {
    test('word, a Tab, the meaning — and back again unchanged', () {
      final text = wordsListText([
        card('lantern', 'a light to carry'),
        card('zephyr', 'a soft west wind'),
      ]);
      expect(text, 'lantern\ta light to carry\nzephyr\ta soft west wind');
      final back = parseWordsBatch(text).entries;
      expect(back.map((e) => (e.word, e.meaning)), [
        ('lantern', 'a light to carry'),
        ('zephyr', 'a soft west wind'),
      ]);
    });

    test(
      'senses on several lines become one line; a Tab inside is a space',
      () {
        final text = wordsListText([
          card('bank', 'river side\nplace\tfor money'),
        ]);
        expect(text, 'bank\triver side ; place for money');
        expect(text.split('\n'), hasLength(1));
      },
    );

    test('a word with no meaning is just the word', () {
      expect(wordsListText([card('solo', '')]), 'solo');
    });
  });

  group('meaning first', () {
    late NexTestHarness harness;
    setUp(() async => harness = await NexTestHarness.create(name: 'wrev_'));
    tearDown(() => harness.dispose());

    Widget host() => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: WordsScreen(store: NexModuleStore(harness.services, 'words')),
    );

    testWidgets('asks the meaning, hides the word until revealed', (
      tester,
    ) async {
      final store = NexModuleStore(harness.services, 'words');
      await store.put('card', 'c1', {
        'schema': 2,
        'headword': 'lantern',
        'language': 'English',
        'meaning': 'a light to carry',
        'createdAt': '2026-10-01T10:00:00',
      });
      await store.put('card', 'c2', {
        'schema': 2,
        'headword': 'blank',
        'language': 'English',
        'createdAt': '2026-10-01T11:00:00',
      });
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('words-start-review')));
      await tester.pumpAndSettle();

      // Forward by default: the word is asked.
      expect(
        find.byKey(const ValueKey('words-review-headword')),
        findsOneWidget,
      );
      expect(find.text('a light to carry'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('words-review-reverse')));
      await tester.pumpAndSettle();
      // Reversed: the meaning is asked, and the word is nowhere in the tree.
      expect(
        find.byKey(const ValueKey('words-review-meaning-first')),
        findsOneWidget,
      );
      expect(find.text('a light to carry'), findsOneWidget);
      expect(find.text('lantern'), findsNothing);
      expect(find.bySemanticsLabel(RegExp('lantern')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('words-review-card')));
      await tester.pumpAndSettle();
      expect(find.text('lantern'), findsOneWidget);
      // Grading still works, once, as before.
      await tester.tap(find.byKey(const ValueKey('words-answer-good')));
      await tester.pumpAndSettle();

      // The next card has no meaning to ask for: it is asked forward.
      expect(
        find.byKey(const ValueKey('words-review-headword')),
        findsOneWidget,
      );
      semantics.dispose();
    });
  });
}
