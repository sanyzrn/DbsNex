import 'dart:io';

import 'package:nex_data/nex_data.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The index shapes and query plans the 2.8.5-era performance work pinned.
///
/// These are plan assertions, not timing tests: a plan that has slipped back
/// to a whole-table scan fails here deterministically, on any machine, no
/// matter how fast that machine happens to be — the same guard style
/// `nex-2.6.23` used for the "On this day" range reads.
void main() {
  late Directory tmp;
  late NexDatabase db;
  late SqliteNoteRepository repo;
  late SqliteThreadRepository threads;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('nex_index_shape_');
    db = NexDatabase.open(p.join(tmp.path, 'nex.sqlite'));
    repo = SqliteNoteRepository(db, localDeviceId: 'd');
    threads = SqliteThreadRepository(db, repo, localDeviceId: 'd');
  });

  tearDown(() {
    db.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Note text(String content) {
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

  List<String> plan(String sql, [List<Object?> args = const []]) => [
    for (final row in db.db.select('EXPLAIN QUERY PLAN $sql', args))
      row['detail']! as String,
  ].map((detail) => detail.replaceAll(RegExp(r'\s+'), ' ').trim()).toList();

  test('the home index carries created_at beside the flags', () {
    final columns = [
      for (final row in db.db.select('PRAGMA index_info(idx_notes_home)'))
        row['name']! as String?,
    ];
    expect(columns, contains('scheduled_until'));
    expect(columns, contains('created_at'));
  });

  test('a library with the old home index shape is rebuilt on open', () {
    // The shape a 2.8.1 library has: every flag, no `created_at`.
    final path = p.join(tmp.path, 'old.sqlite');
    final old = NexDatabase.open(path);
    old.db.execute('DROP INDEX idx_notes_home;');
    old.db.execute(
      'CREATE INDEX idx_notes_home ON notes('
      'id, deleted_at, set_aside_at, set_aside_until, scheduled_until);',
    );
    final columns = [
      for (final row in old.db.select('PRAGMA index_info(idx_notes_home)'))
        row['name']! as String?,
    ];
    expect(columns, isNot(contains('created_at')));
    old.close();

    final reopened = NexDatabase.open(path);
    addTearDown(reopened.close);
    final rebuilt = [
      for (final row in reopened.db.select('PRAGMA index_info(idx_notes_home)'))
        row['name']! as String?,
    ];
    expect(rebuilt, contains('created_at'));
  });

  test(
    "threads.list()'s last-activity arm probes notes, it does not scan them",
    () {
      // One thread with a handful of notes: the correlated MAX subquery is
      // the arm that walked every live note per thread before the covering
      // probe existed (measured 1,228 ms over 40 threads at 50,000 notes).
      final first = repo.insert(text('first'));
      final second = repo.insert(text('second'));
      threads.create('story', noteIds: [first.id, second.id]);

      final rows = plan(
        'SELECT MAX(n.created_at) FROM note_threads nt JOIN notes n '
        'ON n.id = nt.note_id WHERE nt.thread_id = ? AND n.deleted_at '
        'IS NULL AND (n.scheduled_until IS NULL OR n.scheduled_until <= ?)',
        ['story', DateTime.now().toUtc().toIso8601String()],
      );
      expect(rows.join(' '), contains('idx_notes_home'));
      expect(rows.join(' '), isNot(contains('SCAN notes')));
      // And the whole call behaves: counts and last activity both come out.
      final listed = threads.list();
      expect(listed.single.noteCount, 2);
      expect(listed.single.lastActivityAt, isNotNull);
    },
  );

  test('threads.notes() carries every note its tags with it', () {
    final note = repo.insert(text('threaded'));
    repo.upsertTag(name: 'keeps');
    repo.db.execute(
      'INSERT INTO note_tags (note_id, tag_id) '
      "SELECT ?, id FROM tags WHERE name = 'keeps'",
      [note.id],
    );
    final thread = threads.create('story', noteIds: [note.id]);
    final read = threads.notes(thread.id);
    expect(read.single.id, note.id);
    expect(read.single.tags.map((t) => t.name), ['keeps']);
  });

  test('the shelf counts read the kind from the index, not the rows', () {
    final rows = plan(
      "SELECT n.type AS type, COUNT(*) AS c FROM notes n WHERE "
      "n.deleted_at IS NULL AND n.pinned_at IS NULL AND "
      "(n.set_aside_at IS NULL OR (n.set_aside_until IS NOT NULL AND "
      "n.set_aside_until <= ?)) AND (n.scheduled_until IS NULL OR "
      "n.scheduled_until > ?) GROUP BY n.type",
      ['2999', '2999'],
    );
    final joined = rows.join(' ');
    expect(joined, contains('idx_notes_shelves'));
    // Grouped in index order, not sorted in a temporary b-tree.
    expect(joined, isNot(contains('TEMP B-TREE FOR GROUP BY')));
    expect(joined, isNot(contains('SCAN notes')));
    // And the counts themselves are right.
    repo.insert(text('a'));
    final counts = repo.timelineShelfCounts();
    expect(counts['type:text'], 1);
    expect(counts['untagged'], 1);
  });

  test('the media reference probes seek, they do not scan', () {
    // The purge's "is this file still referenced?" arm — one probe per
    // purged file that used to walk the whole notes table.
    final uriRows = plan('SELECT 1 FROM notes WHERE media_uri = ? LIMIT 1', [
      '/tmp/voice-1.rec',
    ]);
    expect(uriRows.join(' '), contains('idx_notes_media_uri'));
    expect(uriRows.join(' '), isNot(contains('SCAN notes')));
    // And the per-hash local paths arm.
    final hashRows = plan(
      'SELECT media_uri FROM notes WHERE media_hash = ? '
      'AND media_uri IS NOT NULL AND deleted_at IS NULL',
      ['hash-1'],
    );
    expect(hashRows.join(' '), contains('idx_notes_media_hash'));
    expect(hashRows.join(' '), isNot(contains('SCAN notes')));
  });

  test('nearestMiss walks the newest notes, it does not sort the library', () {
    final rows = plan(
      'SELECT * FROM notes INDEXED BY idx_notes_created_at WHERE '
      'deleted_at IS NULL AND scheduled_until IS NULL AND '
      '(content IS NOT NULL OR title IS NOT NULL OR caption IS NOT NULL '
      'OR transcript_text IS NOT NULL OR ocr_text IS NOT NULL) '
      'ORDER BY created_at DESC LIMIT 500',
    );
    final joined = rows.join(' ');
    expect(joined, contains('idx_notes_created_at'));
    expect(joined, isNot(contains('TEMP B-TREE')));
    // And the answer itself is unchanged: the closest recent note is found.
    repo.insert(text('the generator needs a service'));
    final miss = LibraryMaintenance(repo).nearestMiss('genrator');
    expect(miss, isNotNull);
    expect(miss!.content, contains('generator'));
  });
}
