import 'dart:io';

import 'package:nex_data/nex_data.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The backup snapshot taken from a second connection (`VACUUM INTO` on the
/// library's own file, from a separate isolate) must be the snapshot the
/// live handle would have taken — and must not disturb, or be disturbed by,
/// the writes that continue on the first connection.
void main() {
  late Directory tmp;
  late NexDatabase db;
  late SqliteNoteRepository repo;
  late Directory backups;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('nex_snapshot_aside_');
    db = NexDatabase.open(p.join(tmp.path, 'nex.sqlite'));
    repo = SqliteNoteRepository(db, localDeviceId: 'd');
    backups = Directory(p.join(tmp.path, 'backups'))
      ..createSync(recursive: true);
  });

  tearDown(() {
    db.close();
    tmp.deleteSync(recursive: true);
  });

  Note insert(String content) {
    final now = DateTime.now().toUtc();
    return repo.insert(
      Note(
        id: newUuidV7(),
        type: NoteType.text,
        content: content,
        createdAt: now,
        updatedAt: now,
        deviceId: 'test',
        rev: 1,
        syncState: SyncState.pending,
      ),
    );
  }

  test('the side snapshot equals the live snapshot', () {
    insert('one');
    insert('two');

    final aside = NexBackupArchive.snapshotDatabaseFromPath(
      dbPath: db.path,
      backupDir: backups.path,
    );
    final live = NexBackupArchive.snapshotDatabase(
      database: db,
      backupDir: backups.path,
    );

    final sideTable = NexDatabase.open(aside.path);
    final liveTable = NexDatabase.open(live.path);
    addTearDown(sideTable.close);
    addTearDown(liveTable.close);
    int count(NexDatabase db) =>
        db.db.select('SELECT COUNT(*) AS n FROM notes').first['n'] as int;
    expect(count(sideTable), count(liveTable));
    expect(count(sideTable), 2);
    expect(
      sideTable.db.select("SELECT value FROM nex_meta WHERE key = 'schema'"),
      isEmpty,
    );
    // The side snapshot is a complete library: its schema version says so.
    expect(
      sideTable.db.select('PRAGMA user_version').first.values.first as int,
      NexDatabase.schemaVersion,
    );
  });

  test('writes after the snapshot are not in it, and it still opens', () {
    insert('before the snapshot');
    final aside = NexBackupArchive.snapshotDatabaseFromPath(
      dbPath: db.path,
      backupDir: backups.path,
    );
    insert('after the snapshot');

    final sideTable = NexDatabase.open(aside.path);
    addTearDown(sideTable.close);
    final contents = sideTable.db
        .select('SELECT content FROM notes ORDER BY created_at')
        .map((row) => row['content']! as String)
        .toList();
    expect(contents, ['before the snapshot']);
    // And the live library carries on unaffected.
    expect(repo.search(const SearchFilters(query: 'after')), hasLength(1));
  });

  test('an in-memory library refuses the side snapshot', () {
    final memory = NexDatabase.openInMemory();
    addTearDown(memory.close);
    expect(
      () => NexBackupArchive.snapshotDatabaseFromPath(
        dbPath: ':memory:',
        backupDir: backups.path,
      ),
      throwsStateError,
    );
  });
}
