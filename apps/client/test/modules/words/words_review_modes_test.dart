import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/words/words_review_page.dart';

import '../../support/nex_harness.dart';

/// 2.8.4: practice that teaches — typing with forgiving matching, and
/// choices drawn from the same deck, both ending on the same four answers
/// so the schedule stays in the person's hands.
void main() {
  late NexTestHarness harness;
  late NexModuleStore store;

  setUp(() async {
    harness = await NexTestHarness.create(name: 'words_modes_');
    store = NexModuleStore(harness.services, 'words');
  });

  tearDown(() => harness.dispose());

  String today() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  Future<void> putCard(
    String id, {
    String headword = 'zephyr',
    String meaning = 'a soft west wind',
    String deckId = 'book',
    String language = 'English',
  }) => store.put('card', id, {
    'schema': 2,
    'headword': headword,
    'language': language,
    'meaning': meaning,
    'createdAt': '2026-11-01T09:00:00',
    'step': 1,
    'reps': 2,
    'due': today(),
    'lastReview': '2026-11-01T09:00:00',
    'introducedOn': '2026-11-01',
    'paused': false,
    'deckId': deckId,
    'log': const [
      {'at': '2026-11-01T09:00:00', 'g': 'good'},
    ],
  });

  Widget reviewPage({
    Locale locale = const Locale('en'),
    TextScaler textScaler = TextScaler.noScaling,
  }) => MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: textScaler),
      child: child!,
    ),
    home: WordsReviewPage(store: store),
  );

  Future<void> chooseMode(WidgetTester tester, String mode) async {
    await tester.tap(find.byKey(const ValueKey('words-exercise')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('words-exercise-$mode')));
    await tester.pumpAndSettle();
  }

  testWidgets('a typed answer is checked forgivingly, then graded', (
    tester,
  ) async {
    await putCard('w1');
    await tester.pumpWidget(reviewPage());
    await tester.pumpAndSettle();

    await chooseMode(tester, 'type');
    expect(find.byKey(const ValueKey('words-typing-card')), findsOneWidget);
    // The answer is not on the card before it is given.
    expect(find.text('a soft west wind'), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('words-typed-answer')),
      '  A SOFT   west wind. ',
    );
    await tester.tap(find.byKey(const ValueKey('words-typed-check')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('words-answer-verdict')), findsOneWidget);
    expect(find.text('Right.'), findsOneWidget);
    // The answer is shown, and the example with it.
    expect(find.text('a soft west wind'), findsOneWidget);

    // The person still grades the card: it was «good».
    await tester.tap(find.byKey(const ValueKey('words-answer-good')));
    await tester.pumpAndSettle();
    final body = (await store.get('card', 'w1'))!;
    expect(body['reps'], 3);
    expect(body['step'], 2);
    expect((body['log'] as List).last['g'], 'good');
  });

  testWidgets('a wrong answer says so and grades nothing by itself', (
    tester,
  ) async {
    await putCard('w1');
    await tester.pumpWidget(reviewPage());
    await tester.pumpAndSettle();
    await chooseMode(tester, 'type');

    await tester.enterText(
      find.byKey(const ValueKey('words-typed-answer')),
      'a hard rain',
    );
    await tester.tap(find.byKey(const ValueKey('words-typed-check')));
    await tester.pumpAndSettle();

    expect(find.text('Not quite — here is the answer.'), findsOneWidget);
    expect(find.text('You wrote: a hard rain'), findsOneWidget);
    // Nothing was graded until the person says how it went.
    expect((await store.get('card', 'w1'))!['reps'], 2);
  });

  testWidgets('choices come from the same deck, and the right one is there', (
    tester,
  ) async {
    // The prompt is a meaning in this card, so the deck's other words are
    // the wrong answers.
    await putCard('w1', headword: 'which word?', meaning: 'a soft west wind');
    await putCard('w2', headword: 'serene', meaning: 'calm and clear');
    await putCard('w3', headword: 'frugal', meaning: 'careful with money');
    await putCard('w4', headword: 'terse', meaning: 'short in speech');
    await tester.pumpWidget(reviewPage());
    await tester.pumpAndSettle();

    await chooseMode(tester, 'choose');
    expect(find.byKey(const ValueKey('words-choice-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('words-choice-3')), findsOneWidget);

    // The right answer is one of them; tapping it says so.
    await tester.tap(find.text('a soft west wind'));
    await tester.pumpAndSettle();
    expect(find.text('Right.'), findsOneWidget);
    // The answer is on the turned card.
    expect(find.text('which word?'), findsOneWidget);
  });

  testWidgets('a wrong choice is named as wrong', (tester) async {
    await putCard('w1', headword: 'which word?', meaning: 'a soft west wind');
    await putCard('w2', headword: 'serene', meaning: 'calm and clear');
    await putCard('w3', headword: 'frugal', meaning: 'careful with money');
    await putCard('w4', headword: 'terse', meaning: 'short in speech');
    await tester.pumpWidget(reviewPage());
    await tester.pumpAndSettle();
    await chooseMode(tester, 'choose');

    await tester.tap(find.text('calm and clear'));
    await tester.pumpAndSettle();
    expect(find.text('Not quite — here is the answer.'), findsOneWidget);
  });

  testWidgets('typing reads in Persian at twice the size, on a small phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await putCard(
      'w1',
      headword: 'نسیم',
      meaning: 'باد آرام از سوی باختر',
      language: 'فارسی',
    );
    await tester.pumpWidget(
      reviewPage(
        locale: const Locale('fa'),
        textScaler: const TextScaler.linear(2),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await chooseMode(tester, 'type');
    expect(tester.takeException(), isNull);
    await tester.enterText(
      find.byKey(const ValueKey('words-typed-answer')),
      'باد ارام از سوی باختر',
    );
    await tester.tap(find.byKey(const ValueKey('words-typed-check')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('درست بود.'), findsOneWidget);
  });
}
