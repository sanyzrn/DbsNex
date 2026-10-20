import 'package:nex_client/modules/module_api.dart';
import 'editor_checkpoint.dart';
import 'local_writes.dart';
import 'parking_logic.dart';
import 'parking_models.dart';

class ParkingConflict implements Exception {}

class ParkingRepository {
  static Future<Future<void> Function()> delete(
    NexModuleStore store,
    String id,
  ) => LocalWrites.serial(store, () async {
    final raw = await store.get(ParkingModels.session, id);
    if (raw == null) throw StateError('Parking no longer exists');
    return LocalWrites.apply(
      store,
      [
        (kind: 'draft', id: 'session:$id', body: null),
        (kind: ParkingModels.session, id: id, body: null),
      ],
      beforeUndo: () async {
        if (!ParkingLogic.isActive(raw)) return;
        final others = await store.list(ParkingModels.session);
        if (others.any(
          (r) =>
              r.id != id &&
              ParkingLogic.isActive(r.body) &&
              ParkingModels.sameVehicle(
                ParkingModels.readString(r.body, 'vehicle'),
                ParkingModels.readString(raw, 'vehicle'),
              ),
        )) {
          throw StateError(
            'Another parking for this vehicle is already active',
          );
        }
      },
    );
  });

  static Future<void> save(
    NexModuleStore store,
    String id,
    Map<String, Object?> body,
    List<String> keys, {
    required bool existing,
    bool closeEarlier = false,
  }) => LocalWrites.serial(store, () async {
    final raw = await store.get(ParkingModels.session, id);
    if (existing && raw == null) {
      throw StateError('Parking no longer exists');
    }
    final next = existing ? EditorCheckpoint.merge(raw!, body, keys) : body;
    final others = [
      for (final r in await store.list(ParkingModels.session))
        if (r.id != id &&
            ParkingLogic.isActive(r.body) &&
            ParkingModels.sameVehicle(
              ParkingModels.readString(r.body, 'vehicle'),
              ParkingModels.readString(next, 'vehicle'),
            ))
          r,
    ];
    if (ParkingLogic.isActive(next) && others.isNotEmpty && !closeEarlier) {
      throw ParkingConflict();
    }
    await LocalWrites.apply(store, [
      if (ParkingLogic.isActive(next))
        for (final r in others)
          (
            kind: ParkingModels.session,
            id: r.id,
            body: {
              ...r.body,
              'foundAt': DateTime.now().toUtc().toIso8601String(),
            },
          ),
      (kind: ParkingModels.session, id: id, body: next),
    ]);
  });
  static Future<void> found(NexModuleStore store, String id) =>
      LocalWrites.serial(store, () async {
        final raw = await store.get(ParkingModels.session, id);
        if (raw == null || !ParkingLogic.isActive(raw)) {
          return;
        }
        await LocalWrites.apply(store, [
          (
            kind: ParkingModels.session,
            id: id,
            body: {...raw, 'foundAt': DateTime.now().toUtc().toIso8601String()},
          ),
        ]);
        // The parking is over, so its reminder is moot — a person who has
        // found the car does not need to be told the paid time ran out.
        // Best-effort: a failed cancel never blocks closing the session.
        try {
          await store.clearReminder('${ParkingModels.session}:$id');
        } catch (_) {}
      });
}
