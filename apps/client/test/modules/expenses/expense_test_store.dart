import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/platform/nex_services.dart';

class ExpenseFaultStore extends NexModuleStore {
  ExpenseFaultStore(NexServices services) : super(services, 'expenses');
  bool failRead = false, failAfterTx = false, failDraftRead = false;
  String? failAfterKind;
  @override
  Future<Map<String, Object?>?> get(String kind, String id) {
    if (failDraftRead && kind == "draft") {
      return Future.error(StateError("draft read"));
    }
    return super.get(kind, id);
  }

  @override
  Future<List<ModuleRecord>> list(String kind) {
    if (failRead && kind == 'tx') return Future.error(StateError('read'));
    return super.list(kind);
  }

  @override
  Future<void> put(String kind, String id, Map<String, Object?> body) async {
    await super.put(kind, id, body);
    if ((failAfterTx && kind == 'tx') || kind == failAfterKind) {
      failAfterTx = false;
      failAfterKind = null;
      throw StateError('after commit');
    }
  }
}
