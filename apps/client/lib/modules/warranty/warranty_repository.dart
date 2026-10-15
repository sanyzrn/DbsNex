import 'package:nex_client/modules/module_api.dart';
import 'editor_checkpoint.dart';
import 'local_writes.dart';
import 'warranty_models.dart';

class WarrantyRepository {
  static Future<void> save(
    NexModuleStore store,
    String id,
    Map<String, Object?> body,
    List<String> keys, {
    required bool existing,
  }) => LocalWrites.serial(store, () async {
    final raw = await store.get(WarrantyModels.warranty, id);
    if (existing && raw == null) {
      throw StateError('Purchase no longer exists');
    }
    final next = existing ? EditorCheckpoint.merge(raw!, body, keys) : body;
    await LocalWrites.apply(store, [
      (kind: WarrantyModels.warranty, id: id, body: next),
    ]);
  });
  static Future<void> claim(
    NexModuleStore store,
    String id,
    String claimId,
    String kind,
    String note,
  ) => LocalWrites.serial(store, () async {
    if (await store.get(WarrantyModels.warranty, id) == null) {
      throw StateError('Purchase no longer exists');
    }
    await LocalWrites.apply(store, [
      (
        kind: WarrantyModels.claim,
        id: claimId,
        body: WarrantyModels.claimBody(
          warrantyId: id,
          kind: kind,
          note: note,
          at: DateTime.now(),
        ),
      ),
    ]);
  });
}
