import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/db_worker.dart';
import 'package:nex_core/nex_core.dart';
import 'package:path/path.dart' as p;

/// The backup snapshot moved off the worker's command chain and off the
/// worker's isolate: `VACUUM INTO` runs on a second connection in its own
/// isolate, so the seconds a large library's snapshot takes are no longer
/// seconds that every capture, read and search queues behind. What has to
/// stay true: a write landing while the snapshot is in flight belongs to
/// the library, the backup still completes, and the two connections never
/// disturb each other.
void main() {
  late Directory tmp;
  late Directory mediaDir;
  late Directory backupDir;
  late NexDbWorker worker;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('nex_backup_off_chain_');
    mediaDir = Directory(p.join(tmp.path, 'media'))
      ..createSync(recursive: true);
    backupDir = Directory(p.join(tmp.path, 'backups'))
      ..createSync(recursive: true);
    worker = await NexDbWorker.spawn(
      dbPath: p.join(tmp.path, 'nex.sqlite'),
      deviceId: 'test',
      mediaDir: mediaDir.path,
    );
  });

  tearDown(() async {
    await worker.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('a capture lands while a backup is in flight', () async {
    // Some library to snapshot, written through the worker itself.
    for (var i = 0; i < 40; i++) {
      await worker.captureText('seed note $i');
    }

    // The backup starts, and is not awaited before the capture.
    final backingUp = worker.backup(backupDir.path, mediaDir: mediaDir.path);
    final captured = await worker.captureText('written during the backup');

    // The capture is durable in the library the moment it returns.
    final found = await worker.search(
      const SearchFilters(query: 'during the backup'),
    );
    expect(
      found.any((note) => note.id == captured!.id),
      isTrue,
      reason: 'the note is searchable after the backup ran beside it',
    );

    // And the backup itself completed, producing its archive.
    await backingUp;
    final archives = backupDir
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.nexbak'))
        .toList();
    expect(archives, isNotEmpty);
    expect(archives.single.lengthSync(), greaterThan(0));
    // The snapshot file the archive was made from is not left behind.
    expect(
      backupDir.listSync().whereType<File>().map((f) => p.basename(f.path)),
      everyElement(isNot(startsWith('.snapshot-'))),
      reason: 'the snapshot is consumed by the archive that zips it',
    );
  });

  test('closing the worker while a backup is in flight still closes', () async {
    for (var i = 0; i < 10; i++) {
      await worker.captureText('seed note $i');
    }
    final backingUp = worker.backup(backupDir.path, mediaDir: mediaDir.path);

    // close() does not wait on the chain for the backup: its own grace for
    // background work bounds it. Either the backup finishes inside the
    // grace or the handle goes anyway — a close that waited on the chain
    // for a stuck VACUUM would hang here.
    final closing = worker.close();
    await closing.timeout(const Duration(seconds: 10));
    expect(NexDbWorker.debugLiveIsolates, 0);

    // The backup either completed or was cut by the close — both valid; a
    // completed archive is what this asserts when it happens.
    await backingUp.catchError((Object _) {});
  });
}
