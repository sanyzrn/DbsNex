import 'dart:io';

import 'package:nex_data/nex_data.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The timeline puts an edited note back at the top, which is right — it is
/// the note you were just working on. Filing one under a tag was doing the
/// same thing, and it is not the same thing: the note still says exactly what
/// it said.
void main() {
  late Directory tmp;
  late NexDatabase db;
  late SqliteNoteRepository repo;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('nex_tagging_');
    db = NexDatabase.open(p.join(tmp.path, 'nex.sqlite'));
    repo = SqliteNoteRepository(db);
  });

  tearDown(() {
    db.close();
    tmp.deleteSync(recursive: true);
  });

  Note capture(String content, {required DateTime at}) => repo.insert(
    Note(
      id: newUuidV7(),
      type: NoteType.text,
      content: content,
      createdAt: at,
      updatedAt: at,
      deviceId: 'test-device',
      rev: 1,
      syncState: SyncState.pending,
    ),
  );

  test('tagging does not move a note up the timeline', () {
    final old = capture('the older note', at: DateTime.utc(2026, 1, 1));
    capture('the newer note', at: DateTime.utc(2026, 6, 1));

    final tag = repo.upsertTag(name: 'errands');
    repo.attachTag(noteId: old.id, tagId: tag.id);

    final reloaded = repo.getById(old.id)!;
    expect(reloaded.updatedAt, DateTime.utc(2026, 1, 1));
    expect(
      repo.listTimeline().first.content,
      'the newer note',
      reason: 'tagging the older note put it back on top',
    );

    // The change still has to reach other devices, which is what rev and the
    // pending state are for — leaving those alone would have made a tag a
    // local secret.
    expect(reloaded.rev, greaterThan(old.rev));
    expect(reloaded.syncState, SyncState.pending);
  });

  test('untagging is not an edit either', () {
    final note = capture('a note', at: DateTime.utc(2026, 1, 1));
    final tag = repo.upsertTag(name: 'errands');
    repo.attachTag(noteId: note.id, tagId: tag.id);
    repo.detachTag(noteId: note.id, tagId: tag.id);

    expect(repo.getById(note.id)!.updatedAt, DateTime.utc(2026, 1, 1));
  });

  test('changing what the note says still moves it', () {
    final note = capture('a note', at: DateTime.utc(2026, 1, 1));
    repo.updateContent(note.id, 'a note, rewritten');

    // The other half of the rule, and the reason the timeline sorts this way
    // at all: this is the note you were just working on.
    expect(
      repo.getById(note.id)!.updatedAt.isAfter(DateTime.utc(2026, 1, 1)),
      isTrue,
    );
  });
}
