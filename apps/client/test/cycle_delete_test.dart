import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nex_data/nex_data.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'support/nex_harness.dart';

/// "Deleted from this phone" has to hold for the backups on it too (SEC-10).
/// The library backups are not encrypted, and the ones made before Cycle was
/// deleted still held every period: a reviewer recovered them without a key.
void main() {
  test('deleting Cycle replaces the backups that still held it', () async {
    final harness = await NexTestHarness.create(
      name: 'nex_cycle_delete_',
      preferences: {'cycle.set_up': true},
    );
    try {
      await harness.services.captureText('a note that must survive');
      await harness.services.cycleStartPeriod(DateTime(2026, 9, 1));
      await harness.db.backup(harness.backupDir, mediaDir: harness.mediaDir);
      List<File> backups() => Directory(harness.backupDir)
          .listSync()
          .whereType<File>()
          .where((f) => NexBackupArchive.isBackupFile(f.path))
          .toList();
      final before = backups().single;

      await harness.services.cycleDeleteAll();

      final after = backups();
      expect(after, hasLength(1));
      expect(after.single.path, isNot(before.path));

      // What the backup that is left would restore: the note, no Cycle.
      final check = p.join(harness.root.path, 'check');
      Directory(p.join(check, 'media')).createSync(recursive: true);
      final restored = p.join(check, 'nex.sqlite');
      NexBackupArchive.restore(
        liveDbPath: restored,
        mediaDir: p.join(check, 'media'),
        backupFile: after.single.path,
      );
      final db = sqlite3.open(restored);
      try {
        expect(db.select('SELECT * FROM cycle_periods'), isEmpty);
        expect(
          db.select("SELECT * FROM notes WHERE content LIKE '%must survive%'"),
          hasLength(1),
        );
      } finally {
        db.dispose();
      }
    } finally {
      await harness.dispose();
    }
  });
}
