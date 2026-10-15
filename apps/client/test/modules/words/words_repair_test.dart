import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/words/words_card_page.dart';
import 'package:nex_client/modules/words/words_dates.dart';
import 'package:nex_client/modules/words/words_models.dart';
import 'package:nex_client/modules/words/words_store.dart';
import '../../support/nex_harness.dart';

void main() {
  late NexTestHarness h;
  late NexModuleStore store;
  setUp(() async {
    h = await NexTestHarness.create(name: 'words_repair_');
    store = NexModuleStore(h.services, 'words');
  });
  tearDown(() => h.dispose());
  test('impossible timestamp offsets are refused', () {
    expect(wordsValidStamp('2026-10-13T12:00:00+99:99'), isNull);
    expect(wordsValidStamp('2026-10-13T12:00:00+03:30'), isNotNull);
  });
  test(
    'repair preserves raw history and never alters a valid fresh schedule',
    () async {
      final repository = WordsRepository(store);
      final body = {
        'schema': 2,
        'headword': 'Example',
        'reps': 7,
        'due': 'bad',
        'paused': true,
        'future': {'keep': true},
        'log': [
          {'at': 'bad old entry', 'g': 'future', 'extra': true},
        ],
      };
      await store.put('card', 'c', body);
      final next = await repository.repairDue('c');
      expect(next!.due, wordsIsoDay(DateTime.now()));
      final raw = (await store.get('card', 'c'))!;
      expect(raw['log'], body['log']);
      expect(raw['future'], body['future']);
      expect(raw['reps'], 7);
      expect(raw['paused'], true);
      await store.put('card', 'c', {...raw, 'due': '2099-01-01'});
      await repository.repairDue('c');
      expect((await store.get('card', 'c'))!['due'], '2099-01-01');
      await store.delete('card', 'c');
      expect(await repository.repairDue('c'), isNull);
    },
  );
  testWidgets('explicit date repair keeps unsaved wording and review history', (
    tester,
  ) async {
    final body = {
      'schema': 2,
      'headword': 'Example',
      'meaning': 'Typed meaning',
      'createdAt': '2026-10-01T12:00:00Z',
      'due': 'invalid',
      'reps': 7,
      'paused': true,
      'log': [
        {'at': '2026-10-01T12:00:00Z', 'g': 'good', 'extra': true},
      ],
    };
    await store.put('card', 'c', body);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: WordsCardPage(store: store, card: WordCard.fromRecord('c', body)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('words-field-headword')),
      'Unsaved wording',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('words-card-repair-date')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -150));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('words-card-repair-date')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('words-repair-confirm')));
    await tester.pumpAndSettle();
    final raw = (await store.get('card', 'c'))!;
    expect(raw['due'], wordsIsoDay(DateTime.now()));
    expect(raw['headword'], 'Example');
    expect(raw['log'], body['log']);
    expect(raw['paused'], true);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('words-field-headword')),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('words-field-headword')))
          .controller!
          .text,
      'Unsaved wording',
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('older created date is Persian and explicitly Gregorian', (
    tester,
  ) async {
    final raw = {'headword': 'Example', 'createdAt': '2026-01-01T12:00:00'};
    await store.put('card', 'c', raw);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fa'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: WordsCardPage(store: store, card: WordCard.fromRecord('c', raw)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('words-card-pause')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('۲۰۲۶-۰۱-۰۱ (میلادی)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
