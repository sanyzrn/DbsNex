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

  /// Preserves an unrecognised record before taking it out of active recovery.
  /// A failed copy leaves the original untouched and the error visible.
  Future<void> quarantine(ModuleRecord record) async {
    await put('__recovery', newId(), {
      'kind': record.kind,
      'id': record.id,
      'body': record.body,
      'updatedAt': record.updatedAt.toIso8601String(),
    });
    await delete(record.kind, record.id);
  }

  Stream<void> get draftChanges => _services.moduleDraftChanges
      .where((changed) => changed == module)
      .map((_) {});

  bool get remindersEnabled => _services.moduleRemindersEnabled(module);
  bool get solarCalendar => _services.solarCalendar;

  Future<bool> setReminder(
    String key, {
    required String sourceKind,
    required String sourceId,
    required DateTime at,
    required String title,
    required String body,
  }) => _services.setModuleReminder(
    module,
    key,
    sourceKind: sourceKind,
    sourceId: sourceId,
    at: at,
    title: title,
    body: body,
  );

  Future<void> clearReminder(String key) =>
      _services.clearModuleReminder(module, key);

  /// A new, unique, time-ordered id for a record.
  String newId() => newUuidV7();

  /// Fires after this module's records change — what a screen listing them
  /// rebuilds on.
  Stream<void> get changes =>
      _services.moduleChanges.where((changed) => changed == module).map((_) {});
}
