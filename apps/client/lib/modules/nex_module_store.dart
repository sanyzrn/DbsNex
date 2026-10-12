import 'package:nex_data/nex_data.dart' show ModuleRecord, newUuidV7;

import '../platform/nex_services.dart';

/// A module's own shelf in the library — the only storage a module has.
///
/// Records are JSON objects filed under a kind the module chooses ("spot",
/// "word", "receipt") and an id. Every call is bound to the module's id, so a
/// module cannot read, write or delete another module's records, or
/// anything else in the library. Records ride along in every backup and are
/// never searched, embedded, shown on the timeline or read by the assistant.
///
/// Values must be what JSON can hold: strings, numbers, booleans, null, and
/// lists and maps of those. A date goes in as `toIso8601String()`.
class NexModuleStore {
  NexModuleStore(this._services, this.module);

  final NexServices _services;

  /// The module these records belong to.
  final String module;

  /// Every record of [kind], the most recently saved first.
  Future<List<ModuleRecord>> list(String kind) =>
      _services.moduleRecords(module, kind);

  /// The record [id] of [kind]'s fields, or null if there is none.
  Future<Map<String, Object?>?> get(String kind, String id) async =>
      (await _services.moduleRecord(module, kind, id))?.body;

  /// Saves [body] as [id], replacing what was there.
  Future<void> put(String kind, String id, Map<String, Object?> body) =>
      _services.modulePut(module, kind, id, body);

  Future<void> delete(String kind, String id) =>
      _services.moduleDelete(module, kind, id);

  /// A new, unique, time-ordered id for a record.
  String newId() => newUuidV7();

  /// Fires after this module's records change — what a screen listing them
  /// rebuilds on.
  Stream<void> get changes =>
      _services.moduleChanges.where((changed) => changed == module).map((_) {});
}
