import 'package:nex_client/modules/habits/record_bundle.dart';
import 'dart:async';
import 'package:nex_client/modules/habits/module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/habits/habits_screen.dart';
import 'package:nex_client/modules/habits/form_draft.dart';
import '../../support/nex_harness.dart';

class FaultStore implements NexModuleStore {
  FaultStore(this.inner);
  final NexModuleStore inner;
  bool failReads = true;
  bool failWrites = false;
  int draftFailures = 0;
  Future<void>? draftGate;
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
    if (failReads) throw StateError('Transient read');
    return inner.list(kind);
  }

  @override
  Future<Map<String, Object?>?> get(String kind, String id) =>
      inner.get(kind, id);
  @override
  Future<void> put(String kind, String id, Map<String, Object?> body) {
    if (kind == 'draft' && draftFailures > 0) {
      draftFailures--;
      throw StateError('Transient draft write');
    }
    if (failWrites) throw StateError('Transient write');
    if (kind == 'draft' && draftGate != null) {
      return draftGate!.then((_) => inner.put(kind, id, body));
    }
    return inner.put(kind, id, body);
  }

  @override
  Future<void> delete(String kind, String id) => inner.delete(kind, id);
}

void main() {
  late NexTestHarness harness;
  setUp(() async {
    harness = await NexTestHarness.create(name: 'nex_habits_fault_');
  });
  tearDown(() => harness.dispose());
  testWidgets('load failure offers retry without an uncaught exception', (
    tester,
  ) async {
    final store = FaultStore(NexModuleStore(harness.services, 'habits'));
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: HabitsScreen(store: store),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Could not load records. Try again.'), findsOneWidget);
    store.failReads = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Could not load records. Try again.'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  test(
    'rapid typing followed by disposal flushes the latest checkpoint',
    () async {
      final store = NexModuleStore(harness.services, 'habits');
      final text = TextEditingController();
      final draft = FormDraft(store, 'editor:new', const {}, {
        'text': text,
      }, () => const {});
      draft.start();
      text.text = 'A';
      text.text = 'A newer edit';
      draft.close();
      text.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final other = TextEditingController();
      final reopened = FormDraft(store, 'editor:new', const {}, {
        'text': other,
      }, () => const {});
      final body = await reopened.load();
      expect(body?['text'], 'A newer edit');
      await reopened.clear();
      other.dispose();
      expect(await store.get('draft', 'editor:new'), isNull);
    },
  );
  test('stale draft cannot override an edited record', () async {
    final store = NexModuleStore(harness.services, 'habits');
    final text = TextEditingController(text: 'unsaved');
    final draft = FormDraft(
      store,
      'editor:x',
      {'name': 'old'},
      {'text': text},
      () => const {},
    );
    draft.start();
    draft.changed();
    draft.close();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final reopened = FormDraft(
      store,
      'editor:x',
      {'name': 'new'},
      {'text': text},
      () => const {},
    );
    expect(await reopened.load(), isNull);
    await reopened.clear();
    text.dispose();
  });

  testWidgets('failed save retains form input and retry creates one record', (
    tester,
  ) async {
    final store = FaultStore(NexModuleStore(harness.services, 'habits'))
      ..failReads = false;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: HabitsScreen(store: store),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('habits-new')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('habit-field-name')),
      'A retained habit',
    );
    store.failWrites = true;
    await tester.ensureVisible(find.byKey(const ValueKey('habit-save')));
    await tester.tap(find.byKey(const ValueKey('habit-save')));
    await tester.pumpAndSettle();
    expect(
      find.text('Could not save. Your changes are still here; try again.'),
      findsOneWidget,
    );
    expect(await store.inner.list('habit'), isEmpty);
    store.failWrites = false;
    await tester.tap(find.byKey(const ValueKey('habit-save')));
    await tester.pumpAndSettle();
    expect(await store.inner.list('habit'), hasLength(1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  test(
    'interrupted compound deletion restores all exact record bodies',
    () async {
      final store = NexModuleStore(harness.services, 'habits');
      const parent = {
        'name': 'Preserved',
        'extra': {
          'future': [1, 2, 3],
        },
      };
      const child = {
        'habit': 'p',
        'amount': 3,
        'date': 'broken',
        'unknown': true,
      };
      await store.put('habit', 'p', parent);
      await store.put('check', 'c', child);
      await store.put('operation', 'habit:p', {
        'v': 1,
        'records': [
          {'kind': 'check', 'id': 'c', 'body': child},
          {'kind': 'habit', 'id': 'p', 'body': parent},
        ],
      });
      await store.delete('check', 'c');
      await RecordBundle.recover(store);
      expect(await store.get('habit', 'p'), parent);
      expect(await store.get('check', 'c'), child);
      expect(await store.list('operation'), isEmpty);
      final bundle = await RecordBundle.capture(
        store,
        'habit',
        'p',
        'check',
        'habit',
      );
      await bundle.delete();
      expect(await store.list('habit'), isEmpty);
      await bundle.restore();
      expect(await store.get('habit', 'p'), parent);
      expect(await store.get('check', 'c'), child);
    },
  );

  test(
    'a completed new-record draft cannot reappear after failed cleanup',
    () async {
      final store = NexModuleStore(harness.services, 'habits');
      final text = TextEditingController(text: 'saved text');
      final draft = FormDraft(store, 'habit:new', const {}, {
        'text': text,
      }, () => {'recordId': 'saved'});
      draft.start();
      draft.changed();
      draft.close();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await store.put('habit', 'saved', {'name': 'Acknowledged'});
      final reopened = FormDraft(store, 'habit:new', const {}, {
        'text': text,
      }, () => const {});
      expect(await reopened.load(), isNull);
      await reopened.clear();
      text.dispose();
    },
  );

  test(
    'transient checkpoint failure retries the newest edit after closing',
    () async {
      final inner = NexModuleStore(harness.services, 'habits');
      final store = FaultStore(inner)
        ..failReads = false
        ..draftFailures = 1;
      final text = TextEditingController();
      final draft = FormDraft(store, 'editor:retry', const {}, {
        'text': text,
      }, () => const {});
      draft.start();
      text.text = 'Old';
      text.text = 'Latest';
      draft.close();
      text.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final body = await inner.get('draft', 'editor:retry');
      expect((body?['fields'] as Map?)?['text'], 'Latest');
      await draft.clear();
    },
  );

  testWidgets(
    'back waits for the latest checkpoint before module data is removed',
    (tester) async {
      final inner = NexModuleStore(harness.services, 'habits');
      final gate = Completer<void>();
      final store = FaultStore(inner)
        ..failReads = false
        ..draftGate = gate.future;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: HabitsScreen(store: store),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('habits-new')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('habit-field-name')),
        '12345',
      );
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(
        find.byKey(const ValueKey('habit-field-name')),
        findsOneWidget,
        reason: 'the route remains until the pending write completes',
      );
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('habit-field-name')), findsNothing);
      final draft = await inner.get('draft', 'habit:new');
      expect((draft?['fields'] as Map?)?['name'], '12345');
      final removed = const HabitsModule().turnOff(
        tester.element(find.byType(HabitsScreen)),
        services: harness.services,
        preferences: harness.preferences,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('module-habits-off-delete')));
      await tester.pumpAndSettle();
      expect(await removed, isTrue);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      expect(
        await inner.list('draft'),
        isEmpty,
        reason: 'no checkpoint is recreated after removal',
      );
    },
  );
  test(
    'a failed flush keeps the editor recoverable for a later retry',
    () async {
      final store = FaultStore(NexModuleStore(harness.services, 'habits'))
        ..failReads = false
        ..failWrites = true;
      final text = TextEditingController(text: 'Keep this');
      final draft = FormDraft(store, 'editor:flush', const {}, {
        'text': text,
      }, () => const {});
      draft.start();
      draft.changed();
      expect(await draft.finish(), isFalse);
      store.failWrites = false;
      draft.resume();
      expect(await draft.finish(), isTrue);
      expect(
        ((await store.inner.get('draft', 'editor:flush'))?['fields']
            as Map?)?['text'],
        'Keep this',
      );
      await draft.clear();
      text.dispose();
    },
  );
}
