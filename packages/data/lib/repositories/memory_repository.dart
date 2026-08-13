import 'package:nex_core/nex_core.dart';
import 'package:sqlite3/sqlite3.dart';

import '../schema/database.dart';

/// SQLite-backed implementation of the [MemoryRepository] port (09-ai.md —
/// Phase 2, ADR-029). Every method is synchronous — package:sqlite3 is a
/// synchronous FFI binding — mirroring [SqliteNoteRepository]'s reasoning.
class SqliteMemoryRepository implements MemoryRepository {
  SqliteMemoryRepository(this._db);

  final NexDatabase _db;

  Database get db => _db.db;

  @override
  MemoryRecord insert(MemoryRecord record) {
    db.execute(
      '''
INSERT INTO memory_records (
  id, kind, key, value_text, source, confidence,
  created_at, updated_at, deleted_at, device_id, rev
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
''',
      [
        record.id,
        record.kind.wireName,
        record.key,
        record.valueText,
        record.source.wireName,
        record.confidence,
        record.createdAt.toUtc().toIso8601String(),
        record.updatedAt.toUtc().toIso8601String(),
        record.deletedAt?.toUtc().toIso8601String(),
        record.deviceId,
        record.rev,
      ],
    );
    return record;
  }

  @override
  MemoryRecord? getById(String id, {bool includeDeleted = false}) {
    final rows = db.select(
      '''
SELECT * FROM memory_records
WHERE id = ?
  ${includeDeleted ? '' : 'AND deleted_at IS NULL'}
''',
      [id],
    );
    if (rows.isEmpty) return null;
    return MemoryRecord.fromRow(rows.first);
  }

  @override
  List<MemoryRecord> listByKind(
    MemoryKind kind, {
    bool includeDeleted = false,
  }) {
    final rows = db.select(
      '''
SELECT * FROM memory_records
WHERE kind = ?
  ${includeDeleted ? '' : 'AND deleted_at IS NULL'}
ORDER BY updated_at DESC
''',
      [kind.wireName],
    );
    return rows.map(MemoryRecord.fromRow).toList();
  }

  @override
  MemoryRecord update(MemoryRecord record) {
    final now = DateTime.now().toUtc().toIso8601String();
    db.execute(
      '''
UPDATE memory_records
SET value_text = ?, confidence = ?, updated_at = ?, rev = rev + 1
WHERE id = ?
''',
      [record.valueText, record.confidence, now, record.id],
    );
    return getById(record.id, includeDeleted: true)!;
  }

  @override
  void softDelete(String id) {
    final now = DateTime.now().toUtc().toIso8601String();
    db.execute(
      '''
UPDATE memory_records
SET deleted_at = ?, updated_at = ?, rev = rev + 1
WHERE id = ?
''',
      [now, now, id],
    );
  }
}
