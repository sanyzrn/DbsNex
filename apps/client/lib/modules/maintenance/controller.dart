import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:nex_client/modules/module_api.dart';
import 'models.dart';
import 'units.dart';
import 'logic.dart';
import 'local_writes.dart';
part 'controller_conversion.dart';

/// One queue includes mutation and its reload; raw journals preserve whole sets.
class MaintenanceController extends ChangeNotifier {
  MaintenanceController(this.store) {
    _changes = store.changes.listen((_) {
      if (_mutating == 0) unawaited(load());
    });
  }
  final NexModuleStore store;
  late final StreamSubscription<void> _changes;
  Future<void> _tail = Future.value();
  int _loadToken = 0, _mutating = 0;
  bool _disposed = false, loading = true, readFailed = false;
  List<MaintenanceAsset> assets = const [];
  List<ServiceEvent> events = const [];
  List<IntervalRule> rules = const [];
  List<MaintenanceReading> readings = const [];
  List<ModuleRecord> invalidRules = const [];
  final _undos = <String, Future<void> Function()>{};
  @override
  void dispose() {
    _disposed = true;
    unawaited(_changes.cancel());
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    final token = ++_loadToken;
    try {
      await LocalWrites.recover(store);
      final result = await Future.wait([
        store.list('asset'),
        store.list('event'),
        store.list('rule'),
        store.list('reading'),
      ]);
      if (_disposed || token != _loadToken) return;
      assets = [
        for (final r in result[0]) MaintenanceAsset.fromBody(r.id, r.body),
      ];
      events = [for (final r in result[1]) ServiceEvent.fromBody(r.id, r.body)];
      rules = [
        for (final r in result[2])
          if (IntervalRule.fromBody(r.id, r.body) case final item?) item,
      ];
      invalidRules = [
        for (final r in result[2])
          if (IntervalRule.fromBody(r.id, r.body) == null) r,
      ];
      readings = [
        for (final r in result[3])
          if (MaintenanceReading.fromBody(r.id, r.body) case final item?) item,
      ];
      loading = false;
      readFailed = false;
      _notify();
    } catch (_) {
      if (_disposed || token != _loadToken) return;
      loading = false;
      readFailed = true;
      _notify();
    }
  }

  Future<void> _mutate(Future<void> Function() action) {
    final done = _tail.then((_) async {
      _mutating++;
      try {
        await action();
        await load();
      } finally {
        _mutating--;
      }
    });
    _tail = done.then<void>((_) {}, onError: (Object _) {});
    return done;
  }

  Future<Map<String, Object?>> _parent(
    String id, {
    bool allowArchived = false,
  }) async {
    final raw = await store.get('asset', id);
    if (raw == null || (!allowArchived && raw['archived'] == true)) {
      throw StateError('Asset no longer active');
    }
    return raw;
  }

  Map<String, Object?> _merge(
    Map<String, Object?>? raw,
    Map<String, Object?> proposed,
    Map<String, Object?>? previous,
    List<String> keys,
  ) {
    final result = {...?raw};
    for (final key in keys) {
      if (previous != null && LocalWrites.same(previous[key], proposed[key])) {
        continue;
      }
      if (proposed.containsKey(key)) {
        result[key] = proposed[key];
      } else {
        result.remove(key);
      }
    }
    return result;
  }

  String newAssetId() => 'asset-${store.newId()}';
  String newEventId() => 'event-${store.newId()}';
  MaintenanceAsset? assetById(String id) {
    for (final a in assets) {
      if (a.id == id) return a;
    }
    return null;
  }

  ServiceEvent? eventById(String id) {
    for (final e in events) {
      if (e.id == id) return e;
    }
    return null;
  }

  IntervalRule? ruleById(String id) {
    for (final v in rules) {
      if (v.id == id) return v;
    }
    return null;
  }

  Future<void> saveAsset(
    MaintenanceAsset asset, {
    MaintenanceAsset? existing,
    bool convertHistory = false,
    String? draftId,
    List<String>? editedKeys,
  }) => _mutate(
    () => LocalWrites.serial(store, () async {
      final raw = await store.get('asset', asset.id);
      if (existing != null && raw == null) throw StateError('Asset deleted');
      final proposed = asset.toBody();
      if (!MaintenanceAsset.fromBody(asset.id, proposed).valid) {
        throw StateError('Invalid asset');
      }
      final keys = [
        'nickname',
        'type',
        'model',
        'purchasedAt',
        'notes',
        'meterKind',
        'distanceUnit',
        'schema',
      ];
      final body = _merge(
        raw,
        proposed,
        editedKeys == null ? existing?.toBody() : null,
        editedKeys ?? keys,
      );
      if (raw == null) body.addAll(proposed);
      body['archived'] = raw?['archived'] ?? asset.archived;
      final fresh = raw == null
          ? null
          : MaintenanceAsset.fromBody(asset.id, raw);
      final after = <LocalChange>[];
      if (convertHistory &&
          fresh != null &&
          fresh.distanceUnit != asset.distanceUnit) {
        if (fresh.meterKind != MeterKind.distance ||
            asset.meterKind != MeterKind.distance) {
          throw StateError('Incompatible meter kinds');
        }
        after.addAll(
          await _converted(asset.id, fresh.distanceUnit, asset.distanceUnit),
        );
      }
      after.add((kind: 'asset', id: asset.id, body: body));
      if (draftId != null) after.add((kind: 'draft', id: draftId, body: null));
      await LocalWrites.apply(store, after);
    }),
  );
  Future<void> setArchived(MaintenanceAsset asset, bool archived) => _mutate(
    () => LocalWrites.patch(store, 'asset', asset.id, {'archived': archived}),
  );
  ({
    MaintenanceAsset asset,
    List<ServiceEvent> events,
    List<IntervalRule> rules,
  })
  snapshotOf(String id) => (
    asset: assetById(id)!,
    events: events.where((e) => e.assetId == id).toList(),
    rules: rules.where((v) => v.assetId == id).toList(),
  );
  Future<void> deleteAsset(String id) => _mutate(
    () => LocalWrites.serial(store, () async {
      await _parent(id, allowArchived: true);
      final after = <LocalChange>[];
      for (final kind in ['event', 'rule', 'reading']) {
        for (final row in await store.list(kind)) {
          if (row.body['assetId'] == id) {
            after.add((kind: kind, id: row.id, body: null));
          }
        }
      }
      for (final row in await store.list('draft')) {
        if (row.id == 'asset:$id' ||
            (row.body['fields'] is Map &&
                (row.body['fields'] as Map)['parentId'] == id)) {
          after.add((kind: 'draft', id: row.id, body: null));
        }
      }
      after.add((kind: 'asset', id: id, body: null));
      _undos['asset:$id'] = await LocalWrites.apply(store, after);
    }),
  );
  Future<void> restoreAsset(
    MaintenanceAsset asset,
    List<ServiceEvent> events,
    List<IntervalRule> rules,
  ) => restore('asset', asset.id);
  Future<void> restore(String kind, String id, {String? parentId}) =>
      _mutate(() async {
        if (parentId != null) await _parent(parentId, allowArchived: true);
        final undo = _undos['$kind:$id'];
        if (undo == null) throw StateError('Undo unavailable');
        await undo();
        _undos.remove('$kind:$id');
      });
  Future<void> _delete(String kind, String id) => _mutate(() async {
    _undos['$kind:$id'] = await LocalWrites.delete(store, kind, id);
  });
  Future<void> deleteEvent(String id) => _delete('event', id);
  Future<void> deleteRule(String id) => _delete('rule', id);
  Future<void> deleteReading(String id) => _delete('reading', id);

  Future<void> saveEvent(
    ServiceEvent event, {
    ServiceEvent? existing,
    List<String>? editedKeys,
    String? draftId,
  }) => _mutate(
    () => LocalWrites.serial(store, () async {
      final parent = MaintenanceAsset.fromBody(
        event.assetId,
        await _parent(event.assetId, allowArchived: existing != null),
      );
      if (event.meter != null &&
          (existing == null ||
              editedKeys == null ||
              editedKeys.contains('meter')) &&
          eventMeterKind(event) != parent.meterKind) {
        throw StateError('Meter kind changed');
      }
      final raw = await store.get('event', event.id);
      if (existing != null && raw == null) throw StateError('Service deleted');
      final proposed = event.toBody();
      if (!ServiceEvent.fromBody(event.id, proposed).valid) {
        throw StateError('Invalid service');
      }
      final keys =
          editedKeys ??
          [
            'assetId',
            'date',
            'task',
            'cost',
            'currency',
            'currency_code',
            'currency_exponent',
            'meter',
            'meter_scale',
            'meter_kind',
            'meterUnit',
            'provider',
            'notes',
            'schema',
          ];
      final body = _merge(raw, proposed, null, keys);
      if (raw == null) body.addAll(proposed);
      await LocalWrites.apply(store, [
        (kind: 'event', id: event.id, body: body),
        if (draftId != null) (kind: 'draft', id: draftId, body: null),
      ]);
    }),
  );
  String ruleIdFor(String assetId, String task) {
    for (final rule in rules) {
      if (rule.assetId == assetId &&
          normalizedTask(rule.task) == normalizedTask(task)) {
        return rule.id;
      }
    }
    return 'rule-${store.newId()}';
  }

  Future<void> saveRule(
    IntervalRule rule, {
    IntervalRule? existing,
    String? draftId,
    List<String>? editedKeys,
  }) => _mutate(
    () => LocalWrites.serial(store, () async {
      final parent = MaintenanceAsset.fromBody(
        rule.assetId,
        await _parent(rule.assetId, allowArchived: existing != null),
      );
      if ((existing == null ||
              editedKeys == null ||
              editedKeys.contains('meters') ||
              editedKeys.contains('hours')) &&
          ((rule.meters != null && parent.meterKind != MeterKind.distance) ||
              (rule.hours != null && parent.meterKind != MeterKind.hours))) {
        throw StateError('Rule does not match meter kind');
      }
      if (IntervalRule.fromBody(rule.id, rule.toBody()) == null) {
        throw StateError('Invalid interval');
      }
      if (existing != null && await store.get('rule', existing.id) == null) {
        throw StateError('Rule deleted');
      }
      var id = rule.id;
      for (final row in await store.list('rule')) {
        if (row.body['assetId'] == rule.assetId &&
            row.body['task'] is String &&
            normalizedTask(row.body['task'] as String) ==
                normalizedTask(rule.task)) {
          if (existing != null && row.id != existing.id) {
            throw StateError('Another task already has that name');
          }
          id = row.id;
          break;
        }
      }
      final raw = await store.get('rule', id);
      final proposed = rule.toBody();
      final body = _merge(
        raw,
        proposed,
        null,
        editedKeys ??
            [
              'assetId',
              'task',
              'days',
              'months',
              'meters',
              'hours',
              'meterUnit',
              'meter_scale',
              'schema',
            ],
      );
      if (raw == null) body.addAll(proposed);
      await LocalWrites.apply(store, [
        (kind: 'rule', id: id, body: body),
        if (draftId != null) (kind: 'draft', id: draftId, body: null),
      ]);
    }),
  );
  Future<void> saveReading(MaintenanceReading reading, {String? draftId}) =>
      _mutate(
        () => LocalWrites.serial(store, () async {
          final parent = MaintenanceAsset.fromBody(
            reading.assetId,
            await _parent(reading.assetId),
          );
          if (parent.meterKind != reading.kind ||
              MaintenanceReading.fromBody(reading.id, reading.toBody()) ==
                  null) {
            throw StateError('Invalid current meter');
          }
          if (reading.at.isAfter(DateTime.now().toUtc())) {
            throw StateError('Future reading');
          }
          await LocalWrites.apply(store, [
            (kind: 'reading', id: reading.id, body: reading.toBody()),
            if (draftId != null) (kind: 'draft', id: draftId, body: null),
          ]);
        }),
      );
}
