import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/words/words_screen.dart';
import 'package:nex_client/modules/words/words_card_page.dart';
import 'package:nex_client/modules/words/words_models.dart';
import 'package:nex_client/modules/words/words_store.dart';
import 'package:nex_client/modules/words/words_batch_sheet.dart';
import 'package:nex_client/modules/words/words_review_page.dart';
import '../../support/nex_harness.dart';

class FaultStore implements NexModuleStore {
  FaultStore(this.inner);
  final NexModuleStore inner;
  bool failList = false;
  bool failDraftRead = false;
  String? failWordOnce;
  bool failAfterReview = false;
  @override
  Future<void> quarantine(ModuleRecord record) async {
    await put('__recovery', newId(), {
      'kind': record.kind,
      'id': record.id,
      'body': record.body,
      'updatedAt': record.updatedAt.toIso8601String(),
    });
    await delete(record.kind, record.id);
  }

  @override
  Stream<void> get draftChanges => inner.draftChanges;
  @override
  bool get remindersEnabled => inner.remindersEnabled;
  @override
  bool get solarCalendar => inner.solarCalendar;
  @override
  Future<bool> setReminder(
    String key, {
    required String sourceKind,
    required String sourceId,
    required DateTime at,
    required String title,
    required String body,
  }) => inner.setReminder(
    key,
    sourceKind: sourceKind,
    sourceId: sourceId,
    at: at,
    title: title,
    body: body,
  );
  @override
  Future<bool> setDailyReminder(
    String key, {
    required String sourceKind,
    required String sourceId,
    required DateTime at,
    required String title,
    required String body,
  }) => inner.setDailyReminder(
    key,
    sourceKind: sourceKind,
    sourceId: sourceId,
    at: at,
    title: title,
    body: body,
  );
  @override
  Future<void> clearReminder(String key) => inner.clearReminder(key);
  @override
  String get module => inner.module;
  @override
  Stream<void> get changes => inner.changes;
  @override
  String newId() => inner.newId();
  @override
  Future<List<ModuleRecord>> list(String kind) {
    if (failList) throw StateError('temporary');
    return inner.list(kind);
  }

  @override
  Future<Map<String, Object?>?> get(String kind, String id) {
    if (kind == 'draft' && failDraftRead) throw StateError('draft read');
    return inner.get(kind, id);
  }

  @override
  Future<void> put(String kind, String id, Map<String, Object?> body) async {
    if (kind == 'card' && failWordOnce == body['headword']) {
      failWordOnce = null;
      throw StateError('one word');
    }
    await inner.put(kind, id, body);
    if (kind == 'card' && failAfterReview && body['lastReviewId'] != null) {
      failAfterReview = false;
      throw StateError('committed but interrupted');
    }
  }

  @override
  Future<void> delete(String kind, String id) => inner.delete(kind, id);
}

void main() {
  late NexTestHarness harness;
  setUp(
    () async => harness = await NexTestHarness.create(name: 'words_fault_'),
  );
  tearDown(() => harness.dispose());
  Widget host(Widget child) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  );
  testWidgets('initial list failure offers a real retry', (tester) async {
    final store = FaultStore(NexModuleStore(harness.services, 'words'))
      ..failList = true;
    await tester.pumpWidget(host(WordsScreen(store: store)));
    await tester.pumpAndSettle();
    expect(find.text('Could not load your words. Try again.'), findsOneWidget);
    store.failList = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Could not load your words. Try again.'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('a failed draft read never replaces the previous checkpoint', (
    tester,
  ) async {
    final inner = NexModuleStore(harness.services, 'words');
    final raw = {
      'v': 1,
      'base': '{}',
      'fields': {
        'headword': 'Keep this',
        'meaning': 'Typed',
        'recordId': 'stable',
        'createdAt': '2026-10-12T12:00:00',
      },
    };
    await inner.put('draft', 'card:new', raw);
    final store = FaultStore(inner)..failDraftRead = true;
    await tester.pumpWidget(host(WordsCardPage(store: store)));
    await tester.pumpAndSettle();
    expect(
      find.text('Could not read the saved draft. Try again before editing.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('words-field-headword')), findsNothing);
    expect(await inner.get('draft', 'card:new'), raw);
    store.failDraftRead = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('words-field-headword')))
          .controller!
          .text,
      'Keep this',
    );
    expect(await inner.list('card'), isEmpty);
  });
  testWidgets('back checkpoints a card and reopening restores its text', (
    tester,
  ) async {
    final store = NexModuleStore(harness.services, 'words');
    await tester.pumpWidget(host(WordsScreen(store: store)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('words-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('words-field-headword')),
      'A saved draft',
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('words-add')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('words-field-headword')))
          .controller!
          .text,
      'A saved draft',
    );
    expect(await store.list('card'), isEmpty);
  });
  testWidgets('partial batch failure keeps only unconfirmed words for retry', (
    tester,
  ) async {
    final inner = NexModuleStore(harness.services, 'words');
    final store = FaultStore(inner)..failWordOnce = 'beta';
    await tester.pumpWidget(
      host(
        Builder(
          builder: (ctx) => Scaffold(
            body: TextButton(
              onPressed: () => showWordsBatchSheet(
                ctx,
                WordsRepository(store),
                onDone: () async {},
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('words-batch-text')),
      'alpha\tMeaning A\nbeta\tMeaning B\ngamma\tMeaning C',
    );
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('words-batch-add')));
    await tester.tap(find.byKey(const ValueKey('words-batch-add')));
    await tester.pumpAndSettle();
    expect(await inner.list('card'), hasLength(2));
    expect(
      tester
          .widget<NexTextField>(find.byKey(const ValueKey('words-batch-text')))
          .controller
          .text,
      'beta\tMeaning B',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('words-batch-add')));
    await tester.tap(find.byKey(const ValueKey('words-batch-add')));
    await tester.pumpAndSettle();
    expect(await inner.list('card'), hasLength(3));
    expect(await inner.get('draft', 'batch:new'), isNull);
  });
  testWidgets('an empty meaning has a useful editor and cannot be graded', (
    tester,
  ) async {
    final store = NexModuleStore(harness.services, 'words');
    await store.put(
      'card',
      'x',
      const WordCard(
        id: 'x',
        headword: 'A word',
        language: 'English',
        createdAtIso: '2026-10-12T12:00:00',
      ).toRecord(),
    );
    await tester.pumpWidget(host(WordsReviewPage(store: store)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('words-review-card')));
    await tester.pumpAndSettle();
    expect(
      find.text('Add your meaning before grading this card.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('words-answer-good')))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const ValueKey('words-review-skip')));
    await tester.pumpAndSettle();
    expect((await store.get('card', 'x'))!['reps'], 0);
  });
  testWidgets('a review committed before an error is confirmed exactly once', (
    tester,
  ) async {
    final inner = NexModuleStore(harness.services, 'words');
    await inner.put(
      'card',
      'x',
      const WordCard(
        id: 'x',
        headword: 'Word',
        language: 'English',
        meaning: 'Typed meaning',
        createdAtIso: '2026-10-12T12:00:00',
      ).toRecord(),
    );
    final store = FaultStore(inner)..failAfterReview = true;
    await tester.pumpWidget(host(WordsReviewPage(store: store)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('words-review-card')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('words-answer-good')));
    await tester.pumpAndSettle();
    expect((await inner.get('card', 'x'))!['reps'], 1);
    expect(find.byKey(const ValueKey('words-review-card')), findsNothing);
  });
}
