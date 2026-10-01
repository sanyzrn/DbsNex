import 'dart:io';

import 'package:nex_data/nex_data.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Reads that must not grow with the whole library (PERF-04, PERF-05,
/// PERF-06).
void main() {
  late Directory tmp;
  late NexDatabase db;
  late SqliteNoteRepository repo;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('nex_large_');
    db = NexDatabase.open(p.join(tmp.path, 'nex.sqlite'));
    repo = SqliteNoteRepository(db);
  });

  tearDown(() {
    db.close();
    tmp.deleteSync(recursive: true);
  });

  void seed(int count) {
    final start = DateTime.utc(2025);
    for (var i = 0; i < count; i++) {
      final at = start.add(Duration(minutes: i));
      repo.insert(
        Note(
          id: newUuidV7(),
          type: NoteType.text,
          content: 'note $i',
          createdAt: at,
          updatedAt: at,
          deviceId: 'test-device',
          rev: 1,
          syncState: SyncState.pending,
        ),
      );
    }
  }

  test('an empty search box reads the newest page, not the library', () {
    seed(SqliteNoteRepository.rankedLimit + 15);
    final shown = repo.search(const SearchFilters(query: ''));
    expect(shown, hasLength(SqliteNoteRepository.rankedLimit));
    expect(
      shown.first.content,
      'note ${SqliteNoteRepository.rankedLimit + 14}',
    );
  });

  test('a chosen filter still lists everything it matches', () {
    seed(SqliteNoteRepository.rankedLimit + 15);
    final shown = repo.search(
      const SearchFilters(query: '', types: [NoteType.text]),
    );
    expect(shown, hasLength(SqliteNoteRepository.rankedLimit + 15));
  });

  test('tags still arrive with each note, in name order', () {
    seed(3);
    final note = repo.listTimeline().first;
    final b = repo.upsertTag(name: 'beta');
    final a = repo.upsertTag(name: 'Alpha');
    repo.attachTag(noteId: note.id, tagId: b.id);
    repo.attachTag(noteId: note.id, tagId: a.id);
    final read = repo.listTimeline().firstWhere((n) => n.id == note.id);
    expect(read.tags.map((t) => t.name), ['Alpha', 'beta']);
  });

  test('the timeline page is read from its index, with no sort', () {
    final plan = db.db
        .select('''
EXPLAIN QUERY PLAN
SELECT n.* FROM notes n
WHERE deleted_at IS NULL
ORDER BY
  (pinned_at IS NOT NULL) DESC,
  pinned_at DESC,
  updated_at DESC,
  n.rowid DESC
LIMIT 50 OFFSET 0
''')
        .map((row) => row['detail'] as String)
        .join('\n');
    expect(plan, contains('idx_notes_timeline'));
    expect(plan, isNot(contains('TEMP B-TREE')));
  });
}
