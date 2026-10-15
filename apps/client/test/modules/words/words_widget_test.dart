import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/words/words_screen.dart';
import 'package:nex_client/platform/nex_services.dart';

import '../../support/nex_harness.dart';

part 'words_browse_cases.dart';

/// Word by Word on screen: the honest empty state, capturing a word,
/// editing it without losing progress, deleting with Undo (history and
/// all), search and filters, and Persian reading. The review session and
/// the batch paste are covered in their own files.
void main() {
  late NexTestHarness harness;

  setUp(() async {
    harness = await NexTestHarness.create(name: 'words_');
  });

  tearDown(() => harness.dispose());

  Widget host(Widget home, {Locale locale = const Locale('en')}) => MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  );

  Widget wordsScreen() =>
      host(WordsScreen(store: NexModuleStore(harness.services, 'words')));

  Finder scrollable() => find.byType(Scrollable).first;

  /// The card page is a long scrolling page; the save button sits at the
  /// bottom of it, where the home screen's floating action button would
  /// sit — so the scroll goes one step further and lifts it clear.
  Future<void> scrollToSave(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('words-card-save')),
      400,
      scrollable: scrollable(),
    );
    await tester.drag(scrollable(), const Offset(0, -150));
    await tester.pumpAndSettle();
  }

  /// Types into a field wherever it sits on the long card page: the
  /// scroll goes to it first, then the text lands.
  Future<void> enterAt(WidgetTester tester, Key key, String text) async {
    await tester.scrollUntilVisible(
      find.byKey(key),
      300,
      scrollable: scrollable(),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(key), text);
  }

  /// A SnackBar can swallow the next tap; put it away first.
  void hideSnackBar(WidgetTester tester) {
    ScaffoldMessenger.of(
      tester.element(find.byType(Scaffold).first),
    ).hideCurrentSnackBar();
  }

  testWidgets('the first screen is an honest empty state', (tester) async {
    await tester.pumpWidget(wordsScreen());
    await tester.pumpAndSettle();
    expect(find.text('Word by Word'), findsOneWidget);
    expect(find.byType(NexEmptyState), findsOneWidget);
    expect(
      find.text(
        'No words yet. Add the first one — a word, a phrase, whatever you '
        'are reading.',
      ),
      findsOneWidget,
    );
    expect(find.text('0 due now · 0 new today'), findsOneWidget);
    expect(find.byKey(const ValueKey('words-add')), findsOneWidget);
  });

  testWidgets('capturing a word, start to finish', (tester) async {
    await tester.pumpWidget(wordsScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('words-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('words-field-headword')),
      'serendipity',
    );
    await tester.enterText(
      find.byKey(const ValueKey('words-field-language')),
      'English',
    );
    await enterAt(
      tester,
      const ValueKey('words-field-meaning'),
      'a happy accident',
    );
    await enterAt(
      tester,
      const ValueKey('words-field-example'),
      'Found by pure serendipity.',
    );
    await enterAt(tester, const ValueKey('words-field-tag'), 'books');
    await scrollToSave(tester);
    await tester.tap(find.byKey(const ValueKey('words-card-save')));
    await tester.pumpAndSettle();

    // Back on the home list, with the word on it.
    expect(find.text('serendipity'), findsOneWidget);
    expect(find.text('English · new · books'), findsOneWidget);
    final records = await harness.services.moduleRecords('words', 'card');
    expect(records, hasLength(1));
    expect(records.single.body['headword'], 'serendipity');
    expect(records.single.body['language'], 'English');
    expect(records.single.body['meaning'], 'a happy accident');
    expect(records.single.body['example'], 'Found by pure serendipity.');
    expect(records.single.body['tag'], 'books');
    expect(records.single.body['step'], 0);
    expect(records.single.body['log'], isEmpty);
  });

  testWidgets('a word is needed; whitespace is folded, not kept', (
    tester,
  ) async {
    await tester.pumpWidget(wordsScreen());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('words-add')));
    await tester.pumpAndSettle();

    await scrollToSave(tester);
    await tester.tap(find.byKey(const ValueKey('words-card-save')));
    await tester.pumpAndSettle();
    expect(find.text('The word itself is needed.'), findsOneWidget);
    expect(await harness.services.moduleRecords('words', 'card'), isEmpty);

    // The SnackBar must be out of the way before the next tap.
    hideSnackBar(tester);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('words-field-headword')),
      '  multiple   spaces  ',
    );
    await scrollToSave(tester);
    await tester.tap(find.byKey(const ValueKey('words-card-save')));
    await tester.pumpAndSettle();
    final records = await harness.services.moduleRecords('words', 'card');
    expect(records.single.body['headword'], 'multiple spaces');
  });

  testWidgets('a duplicate is a question, and both answers work', (
    tester,
  ) async {
    final store = NexModuleStore(harness.services, 'words');
    await store.put('card', 'existing', {
      'schema': 1,
      'headword': 'serendipity',
      'language': 'English',
      'createdAt': '2026-10-01T10:00:00',
    });

    await tester.pumpWidget(host(WordsScreen(store: store)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('words-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('words-field-headword')),
      'Serendipity',
    );
    await tester.enterText(
      find.byKey(const ValueKey('words-field-language')),
      'english',
    );
    await scrollToSave(tester);
    await tester.tap(find.byKey(const ValueKey('words-card-save')));
    await tester.pumpAndSettle();

    expect(find.text('Already in your words'), findsOneWidget);
    expect(find.textContaining('is already saved in English'), findsOneWidget);
    // Cancelled: nothing new was written.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await harness.services.moduleRecords('words', 'card'), hasLength(1));

    // Add anyway: a second card, on purpose.
    await tester.enterText(
      find.byKey(const ValueKey('words-field-headword')),
      'Serendipity',
    );
    await scrollToSave(tester);
    await tester.tap(find.byKey(const ValueKey('words-card-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('words-duplicate-add')));
    await tester.pumpAndSettle();
    expect(await harness.services.moduleRecords('words', 'card'), hasLength(2));
  });

  testWidgets('editing a word preserves its progress', (tester) async {
    final store = NexModuleStore(harness.services, 'words');
    final now = DateTime.now();
    final expectedDue = DateTime(
      now.year,
      now.month,
      now.day + 20,
    ).toIso8601String().substring(0, 10);
    await store.put('card', 'c1', {
      'schema': 1,
      'headword': 'zephyr',
      'language': 'English',
      'meaning': 'a soft west wind',
      'createdAt': '2026-10-01T10:00:00',
      'step': 3,
      'due': expectedDue,
      'lapses': 2,
      'reps': 7,
      'lastReview': '2026-10-18T09:00:00',
      'log': [
        {'at': '2026-10-18T09:00:00', 'g': 'good'},
        {'at': '2026-10-11T09:00:00', 'g': 'again'},
      ],
    });

    await tester.pumpWidget(host(WordsScreen(store: store)));
    await tester.pumpAndSettle();
    expect(find.text('zephyr'), findsOneWidget);

    await tester.tap(find.text('zephyr'));
    await tester.pumpAndSettle();
    // The progress panel shows the carried-over state.
    await tester.scrollUntilVisible(
      find.textContaining('7 reviews · 2 lapses · step 3'),
      400,
      scrollable: scrollable(),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('7 reviews · 2 lapses · step 3'),
      findsOneWidget,
    );
    expect(find.textContaining('Next review: in 20 days'), findsOneWidget);

    // A typo fix only touches the words.
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('words-field-headword')),
      -400,
      scrollable: scrollable(),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('words-field-headword')),
      'Zephyr',
    );
    await enterAt(
      tester,
      const ValueKey('words-field-meaning'),
      'a soft gentle west wind',
    );
    await scrollToSave(tester);
    await tester.tap(find.byKey(const ValueKey('words-card-save')));
    await tester.pumpAndSettle();

    final record = (await harness.services.moduleRecords(
      'words',
      'card',
    )).single;
    expect(record.id, 'c1');
    expect(record.body['headword'], 'Zephyr');
    expect(record.body['meaning'], 'a soft gentle west wind');
    expect(record.body['step'], 3);
    expect(record.body['due'], expectedDue);
    expect(record.body['lapses'], 2);
    expect(record.body['reps'], 7);
    expect(record.body['log'], hasLength(2));
  });

  testWidgets('delete asks; Undo restores the card with its history', (
    tester,
  ) async {
    final store = NexModuleStore(harness.services, 'words');
    await store.put('card', 'c1', {
      'schema': 1,
      'headword': 'zephyr',
      'language': 'English',
      'createdAt': '2026-10-01T10:00:00',
      'step': 2,
      'due': '2026-10-20',
      'reps': 3,
      'log': [
        {'at': '2026-10-05T09:00:00', 'g': 'good'},
        {'at': '2026-10-12T09:00:00', 'g': 'easy'},
        {'at': '2026-10-12T09:05:00', 'g': 'hard'},
      ],
    });

    await tester.pumpWidget(host(WordsScreen(store: store)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('zephyr'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('words-card-delete')));
    await tester.pumpAndSettle();
    expect(find.text('Delete this word?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('words-delete-confirm')));
    await tester.pumpAndSettle();

    expect(find.text('Word deleted'), findsOneWidget);
    expect(await harness.services.moduleRecords('words', 'card'), isEmpty);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    final restored = (await harness.services.moduleRecords(
      'words',
      'card',
    )).single;
    expect(restored.id, 'c1');
    expect(restored.body['headword'], 'zephyr');
    expect(restored.body['log'], hasLength(3));
    expect(restored.body['reps'], 3);
    expect(find.text('Word restored'), findsOneWidget);
  });

  _registerBrowseCases(() => harness, host, wordsScreen, scrollable, enterAt);
}

Future<void> storeWord(
  NexTestHarness harness, {
  required String module,
  required String kind,
  required Map<String, Object?> body,
}) async {
  final store = NexModuleStore(harness.services, module);
  await store.put(kind, store.newId(), body);
}
