import 'dart:io';

import 'package:nex_core/nex_core.dart' show stableUuidV5;
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../repositories/note_repository.dart' show suggestedStarterTags;

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

    // Write-ahead logging, once and permanently (the mode is recorded in the
    // database header, so this is a no-op from the second open onwards).
    // Every write becomes an atomic commit against the `-wal` file instead of
    // page surgery in place, which is what makes a crash mid-write leave a
    // readable database behind rather than a corrupt one — and readers no
    // longer block the writer, so a capture during a search stops contending.
    //
    // `synchronous = NORMAL` is the pairing SQLite itself recommends under
    // WAL: consistent across app crashes, only a power loss can lose the
    // last moments, and the automatic backups are the recovery path for
    // that. The backup and restore paths already checkpoint (`create`) and
    // sweep the sidecar files (`restore`), which is what this mode expects.
    // In-memory databases ignore both pragmas and keep their own behaviour.
    db.execute('PRAGMA journal_mode = WAL;');
    db.execute('PRAGMA synchronous = NORMAL;');
    db.execute('''
CREATE TABLE IF NOT EXISTS notes (
  id TEXT PRIMARY KEY NOT NULL,
  -- No CHECK on the type. It used to enumerate the four types v1 shipped,
  -- which meant adding a fifth was a table rebuild rather than an enum case
  -- — and SQLite cannot drop a CHECK in place, so the constraint outlived
  -- every schema change on databases that already existed. `NoteType.fromWire`
  -- throws on an unknown value, in one place, in the language the rest of the
  -- validation lives in. See [_dropLegacyTypeCheck].
  type TEXT NOT NULL,
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
    // The tag-filtered timeline joins through note_tags from the tag side;
    // it was a full scan — fine at a few hundred notes, a tax that grows
    // with the library otherwise. (The two notes-table indexes live further
    // down, after [_dropLegacyTypeCheck]: the rebuild drops every index on
    // the table it replaces and only recreates the two it has always known
    // about, so anything created here would silently vanish on the exact
    // databases the rebuild exists to migrate.)
    db.execute(
      'CREATE INDEX IF NOT EXISTS idx_note_tags_tag_id ON note_tags(tag_id);',
    );

    // Phase 3: AI-derived columns (idempotent ADD COLUMN).
    _addColumnIfMissing('notes', 'transcript_text', 'TEXT');
    _addColumnIfMissing('notes', 'ocr_text', 'TEXT');
    _addColumnIfMissing('notes', 'summary_text', 'TEXT');
    // User-authored caption (optional, post-capture) + share/file MIME.
    _addColumnIfMissing('notes', 'caption', 'TEXT');
    _addColumnIfMissing('notes', 'mime_type', 'TEXT');
    // When this note wants to be brought back up. Deliberately on the note
    // rather than in a table of its own: one note has at most one reminder,
    // and a join to answer "does this card show a bell" would be paid on
    // every timeline read.
    _addColumnIfMissing('notes', 'due_at', 'TEXT');
    _addColumnIfMissing('notes', 'due_repeat', 'TEXT');

    // Local-only organisation: up to five pinned notes, and a manual
    // position set by dragging in Rearrange mode. Neither is synced or
    // exported (see Note.pinnedAt / Note.sortOrder).
    _addColumnIfMissing('notes', 'pinned_at', 'TEXT');
    _addColumnIfMissing('notes', 'sort_order', 'INTEGER');

    // An optional headline, on any note. Deliberately not asked for at
    // capture — see `Note.title`.
    _addColumnIfMissing('notes', 'title', 'TEXT');
    // A link note's own description, read off the page it points at. The
    // machine-derived text field for links, the way transcript_text is for
    // voice and ocr_text is for photos.
    _addColumnIfMissing('notes', 'link_excerpt', 'TEXT');

    _dropLegacyTypeCheck();

    // Created after [_dropLegacyTypeCheck] on purpose — see the note above.
    // The outbox is scanned on every sync cycle and after every write; the
    // reminder rebuild walks due_at.
    db.execute(
      'CREATE INDEX IF NOT EXISTS idx_notes_sync_state ON notes(sync_state);',
    );
    db.execute(
      'CREATE INDEX IF NOT EXISTS idx_notes_due_at ON notes(due_at);',
    );

    // Tags get the outbox notes have always had.
    //
    // Without it the client cannot tell which tags are dirty, so it pushed the
    // whole tag table on every sync — and every one of those upserts minted a
    // new server sequence, which put all of them above every other device's
    // cursor and made each sync broadcast the entire tag table to every peer.
    // Existing rows default to 'pending' so the first sync after this upgrade
    // reconciles them once, and then stops.
    _addColumnIfMissing(
      'tags',
      'sync_state',
      "TEXT NOT NULL DEFAULT 'pending'",
    );

    db.execute('''
CREATE TABLE IF NOT EXISTS note_embeddings (
  note_id TEXT PRIMARY KEY NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
  dims INTEGER NOT NULL,
  values_json TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
''');

    // Records one-off data migrations, so a seed that the user has since
    // edited or deleted is never quietly put back.
    db.execute('''
CREATE TABLE IF NOT EXISTS nex_meta (
  key TEXT PRIMARY KEY NOT NULL,
  value TEXT NOT NULL
);
''');

    // Local memory/profile store (09-ai.md — Phase 2, ADR-029). Shaped like
    // `notes` (id, timestamps, device_id, rev, soft-delete — ADR-006) so it
    // can ride the same sync machinery later without a schema redesign.
    db.execute('''
CREATE TABLE IF NOT EXISTS memory_records (
  id TEXT PRIMARY KEY NOT NULL,
  kind TEXT NOT NULL,
  key TEXT,
  value_text TEXT NOT NULL,
  source TEXT NOT NULL,
  confidence REAL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT,
  device_id TEXT NOT NULL,
  rev INTEGER NOT NULL
);
''');
    db.execute(
      'CREATE INDEX IF NOT EXISTS idx_memory_records_kind ON memory_records(kind);',
    );

    _seedStarterTags();
  }

  /// Puts the starter tags in the tag table, once.
  ///
  /// They used to be a hardcoded list the add-tag dialog offered and nothing
  /// else knew about: they could not be renamed, recoloured or deleted, and
  /// they were not the user's own tags. As real rows they are ordinary tags
  /// from the first launch onwards.
  void _seedStarterTags() {
    final done = db.select(
      "SELECT value FROM nex_meta WHERE key = 'starter_tags_seeded'",
    );
    if (done.isNotEmpty) return;
    final now = DateTime.now().toUtc().toIso8601String();
    for (final name in suggestedStarterTags) {
      db.execute(
        'INSERT OR IGNORE INTO tags (id, name, color, created_at) '
        'VALUES (?, ?, NULL, ?)',
        // A name-derived id, so two devices seeding the same starters agree on
        // one row rather than syncing into a duplicate.
        [stableUuidV5(name), name, now],
      );
    }
    db.execute(
      "INSERT OR REPLACE INTO nex_meta (key, value) VALUES ('starter_tags_seeded', ?)",
      [now],
    );
  }

  /// Rebuilds `notes` once, to shed the `CHECK (type IN (...))` that v1's
  /// schema pinned to the four types it happened to ship with.
  ///
  /// SQLite cannot drop a constraint in place, and `CREATE TABLE IF NOT
  /// EXISTS` does not touch a table that already exists — so on every database
  /// created before this, inserting a checklist or a link would fail the
  /// constraint no matter what the Dart side believed. This is the documented
  /// twelve-step table rebuild, narrowed to what actually applies here.
  ///
  /// It runs at most once: the marker is the constraint itself, so a database
  /// that has already been through it (or was created after) is left alone.
  void _dropLegacyTypeCheck() {
    final schema = db.select(
      "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'notes'",
    );
    if (schema.isEmpty) return;
    final sql = schema.first['sql'] as String? ?? '';
    if (!sql.contains('CHECK (type IN')) return;

    // Every column the table has right now, in its own order — including the
    // ones added by _addColumnIfMissing above, which is why this runs last.
    final columns = [
      for (final row in db.select('PRAGMA table_info(notes)'))
        row['name']! as String,
    ];
    final columnList = columns.join(', ');

    // Foreign keys off for the swap: note_tags points at notes(id), and the
    // rows have to survive the table being dropped out from under them.
    db.execute('PRAGMA foreign_keys = OFF;');
    db.execute('BEGIN;');
    try {
      db.execute('''
CREATE TABLE notes_rebuilt (
  id TEXT PRIMARY KEY NOT NULL,
  type TEXT NOT NULL,
  content TEXT,
  media_uri TEXT,
  media_hash TEXT,
  duration_ms INTEGER,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT,
  device_id TEXT NOT NULL,
  rev INTEGER NOT NULL,
  sync_state TEXT NOT NULL CHECK (sync_state IN ('pending', 'synced', 'conflict')),
  transcript_text TEXT,
  ocr_text TEXT,
  summary_text TEXT,
  caption TEXT,
  mime_type TEXT,
  -- Every column `_addColumnIfMissing` adds above has to appear here too:
  -- the copy below is generated from the *live* table's columns, so a column
  -- added to notes and forgotten here makes the rebuild fail on exactly the
  -- databases it exists to migrate.
  due_at TEXT,
  due_repeat TEXT,
  pinned_at TEXT,
  sort_order INTEGER,
  title TEXT,
  link_excerpt TEXT
);
''');
      db.execute(
        'INSERT INTO notes_rebuilt ($columnList) SELECT $columnList FROM notes',
      );
      db.execute('DROP TABLE notes;');
      db.execute('ALTER TABLE notes_rebuilt RENAME TO notes;');
      db.execute(
        'CREATE INDEX IF NOT EXISTS idx_notes_created_at ON notes(created_at DESC);',
      );
      db.execute(
        'CREATE INDEX IF NOT EXISTS idx_notes_deleted_at ON notes(deleted_at);',
      );
      db.execute('COMMIT;');
    } catch (_) {
      db.execute('ROLLBACK;');
      rethrow;
    } finally {
      db.execute('PRAGMA foreign_keys = ON;');
    }
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

    final existing =
        dir
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
    //
    // `-journal` goes too. The live database runs in WAL mode, but a crash
    // under an older rollback-journal build (or a file written by one) can
    // leave `nex.sqlite-journal` behind, and SQLite would treat whatever is
    // in it as hot for the file being swapped in and roll old pages back
    // over the restored data. Every sidecar that can carry state goes.
    for (final suffix in ['', '-wal', '-shm', '-journal']) {
      final f = File('$liveDbPath$suffix');
      if (f.existsSync()) f.deleteSync();
    }
    restoring.renameSync(liveDbPath);
  }

  /// Throws unless [dbPath] is a database worth restoring.
  ///
  /// Exposed for [NexBackupArchive], which validates the copy it unpacked
  /// from a zip before letting it near the live files — the same check this
  /// class already made for a bare `.sqlite` backup, and there is no reason
  /// the newer format should get a weaker one.
  static void assertRestorable(String dbPath) {
    final file = File(dbPath);
    if (!file.existsSync()) throw StateError('Missing database: $dbPath');
    if (file.lengthSync() == 0) throw StateError('Empty database: $dbPath');
    try {
      _assertSqliteIntegrity(dbPath);
    } catch (e) {
      // One failure type for every way a backup can be unusable. Opening a
      // file that is not a database at all throws SqliteException from deep
      // inside the driver, and a caller deciding whether to abort a restore
      // should not have to know that.
      throw StateError('Backup failed integrity check: $e');
    }
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
