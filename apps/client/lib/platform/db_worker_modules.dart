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

  /// Several records in one storage transaction — see the repository's
  /// `deleteMany`.
  Future<void> moduleDeleteMany(
    String module,
    List<({String kind, String id})> records,
  ) => _send<void>(_DbCommand.moduleDeleteMany, {
    'module': module,
    'records': records,
  });

  Future<int> moduleDeleteAll(String module) =>
      _send<int>(_DbCommand.moduleDeleteAll, {'module': module});
}

/// The worker side: the module-record commands, answered from [modules].
/// Anything routed here that is not one of them is a routing bug, and the
/// answer used to be "delete everything this module owns" — the switch
/// fell through to `deleteAll` for whatever arrived. It now says so loudly
/// instead of wiping a shelf on a typo.
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
    _DbCommand.moduleDeleteMany => NexDbWorker._voided(
      () => modules.deleteMany(module, [
        for (final record in arg('records')! as List)
          record as ({String kind, String id}),
      ]),
    ),
    _DbCommand.moduleDeleteAll => modules.deleteAll(module),
    _ => throw StateError('$command is not a module command'),
  };
}
