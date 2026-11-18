import 'dart:io';

import 'package:nex_data/nex_data.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The prepared-statement cache behind the hot queries (`NexDatabase`
/// `selectCached`/`executeCached`): a statement run twice with different
/// parameters answers each run with its own rows, the bound the cache keeps
/// is real, and the write path through it lands in the index.
void main() {
  late Directory tmp;
  late NexDatabase db;
  late SqliteNoteRepository repo;

  Note note(String id, {String content = 'words'}) {
    final now = DateTime.now().toUtc();
    return Note(
      id: id,
      type: NoteType.text,
      content: content,
      createdAt: now,
      updatedAt: now,
      deviceId: 'device-a',
      rev: 1,
      syncState: SyncState.pending,
    );
  }

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('nex_statement_cache_');
    db = NexDatabase.open(p.join(tmp.path, 'nex.sqlite'));
    repo = SqliteNoteRepository(db);
  });

  tearDown(() {
    db.close();
    tmp.deleteSync(recursive: true);
  });

  test('two cached runs of one statement do not alias each other', () {
    repo.insert(note('a', content: 'alpha'));
    repo.insert(note('b', content: 'beta'));
    final first = db.selectCached('SELECT id FROM notes WHERE id = ?', ['a']);
    // The same statement, re-run with a different parameter — this resets
    // and re-binds it. The rows the first run returned must still say what
    // the first run read.
    final second = db.selectCached('SELECT id FROM notes WHERE id = ?', ['b']);
    expect(first.single['id'], 'a');
    expect(second.single['id'], 'b');
  });

  test('the timeline read repeats through the cache without drifting', () {
    for (var i = 0; i < 30; i++) {
      repo.insert(note('n$i', content: 'note number $i'));
    }
    final page1 = repo.listTimeline(limit: 10, offset: 0);
    final page2 = repo.listTimeline(limit: 10, offset: 10);
    expect(page1.length, 10);
    expect(page2.length, 10);
    expect(
      page1.map((n) => n.id).toSet().intersection(page2.map((n) => n.id).toSet()),
      isEmpty,
      reason: 'two cached pages of the same query are two answers',
    );
    // And a third read of the first page is still the first page.
    expect(repo.listTimeline(limit: 10, offset: 0).map((n) => n.id),
        page1.map((n) => n.id));
  });

  test('the bound on the cache is real', () {
    for (var i = 0; i < 200; i++) {
      db.selectCached('SELECT $i');
    }
    expect(db.debugStatementCacheSize, lessThanOrEqualTo(128));
    // And the cache still works after being emptied.
    expect(db.selectCached('SELECT 7').single.values.single, 7);
  });

  test('a write through the cached FTS statements lands in the index', () {
    repo.insert(note('searchable', content: 'the parable of the search row'));
    final found = repo
        .search(SearchFilters(query: 'parable'))
        .where((n) => n.id == 'searchable')
        .toList();
    expect(found, isNotEmpty);
    // A rewrite moves the row, not duplicates it: the delete and insert of
    // the upsert both went through the same cached statements.
    repo.updateContent('searchable', 'the fable of the search row');
    expect(
      repo.search(SearchFilters(query: 'fable')).where((n) => n.id == 'searchable'),
      isNotEmpty,
    );
    expect(
      repo.search(SearchFilters(query: 'parable')),
      isEmpty,
      reason: 'the old text is gone from the index',
    );
  });

  test('a schema change under a cached statement re-prepares, not throws', () {
    expect(repo.listTags(), isA<List<Tag>>());
    // A migration-shaped change to a table a cached statement reads.
    db.db.execute('ALTER TABLE tags ADD COLUMN cache_probe TEXT');
    // The cached `SELECT * FROM tags ...` now describes a different table;
    // SQLite re-prepares it on the next run.
    expect(repo.listTags(), isA<List<Tag>>());
  });
}
