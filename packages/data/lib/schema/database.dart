import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

/// Opens (or creates) the Nex SQLite database and applies the Phase 1 schema.
///
/// FTS5 uses `unicode61` with `remove_diacritics=2` and separators that treat
/// ZWNJ (U+200C) as a separator — ADR-028.
class NexDatabase {
  NexDatabase._(this.db, this.path);

  final Database db;
  final String path;

  /// Retention count for automatic rotating backups (FR-7.1 "small fixed number").
  static const int backupRetention = 5;

  static NexDatabase open(String filePath) {
    final file = File(filePath);
    file.parent.createSync(recursive: true);
    final db = sqlite3.open(filePath);
    final nex = NexDatabase._(db, filePath);
    nex._migrate();
    return nex;
  }

  static NexDatabase openInMemory() {
    final db = sqlite3.openInMemory();
    final nex = NexDatabase._(db, ':memory:');
    nex._migrate();
    return nex;
  }

  void _migrate() {
    db.execute('PRAGMA foreign_keys = ON;');
    db.execute('''
CREATE TABLE IF NOT EXISTS notes (
  id TEXT PRIMARY KEY NOT NULL,
  type TEXT NOT NULL CHECK (type IN ('text', 'voice', 'photo', 'file')),
  content TEXT,
  media_uri TEXT,
  media_hash TEXT,
  duration_ms INTEGER,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT,
  device_id TEXT NOT NULL,
  rev INTEGER NOT NULL,
  sync_state TEXT NOT NULL CHECK (sync_state IN ('pending', 'synced', 'conflict'))
);
''');
    db.execute('''
CREATE TABLE IF NOT EXISTS tags (
  id TEXT PRIMARY KEY NOT NULL,
  name TEXT NOT NULL UNIQUE,
  color TEXT,
  created_at TEXT NOT NULL
);
''');
    db.execute('''
CREATE TABLE IF NOT EXISTS note_tags (
  note_id TEXT NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
  tag_id TEXT NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
  PRIMARY KEY (note_id, tag_id)
);
''');

    // FTS5 content table for text-note bodies only (FR-4.2 / ADR-028).
    // ZWNJ (U+200C) listed in separators so Persian compounds tokenize cleanly.
    final zwnj = String.fromCharCode(0x200C);
    db.execute('''
CREATE VIRTUAL TABLE IF NOT EXISTS notes_fts USING fts5(
  note_id UNINDEXED,
  content,
  tokenize = "unicode61 remove_diacritics 2 separators ' $zwnj'"
);
''');

    db.execute(
      'CREATE INDEX IF NOT EXISTS idx_notes_created_at ON notes(created_at DESC);',
    );
    db.execute(
      'CREATE INDEX IF NOT EXISTS idx_notes_deleted_at ON notes(deleted_at);',
    );

    // Phase 3: AI-derived columns (idempotent ADD COLUMN).
    _addColumnIfMissing('notes', 'transcript_text', 'TEXT');
    _addColumnIfMissing('notes', 'ocr_text', 'TEXT');
    _addColumnIfMissing('notes', 'summary_text', 'TEXT');

    db.execute('''
CREATE TABLE IF NOT EXISTS note_embeddings (
  note_id TEXT PRIMARY KEY NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
  dims INTEGER NOT NULL,
  values_json TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
''');
  }

  void _addColumnIfMissing(String table, String column, String type) {
    final rows = db.select('PRAGMA table_info($table)');
    final exists = rows.any((r) => r['name'] == column);
    if (!exists) {
      db.execute('ALTER TABLE $table ADD COLUMN $column $type');
    }
  }

  void close() => db.dispose();

  /// Copies this database file into [backupDir], keeping [backupRetention] newest.
  File createBackup(String backupDir) {
    if (path == ':memory:') {
      throw StateError('Cannot back up an in-memory database');
    }
    final dir = Directory(backupDir)..createSync(recursive: true);
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
    final target = File(p.join(dir.path, 'nex-$stamp.sqlite'));
    // Checkpoint WAL so the main file is consistent, then copy.
    db.execute('PRAGMA wal_checkpoint(FULL);');
    File(path).copySync(target.path);

    final existing = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.sqlite'))
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    for (final stale in existing.skip(backupRetention)) {
      stale.deleteSync();
    }
    return target;
  }

  /// Replaces this database file with [backupFile]. Caller must reopen afterward.
  ///
  /// ADR-026: validate the backup **before** touching the live database. A
  /// corrupt or missing backup must leave the live files untouched.
  static void restoreFromBackup({
    required String liveDbPath,
    required String backupFile,
  }) {
    final backup = File(backupFile);
    if (!backup.existsSync()) {
      throw StateError('Backup file does not exist: $backupFile');
    }
    if (backup.lengthSync() == 0) {
      throw StateError('Backup file is empty: $backupFile');
    }

    final live = File(liveDbPath);
    live.parent.createSync(recursive: true);

    // Copy to a sibling temp path first — never overwrite live until validated.
    final restoringPath = '$liveDbPath.restoring';
    final restoring = File(restoringPath);
    if (restoring.existsSync()) restoring.deleteSync();
    backup.copySync(restoringPath);

    try {
      _assertSqliteIntegrity(restoringPath);
    } catch (e) {
      if (restoring.existsSync()) restoring.deleteSync();
      throw StateError(
        'Backup failed integrity check; live database left untouched: $e',
      );
    }

    // Validation passed — swap into place.
    for (final suffix in ['', '-wal', '-shm']) {
      final f = File('$liveDbPath$suffix');
      if (f.existsSync()) f.deleteSync();
    }
    restoring.renameSync(liveDbPath);
  }

  /// Opens [dbPath] read-only and requires `PRAGMA integrity_check` → `ok`.
  static void _assertSqliteIntegrity(String dbPath) {
    Database? probe;
    try {
      probe = sqlite3.open(dbPath, mode: OpenMode.readOnly);
      final rows = probe.select('PRAGMA integrity_check;');
      if (rows.isEmpty) {
        throw StateError('integrity_check returned no rows');
      }
      final result = rows.first.values.first?.toString() ?? '';
      if (result != 'ok') {
        throw StateError('integrity_check: $result');
      }
    } finally {
      probe?.dispose();
    }
  }
}
