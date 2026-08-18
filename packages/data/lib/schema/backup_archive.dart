import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import 'database.dart';

/// A backup that contains everything, not only the database.
///
/// The old backup was a copy of `nex.sqlite` and nothing else. That is every
/// note, tag, checklist and link — and not one photo, voice recording or
/// attached file, because those live as files in `media/` beside the database
/// and only their paths are in it. Restored onto a new device the library
/// came back with every picture missing and no error anywhere to say so: the
/// notes were all there, so the backup looked like it had worked.
///
/// The format is a plain zip. Nothing here is encrypted or obfuscated —
/// someone who has lost their phone should be able to get their notes out
/// with any unzip tool and a copy of `sqlite3`, without this app and without
/// us.
///
/// ```
/// nex-<timestamp>.nexbak
///   meta.json      what made it, when, and what is inside
///   nex.sqlite     the database, WAL-checkpointed before copying
///   media/…        every file the notes point at
/// ```
class NexBackupArchive {
  /// The extension for the format that carries media.
  ///
  /// A new name rather than reusing `.sqlite`: the two are not
  /// interchangeable, and a file called `.sqlite` that is really a zip is the
  /// kind of thing that wastes an afternoon two years from now.
  static const extension = '.nexbak';

  static const _dbEntry = 'nex.sqlite';
  static const _mediaPrefix = 'media/';
  static const _metaEntry = 'meta.json';

  /// Both formats this app has ever written, newest first when sorted.
  static bool isBackupFile(String path) =>
      path.endsWith(extension) || path.endsWith('.sqlite');

  /// Writes a complete backup into [backupDir] and prunes old ones.
  static File create({
    required NexDatabase database,
    required String mediaDir,
    required String backupDir,
    int retention = NexDatabase.backupRetention,
  }) {
    if (database.path == ':memory:') {
      throw StateError('Cannot back up an in-memory database');
    }
    final dir = Directory(backupDir)..createSync(recursive: true);
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
    final target = File(p.join(dir.path, 'nex-$stamp$extension'));

    // Checkpoint first, or the copy misses everything still sitting in the
    // write-ahead log — which on a busy day is most of it.
    database.db.execute('PRAGMA wal_checkpoint(FULL);');

    final media = Directory(mediaDir);
    final files = media.existsSync()
        ? media.listSync(recursive: true).whereType<File>().toList()
        : <File>[];

    final encoder = ZipFileEncoder()..create(target.path);
    try {
      // Sync, deliberately. `addFile` is a Future in archive 4, and calling
      // it without awaiting produced a zip that closed before anything was
      // written into it — a backup file that exists, weighs nothing, and
      // fails only when someone tries to restore from it.
      encoder.addFileSync(File(database.path), _dbEntry);
      for (final file in files) {
        // Relative, so restoring into a different sandbox path — which is
        // every reinstall on iOS and most on Android — puts them back in the
        // right place rather than at an absolute path that no longer exists.
        final name = p.url.join(
          'media',
          p.relative(file.path, from: media.path).replaceAll(r'\', '/'),
        );
        encoder.addFileSync(file, name);
      }
      final meta = jsonEncode({
        'format': 1,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'mediaFiles': files.length,
      });
      final metaBytes = utf8.encode(meta);
      encoder.addArchiveFile(
        ArchiveFile(_metaEntry, metaBytes.length, metaBytes),
      );
    } finally {
      encoder.closeSync();
    }

    _prune(dir, retention);
    return target;
  }

  /// Restores [backupFile] over the live database and media directory.
  ///
  /// Takes both formats. A `.sqlite` backup from before this existed restores
  /// its notes exactly as it always did and leaves the media directory alone
  /// — which is the honest behaviour: it never held any media to restore, and
  /// wiping the files already on the device would turn an old backup into a
  /// way of losing photos.
  ///
  /// Validates before it touches anything live, the same as
  /// [NexDatabase.restoreFromBackup] does and for the same reason: a corrupt
  /// backup must leave the working library exactly where it was.
  static void restore({
    required String liveDbPath,
    required String mediaDir,
    required String backupFile,
  }) {
    final backup = File(backupFile);
    if (!backup.existsSync()) {
      throw StateError('Backup file does not exist: $backupFile');
    }
    if (!_isZip(backup)) {
      NexDatabase.restoreFromBackup(
        liveDbPath: liveDbPath,
        backupFile: backupFile,
      );
      return;
    }

    final archive = ZipDecoder().decodeBytes(backup.readAsBytesSync());
    final dbEntry = archive.files.where(
      (file) => file.isFile && file.name == _dbEntry,
    );
    if (dbEntry.isEmpty) {
      throw StateError('Backup contains no database: $backupFile');
    }

    // Unpack beside the live files, validate, and only then swap. The staging
    // directory is a sibling so the rename at the end cannot cross a
    // filesystem boundary.
    final staging = Directory('$liveDbPath.restoring.d');
    if (staging.existsSync()) staging.deleteSync(recursive: true);
    staging.createSync(recursive: true);
    try {
      final stagedDb = File(p.join(staging.path, _dbEntry))
        ..writeAsBytesSync(dbEntry.first.content as List<int>);
      NexDatabase.assertRestorable(stagedDb.path);

      for (final file in archive.files) {
        if (!file.isFile || !file.name.startsWith(_mediaPrefix)) continue;
        final relative = file.name.substring(_mediaPrefix.length);
        // A zip is an untrusted file even when this app wrote it. An entry
        // named `../../secrets` would otherwise be written outside the
        // directory it is supposed to land in.
        if (relative.isEmpty ||
            p.url.isAbsolute(relative) ||
            p.url.split(relative).contains('..')) {
          continue;
        }
        File(p.join(staging.path, 'media', relative))
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync(file.content as List<int>);
      }

      for (final suffix in ['', '-wal', '-shm']) {
        final live = File('$liveDbPath$suffix');
        if (live.existsSync()) live.deleteSync();
      }
      stagedDb.renameSync(liveDbPath);

      final stagedMedia = Directory(p.join(staging.path, 'media'));
      if (stagedMedia.existsSync()) {
        final live = Directory(mediaDir);
        if (live.existsSync()) live.deleteSync(recursive: true);
        live.createSync(recursive: true);
        for (final file in stagedMedia.listSync(recursive: true)) {
          if (file is! File) continue;
          final destination = File(
            p.join(mediaDir, p.relative(file.path, from: stagedMedia.path)),
          )..parent.createSync(recursive: true);
          file.copySync(destination.path);
        }
      }
    } finally {
      if (staging.existsSync()) staging.deleteSync(recursive: true);
    }
  }

  /// Zip's local file header. Reading two bytes tells the formats apart
  /// without trusting the extension, which matters because a user can rename
  /// a file and a restore that guesses wrong destroys a library.
  static bool _isZip(File file) {
    final handle = file.openSync();
    try {
      final magic = handle.readSync(2);
      return magic.length == 2 && magic[0] == 0x50 && magic[1] == 0x4B;
    } finally {
      handle.closeSync();
    }
  }

  static void _prune(Directory dir, int retention) {
    final existing =
        dir
            .listSync()
            .whereType<File>()
            .where((file) => isBackupFile(file.path))
            .toList()
          ..sort((a, b) => b.path.compareTo(a.path));
    for (final stale in existing.skip(retention)) {
      stale.deleteSync();
    }
  }
}
