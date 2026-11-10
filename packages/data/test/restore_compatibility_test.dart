import 'dart:io';

import 'package:archive/archive.dart';
import 'package:nex_data/nex_data.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  setUp(
    () => root = Directory.systemTemp.createTempSync('nex-restore-matrix-'),
  );
  tearDown(() => root.deleteSync(recursive: true));

  void currentLibrary(String path, String text) {
    final db = NexDatabase.open(path);
    try {
      final now = DateTime.utc(2026);
      SqliteNoteRepository(db).insert(
        Note(
          id: 'note',
          type: NoteType.text,
          content: text,
          createdAt: now,
          updatedAt: now,
          deviceId: 'test',
          rev: 1,
          syncState: SyncState.pending,
        ),
      );
    } finally {
      db.close();
    }
  }

  void legacyLibrary(String path, int stamp) {
    final db = sqlite3.open(path);
    try {
      db.execute('''
CREATE TABLE notes (
  id TEXT PRIMARY KEY NOT NULL,
  type TEXT NOT NULL CHECK (type IN ('text', 'voice', 'photo', 'file')),
  content TEXT, media_uri TEXT, media_hash TEXT, duration_ms INTEGER,
  created_at TEXT NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT,
  device_id TEXT NOT NULL, rev INTEGER NOT NULL,
  sync_state TEXT NOT NULL CHECK (sync_state IN ('pending', 'synced', 'conflict'))
);
INSERT INTO notes VALUES ('note', 'text', 'یادداشت قدیمی', NULL, NULL, NULL,
  '2025-01-01T00:00:00Z', '2025-01-01T00:00:00Z', NULL, 'old-phone', 1, 'pending');
PRAGMA user_version = $stamp;
''');
    } finally {
      db.close();
    }
  }

  File archiveOf(String database, {List<ArchiveFile> entries = const []}) {
    final bytes = File(database).readAsBytesSync();
    final archive = Archive()
      ..addFile(ArchiveFile('nex.sqlite', bytes.length, bytes));
    for (final entry in entries) {
      archive.addFile(entry);
    }
    return File('${root.path}/selected.nexbak')
      ..writeAsBytesSync(ZipEncoder().encode(archive));
  }

  for (final schema in [0, 1, NexDatabase.schemaVersion]) {
    for (final zip in [false, true]) {
      test(
        'schema $schema, zip=$zip: restore upgrades a copy and can reopen',
        () {
          final live = '${root.path}/live.sqlite';
          final source = '${root.path}/source.sqlite';
          currentLibrary(live, 'keep until restore succeeds');
          if (schema == NexDatabase.schemaVersion) {
            currentLibrary(source, 'یادداشت قدیمی');
          } else {
            legacyLibrary(source, schema);
          }
          final backup = zip ? archiveOf(source) : File(source);
          final before = backup.readAsBytesSync();
          NexBackupArchive.validate(backup.path);
          NexBackupArchive.restore(
            liveDbPath: live,
            mediaDir: '${root.path}/media',
            backupFile: backup.path,
          );
          expect(
            backup.readAsBytesSync(),
            before,
            reason: 'migrations must never alter the selected backup',
          );
          final reopened = NexDatabase.open(live);
          try {
            expect(
              SqliteNoteRepository(reopened).getById('note')!.content,
              'یادداشت قدیمی',
            );
            expect(
              reopened.db.select('PRAGMA user_version').single.values.single,
              NexDatabase.schemaVersion,
            );
          } finally {
            reopened.close();
          }
        },
      );
    }
  }

  for (final invalid in [
    'foreign database',
    'unknown note type',
    'invalid date',
    'failed migration',
  ]) {
    for (final zip in [false, true]) {
      test('$invalid, zip=$zip: leaves the current library intact', () {
        final live = '${root.path}/live.sqlite';
        final source = '${root.path}/source.sqlite';
        currentLibrary(live, 'original');
        if (invalid == 'foreign database') {
          final foreign = sqlite3.open(source);
          foreign.execute('CREATE TABLE unrelated(value TEXT)');
          foreign.close();
        } else {
          if (invalid == 'failed migration') {
            legacyLibrary(source, 0);
          } else {
            currentLibrary(source, 'backup');
          }
          final raw = sqlite3.open(source);
          try {
            switch (invalid) {
              case 'unknown note type':
                raw.execute("UPDATE notes SET type = 'future-type'");
              case 'invalid date':
                raw.execute("UPDATE notes SET updated_at = 'not-a-date'");
              case 'failed migration':
                raw.execute('CREATE TABLE tags(wrong TEXT)');
            }
          } finally {
            raw.close();
          }
        }
        final backup = zip ? archiveOf(source) : File(source);
        final before = File(live).readAsBytesSync();
        final failure = isA<StateError>();
        expect(() => NexBackupArchive.validate(backup.path), throwsA(failure));
        expect(
          () => NexBackupArchive.restore(
            liveDbPath: live,
            mediaDir: '${root.path}/media',
            backupFile: backup.path,
          ),
          throwsA(failure),
        );
        expect(File(live).readAsBytesSync(), before);
        expect(File('$live.restore-journal').existsSync(), isFalse);
        final reopened = NexDatabase.open(live);
        expect(
          SqliteNoteRepository(reopened).getById('note')!.content,
          'original',
        );
        reopened.close();
      });
    }
  }

  test('normalized media aliases are rejected before installation', () {
    final source = '${root.path}/source.sqlite';
    currentLibrary(source, 'backup');
    final archive = archiveOf(
      source,
      entries: [
        ArchiveFile('media/a.txt', 1, [1]),
        ArchiveFile('media/./a.txt', 1, [2]),
      ],
    );
    expect(
      () => NexBackupArchive.validate(archive.path),
      throwsFormatException,
    );
  });

  test(
    'legacy SQLite backup includes committed WAL data with an open reader',
    () {
      final path = '${root.path}/wal.sqlite';
      currentLibrary(path, 'before');
      final writer = NexDatabase.open(path);
      final reader = sqlite3.open(path);
      try {
        writer.db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
        reader.execute('BEGIN');
        expect(
          reader.select('SELECT content FROM notes').single['content'],
          'before',
        );
        writer.db.execute("UPDATE notes SET content = 'committed in WAL'");
        writer.db.execute('PRAGMA busy_timeout = 20');
        final backup = writer.createBackup('${root.path}/snapshots');
        final saved = sqlite3.open(backup.path, mode: OpenMode.readOnly);
        try {
          expect(
            saved.select('SELECT content FROM notes').single['content'],
            'committed in WAL',
          );
        } finally {
          saved.close();
        }
      } finally {
        reader.close();
        writer.close();
      }
    },
  );

  test(
    'a library renamed to zip is recognized independently of its suffix',
    () async {
      final source = '${root.path}/source.sqlite';
      currentLibrary(source, 'backup');
      final renamed = archiveOf(source).copySync('${root.path}/picked.zip');
      expect(await NexBackupArchive.detect(renamed.path), isTrue);
      final exported = Archive()
        ..addFile(ArchiveFile.string('notes.json', '[]'));
      final notes = File('${root.path}/notes.zip')
        ..writeAsBytesSync(ZipEncoder().encode(exported));
      expect(await NexBackupArchive.detect(notes.path), isFalse);
    },
  );
}
