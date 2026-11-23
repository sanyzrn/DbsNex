import 'package:nex_client/modules/module_api.dart';

import 'parking_logic.dart';
import 'parking_models.dart';
import 'editor_checkpoint.dart';
import 'local_writes.dart';
import 'local_values.dart';

class ParkingWrites {
  /// Marks a remembered place as a favourite, or takes the mark away. The
  /// rest of the record is kept as it was.
  static Future<void> setFavourite(
    NexModuleStore store,
    String id,
    bool favourite,
  ) => LocalWrites.serial(store, () async {
    final raw = await store.get(ParkingModels.place, id);
    if (raw == null) {
      return;
    }
    await LocalWrites.apply(store, [
      (
        kind: ParkingModels.place,
        id: id,
        body: {...raw, 'favorite': favourite},
      ),
    ]);
  });

  static Future<void> rememberPlace(
    NexModuleStore store,
    List<ModuleRecord> ignored,
    Map<String, Object?> body,
  ) => LocalWrites.serial(store, () async {
    if (ParkingModels.readString(body, 'place').trim().isEmpty) {
      return;
    }
    final places = await store.list(ParkingModels.place);
    final existing = places
        .where((r) => ParkingLogic.samePlace(r.body, body))
        .firstOrNull;
    final count = existing == null
        ? 0
        : ParkingModels.readCount(existing.body, 'useCount') ?? 0;
    final next = ParkingModels.placeBody(
      place: ParkingModels.readString(body, 'place'),
      floor: ParkingModels.readString(body, 'floor'),
      spot: ParkingModels.readString(body, 'spot'),
      landmark: ParkingModels.readString(body, 'landmark'),
      useCount: count >= LocalValues.maxExact ? count : count + 1,
      lastUsedAt: DateTime.now(),
      // Parking here again is not the same as un-starring the place. A
      // place's favourite mark belongs to the person, not to this visit.
      favourite: existing == null
          ? false
          : ParkingModels.isFavourite(existing.body),
      lat: ParkingModels.readCoord(body, 'lat', min: -90, max: 90),
      lng: ParkingModels.readCoord(body, 'lng', min: -180, max: 180),
    );
    await LocalWrites.apply(store, [
      (
        kind: ParkingModels.place,
        id: existing?.id ?? store.newId(),
        body: EditorCheckpoint.merge(existing?.body ?? {}, next, [
          ...next.keys,
          'lat',
          'lng',
        ]),
      ),
    ]);
  });
  static Future<void> rememberQuery(
    NexModuleStore store,
    List<ModuleRecord> ignored,
    String query,
  ) => LocalWrites.serial(store, () async {
    final q = query.trim();
    if (q.isEmpty) {
      return;
    }
    final records = await store.list(ParkingModels.search);
    final key = ParkingModels.fold(q);
    final existing = records
        .where(
          (r) =>
              ParkingModels.fold(ParkingModels.readString(r.body, 'query')) ==
              key,
        )
        .firstOrNull;
    final seen = <String>{key};
    final keep = <String>{};
    for (final r in records) {
      final folded = ParkingModels.fold(
        ParkingModels.readString(r.body, 'query'),
      );
      if (folded.isNotEmpty &&
          seen.length < ParkingModels.searchHistoryLimit &&
          seen.add(folded)) {
        keep.add(r.id);
      }
    }
    await LocalWrites.apply(store, [
      for (final r in records)
        if (r.id != existing?.id && !keep.contains(r.id))
          (kind: ParkingModels.search, id: r.id, body: null),
      (
        kind: ParkingModels.search,
        id: existing?.id ?? store.newId(),
        body: ParkingModels.searchBody(query: q, at: DateTime.now()),
      ),
    ]);
  });
}
