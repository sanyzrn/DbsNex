import 'dart:io';

import 'package:nex_data/nex_data.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The counts an arranged home's shelves say they hold (2.7.0): over the
/// whole timeline, without pinned, set-aside or deleted notes, and a note with
/// two tags counted once under each.
void main() {
  late Directory tmp;
  late NexDatabase db;
  late SqliteNoteRepository repo;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('nex_shelf_counts_');
    db = NexDatabase.open(p.join(tmp.path, 'nex.sqlite'));
    repo = SqliteNoteRepository(db, localDeviceId: 'd');
  });

  tearDown(() {
    db.close();
    tmp.deleteSync(recursive: true);
  });

  Note insert(NoteType type) {
    final now = DateTime.now().toUtc();
    return repo.insert(
      Note(
        id: newUuidV7(),
        type: type,
        content: type == NoteType.link ? 'https://example.com' : 'words',
        createdAt: now,
        updatedAt: now,
        deviceId: 'test',
        rev: 1,
        syncState: SyncState.pending,
      ),
    );
  }

  test('kinds, tags and untagged, over the home timeline only', () {
    final work = repo.upsertTag(name: 'work');
    final home = repo.upsertTag(name: 'home');
    final a = insert(NoteType.text);
    final b = insert(NoteType.text);
    insert(NoteType.link);
    final pinned = insert(NoteType.text);
    final aside = insert(NoteType.photo);
    final gone = insert(NoteType.photo);

    repo.attachTag(noteId: a.id, tagId: work.id);
    repo.attachTag(noteId: a.id, tagId: home.id);
    repo.attachTag(noteId: b.id, tagId: work.id);
    repo.attachTag(noteId: pinned.id, tagId: work.id);
    repo.pinNote(pinned.id);
    repo.setAside(aside.id);
    repo.softDelete(gone.id);

    final counts = repo.timelineShelfCounts();
    expect(counts['type:text'], 2, reason: 'the pinned text is on its shelf');
    expect(counts['type:link'], 1);
    expect(counts.containsKey('type:photo'), isFalse);
    expect(counts['tag:${work.id}'], 2);
    expect(counts['tag:${home.id}'], 1);
    expect(counts['untagged'], 1, reason: 'the link');
  });

  test('an empty library counts nothing untagged', () {
    expect(repo.timelineShelfCounts(), {'untagged': 0});
  });
}
