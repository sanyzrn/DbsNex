import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/words/words_models.dart';
import 'package:nex_client/modules/words/words_dates.dart';
import 'package:nex_client/modules/words/words_scheduler.dart';
import 'package:nex_client/modules/words/words_store.dart';
import 'package:nex_client/modules/words/words_batch_parse.dart';
import '../../support/nex_harness.dart';

void main() {
  late NexTestHarness harness;
  setUp(
    () async =>
        harness = await NexTestHarness.create(name: 'words_regression_'),
  );
  tearDown(() => harness.dispose());
  WordCard card(
    String id, {
    int reps = 0,
    String due = '',
    String introduced = '',
    String stamp = '',
    int step = 0,
  }) => WordCard(
    id: id,
    headword: 'word-$id',
    language: 'English',
    meaning: 'Typed meaning',
    createdAtIso: '2026-01-01T12:00:00',
    reps: reps,
    due: due,
    introducedOn: introduced,
    lastReviewIso: stamp,
    step: step,
  );
  test('bad dates and short history cannot become due or crash a session', () {
    for (final bad in ['', 'x', '2026-02-30', '2026-13-01', '0000-01-01']) {
      final model = WordCard.fromRecord('old', {
        'reps': 3,
        'due': bad,
        'lastReview': 'x',
        'log': [
          {'at': 'x', 'g': 'good'},
        ],
      });
      expect(model.isNew, isFalse);
      expect(model.isDueOn('2026-10-13'), isFalse);
      expect(
        buildSession(cards: [model], todayIso: '2026-10-13', newPerDay: 10).due,
        isEmpty,
      );
    }
    expect(wordsValidStamp('2026-10-13T25:00:00'), isNull);
    expect(wordsValidStamp('2026-02-30T09:00:00'), isNull);
  });
  test('introduction day survives reading and a capped history', () {
    final raw = {
      'reps': 500,
      'lastReview': '2027-05-15T12:00:00',
      'due': '2027-05-16',
      'log': [
        for (var i = 0; i < 500; i++)
          {'at': DateTime(2026, 1, 1 + i, 12).toIso8601String(), 'g': 'good'},
      ],
    };
    final first = WordCard.fromRecord('old', raw);
    expect(first.log, hasLength(200));
    expect(first.introducedOn, '2026-01-01');
    final next = answerCard(first, WordsGrade.good, DateTime(2027, 5, 16, 12));
    final restored = WordCard.fromRecord('old', next.toRecord());
    expect(restored.introducedOn, '2026-01-01');
    expect(restored.log, hasLength(200));
  });
  test('daily cap remains correct after trimming the first review entry', () {
    final today = '2026-10-13';
    final introduced = card(
      'old',
      reps: 500,
      due: '2026-11-01',
      introduced: today,
      stamp: '2026-10-13T12:00:00',
    );
    final session = buildSession(
      cards: [introduced, card('new')],
      todayIso: today,
      newPerDay: 1,
    );
    expect(session.fresh, isEmpty);
  });
  test(
    'a bounded session prioritizes overdue cards and never exceeds the limit',
    () {
      final cards = [
        for (var i = 0; i < 100; i++)
          card('$i', reps: 1, due: '2026-10-01', stamp: '2026-09-01T12:00:00'),
        card('new'),
      ];
      final session = buildSession(
        cards: cards,
        todayIso: '2026-10-13',
        newPerDay: 10,
        sessionLimit: 20,
      );
      expect(session.due, hasLength(20));
      expect(session.fresh, isEmpty);
      final all = buildSession(
        cards: cards,
        todayIso: '2026-10-13',
        newPerDay: 10,
        sessionLimit: 0,
      );
      expect(all.due, hasLength(100));
      expect(all.fresh, hasLength(1));
    },
  );
  test(
    'finite integer metadata and valid defaults bound counters and caps',
    () {
      for (final invalid in [double.nan, double.infinity, 3.5]) {
        final model = WordCard.fromRecord('x', {
          'step': invalid,
          'reps': invalid,
          'lapses': invalid,
        });
        expect(model.step, 0);
        expect(model.reps, 0);
        expect(model.lapses, 0);
      }
      expect(
        WordsSettings.fromRecord({
          'newPerDay': -5,
          'sessionLimit': -1,
        }).newPerDay,
        10,
      );
      expect(
        WordsSettings.fromRecord({'sessionLimit': 999999}).sessionLimit,
        20,
      );
      expect(previewIntervalDays(card('x', step: 999), WordsGrade.hard), 60);
    },
  );
  test('calendar differences do not depend on elapsed midnight hours', () {
    expect(daysUntil('2024-03-10', '2024-03-11'), 1);
    expect(daysUntil('2028-02-28', '2028-03-01'), 2);
    expect(daysUntil('2026-12-31', '2027-01-01'), 1);
    final paused = card('x').copyWith(paused: true);
    expect(
      answerCard(paused, WordsGrade.good, DateTime(2026, 10, 13)),
      same(paused),
    );
  });
  test(
    'batch parsing preserves optional typed meanings and counts repeats',
    () {
      final batch = parseWordsBatch(
        '  dawn\t first light  \r\ndawn\tAnother sense\n river \n\n',
      );
      expect(batch.entries.map((e) => e.word), ['dawn', 'river']);
      expect(batch.entries.first.meaning, 'first light');
      expect(batch.entries.last.meaning, '');
      expect(batch.duplicates, 1);
    },
  );
  test('editing preserves the latest raw history and unknown fields', () async {
    final store = NexModuleStore(harness.services, 'words');
    final repository = WordsRepository(store);
    final original = card(
      'old',
      reps: 7,
      due: '2026-11-01',
      stamp: '2026-10-12T12:00:00',
    );
    await store.put('card', 'old', {
      ...original.toRecord(),
      'future': {'keep': true},
    });
    final latest = {
      ...original.toRecord(),
      'reps': 8,
      'due': '2026-11-20',
      'lastReview': '2026-10-13T12:00:00',
      'log': [
        for (var i = 0; i < 450; i++)
          {
            'at': DateTime(2025, 1, 1 + i, 12).toIso8601String(),
            'g': 'good',
            'extra': 'retained',
          },
      ],
      'future': {'keep': true},
    };
    await store.put('card', 'old', latest);
    expect(
      await repository.saveCard(
        original.copyWith(headword: 'Fixed'),
        preserveProgress: true,
        requireExisting: true,
      ),
      isTrue,
    );
    final saved = await store.get('card', 'old');
    expect(saved!['headword'], 'Fixed');
    expect(saved['reps'], 8);
    expect(saved['due'], '2026-11-20');
    expect(saved['log'], latest['log']);
    expect(saved['future'], {'keep': true});
  });
  test(
    'pause changes only pause, never the text or raw review history',
    () async {
      final store = NexModuleStore(harness.services, 'words');
      final repository = WordsRepository(store);
      final raw = {
        ...card('x', reps: 4).toRecord(),
        'headword': '  Original  ',
        'log': [
          {'at': 'x', 'g': 'unknown', 'extra': true},
        ],
        'future': 123,
      };
      await store.put('card', 'x', raw);
      expect(await repository.setPaused('x', true), isNotNull);
      expect(await store.get('card', 'x'), {...raw, 'paused': true});
    },
  );
  test(
    'deleted cards cannot be resurrected by a stale editor or reviewer',
    () async {
      final store = NexModuleStore(harness.services, 'words');
      final repository = WordsRepository(store);
      final original = card('x');
      expect(
        await repository.saveCard(
          original,
          preserveProgress: true,
          requireExisting: true,
        ),
        isFalse,
      );
      expect(
        (await repository.answer(original, WordsGrade.good, 'event')).status,
        WordsAnswerStatus.missing,
      );
      expect(await store.list('card'), isEmpty);
    },
  );
  test(
    'one review event stays idempotent across repositories and retries',
    () async {
      final store = NexModuleStore(harness.services, 'words');
      final original = card('x');
      await store.put('card', 'x', {...original.toRecord(), 'future': true});
      final first = await WordsRepository(
        store,
      ).answer(original, WordsGrade.good, 'event');
      final retry = await WordsRepository(
        store,
      ).answer(original, WordsGrade.easy, 'event');
      expect(first.status, WordsAnswerStatus.saved);
      expect(retry.status, WordsAnswerStatus.saved);
      final saved = await store.get('card', 'x');
      expect(saved!['reps'], 1);
      expect(saved['step'], 1);
      expect(saved['future'], isTrue);
      expect(saved['lastReviewId'], 'event');
      expect(
        (await WordsRepository(
          store,
        ).answer(original, WordsGrade.good, 'other')).status,
        WordsAnswerStatus.changed,
      );
    },
  );
  test(
    'settings updates preserve the other cap and unknown metadata',
    () async {
      final store = NexModuleStore(harness.services, 'words');
      final repository = WordsRepository(store);
      await store.put('settings', 'settings', {
        'schema': 2,
        'newPerDay': 5,
        'sessionLimit': 40,
        'future': true,
      });
      expect(await repository.updateSettings(newPerDay: 10), isTrue);
      final saved = await store.get('settings', 'settings');
      expect(saved!['sessionLimit'], 40);
      expect(saved['future'], isTrue);
    },
  );
}
