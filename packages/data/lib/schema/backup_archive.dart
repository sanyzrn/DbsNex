import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'database.dart';
import 'restore_transaction.dart';

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

    // Read from the file, not into memory. `decodeBytes(readAsBytesSync())`
    // held the whole archive — every photo and recording in it — in one byte
    // list before decoding a single entry, so a restore needed free memory
    // the size of the backup, and a phone old enough to be the one someone is
    // restoring onto is the phone least likely to have it. An independent
    // audit flagged it. The stream reads the central directory and then each
    // entry as it is written out, and each entry's decompressed bytes are
    // released once they are on disk.
    final input = InputFileStream(backup.path);
    try {
      final archive = ZipDecoder().decodeStream(input);
      final dbEntry = archive.files.where(
        (file) => file.isFile && file.name == _dbEntry,
      );
      if (dbEntry.isEmpty) {
        throw StateError('Backup contains no database: $backupFile');
      }
      _restoreFrom(
        archive: archive,
        dbEntry: dbEntry.first,
        liveDbPath: liveDbPath,
        mediaDir: mediaDir,
      );
    } finally {
      input.closeSync();
    }
  }

  /// Writes one archive entry to [path] without holding it whole in memory.
  static void _extract(ArchiveFile entry, String path) {
    final output = OutputFileStream(path);
    try {
      entry.writeContent(output);
    } finally {
      output.closeSync();
    }
  }

  static void _restoreFrom({
    required Archive archive,
    required ArchiveFile dbEntry,
    required String liveDbPath,
    required String mediaDir,
  }) {
    // Unpack beside the live files, validate, and only then swap. The staging
    // directory is a sibling so the rename at the end cannot cross a
    // filesystem boundary.
    final staging = Directory('$liveDbPath.restoring.d');
    if (staging.existsSync()) staging.deleteSync(recursive: true);
    staging.createSync(recursive: true);
    try {
      final stagedDb = File(p.join(staging.path, _dbEntry));
      _extract(dbEntry, stagedDb.path);
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
        final target = File(p.join(staging.path, 'media', relative))
          ..parent.createSync(recursive: true);
        _extract(file, target.path);
      }

      // Everything from here to `commit` replaces live files, so it runs as
      // one transaction: the live database and media are set aside rather
      // than deleted, and any failure — here, or the process dying — puts
      // them back. See [RestoreTransaction] for why the old order of
      // "delete the live one, rename the new one in", done twice, could
      // leave the backup's notes installed over newer ones and lose the
      // media outright.
      //
      // The media swap is still one rename, not a per-file copy, and only
      // happens when the backup carried media: a backup without any leaves
      // the photos already on the device where they are.
      final stagedMedia = Directory(p.join(staging.path, 'media'));
      final replacesMedia = stagedMedia.existsSync();
      final transaction = RestoreTransaction.begin(
        liveDbPath: liveDbPath,
        mediaDir: replacesMedia ? mediaDir : null,
      );
      try {
        transaction.installDatabase(stagedDb);
        if (replacesMedia) transaction.installMedia(stagedMedia);

        // The backed-up database still carries whatever absolute paths the
        // device that made it used. The files were deliberately restored
        // relative — this sandbox's media directory is the destination — so
        // every row pointing outside it is rewritten to where the file now
        // actually lives. Without this, a restore onto a reinstall (which is
        // every restore on iOS, and most of them on Android) came back with
        // every photo and recording pointing at a path that no longer
        // exists. Inside the transaction, because it writes to the restored
        // database and a failure here is a failed restore like any other.
        _remapMediaUris(liveDbPath, mediaDir);
        transaction.commit();
      } catch (_) {
        // A rollback that itself fails must not replace the error that
        // caused it. The journal is still on disk in that case, so the next
        // open of the database finishes the rollback — see
        // [NexDatabase.open].
        try {
          transaction.rollBack();
        } on Object {
          // Deliberately swallowed; recovered on next open.
        }
        rethrow;
      }
    } finally {
      if (staging.existsSync()) staging.deleteSync(recursive: true);
    }
  }

  /// Points every note back at its file inside [mediaDir].
  ///
  /// A row whose file already exists at the stored path is left alone — the
  /// common case for a backup restored on the device that made it. For the
  /// rest, the file that actually arrived in the restore is matched by the
  /// longest tail of the stored path that exists under [mediaDir], down to
  /// the bare basename. A row whose file matches nothing is left exactly as
  /// it is — rewriting it to a path that does not exist would turn "stale
  /// path, file findable" into "wrong path, file gone".
  ///
  /// **Longest tail, not basename, and not two probes.** The archive keeps
  /// whatever structure the media directory had (`listSync(recursive: true)`
  /// plus a path relative to the media root), so a row pointing at
  /// `…/media/2026/05/photo.jpg` should match `2026/05/photo.jpg` under the
  /// new root in preference to a bare `photo.jpg`, which may well belong to
  /// a different note.
  ///
  /// The tail has to be searched for rather than computed, because the row
  /// holds an absolute path into the *old* sandbox and nothing here knows
  /// where that sandbox's media root was. This is what the previous version
  /// was reaching for and did not reach: it asked for
  /// `p.relative(stored, from: p.dirname(stored))`, which is the definition
  /// of `p.basename(stored)` — the relative path from a file's own directory
  /// to that file is its name. So its "full relative path" probe and its
  /// "basename" fallback were the same string, and the fallback could never
  /// find anything the first had not. Nothing noticed because this app writes
  /// media flat and a same-device restore returns at the early exit above.
  static void _remapMediaUris(String liveDbPath, String mediaDir) {
    if (!File(liveDbPath).existsSync()) return;
    final db = sqlite3.open(liveDbPath);
    try {
      final rows = db.select(
        'SELECT id, media_uri FROM notes WHERE media_uri IS NOT NULL',
      );
      for (final row in rows) {
        final stored = row['media_uri']! as String;
        if (File(stored).existsSync()) continue;

        final segments = p.split(stored);
        File? candidate;
        // From the longest tail down to the basename. The first segment is
        // the root (`/`, or a drive), which is never part of a path relative
        // to the media directory, so the search starts one in.
        for (var take = segments.length - 1; take >= 1; take--) {
          final tail = p.joinAll(segments.sublist(segments.length - take));
          final file = File(p.join(mediaDir, tail));
          if (file.existsSync()) {
            candidate = file;
            break;
          }
        }
        if (candidate != null) {
          db.execute('UPDATE notes SET media_uri = ? WHERE id = ?', [
            candidate.path,
            row['id']! as String,
          ]);
        }
      }
    } finally {
      db.dispose();
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
