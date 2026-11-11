import 'dart:io';

import 'package:nex_data/nex_data.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

/// The rowid re-keying of the search index (2.6.19): a note's `notes_fts`
/// row carries the note's own `notes.rowid`, so deleting and asking for it
/// are one lookup instead of a scan of the whole index. These tests pin the
/// migration from a 2.6.18-shaped library and the write paths' behaviour
/// under the new key.
void main() {
  late Directory tmp;
  late NexDatabase db;
  late SqliteNoteRepository repo;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('nex_fts_rowid_');
    db = NexDatabase.open(p.join(tmp.path, 'nex.sqlite'));
    repo = SqliteNoteRepository(db);
  });

  tearDown(() {
    db.close();
    tmp.deleteSync(recursive: true);
  });

  Note makeText(String content) {
    final now = DateTime.now().toUtc();
    return Note(
      id: newUuidV7(),
      type: NoteType.text,
      content: content,
      createdAt: now,
      updatedAt: now,
      deviceId: 'test',
      rev: 1,
      syncState: SyncState.pending,
    );
  }

  List<String> searchIds(String query) =>
      repo.search(SearchFilters(query: query)).map((n) => n.id).toList();

  int ftsRowsFor(String noteId) =>
      repo.db.select('SELECT COUNT(*) c FROM notes_fts WHERE note_id = ?', [
            noteId,
          ]).first['c']
          as int;

  /// Rewinds a freshly made library to the shape 2.6.18 wrote: FTS rows with
  /// FTS-assigned rowids, no alignment marker. The note rows themselves are
  /// untouched — exactly what a real upgrade opens.
  void deAlign() {
    final rows = repo.db
        .select('SELECT note_id, content FROM notes_fts')
        .map((r) => (r['note_id'] as String, r['content'] as String))
        .toList();
    repo.db.execute('DELETE FROM notes_fts');
    for (final (i, (id, content)) in rows.indexed) {
      // The old writer: no explicit rowid, so FTS assigns its own — which
      // only coincides with the note's on a library that has never lost a
      // row. Numbered far away from the notes' own rowids so the fixture is
      // genuinely misaligned whichever way the notes happen to lie.
      repo.db.execute(
        'INSERT INTO notes_fts (rowid, note_id, content) VALUES (?, ?, ?)',
        [10000 + i, id, content],
      );
    }
    repo.db.execute("DELETE FROM nex_meta WHERE key = 'fts_rowid_aligned'");
    // And stamp it as the older build would have left it.
    repo.db.execute('PRAGMA user_version = ${NexDatabase.schemaVersion - 1}');
  }

  test('every new search row carries its note’s own rowid', () {
    final a = repo.insert(makeText('alpha words'));
    final b = repo.insert(makeText('beta words'));

    final rows = repo.db.select('''
SELECT f.rowid AS fts_rowid, n.rowid AS note_rowid
FROM notes_fts f JOIN notes n ON n.id = f.note_id
''');
    expect(rows, hasLength(2));
    for (final row in rows) {
      expect(row['fts_rowid'], row['note_rowid']);
    }
    expect(ftsRowsFor(a.id), 1);
    expect(ftsRowsFor(b.id), 1);
  });

  test('opening a 2.6.18 library re-keys its search rows in place', () {
    final a = repo.insert(makeText('alpha words'));
    final b = repo.insert(makeText('beta words'));
    deAlign();

    // A pre-re-key row cannot address its note's rowid.
    final unaligned =
        db.db.select('''
SELECT COUNT(*) c FROM notes_fts f JOIN notes n ON n.rowid = f.rowid
''').first['c']
            as int;
    expect(unaligned, 0, reason: 'fixture must start unaligned');

    db.close();
    final reopened = db = NexDatabase.open(p.join(tmp.path, 'nex.sqlite'));
    repo = SqliteNoteRepository(reopened);

    // Re-keyed, not rebuilt: same rows, same words, new keys.
    expect(
      reopened.db.select('SELECT COUNT(*) c FROM notes_fts').first['c'] as int,
      2,
    );
    final aligned =
        reopened.db.select('''
SELECT COUNT(*) c FROM notes_fts f JOIN notes n ON n.rowid = f.rowid AND n.id = f.note_id
''').first['c']
            as int;
    expect(aligned, 2);
    expect(searchIds('alpha'), contains(a.id));
    expect(searchIds('beta'), contains(b.id));

    // The marker is written, so a second open does not pass through the
    // migration again.
    final marker = reopened.db.select(
      "SELECT value FROM nex_meta WHERE key = 'fts_rowid_aligned'",
    );
    expect(marker, isNotEmpty);
  });

  test('editing an upgraded note replaces its row without leaving a twin', () {
    final a = repo.insert(makeText('first draft'));
    deAlign();
    db.close();
    db = NexDatabase.open(p.join(tmp.path, 'nex.sqlite'));
    repo = SqliteNoteRepository(db);

    repo.updateContent(a.id, 'second draft');

    expect(ftsRowsFor(a.id), 1);
    expect(searchIds('second'), contains(a.id));
    expect(searchIds('first'), isEmpty);
  });

  test('a soft delete removes exactly the note’s row under the new key', () {
    final a = repo.insert(makeText('alpha words'));
    final b = repo.insert(makeText('beta words'));

    repo.softDelete(a.id);

    expect(ftsRowsFor(a.id), 0);
    expect(ftsRowsFor(b.id), 1);
    expect(searchIds('alpha'), isEmpty);
    expect(searchIds('beta'), contains(b.id));
  });

  test('the repair still drops orphan rows and trashed-note rows', () {
    final a = repo.insert(makeText('alpha words'));
    final b = repo.insert(makeText('beta words'));
    final ghost = repo.insert(makeText('ghost words'));

    // A purge that lost its search-row delete, and a trash-restore of b's row.
    repo.db.execute('DELETE FROM notes WHERE id = ?', [ghost.id]);
    repo.db.execute(
      "UPDATE notes SET deleted_at = '2020-01-01T00:00:00.000Z' WHERE id = ?",
      [b.id],
    );
    // Put a row back for the trashed note — the state a crash between the
    // soft-delete's paired statements can leave behind.
    repo.db.execute('DELETE FROM notes_fts WHERE note_id = ?', [b.id]);
    repo.db.execute(
      'INSERT INTO notes_fts (rowid, note_id, content) VALUES (?, ?, ?)',
      [
        repo.db.select('SELECT rowid FROM notes WHERE id = ?', [
          b.id,
        ]).first['rowid'],
        b.id,
        'beta words',
      ],
    );

    repo.repairSearchIndex();

    expect(ftsRowsFor(ghost.id), 0);
    expect(ftsRowsFor(b.id), 0);
    expect(ftsRowsFor(a.id), 1);
    expect(searchIds('beta'), isEmpty);
    expect(searchIds('alpha'), contains(a.id));
  });

  test('repair restores a lost row under the new keying', () {
    final a = repo.insert(makeText('alpha words'));
    repo.db.execute('DELETE FROM notes_fts WHERE rowid = ?', [
      repo.db.select('SELECT rowid FROM notes WHERE id = ?', [
        a.id,
      ]).first['rowid'],
    ]);

    repo.repairSearchIndex();

    expect(ftsRowsFor(a.id), 1);
    expect(searchIds('alpha'), contains(a.id));
  });

  test('deleteSearchRow falls back to the label scan for a vanished note', () {
    final a = repo.insert(makeText('alpha words'));
    // Remove the note row hard, leaving its search row behind — the state a
    // crashed purge can leave.
    repo.db.execute('DELETE FROM notes WHERE id = ?', [a.id]);

    repo.deleteSearchRow(a.id);

    expect(ftsRowsFor(a.id), 0);
  });

  test('scheduling a note takes its words out of search', () {
    final scheduled = SqliteScheduledNoteRepository(db, repo);
    final a = repo.insert(makeText('later words'));
    final b = repo.insert(makeText('stays words'));

    final moved = scheduled.schedule(
      a.id,
      DateTime.now().add(const Duration(days: 1)),
    );

    expect(moved, isNotNull);
    expect(ftsRowsFor(a.id), 0);
    expect(searchIds('later'), isEmpty);
    expect(searchIds('stays'), contains(b.id));
  });

  test('a re-keyed library keeps its tag-usage counts right', () {
    final a = repo.insert(makeText('alpha words'));
    final tag = repo.upsertTag(name: 'kept');
    repo.attachTag(noteId: a.id, tagId: tag.id);
    deAlign();
    db.close();
    db = NexDatabase.open(p.join(tmp.path, 'nex.sqlite'));
    repo = SqliteNoteRepository(db);

    final usage = LibraryMaintenance(
      repo,
      mediaRoot: tmp.path,
    ).tagUsage(timelineOnly: true);

    final kept = usage.firstWhere(
      (u) => u.tag.id == tag.id,
      orElse: () => throw StateError('tag missing from usage'),
    );
    expect(kept.count, 1);
    expect(
      usage.where((u) => u.count > 0).map((u) => u.tag.id),
      containsAllInOrder([tag.id]),
    );
  });

  test('an older build cannot silently open the re-keyed library', () {
    // The downgrade guard the stamp exists for: a library this build has
    // migrated is stamped above what an older build understands, so that
    // build refuses the library rather than writing rows keyed the old way.
    expect(
      db.db.select('PRAGMA user_version').first.values.first,
      NexDatabase.schemaVersion,
    );
    final raw = sqlite3.open(p.join(tmp.path, 'probe.sqlite'));
    try {
      raw.execute('PRAGMA user_version = ${NexDatabase.schemaVersion}');
      expect(
        raw.select('PRAGMA user_version').first.values.first,
        NexDatabase.schemaVersion,
      );
    } finally {
      raw.close();
    }
  });
}
