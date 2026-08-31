import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nex_client/platform/backup_policy.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/nex_services.dart';

import 'support/in_process_db.dart';

/// The orphaned-media sweep, as the app actually calls it.
///
/// `LibraryMaintenance.sweepOrphanMedia` has its own tests in packages/data
/// for what it deletes. This is about the part that was missing: it had no
/// caller at all, so it swept nothing however well it worked. What is covered
/// here is the wiring and the throttle — that it runs, that it runs through
/// the worker port, and that it does not run again the same day.
void main() {
  late Directory tmp;
  late NexServices services;
  late NexPreferences preferences;
  late String mediaDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('nex_media_sweep_');
    final dbPath = p.join(tmp.path, 'nex.sqlite');
    mediaDir = p.join(tmp.path, 'media');
    Directory(mediaDir).createSync(recursive: true);
    Directory(p.join(tmp.path, 'backups')).createSync(recursive: true);
    preferences = await NexPreferences.load();
    services = NexServices.forTest(
      worker: InProcessDb(dbPath: dbPath, deviceId: 'test'),
      deviceId: 'test',
      preferences: preferences,
      backupPolicy: BackupPolicy(await SharedPreferences.getInstance()),
      dbPath: dbPath,
      mediaDir: mediaDir,
      backupDir: p.join(tmp.path, 'backups'),
    );
  });

  tearDown(() async {
    await services.dispose();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// A file nothing points at, old enough to be past the capture window.
  File orphan(String name) {
    final file = File(p.join(mediaDir, name))
      ..writeAsBytesSync(const [1, 2, 3]);
    file.setLastModifiedSync(
      DateTime.now().subtract(const Duration(hours: 3)),
    );
    return file;
  }

  test('sweeps what nothing points at, then not again the same day', () async {
    final stray = orphan('left-over.jpg');

    expect(await services.sweepOrphanMediaIfDue(), 1);
    expect(stray.existsSync(), isFalse);

    // Second launch of the day: the walk is not free, and there is nothing
    // new to find.
    final another = orphan('and-another.jpg');
    expect(await services.sweepOrphanMediaIfDue(), 0);
    expect(
      another.existsSync(),
      isTrue,
      reason: 'the throttle should have skipped the sweep entirely',
    );

    // A day later it is due again.
    expect(await services.sweepOrphanMediaIfDue(interval: Duration.zero), 1);
    expect(another.existsSync(), isFalse);
  });

  test('a freshly captured file is not swept out from under its note', () async {
    // Written now, not three hours ago: this is the shape of a capture whose
    // file lands before its row does, and the sweep must not race it.
    final justWritten = File(p.join(mediaDir, 'still-arriving.m4a'))
      ..writeAsBytesSync(const [1, 2, 3]);

    expect(await services.sweepOrphanMediaIfDue(), 0);
    expect(justWritten.existsSync(), isTrue);
  });
}
