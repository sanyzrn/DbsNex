import 'dart:io';

import 'package:nex_data/nex_data.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A restore that fails must leave the library exactly where it was.
///
/// The bug these hold down, found by an independent audit: a restore deleted
/// the live database, renamed the backup's into place, and only then swapped
/// the media — so a failure between the two left the backup's notes installed
/// over newer ones, and a failure after the live media had been deleted lost
/// the photos outright. Worse, the restore reported failure over a library it
/// had already overwritten.
void main() {
  late Directory tmp;
  late String dbPath;
  late String mediaDir;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('nex_restore_tx_');
    dbPath = p.join(tmp.path, 'nex.sqlite');
    mediaDir = p.join(tmp.path, 'media');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// A database at [path] holding one text note, closed again.
  void writeLibrary(String path, String content) {
    final db = NexDatabase.open(path);
    final now = DateTime.now().toUtc();
    SqliteNoteRepository(db).insert(
      Note(
        id: 'n1',
        type: NoteType.text,
        content: content,
        createdAt: now,
        updatedAt: now,
        deviceId: 'test',
        rev: 1,
        syncState: SyncState.pending,
      ),
    );
    db.close();
  }

  String readNote(String path) {
    final db = NexDatabase.open(path);
    try {
      return SqliteNoteRepository(db).getById('n1')!.content!;
    } finally {
      db.close();
    }
  }

  /// The live library, and a staged copy of an older one beside it.
  ({File stagedDb, Directory stagedMedia}) prepare() {
    writeLibrary(dbPath, 'the live edit');
    Directory(mediaDir).createSync();
    File(p.join(mediaDir, 'live.jpg')).writeAsBytesSync([1, 1, 1]);

    final staging = Directory(p.join(tmp.path, 'staging'))..createSync();
    final stagedDb = File(p.join(staging.path, 'nex.sqlite'));
    writeLibrary(stagedDb.path, 'from the backup');
    final stagedMedia = Directory(p.join(staging.path, 'media'))..createSync();
    File(p.join(stagedMedia.path, 'old.jpg')).writeAsBytesSync([2, 2, 2]);
    return (stagedDb: stagedDb, stagedMedia: stagedMedia);
  }

  test('a failure after the database was swapped puts the live one back', () {
    final staged = prepare();
    final transaction = RestoreTransaction.begin(
      liveDbPath: dbPath,
      mediaDir: mediaDir,
    );
    transaction.installDatabase(staged.stagedDb);
    transaction.installMedia(staged.stagedMedia);
    // Whatever went wrong next — the remap, a full disk — the caller rolls
    // back.
    transaction.rollBack();

    expect(readNote(dbPath), 'the live edit');
    expect(File(p.join(mediaDir, 'live.jpg')).existsSync(), isTrue);
    expect(File(p.join(mediaDir, 'old.jpg')).existsSync(), isFalse);
  });

  test('a restore the process died in the middle of is undone on next open', () {
    // No rollBack, no commit: the app was killed. The journal is all that is
    // left to say a restore was under way, and opening the database is the
    // first thing the next launch does.
    final staged = prepare();
    final transaction = RestoreTransaction.begin(
      liveDbPath: dbPath,
      mediaDir: mediaDir,
    );
    transaction.installDatabase(staged.stagedDb);
    transaction.installMedia(staged.stagedMedia);

    expect(readNote(dbPath), 'the live edit');
    expect(File(p.join(mediaDir, 'live.jpg')).existsSync(), isTrue);
    expect(File('$dbPath.restore-journal').existsSync(), isFalse);
  });

  test('dying between the two swaps is undone too', () {
    // The exact window the audit named: the database already replaced, the
    // media not yet.
    final staged = prepare();
    RestoreTransaction.begin(
      liveDbPath: dbPath,
      mediaDir: mediaDir,
    ).installDatabase(staged.stagedDb);

    expect(readNote(dbPath), 'the live edit');
    expect(File(p.join(mediaDir, 'live.jpg')).existsSync(), isTrue);
  });

  test('a committed restore keeps the backup and leaves nothing aside', () {
    final staged = prepare();
    RestoreTransaction.begin(liveDbPath: dbPath, mediaDir: mediaDir)
      ..installDatabase(staged.stagedDb)
      ..installMedia(staged.stagedMedia)
      ..commit();

    expect(readNote(dbPath), 'from the backup');
    expect(File(p.join(mediaDir, 'old.jpg')).existsSync(), isTrue);
    expect(File('$dbPath.restore-journal').existsSync(), isFalse);
    expect(Directory('$dbPath.rollback.d').existsSync(), isFalse);
    expect(Directory('$mediaDir.rollback').existsSync(), isFalse);
  });

  test('a legacy .sqlite restore is a transaction as well', () {
    writeLibrary(dbPath, 'the live edit');
    final backup = p.join(tmp.path, 'old.sqlite');
    writeLibrary(backup, 'from the backup');

    NexDatabase.restoreFromBackup(liveDbPath: dbPath, backupFile: backup);

    expect(readNote(dbPath), 'from the backup');
    expect(Directory('$dbPath.rollback.d').existsSync(), isFalse);
  });

  test('opening a library with nothing to recover changes nothing', () {
    writeLibrary(dbPath, 'the live edit');
    expect(readNote(dbPath), 'the live edit');
  });
}
