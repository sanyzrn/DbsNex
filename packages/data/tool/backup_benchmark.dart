// Host-only synthetic benchmark. Never opens an installed Nex library.
// dart run tool/backup_benchmark.dart 400
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:nex_data/nex_data.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  final mb = args.isEmpty ? 16 : int.parse(args.first);
  final root = Directory.systemTemp.createTempSync('nex-backup-benchmark-');
  final media = Directory(p.join(root.path, 'media'))..createSync();
  final backups = p.join(root.path, 'backups');
  final db = NexDatabase.open(p.join(root.path, 'library.sqlite'));
  final repo = SqliteNoteRepository(db, localDeviceId: 'benchmark');
  final results = <String, Object>{'media_mb': mb};
  final random = Random(42);
  final block = Uint8List.fromList(
    List.generate(64 * 1024, (_) => random.nextInt(256)),
  );
  try {
    final file = File(p.join(media.path, 'fixture.bin'));
    final output = file.openSync(mode: FileMode.write);
    for (var i = 0; i < mb * 16; i++) {
      output.writeFromSync(block);
    }
    output.closeSync();
    final digest = (await sha256.bind(file.openRead()).first).toString();
    final now = DateTime.now().toUtc();
    repo.insert(
      Note(
        id: 'fixture',
        type: NoteType.file,
        mediaUri: file.path,
        mediaHash: digest,
        content: 'آزمایش.bin',
        caption: 'آزمایش پشتیبان فارسی — یادداشت و تصویر',
        createdAt: now,
        updatedAt: now,
        deviceId: 'benchmark',
        rev: 1,
        syncState: SyncState.pending,
      ),
    );
    final watch = Stopwatch()..start();
    final snapshot = repo.backupSnapshot(backups);
    results['snapshot_ms'] = watch.elapsedMilliseconds;
    watch.reset();
    final first = NexBackupArchive.createFromSnapshot(
      snapshotPath: snapshot.path,
      mediaDir: media.path,
      backupDir: backups,
      compact: true,
    );
    results['first_backup_ms'] = watch.elapsedMilliseconds;
    watch.reset();
    final second = NexBackupArchive.createFromSnapshot(
      snapshotPath: snapshot.path,
      mediaDir: media.path,
      backupDir: backups,
      compact: true,
    );
    results['second_backup_ms'] = watch.elapsedMilliseconds;
    results['second_manifest_bytes'] = second.lengthSync();
    results['blob_store_bytes'] = Directory(p.join(backups, '.media'))
        .listSync()
        .whereType<File>()
        .fold<int>(0, (sum, f) => sum + f.lengthSync());
    watch.reset();
    final portable = NexBackupArchive.portable(
      first.path,
      p.join(root.path, 'portable.nexbak'),
    );
    results['portable_ms'] = watch.elapsedMilliseconds;
    watch.reset();
    NexBackupArchive.restore(
      liveDbPath: p.join(root.path, 'restored.sqlite'),
      mediaDir: p.join(root.path, 'restored-media'),
      backupFile: portable,
    );
    results['restore_ms'] = watch.elapsedMilliseconds;
    watch.reset();
    final zip = await repo.exportArchive(
      outputPath: p.join(root.path, 'transfer.zip'),
      mediaRoot: media.path,
    );
    results['export_ms'] = watch.elapsedMilliseconds;
    final importDb = NexDatabase.open(p.join(root.path, 'imported.sqlite'));
    try {
      final importer = SqliteNoteRepository(importDb, localDeviceId: 'import');
      watch.reset();
      final imported = await importer.importArchive(
        archiveFile: zip,
        mediaRoot: p.join(root.path, 'imported-media'),
      );
      results['import_ms'] = watch.elapsedMilliseconds;
      if (imported.imported != 1) throw StateError('Import lost the fixture');
    } finally {
      importDb.close();
    }
    // Independent ZIP readers validate headers, UTF-8 lengths and CRCs.
    final py = await Process.run('python', [
      '-c',
      'import zipfile,sys; z=zipfile.ZipFile(sys.argv[1]); assert z.testzip() is None; print("ok")',
      zip.path,
    ]);
    results['python_zip'] = py.exitCode == 0 ? 'passed' : '${py.stderr}';
    final javaSource = File(p.join(root.path, 'CheckZip.java'))
      ..writeAsStringSync('''
import java.util.zip.*; import java.io.*;
class CheckZip { public static void main(String[] args) throws Exception {
  try (var in = new ZipInputStream(new FileInputStream(args[0]))) {
    byte[] bytes = new byte[65536]; while (in.getNextEntry() != null) {
      while (in.read(bytes) != -1) {} in.closeEntry();
    }
  }
}}
''');
    final java = await Process.run('java', [javaSource.path, zip.path]);
    results['java_zip'] = java.exitCode == 0 ? 'passed' : '${java.stderr}';
    if (py.exitCode != 0 || java.exitCode != 0) {
      throw StateError('Independent ZIP validation failed: $results');
    }
    results['max_rss_bytes'] = ProcessInfo.maxRss;
    stdout.writeln(jsonEncode(results));
  } finally {
    db.close();
    // This path is exclusively created by this invocation in the system temp.
    root.deleteSync(recursive: true);
  }
}
