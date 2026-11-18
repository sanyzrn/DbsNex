part of 'controller.dart';

extension _MaintenanceConversions on MaintenanceController {
  Future<List<LocalChange>> _converted(
    String assetId,
    DistanceUnit from,
    DistanceUnit to,
  ) async {
    final after = <LocalChange>[];
    for (final kind in ['event', 'rule', 'reading']) {
      for (final row in await store.list(kind)) {
        if (row.body['assetId'] != assetId) continue;
        final unitKey = kind == 'reading' ? 'unit' : 'meterUnit';
        if (row.body[unitKey] != from.name) continue;
        final valueKey = kind == 'event'
            ? 'meter'
            : kind == 'rule'
            ? 'meters'
            : 'value';
        final scaleKey = kind == 'reading' ? 'scale' : 'meter_scale';
        final value = row.body[valueKey], scale = row.body[scaleKey] ?? 1;
        if (value is! int || value < 0 || !validMeterScale(scale)) {
          throw StateError('Cannot convert an incomplete reading');
        }
        final milli = convertMilli(
          toMeterMilli(value, scale as int)!,
          from,
          to,
        );
        if (milli > meterMilliMax || (kind == 'rule' && milli == 0)) {
          throw RangeError('Converted reading outside bounds');
        }
        after.add((
          kind: kind,
          id: row.id,
          body: {
            ...row.body,
            valueKey: milli,
            scaleKey: 1000,
            unitKey: to.name,
          },
        ));
      }
    }
    return after;
  }
}

extension MaintenanceUnitChanges on MaintenanceController {
  /// The public explicit conversion also changes the asset in the same group.
  Future<void> convertAssetUnit(
    String id,
    DistanceUnit from,
    DistanceUnit to,
  ) => _mutate(
    () => LocalWrites.serial(store, () async {
      final raw = await _parent(id, allowArchived: true);
      if (raw['meterKind'] != 'distance' || raw['distanceUnit'] != from.name) {
        throw StateError('Unit changed');
      }
      final changes = await _converted(id, from, to);
      changes.add((
        kind: 'asset',
        id: id,
        body: {...raw, 'distanceUnit': to.name},
      ));
      await LocalWrites.apply(store, changes);
    }),
  );
}

/// Writing the current meter (the quick odometer update).
extension MaintenanceReadingWrites on MaintenanceController {
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
