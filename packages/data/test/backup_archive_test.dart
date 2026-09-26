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

  for (final unsafe in [
    r'media/..\escaped.txt',
    'media/../../escaped.txt',
    'media/C:/escaped.txt',
  ]) {
    test(
      'restore rejects unsafe archive path $unsafe before replacing the library',
      () {
        repo.insert(photoNote('keep', 'original.jpg'));
        File(p.join(mediaDir, 'original.jpg')).writeAsBytesSync([1, 2, 3]);
        final valid = repo.backup(backupDir, mediaDir: mediaDir);
        final archive = ZipDecoder().decodeBytes(valid.readAsBytesSync());
        archive.addFile(ArchiveFile(unsafe, 3, [1, 2, 3]));
        final malicious = File(p.join(tmp.path, 'unsafe.nexbak'))
          ..writeAsBytesSync(ZipEncoder().encode(archive));
        expect(
          () => NexBackupArchive.restore(
            liveDbPath: dbPath,
            mediaDir: mediaDir,
            backupFile: malicious.path,
          ),
          throwsFormatException,
        );
        expect(repo.getById('keep'), isNotNull);
        expect(File(p.join(tmp.path, 'escaped.txt')).existsSync(), isFalse);
      },
    );
  }

  test(
    'compression reads a consistent snapshot while the live library changes',
    () {
      repo.insert(photoNote('before', 'a.jpg'));
      File(p.join(mediaDir, 'a.jpg')).writeAsBytesSync([4, 5, 6]);
      final snapshot = repo.backupSnapshot(backupDir);
      repo.insert(photoNote('after', 'b.jpg'));
      final backup = NexBackupArchive.createFromSnapshot(
        snapshotPath: snapshot.path,
        mediaDir: mediaDir,
        backupDir: backupDir,
      );
      final restoredPath = p.join(tmp.path, 'restored.sqlite');
      NexBackupArchive.restore(
        liveDbPath: restoredPath,
        mediaDir: p.join(tmp.path, 'restored-media'),
        backupFile: backup.path,
      );
      final restored = NexDatabase.open(restoredPath);
      try {
        final copy = SqliteNoteRepository(restored);
        expect(copy.getById('before'), isNotNull);
        expect(copy.getById('after'), isNull);
        expect(repo.getById('after'), isNotNull);
      } finally {
        restored.close();
      }
    },
  );

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
    expect(
      restored.mediaUri,
      startsWith(newMediaDir),
      reason: 'the row must point where the file actually landed',
    );
    expect(
      File(restored.mediaUri!).existsSync(),
      isTrue,
      reason: 'and the file must be there',
    );
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

  test('a media CRC failure leaves the live library untouched', () {
    final marker = [241, 232, 223, 214, 205, 196, 187, 178];
    File(p.join(mediaDir, 'a.jpg')).writeAsBytesSync(marker);
    repo.insert(photoNote('n', 'a.jpg'));
    final backup = repo.backup(backupDir, mediaDir: mediaDir);
    final original = ZipDecoder().decodeBytes(backup.readAsBytesSync());
    final archive = Archive();
    for (final entry in original.files) {
      archive.addFile(
        entry.name == 'media/a.jpg'
            ? (ArchiveFile('media/a.jpg', marker.length, marker)
                ..compression = CompressionType.none)
            : entry,
      );
    }
    final bytes = ZipEncoder().encode(archive);
    var offset = -1;
    for (var i = 0; i <= bytes.length - marker.length; i++) {
      if (List.generate(
        marker.length,
        (j) => bytes[i + j] == marker[j],
      ).every((v) => v)) {
        offset = i;
        break;
      }
    }
    expect(offset, greaterThanOrEqualTo(0));
    bytes[offset] ^= 1;
    final corrupt = File(p.join(tmp.path, 'crc.nexbak'))
      ..writeAsBytesSync(bytes);
    expect(
      () => NexBackupArchive.restore(
        liveDbPath: dbPath,
        mediaDir: mediaDir,
        backupFile: corrupt.path,
      ),
      throwsFormatException,
    );
    expect(repo.getById('n'), isNotNull);
    expect(File(p.join(mediaDir, 'a.jpg')).readAsBytesSync(), marker);
  });

  test('retention prunes both formats together', () {
    for (var i = 0; i < NexDatabase.backupRetention + 3; i++) {
      repo.backup(backupDir, mediaDir: mediaDir);
    }
    final kept = Directory(backupDir).listSync().whereType<File>().length;
    expect(kept, NexDatabase.backupRetention);
  });

  test(
    'local backups reuse blobs; shared backup restores without the blob store',
    () {
      File(
        p.join(mediaDir, 'a.jpg'),
      ).writeAsBytesSync(List.generate(200000, (i) => i % 251));
      repo.insert(photoNote('n', 'a.jpg'));
      final snapshot = repo.backupSnapshot(backupDir);
      final first = NexBackupArchive.createFromSnapshot(
        snapshotPath: snapshot.path,
        mediaDir: mediaDir,
        backupDir: backupDir,
        compact: true,
      );
      NexBackupArchive.createFromSnapshot(
        snapshotPath: snapshot.path,
        mediaDir: mediaDir,
        backupDir: backupDir,
        compact: true,
      );
      expect(
        Directory(p.join(backupDir, '.media')).listSync().whereType<File>(),
        hasLength(1),
      );
      final portable = NexBackupArchive.portable(
        first.path,
        p.join(tmp.path, 'portable.nexbak'),
      );
      Directory(backupDir).deleteSync(recursive: true);
      final newDb = p.join(tmp.path, 'new.sqlite');
      final newMedia = p.join(tmp.path, 'new-media');
      NexBackupArchive.restore(
        liveDbPath: newDb,
        mediaDir: newMedia,
        backupFile: portable,
      );
      final restored = NexDatabase.open(newDb);
      try {
        final note = SqliteNoteRepository(restored).getById('n')!;
        expect(note.mediaUri, p.join(newMedia, 'a.jpg'));
        expect(
          File(note.mediaUri!).readAsBytesSync(),
          File(p.join(mediaDir, 'a.jpg')).readAsBytesSync(),
        );
      } finally {
        restored.close();
      }
    },
  );

  test(
    'missing and corrupt local blobs fail before replacing the live database',
    () {
      File(p.join(mediaDir, 'a.jpg')).writeAsBytesSync([1, 2, 3]);
      repo.insert(photoNote('n', 'a.jpg'));
      final snapshot = repo.backupSnapshot(backupDir);
      final backup = NexBackupArchive.createFromSnapshot(
        snapshotPath: snapshot.path,
        mediaDir: mediaDir,
        backupDir: backupDir,
        compact: true,
      );
      final blob = Directory(
        p.join(backupDir, '.media'),
      ).listSync().whereType<File>().single;
      blob.writeAsBytesSync([9, 8, 7]);
      expect(
        () => NexBackupArchive.restore(
          liveDbPath: dbPath,
          mediaDir: mediaDir,
          backupFile: backup.path,
        ),
        throwsFormatException,
      );
      expect(repo.getById('n'), isNotNull);
      blob.deleteSync();
      expect(
        () => NexBackupArchive.restore(
          liveDbPath: dbPath,
          mediaDir: mediaDir,
          backupFile: backup.path,
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(File(p.join(mediaDir, 'a.jpg')).readAsBytesSync(), [1, 2, 3]);
    },
  );

  test('missing referenced media refuses to publish a new backup', () {
    repo.insert(photoNote('missing', 'missing.jpg'));
    expect(() => repo.backup(backupDir, mediaDir: mediaDir), throwsStateError);
    expect(
      Directory(backupDir).listSync().where((e) => e.path.endsWith('.nexbak')),
      isEmpty,
    );
  });

  test('a pinned restore source protects blobs during retention cleanup', () {
    File(p.join(mediaDir, 'a.jpg')).writeAsBytesSync([1, 2, 3]);
    repo.insert(photoNote('n', 'a.jpg'));
    final snapshot = repo.backupSnapshot(backupDir);
    final backup = NexBackupArchive.createFromSnapshot(
      snapshotPath: snapshot.path,
      mediaDir: mediaDir,
      backupDir: backupDir,
      compact: true,
    );
    final pin = backup.copySync(p.join(backupDir, '.restore-source-test'));
    backup.deleteSync();
    final blob = Directory(
      p.join(backupDir, '.media'),
    ).listSync().whereType<File>().single;
    blob.setLastModifiedSync(DateTime.now().subtract(const Duration(days: 8)));
    NexBackupArchive.collectUnusedMedia(backupDir);
    expect(blob.existsSync(), isTrue);
    pin.deleteSync();
    NexBackupArchive.collectUnusedMedia(backupDir);
    expect(blob.existsSync(), isFalse);
  });

  test(
    'a changed media generation cannot be published with the old snapshot',
    () {
      final file = File(p.join(mediaDir, 'a.jpg'))..writeAsBytesSync([1, 2, 3]);
      repo.insert(photoNote('n', 'a.jpg'));
      db.db.execute('UPDATE notes SET media_hash = ? WHERE id = ?', [
        '039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81',
        'n',
      ]);
      final snapshot = repo.backupSnapshot(backupDir);
      file.writeAsBytesSync([4, 5, 6]);
      expect(
        () => NexBackupArchive.createFromSnapshot(
          snapshotPath: snapshot.path,
          mediaDir: mediaDir,
          backupDir: backupDir,
          compact: true,
        ),
        throwsStateError,
      );
      expect(
        Directory(
          backupDir,
        ).listSync().where((f) => f.path.endsWith('.nexbak')),
        isEmpty,
      );
    },
  );

  test('an incomplete archive rolls back both the database and media', () {
    File(p.join(mediaDir, 'a.jpg')).writeAsBytesSync([1, 2, 3]);
    File(p.join(mediaDir, 'b.jpg')).writeAsBytesSync([4, 5, 6]);
    repo.insert(photoNote('n', 'a.jpg'));
    final backup = repo.backup(backupDir, mediaDir: mediaDir);
    final archive = ZipDecoder().decodeBytes(backup.readAsBytesSync());
    final incomplete = Archive();
    for (final entry in archive.files) {
      if (entry.name != 'media/a.jpg') incomplete.addFile(entry);
    }
    final broken = File(p.join(tmp.path, 'incomplete.nexbak'))
      ..writeAsBytesSync(ZipEncoder().encode(incomplete));
    db.close();
    expect(
      () => NexBackupArchive.restore(
        liveDbPath: dbPath,
        mediaDir: mediaDir,
        backupFile: broken.path,
      ),
      throwsFormatException,
    );
    db = NexDatabase.open(dbPath);
    repo = SqliteNoteRepository(db);
    expect(repo.getById('n'), isNotNull);
    expect(File(p.join(mediaDir, 'a.jpg')).readAsBytesSync(), [1, 2, 3]);
  });
}
