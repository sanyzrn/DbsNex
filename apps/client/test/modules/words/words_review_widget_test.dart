import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/words/words_scheduler.dart';
import 'package:nex_client/modules/words/words_screen.dart';
import 'package:nex_client/platform/nex_services.dart';

import '../../support/nex_harness.dart';

/// The review session on screen: due and new cards in one queue, tap to
/// reveal, answer and move on, the double-tap guard, the day's
/// introduction cap, the calm done state — and the batch paste with its
/// confirmation and its honest duplicate skip.
void main() {
  late NexTestHarness harness;

  setUp(() async {
    harness = await NexTestHarness.create(name: 'words_r_');
  });

  tearDown(() => harness.dispose());

  Widget host(Widget home, {Locale locale = const Locale('en')}) => MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  );

  Future<void> putCard(String id, Map<String, Object?> body) =>
      NexModuleStore(harness.services, 'words').put('card', id, body);

  testWidgets('a session: reveal, answer, next, done', (tester) async {
    await putCard('due1', {
      'schema': 1,
      'headword': 'lantern',
      'language': 'English',
      'meaning': 'a light to carry',
      'example': 'The lantern swayed.',
      'createdAt': '2026-10-01T10:00:00',
      'due': '2026-10-10',
      'reps': 1,
      'lastReview': '2026-10-05T09:00:00',
      'log': [
        {'at': '2026-10-05T09:00:00', 'g': 'good'},
      ],
    });
    await putCard('new1', {
      'schema': 1,
      'headword': 'zephyr',
      'language': 'English',
      'meaning': 'a soft west wind',
      'createdAt': '2026-10-02T10:00:00',
    });

    // The concealed card's label is a semantic property, not painted
    // text; the semantics tree is enabled for the checks that read it.
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      host(WordsScreen(store: NexModuleStore(harness.services, 'words'))),
    );
    await tester.pumpAndSettle();
    // One due, one new — both go into today's session.
    expect(find.text('1 due now · 1 new today'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('words-start-review')));
    await tester.pumpAndSettle();

    // The due card comes first, concealed: the meaning is not even in the
    // tree.
    expect(find.text('lantern'), findsOneWidget);
    expect(find.text('a light to carry'), findsNothing);
    expect(find.bySemanticsLabel(RegExp('Tap to reveal')), findsOneWidget);
    expect(find.text('1 of 2'), findsOneWidget);

    // Reveal: the meaning appears, along with the answer buttons.
    await tester.tap(find.byKey(const ValueKey('words-review-card')));
    await tester.pumpAndSettle();
    expect(find.text('a light to carry'), findsOneWidget);
    expect(find.text('The lantern swayed.'), findsOneWidget);
    expect(find.byKey(const ValueKey('words-answer-again')), findsOneWidget);

    // Answer Good: saved, and the new card follows.
    await tester.tap(find.byKey(const ValueKey('words-answer-good')));
    await tester.pumpAndSettle();
    expect(find.text('zephyr'), findsOneWidget);
    expect(find.text('a soft west wind'), findsNothing);
    expect(find.text('2 of 2'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('words-review-card')));
    await tester.pumpAndSettle();
    expect(find.text('a soft west wind'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('words-answer-easy')));
    await tester.pumpAndSettle();

    // The calm done state.
    expect(
      find.text('That is the session — 2 cards reviewed.'),
      findsOneWidget,
    );
    expect(
      find.text('Come back tomorrow; a few will be waiting.'),
      findsOneWidget,
    );
    semantics.dispose();

    // Both answers were written, each with its own schedule.
    final records = await harness.services.moduleRecords('words', 'card');
    final byId = {for (final record in records) record.id: record.body};
    expect(byId['due1']!['reps'], 2);
    expect(byId['due1']!['step'], 1);
    expect(byId['due1']!['log'], hasLength(2));
    expect(byId['new1']!['reps'], 1);
    expect(byId['new1']!['step'], 2);
  });

  testWidgets('Again leaves the session — nothing loops inside one sitting', (
    tester,
  ) async {
    await putCard('c1', {
      'schema': 1,
      'headword': 'lantern',
      'language': 'English',
      'meaning': 'a light to carry',
      'createdAt': '2026-10-01T10:00:00',
      'due': '2026-10-10',
      'reps': 1,
      'lastReview': '2026-10-05T09:00:00',
      'log': [
        {'at': '2026-10-05T09:00:00', 'g': 'good'},
      ],
    });

    await tester.pumpWidget(
      host(WordsScreen(store: NexModuleStore(harness.services, 'words'))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('words-start-review')));
    await tester.pumpAndSettle();
    expect(find.text('1 of 1'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('words-review-card')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('words-answer-again')));
    await tester.pumpAndSettle();

    // Done immediately: the card comes back tomorrow, not in a loop now.
    expect(
      find.text('That is the session — 1 cards reviewed.'),
      findsOneWidget,
    );
    final record = (await harness.services.moduleRecords(
      'words',
      'card',
    )).single;
    expect(record.body['step'], 0);
    expect(record.body['lapses'], 1);
    // Tomorrow, in date-only form, whatever today is.
    final due = record.body['due'] as String;
    expect(due, hasLength(10));
  });

  testWidgets('a double tap answers once', (tester) async {
    await putCard('c1', {
      'schema': 1,
      'headword': 'lantern',
      'language': 'English',
      'meaning': 'a light to carry',
      'createdAt': '2026-10-01T10:00:00',
      'due': '2026-10-10',
      'reps': 1,
      'lastReview': '2026-10-05T09:00:00',
      'log': [
        {'at': '2026-10-05T09:00:00', 'g': 'good'},
      ],
    });

    await tester.pumpWidget(
      host(WordsScreen(store: NexModuleStore(harness.services, 'words'))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('words-start-review')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('words-review-card')));
    await tester.pumpAndSettle();

    // Two taps on Good in the same instant: one answer.
    await tester.tap(find.byKey(const ValueKey('words-answer-good')));
    await tester.tap(find.byKey(const ValueKey('words-answer-good')));
    await tester.pumpAndSettle();

    final record = (await harness.services.moduleRecords(
      'words',
      'card',
    )).single;
    expect(record.body['reps'], 2); // one earlier review + exactly one now
    expect(record.body['log'], hasLength(2));
  });

  testWidgets('the daily cap bounds the new cards in a session', (
    tester,
  ) async {
    // The default cap is 10; three new cards, but only two allowed today
    // because one card was already introduced this morning.
    final today = DateTime.now();
    final todayIso =
        '${today.year.toString().padLeft(4, '0')}-'
        '${today.month.toString().padLeft(2, '0')}-'
        '${today.day.toString().padLeft(2, '0')}';
    await putCard('intro', {
      'schema': 1,
      'headword': 'already',
      'language': 'English',
      'createdAt': '2026-10-01T10:00:00',
      // Its first Good answer was this morning: due three days out.
      'due': isoDay(addDays(today, 3)),
      'log': [
        {'at': '${todayIso}T08:00:00', 'g': 'good'},
      ],
      'lastReview': '${todayIso}T08:00:00',
    });
    for (final id in ['n1', 'n2', 'n3']) {
      await putCard(id, {
        'schema': 1,
        'headword': id,
        'meaning': 'User-entered meaning',
        'language': 'English',
        'createdAt': '2026-10-02T10:00:00',
      });
    }
    await NexModuleStore(
      harness.services,
      'words',
    ).put('settings', 'settings', {'schema': 1, 'newPerDay': 3});

    await tester.pumpWidget(
      host(WordsScreen(store: NexModuleStore(harness.services, 'words'))),
    );
    await tester.pumpAndSettle();
    expect(find.text('0 due now · 2 new today'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('words-start-review')));
    await tester.pumpAndSettle();
    // The third new card waits for tomorrow.
    for (var i = 0; i < 2; i++) {
      expect(find.textContaining('${i + 1} of 2'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('words-review-card')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('words-answer-good')));
      await tester.pumpAndSettle();
    }
    expect(
      find.text('That is the session — 2 cards reviewed.'),
      findsOneWidget,
    );
    expect(find.text('n3'), findsNothing);
  });

  testWidgets('nothing to review is said plainly', (tester) async {
    await putCard('future', {
      'schema': 1,
      'headword': 'someday',
      'language': 'English',
      'createdAt': '2026-10-01T10:00:00',
      'due': '2086-01-01',
      'lastReview': '2026-10-01T09:00:00',
      'log': [
        {'at': '2026-10-01T09:00:00', 'g': 'good'},
      ],
    });

    await tester.pumpWidget(
      host(WordsScreen(store: NexModuleStore(harness.services, 'words'))),
    );
    await tester.pumpAndSettle();
    expect(find.text('0 due now · 0 new today'), findsOneWidget);
    expect(
      find.text(
        'Nothing to review right now. Words come back on their own days.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('words-start-review')), findsNothing);
  });

  testWidgets(
    'the batch paste confirms before it saves, and skips known words',
    (tester) async {
      await putCard('existing', {
        'schema': 1,
        'headword': 'zephyr',
        'language': 'English',
        'createdAt': '2026-10-01T10:00:00',
      });

      await tester.pumpWidget(
        host(WordsScreen(store: NexModuleStore(harness.services, 'words'))),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('words-batch')));
      await tester.pumpAndSettle();

      expect(find.text('Paste a list of words'), findsOneWidget);
      expect(
        find.text('Nothing to add yet — paste a few lines first.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('words-batch-add')), findsNothing);

      await tester.enterText(
        find.byKey(const ValueKey('words-batch-text')),
        'zephyr\n  harbor  \n\nlantern\nzephyr',
      );
      await tester.pump();
      // The in-paste repeat of «zephyr» folds away; three distinct words
      // are ready (one of them will be skipped as already saved).
      expect(find.text('3 words ready to add'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('words-batch-add')));
      await tester.pumpAndSettle();

      expect(
        find.text('2 words added · 2 skipped — repeated or already saved'),
        findsOneWidget,
      );
      final records = await harness.services.moduleRecords('words', 'card');
      expect(records, hasLength(3));
      final words = records.map((r) => r.body['headword']).toSet();
      expect(words, containsAll(['zephyr', 'harbor', 'lantern']));
    },
  );

  testWidgets('the review card in Persian reads right to left', (tester) async {
    await putCard('c1', {
      'schema': 1,
      'headword': 'serendipity',
      'language': 'English',
      'meaning': 'یافتنِ خوش‌سُرپرست',
      'createdAt': '2026-10-01T10:00:00',
      'due': '2026-10-10',
      'reps': 1,
      'lastReview': '2026-10-05T09:00:00',
      'log': [
        {'at': '2026-10-05T09:00:00', 'g': 'good'},
      ],
    });

    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      host(
        WordsScreen(store: NexModuleStore(harness.services, 'words')),
        locale: const Locale('fa'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('۱ واژه سررسید · ۰ تازه امروز'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('words-start-review')));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp('بلمسید')), findsOneWidget);
    expect(find.text('۱ از ۱'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('words-review-card')));
    await tester.pumpAndSettle();
    expect(find.text('یافتنِ خوش‌سُرپرست'), findsOneWidget);
    expect(find.byKey(const ValueKey('words-answer-good')), findsOneWidget);
    // The English headword stays left-to-right inside the Persian card.
    expect(
      Directionality.of(tester.element(find.text('serendipity'))),
      TextDirection.ltr,
    );
    expect(
      Directionality.of(tester.element(find.text('یافتنِ خوش‌سُرپرست'))),
      TextDirection.rtl,
    );
    semantics.dispose();
  });
}
