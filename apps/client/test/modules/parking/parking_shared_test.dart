import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/parking/parking_alarm.dart';
import 'package:nex_client/modules/parking/parking_shared.dart';

import '../../support/nex_harness.dart';
import 'parking_fault_store.dart';

/// Parking in the shape every module shares (docs/18) — its paid times as
/// dates falling due, a line about each record — and a reminder before the
/// end that follows the end when it is changed (2.8.4).
class _Recording extends FaultStore {
  _Recording(super.inner);

  final set = <(String, DateTime, String)>[];
  final cleared = <String>[];

  @override
  Future<bool> setReminder(
    String key, {
    required String sourceKind,
    required String sourceId,
    required DateTime at,
    required String title,
    required String body,
  }) async {
    set.add((key, at, title));
    return true;
  }

  @override
  Future<void> clearReminder(String key) async => cleared.add(key);
}

void main() {
  ModuleRecord session(String id, Map<String, Object?> body) => ModuleRecord(
    module: 'parking',
    kind: 'session',
    id: id,
    body: body,
    updatedAt: DateTime(2026),
  );

  test('a paid time is a date falling due; a closed parking is done', () {
    final dues = ParkingShared([
      session('a', {
        'place': 'North lot',
        'startedAt': '2026-11-20T08:00:00Z',
        'expiresAt': '2026-11-20T10:00:00Z',
      }),
      session('b', {
        'vehicle': 'Pride',
        'startedAt': '2026-11-21T08:00:00Z',
        'expiresAt': '2026-11-21T09:00:00Z',
        'foundAt': '2026-11-21T08:40:00Z',
      }),
      session('c', {'place': 'No meter', 'startedAt': '2026-11-20T08:00:00Z'}),
      session('d', {
        'place': 'Next month',
        'startedAt': '2026-12-20T08:00:00Z',
        'expiresAt': '2026-12-20T09:00:00Z',
      }),
    ]).duesBetween(DateTime.utc(2026, 11, 1), DateTime.utc(2026, 11, 30));
    expect([for (final d in dues) d.recordId], ['a', 'b']);
    expect(dues.first.title, 'North lot');
    expect(dues.first.kind, 'paid-until');
    expect(dues.first.done, isFalse);
    expect(dues.last.title, 'Pride', reason: 'no place: the vehicle names it');
    expect(dues.last.done, isTrue);
  });

  test('a line about a parking or a place; nothing about the module\'s own '
      'bookkeeping', () {
    final line = ParkingShared.summarize(
      session('a', {'place': 'Mall', 'floor': '-2', 'spot': 'B14'}),
    )!;
    expect((line.title, line.detail), ('Mall', '-2 · B14'));
    expect(ParkingShared.summarize(session('e', {})), isNull);
    expect(
      ParkingShared.summarize(
        ModuleRecord(
          module: 'parking',
          kind: 'draft',
          id: 'x',
          body: const {'place': 'typing'},
          updatedAt: DateTime(2026),
        ),
      ),
      isNull,
    );
  });

  testWidgets('the reminder before the end follows a changed end, and goes '
      'when the new end leaves no room for it', (tester) async {
    final h = await NexTestHarness.create(name: 'parking_alarm_');
    addTearDown(h.dispose);
    final store = _Recording(NexModuleStore(h.services, 'parking'));
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    final end = DateTime.now().add(const Duration(hours: 2));
    await tester.runAsync(() async {
      await store.put('session', 's', {
        'place': 'North lot',
        'startedAt': DateTime.now().toUtc().toIso8601String(),
        'expiresAt': end.toUtc().toIso8601String(),
      });
      expect(
        await ParkingAlarm.arm(
          context,
          store,
          's',
          expiresAt: end,
          minutes: 15,
          place: 'North lot',
        ),
        isTrue,
      );
    });
    expect(store.set.single.$1, 'session:s');
    expect(store.set.single.$3, 'Parking: 15 min left');
    await tester.runAsync(() async {
      expect((await store.get('session', 's'))!['remindMinutes'], 15);

      // The end moves an hour later: the reminder moves with it.
      final later = end.add(const Duration(hours: 1));
      await store.put('session', 's', {
        ...?await store.get('session', 's'),
        'expiresAt': later.toUtc().toIso8601String(),
      });
      await ParkingAlarm.follow(context, store, 's');
      expect(
        store.set.last.$2.difference(
          later.subtract(const Duration(minutes: 15)),
        ),
        lessThan(const Duration(seconds: 1)),
      );

      // Now the end is five minutes away: fifteen before it has passed.
      await store.put('session', 's', {
        ...?await store.get('session', 's'),
        'expiresAt': DateTime.now()
            .add(const Duration(minutes: 5))
            .toUtc()
            .toIso8601String(),
      });
      await ParkingAlarm.follow(context, store, 's');
      expect(store.cleared, ['session:s']);
      expect(
        (await store.get('session', 's'))!.containsKey('remindMinutes'),
        isFalse,
      );
    });
  });
}
