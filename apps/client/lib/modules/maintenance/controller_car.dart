part of 'controller.dart';

/// The car's fuel log and the rates/quotas it is measured against. Both are
/// plain records in the module's store; neither is fetched, and no rate is
/// treated as official.
extension MaintenanceCarRecords on MaintenanceController {
  /// Writes one fill-up, refusing a malformed date, litres or price.
  Future<void> saveFuel(FuelEntry entry, {String? draftId}) => _mutate(
    () => LocalWrites.serial(store, () async {
      await _parent(entry.assetId);
      final proposed = entry.toBody();
      if (FuelEntry.fromBody(entry.id, proposed) == null) {
        throw StateError('Invalid fuel entry');
      }
      final raw = await store.get('fuel', entry.id);
      final body = _merge(raw, proposed, null, proposed.keys.toList());
      if (raw == null) body.addAll(proposed);
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
  /// readable but do not rewrite history.
  Future<void> saveFuelRates(String assetId, List<FuelRate> rates) => _mutate(
    () => LocalWrites.serial(store, () async {
      await _parent(assetId);
      final changes = <LocalChange>[];
      for (final row in await store.list('fuel_rate')) {
        if (row.body['assetId'] != assetId) continue;
        if (!rates.any((r) => r.id == row.id)) {
          changes.add((kind: 'fuel_rate', id: row.id, body: null));
        }
      }
      for (final rate in rates) {
        final proposed = rate.toBody();
        if (FuelRate.fromBody(rate.id, proposed) == null) {
          throw StateError('Invalid fuel rate');
        }
        changes.add((kind: 'fuel_rate', id: rate.id, body: proposed));
      }
      await LocalWrites.apply(store, changes);
    }),
  );
}
