import 'dart:io';

import 'package:archive/archive.dart';
import 'package:nex_data/nex_data.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  for (final zipped in [false, true]) {
    test(
      'newer ${zipped ? 'archive' : 'SQLite'} is rejected before live files move',
      () {
        final tmp = Directory.systemTemp.createTempSync('nex_restore_version_');
        addTearDown(() => tmp.deleteSync(recursive: true));
        final live = '${tmp.path}/live.sqlite';
        final media = Directory('${tmp.path}/media')..createSync();
        File('${media.path}/keep.txt').writeAsStringSync('original media');
        final db = NexDatabase.open(live);
        db.db.execute("CREATE TABLE keep(value TEXT)");
        db.db.execute("INSERT INTO keep(value) VALUES ('original')");
        db.close();
        final before = File(live).readAsBytesSync();
        final future = '${tmp.path}/future.sqlite';
        final probe = sqlite3.open(future);
        probe.execute('CREATE TABLE future_only(value TEXT)');
        probe.execute('PRAGMA user_version = ${NexDatabase.schemaVersion + 1}');
        probe.close();
        var backup = future;
        if (zipped) {
          final bytes = File(future).readAsBytesSync();
          final archive = Archive()
            ..addFile(ArchiveFile('nex.sqlite', bytes.length, bytes));
          backup = '${tmp.path}/future.nexbak';
          File(backup).writeAsBytesSync(ZipEncoder().encode(archive));
        }
        expect(
          () => NexBackupArchive.restore(
            liveDbPath: live,
            mediaDir: media.path,
            backupFile: backup,
          ),
          throwsA(isA<NewerLibraryException>()),
        );
        expect(File(live).readAsBytesSync(), before);
        expect(
          File('${media.path}/keep.txt').readAsStringSync(),
          'original media',
        );
        expect(Directory('$live.rollback.d').existsSync(), isFalse);
        final reopened = NexDatabase.open(live);
        expect(
          reopened.db.select("SELECT value FROM keep").single['value'],
          'original',
        );
        reopened.close();
      },
    );
  }
}
