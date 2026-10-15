import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/maintenance/controller.dart';
import 'package:nex_client/modules/maintenance/models.dart';
import 'package:nex_client/modules/maintenance/units.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/platform/nex_services.dart';

import '../../support/nex_harness.dart';

/// The controller over a real store: writes land ordered, rules
/// replace per task, deleting an asset takes its history and Undo
/// restores all of it, unit conversion rewrites exactly, and no other
/// module sees any of it.
void main() {
  late NexTestHarness harness;
  late NexModuleStore store;
  late MaintenanceController controller;

  setUp(() async {
    harness = await NexTestHarness.create(name: 'nex_mnt_');
    store = NexModuleStore(harness.services, 'maintenance');
    controller = MaintenanceController(store);
    await controller.load();
  });

  tearDown(() async {
    controller.dispose();
    await harness.dispose();
  });

  MaintenanceAsset car({String id = 'car-1', bool archived = false}) =>
      MaintenanceAsset(
        id: id,
        nickname: 'Car',
        type: 'car',
        meterKind: MeterKind.distance,
        distanceUnit: DistanceUnit.km,
        archived: archived,
      );

  ServiceEvent oilChange({
    String id = 'ev-1',
    String assetId = 'car-1',
    DateTime? date,
    int? meter = 100000,
    int? cost = 1500000,
  }) => ServiceEvent(
    id: id,
    assetId: assetId,
    date: date ?? DateTime(2026, 6, 1),
    task: 'oil change',
    meter: meter,
    meterUnit: meter == null ? null : DistanceUnit.km,
    cost: cost,
    currency: cost == null ? null : 'IRR',
  );

  test('assets, events and rules are written and read back', () async {
    await controller.saveAsset(car());
    await controller.saveEvent(oilChange());
    await controller.saveRule(
      IntervalRule(
        id: controller.ruleIdFor('car-1', 'oil change'),
        assetId: 'car-1',
        task: 'oil change',
        months: 6,
        meters: 10000,
        meterUnit: DistanceUnit.km,
      ),
    );
    expect(controller.assets, hasLength(1));
    expect(controller.events, hasLength(1));
    expect(controller.rules, hasLength(1));
    expect(controller.rules.first.meters, 10000);
    expect(controller.assetById('car-1')!.nickname, 'Car');
    expect(controller.eventById('ev-1')!.task, 'oil change');
  });

  test('saving a rule for the same task replaces, never duplicates', () async {
    await controller.saveAsset(car());
    await controller.saveRule(
      IntervalRule(
        id: controller.ruleIdFor('car-1', 'Oil Change'),
        assetId: 'car-1',
        task: 'Oil Change',
        months: 6,
      ),
    );
    await controller.load();
    await controller.saveRule(
      IntervalRule(
        // Case-insensitive: the same task reuses the existing id.
        id: controller.ruleIdFor('car-1', 'oil change'),
        assetId: 'car-1',
        task: 'oil change',
        days: 180,
      ),
    );
    expect(controller.rules, hasLength(1));
    expect(controller.rules.first.days, 180);
    // A different task is a different rule.
    await controller.saveRule(
      IntervalRule(
        id: controller.ruleIdFor('car-1', 'brakes'),
        assetId: 'car-1',
        task: 'brakes',
        days: 365,
      ),
    );
    expect(controller.rules, hasLength(2));
  });

  test(
    'deleting an asset removes events and rules; Undo restores all',
    () async {
      await controller.saveAsset(car());
      await controller.saveEvent(oilChange());
      await controller.saveEvent(
        oilChange(id: 'ev-2', date: DateTime(2026, 9, 1)),
      );
      await controller.saveRule(
        IntervalRule(
          id: controller.ruleIdFor('car-1', 'oil change'),
          assetId: 'car-1',
          task: 'oil change',
          months: 6,
        ),
      );
      final snapshot = controller.snapshotOf('car-1');
      expect(snapshot.events, hasLength(2));
      expect(snapshot.rules, hasLength(1));

      await controller.deleteAsset('car-1');
      expect(controller.assets, isEmpty);
      expect(controller.events, isEmpty);
      expect(controller.rules, isEmpty);

      await controller.restoreAsset(
        snapshot.asset,
        snapshot.events,
        snapshot.rules,
      );
      expect(controller.assets, hasLength(1));
      expect(controller.events, hasLength(2));
      expect(controller.rules, hasLength(1));
      expect(controller.eventById('ev-2')!.date, DateTime(2026, 9, 1));
    },
  );

  test('archive keeps everything and unarchive brings it back', () async {
    await controller.saveAsset(car());
    await controller.saveEvent(oilChange());
    await controller.setArchived(controller.assets.first, true);
    expect(controller.assets.single.archived, isTrue);
    expect(controller.events, hasLength(1)); // untouched
    await controller.setArchived(controller.assets.first, false);
    expect(controller.assets.single.archived, isFalse);
  });

  test('the unit conversion rewrites readings and rules exactly', () async {
    await controller.saveAsset(car());
    await controller.saveEvent(oilChange(meter: 100000));
    await controller.saveRule(
      IntervalRule(
        id: controller.ruleIdFor('car-1', 'oil change'),
        assetId: 'car-1',
        task: 'oil change',
        meters: 10000,
        meterUnit: DistanceUnit.km,
      ),
    );

    await controller.convertAssetUnit(
      'car-1',
      DistanceUnit.km,
      DistanceUnit.mi,
    );

    final event = controller.events.single;
    expect(event.meter, 62137119);
    expect(event.meterScale, 1000); // 100000 × 15625/25146, half up
    expect(event.meterUnit, DistanceUnit.mi);
    final rule = controller.rules.single;
    expect(rule.meters, 6213712);
    expect(rule.meterScale, 1000); // 10000 km as miles
    expect(rule.meterUnit, DistanceUnit.mi);

    // And back: within the unit of drift integers carry.
    await controller.convertAssetUnit(
      'car-1',
      DistanceUnit.mi,
      DistanceUnit.km,
    );
    expect(
      controller.events.single.meter,
      100000000,
    ); // exact: 62137 → 99999.5 → 100000? see below
  });

  test('events survive a fresh controller, as after reopening', () async {
    await controller.saveAsset(car());
    await controller.saveEvent(oilChange(cost: 42, meter: 7));
    final reopened = MaintenanceController(store);
    await reopened.load();
    expect(reopened.assets, hasLength(1));
    expect(reopened.events.single.cost, 42);
    expect(reopened.events.single.meter, 7);
    reopened.dispose();
  });

  test('no other module sees these records', () async {
    await controller.saveAsset(car());
    final other = NexModuleStore(harness.services, 'expenses');
    expect(await other.list('asset'), isEmpty);
    expect(
      await harness.services.moduleRecords('maintenance', 'asset'),
      hasLength(1),
    );
  });

  test('ids are unique and prefixed', () {
    expect(controller.newAssetId(), isNot(controller.newAssetId()));
    expect(controller.newEventId(), startsWith('event-'));
    expect(controller.newAssetId(), startsWith('asset-'));
  });
}
