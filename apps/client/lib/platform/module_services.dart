part of 'nex_services.dart';

/// Module records (ADR-040, `docs/17-modules.md`).
extension NexModuleServices on NexServices {
  /// Module records — reached through a module's own NexModuleStore, never
  /// directly (lib/modules/nex_module_store.dart).
  Future<List<ModuleRecord>> moduleRecords(String module, String kind) =>
      worker.moduleRecords(module, kind);

  Future<ModuleRecord?> moduleRecord(String module, String kind, String id) =>
      worker.moduleRecord(module, kind, id);

  Future<ModuleRecord> modulePut(
    String module,
    String kind,
    String id,
    Map<String, Object?> body,
  ) => _moduleWrite(module, worker.modulePut(module, kind, id, body));

  Future<void> moduleDelete(String module, String kind, String id) =>
      _moduleWrite(module, worker.moduleDelete(module, kind, id));

  /// Everything [module] saved, gone — and, as with Cycle, the backups on
  /// this phone that still held it replaced by one that does not.
  Future<void> moduleDeleteAll(String module) async {
    final removed = await _moduleWrite(module, worker.moduleDeleteAll(module));
    if (removed > 0) await _replaceBackupsHoldingDeleted();
  }
}
