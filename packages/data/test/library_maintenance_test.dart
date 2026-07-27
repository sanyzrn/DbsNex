import 'dart:io';

import 'package:nex_data/nex_data.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late NexDatabase db;
  late SqliteNoteRepository repo;
  late LibraryMaintenance maintenance;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('nex_maintenance_');
    db = NexDatabase.open(p.join(tmp.path, 'nex.sqlite'));
    repo = SqliteNoteRepository(db);
    maintenance = LibraryMaintenance(repo);
  });

  tearDown(() {
    db.close();
    tmp.deleteSync(recursive: true);
  });

  Note insertText(String content) {
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

  group('trash', () {
    test('purgeNote removes one trashed note and leaves the rest', () {
      final doomed = insertText('doomed');
      final spared = insertText('spared');
      repo.softDelete(doomed.id);
      repo.softDelete(spared.id);
      expect(maintenance.deletedNotes(), hasLength(2));

      maintenance.purgeNote(doomed.id);

      final left = maintenance.deletedNotes();
      expect(left, hasLength(1));
      expect(left.single.id, spared.id);
      expect(repo.getById(doomed.id, includeDeleted: true), isNull);
    });

    test('purgeNote cannot reach a live note', () {
      final live = insertText('still here');

      maintenance.purgeNote(live.id);

      expect(repo.getById(live.id), isNotNull);
      expect(repo.listTimeline(), hasLength(1));
    });

    test('purgeAllDeleted empties the trash without touching the timeline', () {
      final kept = insertText('kept');
      final first = insertText('first');
      final second = insertText('second');
      repo.softDelete(first.id);
      repo.softDelete(second.id);

      maintenance.purgeAllDeleted();

      expect(maintenance.deletedNotes(), isEmpty);
      expect(repo.listTimeline().single.id, kept.id);
    });

    test('purging a tagged note drops its tag links, not the tag', () {
      final note = insertText('tagged');
      final tag = repo.upsertTag(name: 'Work');
      repo.attachTag(noteId: note.id, tagId: tag.id);
      repo.softDelete(note.id);

      maintenance.purgeNote(note.id);

      expect(
        repo.db.select('SELECT * FROM note_tags WHERE note_id = ?', [note.id]),
        isEmpty,
      );
      expect(maintenance.tagUsage().map((u) => u.tag.name), contains('Work'));
    });
  });
}
