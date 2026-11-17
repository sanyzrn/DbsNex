import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/l10n/app_localizations_en.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/maintenance/asset_page.dart';
import 'package:nex_client/modules/maintenance/car_reminders.dart';
import 'package:nex_client/modules/maintenance/maintenance_shared.dart';
import 'package:nex_client/modules/maintenance/models.dart';

import '../../support/nex_harness.dart';

/// A store that records what would be scheduled, keeping the reminder rows
/// it was told about as `__reminder` records.
class AlarmStore extends NexModuleStore {
  AlarmStore(NexTestHarness h) : super(h.services, 'maintenance');
  final armed = <String, DateTime>{};
  final withdrawn = <String>[], cleared = <String>[];
  final held = <String, Map<String, Object?>>{};
  bool result = true;

  @override
  Future<List<ModuleRecord>> list(String kind) async => kind == '__reminder'
      ? [
          for (final MapEntry(:key, :value) in held.entries)
            ModuleRecord(
              module: 'maintenance',
              kind: '__reminder',
              id: key,
              body: value,
              updatedAt: DateTime(2026),
            ),
        ]
      : await super.list(kind);

  @override
  Future<bool> setReminder(
    String key, {
    required String sourceKind,
    required String sourceId,
    required DateTime at,
    required String title,
    required String body,
  }) async {
    armed[key] = at;
    if (result) {
      held[key] = {'at': at.toUtc().toIso8601String(), 'body': body};
    }
    return result;
  }

  @override
  Future<void> withdrawReminder(String key) async {
    withdrawn.add(key);
    held.remove(key);
  }

  @override
  Future<void> clearReminder(String key) async {
    cleared.add(key);
    held.remove(key);
  }
}

void main() {
  final l10n = AppLocalizationsEn();
  late NexTestHarness h;
  late AlarmStore store;
  final now = DateTime(2026, 11, 17, 10);

  setUp(() async {
    h = await NexTestHarness.create(name: 'maintenance_car_alarm_');
    store = AlarmStore(h);
  });
  tearDown(() => h.dispose());

  MaintenanceAsset car({
    DateTime? insurance,
    bool remind = true,
    bool archived = false,
  }) => MaintenanceAsset(
    id: 'a1',
    nickname: 'Pride',
    type: 'car',
    insuranceExpiresAt: insurance ?? DateTime(2027, 1, 20),
    insuranceRemind: remind,
    archived: archived,
  );

  test('the remind flag is kept only when on, and read back', () {
    expect(car(remind: false).toBody().containsKey('insuranceRemind'), isFalse);
    final read = MaintenanceAsset.fromBody('a1', car().toBody());
    expect(read.insuranceRemind, isTrue);
    expect(read.inspectionRemind, isFalse);
  });

  test(
    'an alarm follows the date: set, moved when renewed, never twice',
    () async {
      expect(await CarReminders.plan(store, [car()], l10n, now: now), isTrue);
      expect(store.armed['insurance:a1'], DateTime(2027, 1, 6, 9));
      // Nothing changed: not set again.
      store.armed.clear();
      await CarReminders.plan(store, [car()], l10n, now: now);
      expect(store.armed, isEmpty);
      // Renewed for a year: the alarm moves with the date.
      await CarReminders.plan(
        store,
        [car(insurance: DateTime(2028, 1, 20))],
        l10n,
        now: now,
      );
      expect(store.armed['insurance:a1'], DateTime(2028, 1, 6, 9));
      // Inspection has no date, so nothing is set for it.
      expect(store.armed.containsKey('inspection:a1'), isFalse);
    },
  );

  test(
    'archived, turned off or past its moment: the alarm is withdrawn',
    () async {
      for (final asset in [
        car(archived: true),
        car(remind: false),
        car(insurance: DateTime(2026, 11, 20)),
      ]) {
        store.held['insurance:a1'] = {'at': 'x', 'body': 'y'};
        store.withdrawn.clear();
        await CarReminders.plan(store, [asset], l10n, now: now);
        expect(store.withdrawn, ['insurance:a1']);
      }
      // No alarm held and none wanted: nothing to withdraw.
      store.withdrawn.clear();
      await CarReminders.plan(store, [car(remind: false)], l10n, now: now);
      expect(store.withdrawn, isEmpty);
    },
  );

  test('a refused alarm is reported', () async {
    store.result = false;
    expect(await CarReminders.plan(store, [car()], l10n, now: now), isFalse);
  });

  testWidgets('a date picked on the page keeps a set reminder, and Off '
      'turns it off', (tester) async {
    await tester.runAsync(
      () => store.put('asset', 'a1', {
        ...car(insurance: DateTime.now().add(const Duration(days: 60)))
            .toBody(),
        'meterKind': 'none',
      }),
    );
    tester.view.physicalSize = const Size(800, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AssetPage(store: store, assetId: 'a1'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Reminder on, 14 days before'), findsOneWidget);
    final button = find.byKey(
      const ValueKey('maintenance-car-remind-insurance'),
    );
    await Scrollable.ensureVisible(tester.element(button), alignment: 0.4);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('maintenance-car-reminder-off')),
    );
    await tester.pumpAndSettle();
    final saved = (await tester.runAsync(() => store.get('asset', 'a1')))!;
    expect(saved.containsKey('insuranceRemind'), isFalse);
    expect(store.cleared, ['insurance:a1']);
    expect(find.text('Remind me 14 days before'), findsWidgets);
  });

  group('shared shape', () {
    test(
      'insurance, inspection and dated services fall due; archived do not',
      () {
        final shared = MaintenanceShared(
          assets: [
            MaintenanceAsset(
              id: 'a1',
              nickname: 'Pride',
              type: 'car',
              insuranceExpiresAt: DateTime(2026, 12, 1),
              inspectionExpiresAt: DateTime(2027, 6, 1),
            ),
            MaintenanceAsset(
              id: 'a2',
              nickname: 'Old',
              type: 'car',
              insuranceExpiresAt: DateTime(2026, 12, 2),
              archived: true,
            ),
          ],
          events: [
            ServiceEvent.fromBody('e1', {
              'assetId': 'a1',
              'task': 'Oil change',
              'date': '2026-09-01',
              'schema': 2,
            }),
          ],
          rules: [
            IntervalRule.fromBody('r1', {
              'assetId': 'a1',
              'task': 'Oil change',
              'months': 3,
              'schema': 2,
            })!,
          ],
        );
        final dues = shared.duesBetween(
          DateTime(2026, 11, 1),
          DateTime(2026, 12, 31),
        );
        expect(dues.map((d) => '${d.kind}:${d.recordId}'), [
          'insurance-expiry:a1',
          'service:r1',
        ]);
        expect(dues.last.at, DateTime(2026, 12, 1));
        expect(dues.last.title, 'Oil change · Pride');
      },
    );

    test('a line per record in the person\'s words; readings stay out', () {
      ModuleRecord r(String kind, Map<String, Object?> body) => ModuleRecord(
        module: 'maintenance',
        kind: kind,
        id: 'x',
        body: body,
        updatedAt: DateTime(2026),
      );
      expect(
        MaintenanceShared.summarize(
          r('asset', {'nickname': 'Pride', 'model': '131'}),
        )!.detail,
        '131',
      );
      expect(
        MaintenanceShared.summarize(
          r('event', {'task': 'Oil', 'provider': 'Ali', 'notes': 'synthetic'}),
        )!.detail,
        'Ali · synthetic',
      );
      expect(
        MaintenanceShared.summarize(r('fuel', {'rate': 'Quota'}))!.title,
        'Quota',
      );
      expect(MaintenanceShared.summarize(r('reading', {'value': 3})), isNull);
      expect(MaintenanceShared.summarize(r('draft', {'task': 'x'})), isNull);
    });
  });
}
