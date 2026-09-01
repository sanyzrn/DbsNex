import 'dart:io';

import 'package:nex_data/nex_data.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late NexDatabase db;
  late SqliteNoteRepository repo;
  late LibraryMaintenance maintenance;
  late Directory tmp;
  late String mediaDir;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('nex_purge_media_');
    mediaDir = p.join(tmp.path, 'media');
    Directory(mediaDir).createSync(recursive: true);
    db = NexDatabase.open(p.join(tmp.path, 'nex.sqlite'));
    repo = SqliteNoteRepository(db, localDeviceId: 'test');
    maintenance = LibraryMaintenance(repo, mediaRoot: mediaDir);
  });

  tearDown(() {
    db.close();
    tmp.deleteSync(recursive: true);
  });

  Note insertPhotoWithFile(String name, {List<int> bytes = const [1, 2, 3]}) {
    final file = File(p.join(mediaDir, name))..writeAsBytesSync(bytes);
    final now = DateTime.now().toUtc();
    return repo.insert(
      Note(
        id: newUuidV7(),
        type: NoteType.photo,
        mediaUri: file.path,
        mediaHash: 'hash-$name',
        createdAt: now,
        updatedAt: now,
        deviceId: 'test',
        rev: 1,
        syncState: SyncState.pending,
      ),
    );
  }

  void softDelete(String id) => repo.softDelete(id);

  test('purgeNote deletes the attachment file, not just the row', () {
    final note = insertPhotoWithFile('a.jpg');
    softDelete(note.id);
    final file = File(note.mediaUri!);
    expect(file.existsSync(), isTrue);

    maintenance.purgeNote(note.id);

    expect(repo.db.select('SELECT id FROM notes WHERE id = ?', [
      note.id,
    ]), isEmpty);
    expect(file.existsSync(), isFalse, reason: 'delete forever means the file');
  });

  test('emptying the trash removes every purged attachment', () {
    final a = insertPhotoWithFile('a.jpg');
    final b = insertPhotoWithFile('b.jpg');
    softDelete(a.id);
    softDelete(b.id);

    maintenance.purgeAllDeleted();

    expect(File(a.mediaUri!).existsSync(), isFalse);
    expect(File(b.mediaUri!).existsSync(), isFalse);
  });

  test('a live note keeps its file when the trash is emptied', () {
    final live = insertPhotoWithFile('live.jpg');
    final trashed = insertPhotoWithFile('trashed.jpg');
    softDelete(trashed.id);

    maintenance.purgeAllDeleted();

    expect(File(live.mediaUri!).existsSync(), isTrue);
    expect(File(trashed.mediaUri!).existsSync(), isFalse);
  });

  test('a media path outside the media root is never deleted', () async {
    // A corrupted or hand-edited row must fail to delete rather than
    // succeed: the worst case of a bug here is destroying a file that
    // belongs to something else entirely.
    final outside = File(p.join(tmp.path, 'elsewhere.jpg'))
      ..writeAsBytesSync(const [9, 9, 9]);
    final now = DateTime.now().toUtc();
    final note = repo.insert(
      Note(
        id: newUuidV7(),
        type: NoteType.photo,
        mediaUri: outside.path,
        mediaHash: 'hash-x',
        createdAt: now,
        updatedAt: now,
        deviceId: 'test',
        rev: 1,
        syncState: SyncState.pending,
      ),
    );
    softDelete(note.id);

    maintenance.purgeNote(note.id);

    expect(outside.existsSync(), isTrue);
  });

  test('sweepOrphanMedia removes unreferenced old files and keeps the rest', () {
    final kept = insertPhotoWithFile('kept.jpg');
    // Old enough to be sweepable, and referenced by no note.
    final stray = File(p.join(mediaDir, 'stray.jpg'))
      ..writeAsBytesSync(const [4, 4, 4]);
    // Set old, because a capture mid-flight writes the file before its row.
    stray.setLastModifiedSync(DateTime.now().subtract(const Duration(days: 2)));
    // Fresh and unreferenced: left alone, it may belong to a capture in
    // progress.
    final fresh = File(p.join(mediaDir, 'fresh.jpg'))
      ..writeAsBytesSync(const [5, 5, 5]);

    final removed = maintenance.sweepOrphanMedia();

    expect(removed, 1);
    expect(stray.existsSync(), isFalse);
    expect(fresh.existsSync(), isTrue);
    expect(File(kept.mediaUri!).existsSync(), isTrue);
  });

  test('sweepOrphanMedia never looks inside a subdirectory', () {
    // The regression this exists for: the app keeps the user's profile
    // picture in `profile/` under the media root. No note references it, it
    // is older than an hour, and a recursive sweep deleted it — silently, a
    // day after the release that gave the sweep a caller.
    //
    // Every note's media is written flat into the root, so anything in a
    // subdirectory belongs to something that is not a note.
    final profile = Directory(p.join(mediaDir, 'profile'))
      ..createSync(recursive: true);
    final avatar = File(p.join(profile.path, 'avatar.jpg'))
      ..writeAsBytesSync(const [7, 7, 7])
      ..setLastModifiedSync(DateTime.now().subtract(const Duration(days: 30)));

    // A stray beside it, so the sweep is proved to still be doing its job.
    final stray = File(p.join(mediaDir, 'stray.jpg'))
      ..writeAsBytesSync(const [8, 8, 8])
      ..setLastModifiedSync(DateTime.now().subtract(const Duration(days: 2)));

    final removed = maintenance.sweepOrphanMedia();

    expect(removed, 1);
    expect(stray.existsSync(), isFalse);
    expect(avatar.existsSync(), isTrue, reason: 'the profile picture is not note media');
  });

  test('sweepOrphanMedia leaves trashed notes\u2019 files alone', () {
    final trashed = insertPhotoWithFile('trashed.jpg');
    softDelete(trashed.id);

    final removed = maintenance.sweepOrphanMedia();

    expect(removed, 0);
    expect(File(trashed.mediaUri!).existsSync(), isTrue);
  });
}
