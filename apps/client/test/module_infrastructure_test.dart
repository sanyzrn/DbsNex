import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/habits/module.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/module_registry.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/platform/reminders.dart';

import 'support/nex_harness.dart';

/// The shared module infrastructure: the write path's scoped reminder
/// reconciliation, the record bundle's transactional delete, the store's
/// reserved kinds, the one draft implementation, and the gates the registry
/// answers (`docs/17-modules.md`).
void main() {
  late NexTestHarness harness;
  setUp(() async => harness = await NexTestHarness.create(name: 'nex_infra_'));
  tearDown(() => harness.dispose());

  group('the registry answers through one index and one gate', () {
    test('every module is in the by-id index exactly once', () {
      expect(nexModulesById.keys.toSet(), {
        for (final module in nexModules) module.id,
      });
      for (final module in nexModules) {
        expect(identical(nexModulesById[module.id], module), isTrue);
      }
    });

    test('active means available and added, and nothing else does', () async {
      final prefs = harness.preferences;
      expect(nexModuleActive('habits', prefs), isFalse);
      expect(nexModuleActive('no-such-module', prefs), isFalse);
      await prefs.setModuleOn('habits', true);
      await prefs.setModuleOn('no-such-module', true);
      expect(nexModuleActive('habits', prefs), isTrue);
      expect(nexModuleActive('no-such-module', prefs), isFalse);
      // Every add-on is available on a phone since 2.8.4; a desktop has
      // none, so there a saved choice is still not availability.
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        expect(
          nexModuleActive('habits', prefs),
          isFalse,
          reason: 'a saved choice is not availability',
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('a write reconciles only the reminders pointing at it', () {
    test('not every module\u2019s every reminder', () async {
      final prefs = harness.preferences;
      await prefs.setModuleOn('habits', true);
      await prefs.setModuleOn('occasions', true);
      final store = NexModuleStore(harness.services, 'habits');
      await store.put('habit', 'one', {'name': 'Water'});
      final occasionStore = NexModuleStore(harness.services, 'occasions');
      await occasionStore.put('occasion', 'one', {'title': 'Birthday'});

      harness.db.moduleRecordsCalls.clear();
      await store.put('check', 'one:2026-11-15', {'habit': 'one', 'amount': 1});

      final reminderReads = harness.db.moduleRecordsCalls
          .where((call) => call.endsWith('/__reminder'))
          .toList();
      expect(reminderReads, ['habits/__reminder']);
      expect(reminderReads, isNot(contains('occasions/__reminder')));
    });

    test('a write to a module that is off reconciles nothing', () async {
      final store = NexModuleStore(harness.services, 'habits');
      harness.db.moduleRecordsCalls.clear();
      await store.put('habit', 'one', {'name': 'Water'});
      expect(
        harness.db.moduleRecordsCalls.where((c) => c.endsWith('__reminder')),
        isEmpty,
      );
    });
  });

  group('a record bundle deletes in one transaction', () {
    test('and writes no journal on the way', () async {
      final store = NexModuleStore(harness.services, 'words');
      await store.put('card', 'w1', {'headword': 'vex'});
      await store.put('check', 'c1', {'card': 'w1'});
      await store.put('draft', 'card:w1', {'headword': 'unsaved'});
      final bundle = await NexModuleRecordBundle.capture(
        store,
        'card',
        'w1',
        'check',
        'card',
      );
      await bundle.delete();
      expect(await store.list('card'), isEmpty);
      expect(await store.list('check'), isEmpty);
      expect(await store.get('draft', 'card:w1'), isNull);
      expect(await store.list('operation'), isEmpty);
      await bundle.restore();
      expect(await store.get('card', 'w1'), {'headword': 'vex'});
    });

    test('a refused delete leaves every record exactly where it was', () async {
      final store = NexModuleStore(harness.services, 'words');
      await store.put('card', 'w1', {'headword': 'vex'});
      await store.put('check', 'c1', {'card': 'w1'});
      final bundle = await NexModuleRecordBundle.capture(
        store,
        'card',
        'w1',
        'check',
        'card',
      );
      harness.db.failModuleDeleteMany = 1;
      await expectLater(bundle.delete(), throwsStateError);
      expect(await store.get('card', 'w1'), {'headword': 'vex'});
      expect(await store.get('check', 'c1'), {'card': 'w1'});
      expect(await store.list('operation'), isEmpty);
    });

    test('extra records ride along when a capture asks for them', () async {
      final store = NexModuleStore(harness.services, 'words');
      await store.put('card', 'w1', {'headword': 'vex'});
      await store.put('settings', 's1', {'newPerDay': 5});
      final bundle = await NexModuleRecordBundle.capture(
        store,
        'card',
        'w1',
        'check',
        'card',
        also: const [(kind: 'settings', id: 's1')],
      );
      await bundle.delete();
      expect(await store.get('settings', 's1'), isNull);
      await bundle.restore();
      expect((await store.get('settings', 's1'))?['newPerDay'], 5);
    });

    test('journals older versions left behind are still replayed', () async {
      final store = NexModuleStore(harness.services, 'words');
      const body = {'headword': 'vex'};
      await store.put('card', 'w1', body);
      await store.put('operation', 'card:w1', {
        'v': 1,
        'records': [
          {'kind': 'card', 'id': 'w1', 'body': body},
        ],
      });
      await store.delete('card', 'w1');
      await NexModuleRecordBundle.recover(store);
      expect(await store.get('card', 'w1'), body);
      expect(await store.list('operation'), isEmpty);
    });
  });

  group('the kinds the platform keeps for itself', () {
    test('cannot be written through a module\u2019s store', () async {
      final store = NexModuleStore(harness.services, 'words');
      await expectLater(
        () => store.put('__reminder', 'smuggled', {'at': 'x'}),
        throwsArgumentError,
      );
      await expectLater(
        () => store.put('__recovery', 'smuggled', {}),
        throwsArgumentError,
      );
      await expectLater(
        () => store.delete('__reminder', 'smuggled'),
        throwsArgumentError,
      );
      await expectLater(
        () => store.deleteRecords(const [(kind: '__recovery', id: 'x')]),
        throwsArgumentError,
      );
    });

    test(
      'reading a platform reminder stays open for the legacy migration',
      () async {
        final store = NexModuleStore(harness.services, 'habits');
        await harness.db.modulePut('habits', '__reminder', 'habit:old', {
          'repeat': 'daily',
          'at': '2026-11-01T04:00:00.000Z',
        });
        expect(await store.get('__reminder', 'habit:old'), isNotNull);
      },
    );
  });

  group('one draft implementation, both names', () {
    test('the checked name is the same class', () {
      expect(identical(NexModuleFormDraft, NexCheckedModuleFormDraft), isTrue);
    });

    test('an untouched form writes no checkpoint on close', () async {
      final store = NexModuleStore(harness.services, 'habits');
      final text = TextEditingController(text: 'same');
      final draft = NexModuleFormDraft(store, 'habit:new', const {}, {
        'text': text,
      }, () => const {});
      draft.start();
      draft.close();
      await draft.finish();
      expect(await store.get('draft', 'habit:new'), isNull);
      text.dispose();
    });

    test('a touched form does, and clear reports success', () async {
      final store = NexModuleStore(harness.services, 'habits');
      final text = TextEditingController();
      final draft = NexModuleFormDraft(store, 'habit:new', const {}, {
        'text': text,
      }, () => const {});
      draft.start();
      text.text = 'typed';
      draft.close();
      await draft.finish();
      final body = await store.get('draft', 'habit:new');
      expect((body?['fields'] as Map?)?['text'], 'typed');
      expect(await draft.clear(), isTrue);
      expect(await store.get('draft', 'habit:new'), isNull);
      text.dispose();
    });

    test('start cannot listen twice, and a failed load is visible', () async {
      final store = _FailingDraftReads(
        NexModuleStore(harness.services, 'habits'),
      );
      final text = TextEditingController();
      final draft = NexModuleFormDraft(store, 'habit:x', const {}, {
        'text': text,
      }, () => const {});
      draft.start();
      draft.start();
      expect(draft.loadFailed, isFalse);
      expect(await draft.load(), isNull);
      expect(draft.loadFailed, isTrue);
      draft.close();
      await draft.finish();
      text.dispose();
    });
  });

  group('a daily reminder keeps the face of the clock it was set for', () {
    test('the next ring is read from the wall, not the stored instant', () {
      final now = DateTime(2026, 11, 15, 10);
      // Set at noon; the stored instant, read in a zone that has since
      // moved, shows as eight in the morning on today's wall.
      final ring = nexNextDailyReminderRing({
        'repeat': 'daily',
        'at': DateTime(2026, 10, 1, 8).toUtc().toIso8601String(),
        'wallMinutes': 12 * 60,
      }, now);
      expect(ring, DateTime(2026, 11, 15, 12));
    });

    test(
      'a record written before the wall was kept falls back to the instant',
      () {
        final now = DateTime(2026, 11, 15, 10);
        final yesterdayNine = DateTime(2026, 11, 14, 9);
        final ring = nexNextDailyReminderRing({
          'repeat': 'daily',
          'at': yesterdayNine.toUtc().toIso8601String(),
        }, now);
        expect(ring, DateTime(2026, 11, 16, 9));
      },
    );

    test('a one-shot reminder stays the instant it was given', () {
      final at = DateTime.utc(2026, 12, 1, 9);
      expect(
        nexNextDailyReminderRing({
          'at': at.toIso8601String(),
        }, DateTime(2026, 11, 15)),
        at,
      );
      expect(
        nexNextDailyReminderRing({'at': 'not a date'}, DateTime(2026, 11, 15)),
        isNull,
      );
    });

    test('a kept wall face survives a full restore', () async {
      final prefs = harness.preferences;
      await prefs.setModuleOn('habits', true);
      final services = harness.services;
      await services.modulePut('habits', 'habit', 'one', {
        'name': 'Water',
        'schedule': 'daily',
        'goal': 1,
      });
      final inTwoHours = DateTime.now().add(const Duration(hours: 2));
      await services.worker.modulePut('habits', '__reminder', 'habit:one', {
        'sourceKind': 'habit',
        'sourceId': 'one',
        'at': DateTime.now()
            .subtract(const Duration(days: 40))
            .toUtc()
            .toIso8601String(),
        'wallMinutes': inTwoHours.hour * 60 + inTwoHours.minute,
        'repeat': 'daily',
        'title': 'Habit',
        'body': 'A habit is waiting.',
      });
      final wanted = await services.restoreModuleReminders();
      expect(wanted, contains(NexModuleAlarms.moduleId('habits', 'habit:one')));
    });
  });

  group('the lifecycle survives a storage that refuses', () {
    Future<BuildContext> pumpHost(WidgetTester tester, Widget home) async {
      late BuildContext captured;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              captured = context;
              return home;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      return captured;
    }

    testWidgets('a delete that fails leaves the module on, and says so', (
      tester,
    ) async {
      final prefs = harness.preferences;
      await prefs.setModuleOn('habits', true);
      final store = NexModuleStore(harness.services, 'habits');
      await store.put('habit', 'one', {'name': 'Water'});
      harness.db.failModuleDeleteAll = 1;

      final context = await pumpHost(tester, const SizedBox());
      final off = const HabitsModule().turnOff(
        context,
        services: harness.services,
        preferences: prefs,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('module-habits-off-delete')));
      await tester.pumpAndSettle();

      // The wipe is one transaction: failing, it deleted nothing. Turning
      // the module off anyway would tell the person their records were gone
      // while all of them stayed — so it stays on, and the banner says why.
      expect(await off, isFalse);
      expect(prefs.isModuleOn('habits'), isTrue);
      expect(await store.list('habit'), isNotEmpty);
      expect(find.textContaining('could not be deleted'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('turning it on arms what its kept data still asks for', (
      tester,
    ) async {
      final prefs = harness.preferences;
      final services = harness.services;
      await services.worker.modulePut('habits', '__reminder', 'habit:one', {
        'sourceKind': 'habit',
        'sourceId': 'one',
        'at': DateTime.now()
            .add(const Duration(days: 1))
            .toUtc()
            .toIso8601String(),
        'title': 'Habit',
        'body': 'A habit is waiting.',
      });
      final context = await pumpHost(tester, const SizedBox());
      harness.db.moduleRecordsCalls.clear();
      await const HabitsModule().turnOn(
        context,
        services: services,
        preferences: prefs,
      );
      expect(prefs.isModuleOn('habits'), isTrue);
      expect(
        harness.db.moduleRecordsCalls,
        contains('habits/__reminder'),
        reason: 'the re-arm ran without waiting for the next launch',
      );
    });
  });
}

/// A store whose draft reads fail once, for [NexModuleFormDraft.loadFailed].
class _FailingDraftReads implements NexModuleStore {
  _FailingDraftReads(this.inner);
  final NexModuleStore inner;

  @override
  Future<Map<String, Object?>?> get(String kind, String id) async {
    if (kind == 'draft') throw StateError('draft read refused');
    return inner.get(kind, id);
  }

  @override
  Future<void> deleteRecords(List<({String kind, String id})> records) =>
      inner.deleteRecords(records);

  @override
  Future<void> quarantine(ModuleRecord record) => inner.quarantine(record);

  @override
  Future<void> put(String kind, String id, Map<String, Object?> body) =>
      inner.put(kind, id, body);

  @override
  Future<void> delete(String kind, String id) => inner.delete(kind, id);

  @override
  Future<List<ModuleRecord>> list(String kind) => inner.list(kind);

  @override
  String get module => inner.module;

  @override
  Stream<void> get changes => inner.changes;

  @override
  Stream<void> get draftChanges => inner.draftChanges;

  @override
  String newId() => inner.newId();

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
  Future<void> withdrawReminder(String key) => inner.withdrawReminder(key);
}
