import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/platform/nex_services.dart';

class LensFaultStore extends NexModuleStore {
  LensFaultStore(NexServices services) : super(services, 'price_lens');
  bool failRead = false;
  String? failAfterKind;
  @override
  Future<List<ModuleRecord>> list(String kind) {
    if (failRead && kind == 'memory') return Future.error(StateError('read'));
    return super.list(kind);
  }

  @override
  Future<void> put(String kind, String id, Map<String, Object?> body) async {
    await super.put(kind, id, body);
    if (kind == failAfterKind) {
      failAfterKind = null;
      throw StateError('after put');
    }
  }
}
