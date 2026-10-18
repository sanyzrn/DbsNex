import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';
import 'package:nex_core/nex_core.dart' show newUuidV7;

import '../schema/database.dart';
import '../schema/write_lock.dart';

/// One thing a module saved: a JSON object under the module's id, a kind of
/// its own choosing ("entry", "word", "receipt") and an id within that kind.
class ModuleRecord {
  const ModuleRecord({
    required this.module,
    required this.kind,
    required this.id,
    required this.body,
    required this.updatedAt,
  });

  final String module;
  final String kind;
  final String id;
  final Map<String, Object?> body;
  final DateTime updatedAt;
}

/// Storage for every module after «Cycle» — see `docs/17-modules.md`.
///
/// A module only ever reaches its own rows: every call is scoped by
/// [ModuleRecord.module], and the app hands each module a store already bound
/// to its id. Synchronous, like every repository here; it runs inside the
/// database worker's isolate.
class SqliteModuleRecordRepository {
  SqliteModuleRecordRepository(this._db);

  final NexDatabase _db;

  Database get db => _db.db;

  /// Every record of [kind], the most recently saved first.
  List<ModuleRecord> list(String module, String kind) => [
    for (final row in db.select(
      'SELECT * FROM module_records WHERE module = ? AND kind = ? '
      'ORDER BY updated_at DESC, id',
      [module, kind],
    ))
      if (_read(row) case final record?) record,
  ];

  ModuleRecord? get(String module, String kind, String id) {
    final rows = db.select(
      'SELECT * FROM module_records WHERE module = ? AND kind = ? AND id = ?',
      [module, kind, id],
    );
    return rows.isEmpty ? null : _read(rows.first);
  }

  /// Saves [body] as [id], replacing what was there.
  ModuleRecord put(
    String module,
    String kind,
    String id,
    Map<String, Object?> body, {
    DateTime? now,
  }) {
    final record = ModuleRecord(
      module: module,
      kind: kind,
      id: id,
      body: body,
      updatedAt: (now ?? DateTime.now()).toUtc(),
    );
    db.execute(
      'INSERT INTO module_records (module, kind, id, body, updated_at) '
      'VALUES (?, ?, ?, ?, ?) '
      'ON CONFLICT(module, kind, id) DO UPDATE SET '
      'body = excluded.body, updated_at = excluded.updated_at',
      [module, kind, id, jsonEncode(body), record.updatedAt.toIso8601String()],
    );
    return record;
  }

  void delete(String module, String kind, String id) => db.execute(
    'DELETE FROM module_records WHERE module = ? AND kind = ? AND id = ?',
    [module, kind, id],
  );

  /// Everything [module] ever saved, gone — what "Remove and delete its
  /// data" does. Returns how many records went.
  int deleteAll(String module) => db.together(() {
    final count =
        db.select('SELECT COUNT(*) AS n FROM module_records WHERE module = ?', [
              module,
            ]).first['n']
            as int;
    db.execute('DELETE FROM module_records WHERE module = ?', [module]);
    return count;
  });

  /// How many records [module] holds, across its kinds.
  int count(String module) =>
      db.select('SELECT COUNT(*) AS n FROM module_records WHERE module = ?', [
            module,
          ]).first['n']
          as int;

  /// Bad JSON or metadata affects only that row. Copy its exact bytes inside
  /// the same transaction before removing it from the active shelf; backups
  /// retain the recovery envelope. Storage errors are deliberately not hidden.
  ModuleRecord? _read(Row row) {
    try {
      return _record(row);
    } on FormatException {
      _quarantine(row);
    } on TypeError {
      _quarantine(row);
    }
    return null;
  }

  void _quarantine(Row row) => db.together(() {
    final module = row['module'] as String;
    final kind = row['kind'] as String;
    if (kind == '__recovery') return;
    // SQLite's TEXT affinity still permits BLOB values. A malformed field
    // must not throw again while we are trying to preserve the damaged row.
    final id = row['id'];
    final rawBody = row['body'];
    final stamp = row['updated_at'];
    Object? preserve(Object? value) => value is List<int>
        ? {'encoding': 'base64', 'value': base64Encode(value)}
        : value;
    // Each original gets its own key, including its raw bytes. Never replace
    // a different damaged version of the same record.
    final recoveryId = newUuidV7();
    put(module, '__recovery', recoveryId, {
      'kind': kind,
      'id': preserve(id),
      'rawBody': preserve(rawBody),
      'updatedAt': preserve(stamp),
    });
    db.execute(
      'DELETE FROM module_records WHERE module = ? AND kind = ? AND id = ? '
      'AND body = ? AND updated_at = ?',
      [module, kind, id, rawBody, stamp],
    );
  });

  ModuleRecord _record(Row row) => ModuleRecord(
    module: row['module'] as String,
    kind: row['kind'] as String,
    id: row['id'] as String,
    body: (jsonDecode(row['body'] as String) as Map).cast<String, Object?>(),
    updatedAt: DateTime.parse(row['updated_at'] as String),
  );
}
