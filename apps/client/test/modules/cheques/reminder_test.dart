import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/cheques/reminders.dart';
import 'package:nex_client/modules/cheques/model.dart';

import '../../support/nex_harness.dart';
import 'fixtures.dart';

class AlarmStore extends NexModuleStore {
  AlarmStore(NexTestHarness h) : super(h.services, 'cheques');
  final armed = <String>[], cleared = <String>[], withdrawn = <String>[];
  List<ModuleRecord> stale = [];
  @override
  Future<List<ModuleRecord>> list(String kind) async =>
      kind == '__reminder' ? stale : await super.list(kind);
  bool result = true;
  String? body, title, source;
  @override
  Future<bool> setReminder(
    String key, {
    required String sourceKind,
    required String sourceId,
    required DateTime at,
    required String title,
    required String body,
  }) async {
    armed.add(key);
    this.body = body;
    this.title = title;
    source = '$sourceKind:$sourceId';
    return result;
  }

  @override
  Future<void> clearReminder(String key) async {
    cleared.add(key);
  }

  @override
  Future<void> withdrawReminder(String key) async {
    withdrawn.add(key);
  }
}

void main() {
  test(
    'private alarms reference the exact source and failures are honest',
    () async {
      final h = await NexTestHarness.create(name: 'cheque_alarm_');
      addTearDown(h.dispose);
      final store = AlarmStore(h),
          l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final c = Cheque('a', {
        ...chequeRaw(date: '2026-11-20'),
        'remind': true,
        'privateAlert': true,
      });
      store.result = false;
      expect(
        await armCheque(store, c, l10n, now: DateTime(2026, 11, 16)),
        isFalse,
      );
      expect(store.armed.toSet(), {'cheque:a:0', 'cheque:a:1', 'cheque:a:3'});
      expect(store.source, 'cheque:a');
      expect(store.body, isNot(contains('Sample party')));
      expect(store.body, isNot(contains('1000')));
    },
  );
  test(
    'upkeep preserves shown notices; explicit disable clears them',
    () async {
      final h = await NexTestHarness.create(name: 'cheque_alarm_');
      addTearDown(h.dispose);
      final store = AlarmStore(h),
          l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final c = Cheque('a', {
        ...chequeRaw(date: '2026-11-20'),
        'remind': true,
        'privateAlert': true,
      });
      await armCheque(
        store,
        c,
        l10n,
        now: DateTime(2026, 11, 21),
        upkeep: true,
      );
      expect(store.withdrawn.length, 6);
      expect(store.cleared, isEmpty);
      await armCheque(
        store,
        Cheque('a', {...c.raw, 'remind': false}),
        l10n,
        now: DateTime(2026, 11, 16),
      );
      expect(store.cleared.length, 6);
      expect(store.armed, isEmpty);
    },
  );
  test('plan schedule edits withdraw obsolete slots without touching cheque alarms', () async {
    final h = await NexTestHarness.create(name: 'plan_prune_');
    addTearDown(h.dispose);
    final store = AlarmStore(h),
        l10n = await AppLocalizations.delegate.load(const Locale('en'));
    store.stale = [
      for (final id in ['plan:p:99:0', 'cheque:a:0'])
        ModuleRecord(
          module: 'cheques',
          kind: '__reminder',
          id: id,
          body: const {},
          updatedAt: DateTime(2026),
        ),
    ];
    await renewPlans(store, l10n);
    expect(store.withdrawn, ['plan:p:99:0']);
    expect(store.cleared, isEmpty);
  });
}
