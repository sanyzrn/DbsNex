import 'package:nex_data/nex_data.dart';
import 'package:test/test.dart';

/// Two notes with the same timestamp come back in the order they were written.
///
/// The timeline was ordered by `updated_at` alone, so a tie — two files shared
/// at once, an import, or two captures inside one tick of a coarse clock — was
/// left to SQLite, which promises nothing, and the pair could swap between one
/// read and the next. An independent audit met it as a test that failed on
/// Windows and passed on rerun.
void main() {
  late NexDatabase db;
  late SqliteNoteRepository repo;
  final at = DateTime.utc(2026, 9, 24, 8);

  setUp(() {
    db = NexDatabase.openInMemory();
    repo = SqliteNoteRepository(db);
  });

  tearDown(() => db.close());

  Note note(String id, String content) => Note(
    id: id,
    type: NoteType.text,
    content: content,
    createdAt: at,
    updatedAt: at,
    deviceId: 'test',
    rev: 1,
    syncState: SyncState.pending,
  );

  test('a tie on the timestamp is broken by write order, newest first', () {
    // Ids chosen so that sorting by id would give the *other* answer — the
    // tie-break must be the order of writing, not anything about the id.
    repo.insert(note('b-written-first', 'first'));
    repo.insert(note('a-written-second', 'second'));

    for (var read = 0; read < 3; read++) {
      expect(repo.listTimeline().map((n) => n.content), [
        'second',
        'first',
      ], reason: 'read $read');
    }
  });

  test('search breaks the same tie the same way', () {
    repo.insert(note('b-written-first', 'first match'));
    repo.insert(note('a-written-second', 'second match'));

    expect(
      repo.search(const SearchFilters(query: 'match')).map((n) => n.content),
      ['second match', 'first match'],
    );
  });

  test(
    'pins with millisecond and microsecond timestamps stay chronological',
    () {
      final first = repo.insert(note('first', 'pinned first'));
      final second = repo.insert(note('second', 'pinned second'));
      final firstPin = DateTime.utc(2026, 11, 4, 21, 51, 27, 448);
      final secondPin = firstPin.add(const Duration(microseconds: 24));
      for (final (id, time) in [(first.id, firstPin), (second.id, secondPin)]) {
        db.db.execute('UPDATE notes SET pinned_at = ? WHERE id = ?', [
          time.toIso8601String(),
          id,
        ]);
      }
      final tag = repo.upsertTag(name: 'Both');
      repo.attachTag(noteId: first.id, tagId: tag.id);
      repo.attachTag(noteId: second.id, tagId: tag.id);

      for (final tagId in [null, tag.id]) {
        expect(repo.listTimeline(tagId: tagId).map((n) => n.id), [
          second.id,
          first.id,
        ]);
      }
      // Reading repairs the order without rewriting stored timestamps.
      expect(repo.getById(first.id)!.pinnedAt, firstPin);
      expect(repo.getById(second.id)!.pinnedAt, secondPin);
    },
  );
}
