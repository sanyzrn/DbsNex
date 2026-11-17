import 'package:nex_client/modules/module_api.dart';

import 'editor_checkpoint.dart';
import 'local_writes.dart';
import 'medicine_logic.dart';
import 'medicine_models.dart';

/// Every write the medicine cabinet makes, in one place: the medicine, one
/// dose, one box, one place. Each goes through [LocalWrites], so a group is
/// rolled back as a whole if it fails, and each returns a guarded Undo.
class MedicineRepository {
  const MedicineRepository._();

  /// Saves the editor's body. Text edits merge into what is stored, so
  /// stock and history written in the meantime are never overwritten.
  static Future<void> save(
    NexModuleStore store,
    String id,
    Map<String, Object?> body,
    List<String> keys, {
    required bool existing,
  }) => LocalWrites.serial(store, () async {
    final raw = await store.get(MedicineModels.medicine, id);
    if (existing && raw == null) {
      throw StateError('Medicine no longer exists');
    }
    final next = existing
        ? EditorCheckpoint.merge(raw!, body, keys)
        : Map.of(body);
    // A manual recount or unit change starts a new inventory baseline.
    if (!existing || keys.contains('quantity') || keys.contains('package')) {
      next['stockEpoch'] = store.newId();
    }
    // An every-N-days count needs a day to count from, kept once so a
    // later edit does not quietly move the days it lands on.
    if (next['everyDays'] is int &&
        MedicineModels.readDay(next, 'scheduleFrom') == null) {
      next['scheduleFrom'] = MedicineModels.dayText(DateTime.now());
    }
    next['v'] = 3;
    await LocalWrites.apply(store, [
      (kind: MedicineModels.medicine, id: id, body: next),
    ]);
  });

  /// Writes one dose log. When the medicine says, in the person's own
  /// numbers, how many units a dose uses, stock falls by exactly that —
  /// never by anything guessed. [at] and [slot] let the Today page log the
  /// routine moment it answers, rather than "now".
  static Future<void> log(
    NexModuleStore store,
    String id,
    String action, {
    DateTime? at,
    String? slot,
  }) => LocalWrites.serial(store, () async {
    if (action != MedicineModels.taken && action != MedicineModels.skipped) {
      throw ArgumentError('Unknown action');
    }
    final raw = await store.get(MedicineModels.medicine, id);
    if (raw == null || raw['archived'] == true) {
      throw StateError('Medicine unavailable');
    }
    final qty = MedicineModels.readCount(raw, 'quantity');
    final units = MedicineModels.readCount(raw, 'doseUnits');
    // Record only the inventory actually deducted; never restore an
    // unfulfilled amount or infer whether the medicine was taken correctly.
    final delta =
        action == MedicineModels.taken &&
            qty != null &&
            units != null &&
            units > 0
        ? (units > qty ? qty : units)
        : 0;
    final log = MedicineModels.doseBody(
      medicineId: id,
      action: action,
      at: at ?? DateTime.now(),
      takenUnits: delta,
      slot: slot,
    );
    log['v'] = 2;
    log['stockEpoch'] = raw['stockEpoch'];
    log['stockDelta'] = delta;
    log['stockLimited'] =
        action == MedicineModels.taken &&
        qty != null &&
        units != null &&
        units > qty;
    await LocalWrites.apply(store, [
      (kind: MedicineModels.dose, id: store.newId(), body: log),
      if (delta > 0)
        (
          kind: MedicineModels.medicine,
          id: id,
          body: {...raw, 'quantity': qty! - delta},
        ),
    ]);
  });

  /// Deletes one dose log as a correction, giving back the stock it took.
  static Future<Future<void> Function()> deleteDose(
    NexModuleStore store,
    String id,
    String doseId,
  ) => LocalWrites.serial(store, () async {
    final raw = await store.get(MedicineModels.medicine, id);
    final dose = await store.get(MedicineModels.dose, doseId);
    if (raw == null || dose == null || dose['medicineId'] != id) {
      throw StateError('Dose no longer exists');
    }
    final delta = dose['action'] == MedicineModels.taken
        ? MedicineModels.readCount(
                dose,
                dose['v'] == 2 ? 'stockDelta' : 'takenUnits',
              ) ??
              0
        : 0;
    final qty = MedicineModels.readCount(raw, 'quantity');
    final sameEpoch = raw['stockEpoch'] == dose['stockEpoch'];
    return LocalWrites.apply(store, [
      (kind: MedicineModels.dose, id: doseId, body: null),
      if (delta > 0 && qty != null && sameEpoch)
        (
          kind: MedicineModels.medicine,
          id: id,
          body: {...raw, 'quantity': MedicineLogic.restoreStock(qty, delta)},
        ),
    ]);
  });

  /// Deletes a medicine with its doses, its boxes and its places, as one
  /// journaled group with one Undo that brings the whole set back.
  static Future<Future<void> Function()> deleteMedicine(
    NexModuleStore store,
    String id,
  ) => LocalWrites.delete(
    store,
    MedicineModels.medicine,
    id,
    children: MedicineModels.dose,
    parentField: 'medicineId',
    moreChildren: const [MedicineModels.box, MedicineModels.source],
  );

  /// Adds one box to a medicine's shelf and hands back its Undo.
  static Future<Future<void> Function()> addBox(
    NexModuleStore store,
    String id, {
    required DateTime expiresAt,
    int? units,
  }) => LocalWrites.serial(store, () async {
    final raw = await store.get(MedicineModels.medicine, id);
    if (raw == null) {
      throw StateError('Medicine no longer exists');
    }
    return LocalWrites.apply(store, [
      (
        kind: MedicineModels.box,
        id: store.newId(),
        body: MedicineModels.boxBody(
          medicineId: id,
          expiresAt: expiresAt,
          units: units,
          addedAt: DateTime.now(),
        ),
      ),
    ]);
  });

  /// Removes one box, with Undo.
  static Future<Future<void> Function()> deleteBox(
    NexModuleStore store,
    String boxId,
  ) => LocalWrites.serial(store, () async {
    final raw = await store.get(MedicineModels.box, boxId);
    if (raw == null) {
      throw StateError('Box no longer exists');
    }
    return LocalWrites.apply(store, [
      (kind: MedicineModels.box, id: boxId, body: null),
    ]);
  });

  /// Adds one place — where it was found, for how much, on which day —
  /// and hands back its Undo.
  static Future<Future<void> Function()> addSource(
    NexModuleStore store,
    String id, {
    required String place,
    int? priceRials,
    required DateTime at,
  }) => LocalWrites.serial(store, () async {
    final raw = await store.get(MedicineModels.medicine, id);
    if (raw == null) {
      throw StateError('Medicine no longer exists');
    }
    if (place.trim().isEmpty) {
      throw ArgumentError('A place is needed');
    }
    return LocalWrites.apply(store, [
      (
        kind: MedicineModels.source,
        id: store.newId(),
        body: MedicineModels.sourceBody(
          medicineId: id,
          place: place,
          priceRials: priceRials,
          at: at,
        ),
      ),
    ]);
  });

  /// Removes one place, with Undo.
  static Future<Future<void> Function()> deleteSource(
    NexModuleStore store,
    String sourceId,
  ) => LocalWrites.serial(store, () async {
    final raw = await store.get(MedicineModels.source, sourceId);
    if (raw == null) {
      throw StateError('Place no longer exists');
    }
    return LocalWrites.apply(store, [
      (kind: MedicineModels.source, id: sourceId, body: null),
    ]);
  });
}
