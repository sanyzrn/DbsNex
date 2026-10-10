import 'dart:io';

import 'package:nex_data/nex_data.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

/// A library as the first public release left it, opened by this build
/// (DATA-06). Each migration step has its own test; this one is the whole
/// path at once, so two steps that compose wrongly — a column added by one
/// and forgotten in another's rebuild — fail here.
void main() {
  late Directory tmp;
  late String path;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('nex_migration_');
    path = p.join(tmp.path, 'nex.sqlite');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  /// The v1 layout: four note types pinned by a CHECK, the plain FTS table,
  /// tags and nothing else — no meta table, no receipts, no embeddings.
  void writeV1Library() {
    final zwnj = String.fromCharCode(0x200C);
    final db = sqlite3.open(path);
    db.execute('''
CREATE TABLE notes (
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
CREATE TABLE tags (
  id TEXT PRIMARY KEY NOT NULL,
  name TEXT NOT NULL UNIQUE,
  color TEXT,
  created_at TEXT NOT NULL
);
CREATE TABLE note_tags (
  note_id TEXT NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
  tag_id TEXT NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
  PRIMARY KEY (note_id, tag_id)
);
CREATE VIRTUAL TABLE notes_fts USING fts5(
  note_id UNINDEXED,
  content,
  tokenize = "unicode61 remove_diacritics 2 separators ' $zwnj'"
);
CREATE INDEX idx_notes_created_at ON notes(created_at DESC);
''');
    const at = '2026-01-01T00:00:00.000Z';
    db.execute(
      "INSERT INTO notes VALUES ('text-1', 'text', 'کتاب‌خانه و boiler service', "
      "NULL, NULL, NULL, '$at', '$at', NULL, 'phone', 3, 'synced')",
    );
    db.execute(
      "INSERT INTO notes VALUES ('voice-1', 'voice', NULL, '/media/v.m4a', "
      "'abc', 4200, '$at', '$at', NULL, 'phone', 1, 'synced')",
    );
    db.execute(
      "INSERT INTO notes VALUES ('gone-1', 'text', 'deleted long ago', NULL, "
      "NULL, NULL, '$at', '$at', '$at', 'phone', 2, 'synced')",
    );
    db.execute("INSERT INTO tags VALUES ('t-legacy', 'legacy', NULL, '$at')");
    db.execute("INSERT INTO note_tags VALUES ('text-1', 't-legacy')");
    db.execute(
      "INSERT INTO notes_fts (note_id, content) VALUES "
      "('text-1', 'کتاب‌خانه و boiler service')",
    );
    db.dispose();
  }

  Map<String, Object?> shape(NexDatabase db) => {
    'schema': [
      for (final row in db.db.select(
        "SELECT type, name, sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' "
        'ORDER BY name',
      ))
        '${row['type']} ${row['name']} ${row['sql']}',
    ],
    'notes': db.db.select('SELECT COUNT(*) AS n FROM notes').first['n'],
    'tags': db.db.select('SELECT COUNT(*) AS n FROM tags').first['n'],
    'fts': db.db.select('SELECT COUNT(*) AS n FROM notes_fts').first['n'],
  };

  test('a v1 library opens, keeps everything and takes new types', () {
    writeV1Library();
    final db = NexDatabase.open(path);
    final repo = SqliteNoteRepository(db, localDeviceId: 'phone');

    final text = repo.getById('text-1')!;
    expect(text.content, 'کتاب‌خانه و boiler service');
    expect(text.rev, 3);
    expect(text.tags.map((t) => t.name), ['legacy']);
    expect(repo.getById('voice-1')!.durationMs, 4200);
    // Still in the trash, not lost and not back on the timeline.
    expect(repo.getById('gone-1'), isNull);
    expect(
      db.db
          .select("SELECT deleted_at FROM notes WHERE id = 'gone-1'")
          .single['deleted_at'],
      isNotNull,
    );

    // Found by search after the index was rebuilt and folded.
    expect(
      repo.search(const SearchFilters(query: 'boil')).map((n) => n.id),
      contains('text-1'),
    );
    expect(
      repo.search(const SearchFilters(query: 'کتاب')).map((n) => n.id),
      contains('text-1'),
    );

    // The types v1's CHECK refused.
    final now = DateTime.now().toUtc();
    for (final type in [NoteType.checklist, NoteType.link]) {
      repo.insert(
        Note(
          id: 'new-${type.wireName}',
          type: type,
          content: type == NoteType.link ? 'https://example.com' : '- [ ] a',
          createdAt: now,
          updatedAt: now,
          deviceId: 'phone',
          rev: 1,
          syncState: SyncState.pending,
        ),
      );
    }
    expect(repo.getById('new-checklist'), isNotNull);
    expect(repo.getById('new-link'), isNotNull);

    // Starter tags beside the old one, once.
    expect(repo.listTags(), hasLength(suggestedStarterTags.length + 1));
    expect(
      db.db.select('PRAGMA user_version').first.values.first,
      NexDatabase.schemaVersion,
    );
    final first = shape(db);
    db.close();

    // A second open changes nothing.
    final again = NexDatabase.open(path);
    expect(shape(again), first);
    expect(
      SqliteNoteRepository(again).listTags(),
      hasLength(suggestedStarterTags.length + 1),
    );
    again.close();
  });

  test('a library from a newer build is refused, not written to', () {
    NexDatabase.open(path).close();
    final db = sqlite3.open(path);
    db.execute('PRAGMA user_version = ${NexDatabase.schemaVersion + 1}');
    db.dispose();

    expect(() => NexDatabase.open(path), throwsA(isA<NewerLibraryException>()));
    // Untouched: the stamp is still the newer build's.
    final check = sqlite3.open(path);
    expect(
      check.select('PRAGMA user_version').first.values.first,
      NexDatabase.schemaVersion + 1,
    );
    check.dispose();
  });
}
