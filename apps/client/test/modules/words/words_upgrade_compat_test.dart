import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/words/words_models.dart';
import 'package:nex_client/modules/words/words_screen.dart';
import 'package:nex_client/modules/words/words_store.dart';

import '../../support/nex_harness.dart';

/// Live module (2.8.4): everything saved by the version people have today
/// opens, shows and saves exactly as it did. The records below are written
/// in the shape that version writes — no `deckId` on a card, no
/// `goalPerDay` in the settings — and every field, including one this
/// version knows nothing about, has to survive being read, graded and
/// edited.
void main() {
  late NexTestHarness harness;
  late NexModuleStore store;

  setUp(() async {
    harness = await NexTestHarness.create(name: 'words_upgrade_');
    store = NexModuleStore(harness.services, 'words');
  });

  tearDown(() => harness.dispose());

  /// Exactly what 2.8.3 writes for a card that was reviewed once.
  Map<String, Object?> legacyCard() => {
    'schema': 2,
    'headword': 'lantern',
    'language': 'English',
    'meaning': 'a light to carry',
    'example': 'The lantern swayed.',
    'note': 'from the first chapter',
    'tag': 'books',
    'createdAt': '2026-10-13T12:00:00',
    'step': 1,
    'due': '2026-10-16',
    'lapses': 0,
    'reps': 1,
    'lastReview': '2026-10-13T12:05:00',
    'paused': false,
    'introducedOn': '2026-10-13',
    'log': [
      {'at': '2026-10-13T12:05:00', 'g': 'good'},
    ],
    'lastReviewId': 'review-event-id',
    // A field a later version added: this one must write it back untouched.
    'reviewNote': 'keep me',
  };

  test('an old card reads with every field it had', () async {
    await store.put('card', 'w1', legacyCard());
    final cards = await WordsRepository(store).loadCards();
    final card = cards.single;
    expect(card.headword, 'lantern');
    expect(card.language, 'English');
    expect(card.meaning, 'a light to carry');
    expect(card.example, 'The lantern swayed.');
    expect(card.note, 'from the first chapter');
    expect(card.tag, 'books');
    expect(card.step, 1);
    expect(card.reps, 1);
    expect(card.due, '2026-10-16');
    expect(card.introducedOn, '2026-10-13');
    expect(card.log, hasLength(1));
    // No deck was ever chosen, and that is not the same as a lost field.
    expect(card.deckId, '');
  });

  test(
    'the settings people have today open with the goal at its default',
    () async {
      await store.put('settings', 'settings', {
        'schema': 2,
        'newPerDay': 20,
        'sessionLimit': 40,
      });
      final settings = await WordsRepository(store).loadSettings();
      expect(settings.newPerDay, 20);
      expect(settings.sessionLimit, 40);
      expect(settings.goalPerDay, WordsSettings.defaultGoalPerDay);
      // Changing the goal keeps the other two.
      expect(
        await WordsRepository(store).updateSettings(goalPerDay: 5),
        isTrue,
      );
      final after = await WordsRepository(store).loadSettings();
      expect(after.goalPerDay, 5);
      expect(after.newPerDay, 20);
      expect(after.sessionLimit, 40);
    },
  );

  test(
    'grading an old card keeps its history and its unknown fields',
    () async {
      await store.put('card', 'w1', legacyCard());
      final before = WordCard.fromRecord('w1', legacyCard());
      final result = await WordsRepository(store)
          .answer(before, WordsGrade.good, 'new-event');
      expect(result.status, WordsAnswerStatus.saved);
      expect(result.card!.reps, 2);
      expect(result.card!.step, 2);
      expect(result.card!.log, hasLength(2));
      expect(result.card!.introducedOn, '2026-10-13');
      final body = (await store.get('card', 'w1'))!;
      expect(body['reviewNote'], 'keep me');
      expect(body['lastReviewId'], 'new-event');
      expect(body['headword'], 'lantern');
      expect(body['example'], 'The lantern swayed.');
      expect(body['introducedOn'], '2026-10-13');
      // The ladder did not forget where it was.
      expect(body['step'], 2);
    },
  );

  test(
    'editing the words leaves the progress and the unknown fields',
    () async {
      await store.put('card', 'w1', legacyCard());
      final card = WordCard.fromRecord('w1', legacyCard());
      final edited = card.copyWith(
        meaning: 'a lamp you carry',
        deckId: 'deck-1',
      );
      expect(
        await WordsRepository(store).saveCard(edited, preserveProgress: true),
        isTrue,
      );
      final body = (await store.get('card', 'w1'))!;
      expect(body['meaning'], 'a lamp you carry');
      expect(body['deckId'], 'deck-1');
      expect(body['reviewNote'], 'keep me');
      expect(body['lastReviewId'], 'review-event-id');
      expect(body['step'], 1);
      expect(body['due'], '2026-10-16');
      expect(body['log'], hasLength(1));
    },
  );

  testWidgets('the home page opens old records unchanged', (tester) async {
    await store.put('card', 'w1', legacyCard());
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: WordsScreen(store: store),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('lantern'), findsOneWidget);
    expect(find.text('a light to carry'), findsOneWidget);
    // The goal starts at ten, said as a fact — and the old streak is gone,
    // because a missed day must cost nothing.
    expect(find.text('0/10 today'), findsOneWidget);
    expect(find.byKey(const ValueKey('words-streak')), findsNothing);
    // The word sits outside every deck, and no deck exists yet, so the
    // deck row stays out of the way until there is one.
    expect(find.byKey(const ValueKey('words-deck-filters')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
