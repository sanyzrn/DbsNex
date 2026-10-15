import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/maintenance/controller.dart';
import 'package:nex_client/modules/maintenance/models.dart';
import 'package:nex_client/modules/maintenance/units.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/platform/nex_services.dart';
import '../../support/nex_harness.dart';

class FaultStore extends NexModuleStore {
  FaultStore(NexServices services) : super(services, 'maintenance');
  String? failKind;
  @override
  Future<void> put(String kind, String id, Map<String, Object?> body) async {
    await super.put(kind, id, body);
    if (kind == failKind) {
      failKind = null;
      throw StateError('after write');
    }
  }
}

void main() {
  late NexTestHarness h;
  late FaultStore store;
  late MaintenanceController c;
  final a = MaintenanceAsset(
    id: 'a',
    nickname: 'Car',
    type: 'car',
    meterKind: MeterKind.distance,
    distanceUnit: DistanceUnit.km,
  );
  setUp(() async {
    h = await NexTestHarness.create(name: 'maintenance_reliability_');
    store = FaultStore(h.services);
    c = MaintenanceController(store);
    await c.load();
    await c.saveAsset(a);
  });
  tearDown(() async {
    c.dispose();
    await h.dispose();
  });
  test('independent current reading does not create a service', () async {
    await c.saveReading(
      MaintenanceReading(
        id: 'm',
        assetId: 'a',
        value: 123456,
        kind: MeterKind.distance,
        unit: DistanceUnit.km,
        at: DateTime.now().toUtc(),
      ),
    );
    expect(c.events, isEmpty);
    expect(c.readings.single.milli, 123456);
  });
  test(
    'post-write failure rolls back and retry is one stable reading',
    () async {
      final entry = MaintenanceReading(
        id: 'm',
        assetId: 'a',
        value: 1000,
        kind: MeterKind.distance,
        unit: DistanceUnit.km,
        at: DateTime.now().toUtc(),
      );
      store.failKind = 'reading';
      await expectLater(c.saveReading(entry), throwsStateError);
      expect(await store.get('reading', 'm'), isNull);
      await c.saveReading(entry);
      expect(await store.list('reading'), hasLength(1));
      expect(await store.list('operation'), isEmpty);
    },
  );
  test(
    'concurrent same-task rule saves resolve identity inside mutation queue',
    () async {
      await Future.wait([
        c.saveRule(
          const IntervalRule(id: 'one', assetId: 'a', task: 'Oil', days: 10),
        ),
        c.saveRule(
          const IntervalRule(
            id: 'two',
            assetId: 'a',
            task: '  OIL  ',
            days: 20,
          ),
        ),
      ]);
      expect(await store.list('rule'), hasLength(1));
      expect(c.rules.single.days, 20);
    },
  );
  test(
    'fresh asset edit keeps archive and fields added by another writer',
    () async {
      await store.put('asset', 'a', {
        ...a.toBody(),
        'archived': true,
        'future': {'keep': 1},
      });
      await c.saveAsset(
        MaintenanceAsset(
          id: 'a',
          nickname: 'Renamed',
          type: 'car',
          meterKind: MeterKind.distance,
          distanceUnit: DistanceUnit.km,
        ),
        existing: a,
        editedKeys: ['nickname'],
      );
      final raw = (await store.get('asset', 'a'))!;
      expect(raw['archived'], true);
      expect(raw['future'], {'keep': 1});
      expect(raw['nickname'], 'Renamed');
    },
  );
  test(
    'compound deletion and Undo preserve malformed children and drafts exactly',
    () async {
      final raw = {
        'assetId': 'a',
        'task': '?',
        'future': [1, 2],
        'date': 'broken',
      };
      final draft = {
        'fields': {'parentId': 'a', 'raw': '۱۲٫'},
      };
      await store.put('event', 'bad', raw);
      await store.put('draft', 'event:a:new', draft);
      await store.put('reading', 'bad', {'assetId': 'a', 'future': 9});
      await c.deleteAsset('a');
      expect(await store.list('event'), isEmpty);
      expect(await store.list('reading'), isEmpty);
      expect(await store.list('draft'), isEmpty);
      await c.restore('asset', 'a');
      expect(await store.get('event', 'bad'), raw);
      expect(await store.get('draft', 'event:a:new'), draft);
      expect((await store.get('reading', 'bad'))!['future'], 9);
    },
  );
  test(
    'failed conversion restores preference and all raw counter metadata',
    () async {
      final raw = {
        'assetId': 'a',
        'task': 'Oil',
        'date': '2026-01-01T00:00:00',
        'meter': 25146,
        'meterUnit': 'km',
        'future': 7,
      };
      await store.put('event', 'e', raw);
      store.failKind = 'asset';
      await expectLater(
        c.convertAssetUnit(a.id, DistanceUnit.km, DistanceUnit.mi),
        throwsStateError,
      );
      expect(await store.get('event', 'e'), raw);
      expect((await store.get('asset', 'a'))!['distanceUnit'], 'km');
      await c.convertAssetUnit(a.id, DistanceUnit.km, DistanceUnit.mi);
      final converted = (await store.get('event', 'e'))!;
      expect(converted['meter'], 15625000);
      expect(converted['meter_scale'], 1000);
      expect(converted['future'], 7);
    },
  );
  test('archived or removed parent blocks new records', () async {
    await c.setArchived(a, true);
    await expectLater(
      c.saveRule(
        const IntervalRule(id: 'r', assetId: 'a', task: 'Oil', days: 1),
      ),
      throwsStateError,
    );
    await c.deleteAsset('a');
    await expectLater(
      c.saveReading(
        MaintenanceReading(
          id: 'm',
          assetId: 'a',
          value: 1,
          kind: MeterKind.distance,
          unit: DistanceUnit.km,
          at: DateTime.now(),
        ),
      ),
      throwsStateError,
    );
    expect(await store.list('reading'), isEmpty);
  });
}
