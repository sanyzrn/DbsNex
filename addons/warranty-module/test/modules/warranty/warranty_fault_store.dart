import 'dart:async';
import 'package:nex_client/modules/module_api.dart';

class FaultStore implements NexModuleStore {
  FaultStore(this.inner);
  final NexModuleStore inner;
  bool failList = false;
  bool failDraft = false;
  int draftReads = 0;
  Completer<void>? pauseDraft;
  String? failPut;
  String? failDelete;
  bool after = false;
  @override
  String get module => inner.module;
  @override
  Stream<void> get changes => inner.changes;
  @override
  String newId() => inner.newId();
  @override
  Future<List<ModuleRecord>> list(String kind) {
    if (failList) throw StateError('temporary read');
    return inner.list(kind);
  }

  @override
  Future<Map<String, Object?>?> get(String kind, String id) async {
    if (kind == 'draft') {
      draftReads++;
    }
    if (kind == 'draft' && !failDraft) {
      await pauseDraft?.future;
    }
    if (kind == 'draft' && failDraft) throw StateError('checkpoint read');
    return inner.get(kind, id);
  }

  @override
  Future<void> put(String kind, String id, Map<String, Object?> body) async {
    if (failPut == kind) {
      failPut = null;
      if (after) await inner.put(kind, id, body);
      throw StateError('temporary write');
    }
    await inner.put(kind, id, body);
  }

  @override
  Future<void> delete(String kind, String id) async {
    if (failDelete == kind) {
      failDelete = null;
      throw StateError('temporary delete');
    }
    await inner.delete(kind, id);
  }
}
