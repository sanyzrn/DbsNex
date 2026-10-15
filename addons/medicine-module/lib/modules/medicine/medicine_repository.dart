import 'package:nex_client/modules/module_api.dart';
import 'editor_checkpoint.dart';
import 'local_writes.dart';
import 'medicine_logic.dart';
import 'medicine_models.dart';

class MedicineRepository {
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
    next['v'] = 2;
    await LocalWrites.apply(store, [
      (kind: MedicineModels.medicine, id: id, body: next),
    ]);
  });
  static Future<void> log(NexModuleStore store, String id, String action) =>
      LocalWrites.serial(store, () async {
        if (action != MedicineModels.taken &&
            action != MedicineModels.skipped) {
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
          at: DateTime.now(),
          takenUnits: delta,
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
}
