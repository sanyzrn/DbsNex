part of 'db_worker.dart';

/// The module-record half of [NexDbWorker]'s client side — see
/// `docs/17-modules.md`. Each call is sent to the worker isolate, where
/// SqliteModuleRecordRepository answers it.
mixin _DbModuleRecords {
  Future<T> _send<T>(_DbCommand command, [Map<String, Object?> args]);

  Future<List<ModuleRecord>> moduleRecords(String module, String kind) =>
      _send<List<ModuleRecord>>(_DbCommand.moduleRecords, {
        'module': module,
        'kind': kind,
      });

  Future<ModuleRecord?> moduleRecord(String module, String kind, String id) =>
      _send<ModuleRecord?>(_DbCommand.moduleRecord, {
        'module': module,
        'kind': kind,
        'id': id,
      });

  Future<ModuleRecord> modulePut(
    String module,
    String kind,
    String id,
    Map<String, Object?> body,
  ) => _send<ModuleRecord>(_DbCommand.modulePut, {
    'module': module,
    'kind': kind,
    'id': id,
    'body': body,
  });

  Future<void> moduleDelete(String module, String kind, String id) =>
      _send<void>(_DbCommand.moduleDelete, {
        'module': module,
        'kind': kind,
        'id': id,
      });

  Future<int> moduleDeleteAll(String module) =>
      _send<int>(_DbCommand.moduleDeleteAll, {'module': module});
}

/// The worker side: one module-record command, answered from [modules].
Object? _moduleCommand(
  SqliteModuleRecordRepository modules,
  _DbCommand command,
  Object? Function(String key) arg,
) {
  final module = arg('module')! as String;
  return switch (command) {
    _DbCommand.moduleRecords => modules.list(module, arg('kind')! as String),
    _DbCommand.moduleRecord => modules.get(
      module,
      arg('kind')! as String,
      arg('id')! as String,
    ),
    _DbCommand.modulePut => modules.put(
      module,
      arg('kind')! as String,
      arg('id')! as String,
      (arg('body')! as Map).cast<String, Object?>(),
    ),
    _DbCommand.moduleDelete => NexDbWorker._voided(
      () =>
          modules.delete(module, arg('kind')! as String, arg('id')! as String),
    ),
    _ => modules.deleteAll(module),
  };
}
