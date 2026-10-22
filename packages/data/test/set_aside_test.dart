import 'dart:io';

import 'package:nex_data/nex_data.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late NexDatabase db;
  late SqliteNoteRepository repo;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('nex_aside_');
    db = NexDatabase.open(p.join(tmp.path, 'nex.sqlite'));
    repo = SqliteNoteRepository(db);
  });

  tearDown(() {
    db.close();
    tmp.deleteSync(recursive: true);
  });

  Note make(String content) {
    final now = DateTime.now().toUtc();
    return repo.insert(
      Note(
        id: newUuidV7(),
        type: NoteType.text,
        content: content,
        createdAt: now,
        updatedAt: now,
        deviceId: 'test-device',
        rev: 1,
        syncState: SyncState.pending,
      ),
    );
  }

  group('set aside', () {
    test('leaves the home timeline but stays searchable and countable', () {
      final keep = make('stays on the home screen');
      final aside = make('quietly put to one side');
      expect(repo.setAside(aside.id), isTrue);

      expect([for (final n in repo.listTimeline()) n.id], [keep.id]);
      expect(repo.setAsideCount(), 1);
      expect([for (final n in repo.listSetAside()) n.id], [aside.id]);
      // Still a live note: search finds it and it is not in the trash.
      expect(repo.getById(aside.id), isNotNull);
      expect(
        repo.search(const SearchFilters(query: 'quietly')).map((n) => n.id),
        [aside.id],
      );
      expect(repo.getById(aside.id)!.isSetAside(), isTrue);
    });

    test('bring back returns it to its own place', () {
      final aside = make('back again');
      repo.setAside(aside.id);
      expect(repo.listTimeline(), isEmpty);
      repo.bringBack(aside.id);
      expect([for (final n in repo.listTimeline()) n.id], [aside.id]);
      expect(repo.setAsideCount(), 0);
      expect(repo.getById(aside.id)!.setAsideAt, isNull);
    });

    test('a return time that has passed puts the note back by itself', () {
      final aside = make('later');
      expect(
        repo.setAside(
          aside.id,
          until: DateTime.now().add(const Duration(days: 1)),
        ),
        isTrue,
      );
      expect(repo.listTimeline(), isEmpty);
      // Wind the return time into the past, as a day going by would.
      db.db.execute('UPDATE notes SET set_aside_until = ? WHERE id = ?', [
        DateTime.now()
            .toUtc()
            .subtract(const Duration(minutes: 1))
            .toIso8601String(),
        aside.id,
      ]);
      // Back on the timeline before anything has cleared the columns.
      expect([for (final n in repo.listTimeline()) n.id], [aside.id]);
      expect(repo.setAsideCount(), 0);
      expect(repo.getById(aside.id)!.isSetAside(), isFalse);

      expect(repo.releaseDueSetAside(), [aside.id]);
      expect(repo.getById(aside.id)!.setAsideAt, isNull);
      expect(repo.releaseDueSetAside(), isEmpty);
    });

    test('refuses a return time that is not in the future', () {
      final note = make('too late');
      expect(
        repo.setAside(
          note.id,
          until: DateTime.now().subtract(const Duration(minutes: 1)),
        ),
        isFalse,
      );
      expect(repo.listTimeline(), hasLength(1));
    });

    test('a pinned note gives up its pin and does not hold a slot', () {
      final note = make('pinned then hidden');
      expect(repo.pinNote(note.id), isTrue);
      repo.setAside(note.id);
      expect(repo.pinnedNoteCount(), 0);
    });

    test('the tag filter honours it too', () {
      final tag = repo.upsertTag(name: 'work', color: tagAccentPalette.first);
      final aside = make('tagged aside');
      repo.attachTag(noteId: aside.id, tagId: tag.id);
      expect(repo.listTimeline(tagId: tag.id), hasLength(1));
      repo.setAside(aside.id);
      expect(repo.listTimeline(tagId: tag.id), isEmpty);
    });

    test('a deleted note cannot be set aside', () {
      final note = make('gone');
      repo.softDelete(note.id);
      expect(repo.setAside(note.id), isFalse);
    });
  });
}
