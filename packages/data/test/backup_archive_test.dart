import 'dart:io';

import 'package:archive/archive.dart';
import 'package:test/test.dart';
import 'package:nex_data/nex_data.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  late String dbPath;
  late String mediaDir;
  late String backupDir;
  late NexDatabase db;
  late SqliteNoteRepository repo;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('nex_backup_');
    dbPath = p.join(tmp.path, 'nex.sqlite');
    mediaDir = p.join(tmp.path, 'media');
    backupDir = p.join(tmp.path, 'backups');
    Directory(mediaDir).createSync(recursive: true);
    db = NexDatabase.open(dbPath);
    repo = SqliteNoteRepository(db);
  });

  tearDown(() {
    try {
      db.close();
    } catch (_) {}
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Note photoNote(String id, String fileName) {
    final now = DateTime.now().toUtc();
    return Note(
      id: id,
      type: NoteType.photo,
      mediaUri: p.join(mediaDir, fileName),
      createdAt: now,
      updatedAt: now,
      deviceId: 'test',
      rev: 1,
      syncState: SyncState.pending,
    );
  }

  test('a restore onto a moved sandbox rewrites media paths', () {
    // The reinstall case: every restore on iOS and most on Android lands in
    // a support directory whose path has changed, and a database row that
    // still points at the old absolute path means a photo that "came back"
    // but cannot be opened.
    File(p.join(mediaDir, 'a.jpg')).writeAsBytesSync([1, 2, 3]);
    repo.insert(photoNote('n1', 'a.jpg'));

    final backup = repo.backup(backupDir, mediaDir: mediaDir);
    db.close();

    // Lose everything, then restore into a *different* media directory, the
    // way a fresh install would have.
    File(dbPath).deleteSync();
    Directory(mediaDir).deleteSync(recursive: true);
    final newMediaDir = p.join(tmp.path, 'support2', 'media');
    Directory(newMediaDir).createSync(recursive: true);

    NexBackupArchive.restore(
      liveDbPath: dbPath,
      mediaDir: newMediaDir,
      backupFile: backup.path,
    );

    final reopened = NexDatabase.open(dbPath);
    final restored = SqliteNoteRepository(reopened).getById('n1')!;
    expect(restored.mediaUri, startsWith(newMediaDir),
        reason: 'the row must point where the file actually landed');
    expect(File(restored.mediaUri!).existsSync(), isTrue,
        reason: 'and the file must be there');
    reopened.close();
  });

  test('a nested row is remapped to its nested file, not a same-named one', () {
    // The case the "nested, then flat" fallback in `_remapMediaUris` was
    // written for, and could not serve. It asked for
    // `p.relative(stored, from: p.dirname(stored))` — which is the definition
    // of `p.basename(stored)`, since the relative path from a file's own
    // directory to that file is its name. So both of its probes were the
    // same string, and a row pointing at `…/media/thumbs/a.jpg` could only
    // ever be matched by a bare `a.jpg`.
    //
    // Two files with the same name, one of them nested, is what makes the
    // difference visible: matching by basename picks the wrong one, silently,
    // and the note comes back showing somebody else's photo.
    final nested = Directory(p.join(mediaDir, 'thumbs'))
      ..createSync(recursive: true);
    File(p.join(nested.path, 'a.jpg')).writeAsBytesSync([9, 9, 9]);
    File(p.join(mediaDir, 'a.jpg')).writeAsBytesSync([1, 1, 1]);
    repo.insert(photoNote('nested', p.join('thumbs', 'a.jpg')));
    repo.insert(photoNote('flat', 'a.jpg'));

    final backup = repo.backup(backupDir, mediaDir: mediaDir);
    db.close();
    File(dbPath).deleteSync();
    Directory(mediaDir).deleteSync(recursive: true);
    final newMediaDir = p.join(tmp.path, 'support2', 'media');
    Directory(newMediaDir).createSync(recursive: true);

    NexBackupArchive.restore(
      liveDbPath: dbPath,
      mediaDir: newMediaDir,
      backupFile: backup.path,
    );

    final reopened = NexDatabase.open(dbPath);
    final repo2 = SqliteNoteRepository(reopened);
    expect(
      repo2.getById('nested')!.mediaUri,
      p.join(newMediaDir, 'thumbs', 'a.jpg'),
    );
    expect(repo2.getById('flat')!.mediaUri, p.join(newMediaDir, 'a.jpg'));
    // And each is the file it was, not the one it shares a name with.
    expect(File(repo2.getById('nested')!.mediaUri!).readAsBytesSync(), [
      9,
      9,
      9,
    ]);
    expect(File(repo2.getById('flat')!.mediaUri!).readAsBytesSync(), [1, 1, 1]);
    reopened.close();
  });

  test('a stale rollback journal is swept by restore, not replayed', () {
    // A -journal left beside the live file is treated by SQLite as hot for
    // whatever file it sits next to; after a swap it would roll *old* pages
    // over the restored database.
    File(p.join(mediaDir, 'a.jpg')).writeAsBytesSync([1]);
    repo.insert(photoNote('n1', 'a.jpg'));
    final backup = repo.backup(backupDir, mediaDir: mediaDir);
    db.close();
    File('$dbPath-journal').writeAsBytesSync([0xAA, 0xBB]);

    NexBackupArchive.restore(
      liveDbPath: dbPath,
      mediaDir: mediaDir,
      backupFile: backup.path,
    );

    expect(File('$dbPath-journal').existsSync(), isFalse);
  });

  test('a backup carries the media, not only the database', () {
    File(p.join(mediaDir, 'a.jpg')).writeAsBytesSync([1, 2, 3]);
    File(p.join(mediaDir, 'clip.m4a')).writeAsBytesSync([4, 5, 6, 7]);
    repo.insert(photoNote('n1', 'a.jpg'));

    final backup = repo.backup(backupDir, mediaDir: mediaDir);
    expect(backup.path, endsWith(NexBackupArchive.extension));
    db.close();

    // Lose everything the way a reinstall does: the database and the files.
    File(dbPath).deleteSync();
    Directory(mediaDir).deleteSync(recursive: true);

    NexBackupArchive.restore(
      liveDbPath: dbPath,
      mediaDir: mediaDir,
      backupFile: backup.path,
    );

    db = NexDatabase.open(dbPath);
    repo = SqliteNoteRepository(db);
    expect(repo.listTimeline().single.id, 'n1');
    // The part that used to come back empty.
    expect(File(p.join(mediaDir, 'a.jpg')).readAsBytesSync(), [1, 2, 3]);
    expect(File(p.join(mediaDir, 'clip.m4a')).readAsBytesSync(), [4, 5, 6, 7]);
  });

  test('media in subdirectories keeps its shape', () {
    final nested = Directory(p.join(mediaDir, 'thumbs'))
      ..createSync(recursive: true);
    File(p.join(nested.path, 'a.jpg')).writeAsBytesSync([9]);
    repo.insert(photoNote('n1', 'thumbs/a.jpg'));

    final backup = repo.backup(backupDir, mediaDir: mediaDir);
    db.close();
    Directory(mediaDir).deleteSync(recursive: true);

    NexBackupArchive.restore(
      liveDbPath: dbPath,
      mediaDir: mediaDir,
      backupFile: backup.path,
    );
    expect(File(p.join(mediaDir, 'thumbs', 'a.jpg')).existsSync(), isTrue);
  });

  test('an old .sqlite backup still restores, and keeps existing media', () {
    // The format before this existed. It never held media, so a restore from
    // one must not take the files that are on the device now with it.
    repo.insert(photoNote('n1', 'a.jpg'));
    final legacy = db.createBackup(backupDir);
    expect(legacy.path, endsWith('.sqlite'));
    db.close();

    File(p.join(mediaDir, 'a.jpg')).writeAsBytesSync([1, 2, 3]);
    File(dbPath).writeAsBytesSync([0, 0, 0]);

    NexBackupArchive.restore(
      liveDbPath: dbPath,
      mediaDir: mediaDir,
      backupFile: legacy.path,
    );

    db = NexDatabase.open(dbPath);
    repo = SqliteNoteRepository(db);
    expect(repo.listTimeline().single.id, 'n1');
    expect(File(p.join(mediaDir, 'a.jpg')).existsSync(), isTrue);
  });

  test('a corrupt archive leaves the live library untouched', () {
    repo.insert(photoNote('n1', 'a.jpg'));
    File(p.join(mediaDir, 'a.jpg')).writeAsBytesSync([1, 2, 3]);
    final backup = repo.backup(backupDir, mediaDir: mediaDir);

    // A zip whose database entry is not a database.
    final bytes = backup.readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);
    final rebuilt = Archive();
    for (final file in archive.files) {
      rebuilt.addFile(
        file.name == 'nex.sqlite'
            ? ArchiveFile('nex.sqlite', 3, [1, 2, 3])
            : file,
      );
    }
    final broken = File(p.join(backupDir, 'broken.nexbak'))
      ..writeAsBytesSync(ZipEncoder().encode(rebuilt));

    expect(
      () => NexBackupArchive.restore(
        liveDbPath: dbPath,
        mediaDir: mediaDir,
        backupFile: broken.path,
      ),
      throwsA(isA<StateError>()),
    );
    // Both halves survived: the notes and the files.
    expect(repo.listTimeline().single.id, 'n1');
    expect(File(p.join(mediaDir, 'a.jpg')).existsSync(), isTrue);
  });

  test('retention prunes both formats together', () {
    for (var i = 0; i < NexDatabase.backupRetention + 3; i++) {
      repo.backup(backupDir, mediaDir: mediaDir);
    }
    final kept = Directory(backupDir).listSync().whereType<File>().length;
    expect(kept, NexDatabase.backupRetention);
  });
}
