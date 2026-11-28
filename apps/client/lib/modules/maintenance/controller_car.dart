part of 'controller.dart';

/// The car's fuel log and the rates/quotas it is measured against. Both are
/// plain records in the module's store; neither is fetched, and no rate is
/// treated as official.
extension MaintenanceCarRecords on MaintenanceController {
  /// Saves a fill-up and clears its draft in the same write.
  Future<void> saveFuel(
    FuelEntry entry, {
    FuelEntry? existing,
    List<String>? editedKeys,
    String? draftId,
  }) => _mutate(
    () => LocalWrites.serial(store, () async {
      await _parent(entry.assetId);
      final raw = await store.get('fuel', entry.id);
      if ((existing != null && raw == null) ||
          (raw != null && raw['assetId'] != entry.assetId)) {
        throw StateError('Fuel entry is no longer available');
      }
      final proposed = entry.toBody();
      final body = raw == null
          ? proposed
          : _merge(
              raw,
              proposed,
              null,
              editedKeys ?? [...proposed.keys, 'notes'],
            );
      final fuel = FuelEntry.fromBody(entry.id, body);
      if (fuel == null || dayOf(fuel.date).isAfter(dayOf(DateTime.now()))) {
        throw StateError('Invalid fuel entry');
      }
      await LocalWrites.apply(store, [
        (kind: 'fuel', id: entry.id, body: body),
        if (draftId != null) (kind: 'draft', id: draftId, body: null),
      ]);
    }),
  );

  Future<void> deleteFuel(String id) => _delete('fuel', id);

  /// Replaces one asset's rate list in one recoverable group: rows the
  /// person removed go, the rest are written with their quotas. A rate's
  /// name is its identity inside the log, so renames keep their fuel rows
  /// readable but do not rewrite history. Two rates may not share a name —
  /// the quota view is by name, and a shared name would count one row's
  /// litres against another's quota.
  Future<void> saveFuelRates(String assetId, List<FuelRate> rates) => _mutate(
    () => LocalWrites.serial(store, () async {
      await _parent(assetId);
      final saved = {
        for (final row in await store.list('fuel_rate')) row.id: row.body,
      };
      final ids = <String>{};
      final names = <String>{};
      final changes = <LocalChange>[];
      for (final rate in rates) {
        final raw = saved[rate.id];
        final proposed = rate.toBody();
        if (rate.assetId != assetId ||
            (raw != null && raw['assetId'] != assetId) ||
            !ids.add(rate.id) ||
            FuelRate.fromBody(rate.id, proposed) == null) {
          throw StateError('Invalid fuel rate');
        }
        if (!names.add(rate.name.trim())) {
          throw StateError('Duplicate rate name');
        }
        changes.add((
          kind: 'fuel_rate',
          id: rate.id,
          body: _merge(raw, proposed, null, [...proposed.keys, 'example']),
        ));
      }
      for (final row in saved.entries) {
        if (!ids.contains(row.key) &&
            row.value['assetId'] == assetId &&
            FuelRate.fromBody(row.key, row.value) != null) {
          changes.add((kind: 'fuel_rate', id: row.key, body: null));
        }
      }
      await LocalWrites.apply(store, changes);
    }),
  );
}
