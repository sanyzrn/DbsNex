import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'database.dart';
import 'restore_transaction.dart';
import 'backup_media_store.dart';
import 'zip_file_writer.dart';

/// A backup that contains everything, not only the database.
///
/// The old backup was a copy of `nex.sqlite` and nothing else. That is every
/// note, tag, checklist and link — and not one photo, voice recording or
/// attached file, because those live as files in `media/` beside the database
/// and only their paths are in it. Restored onto a new device the library
/// came back with every picture missing and no error anywhere to say so: the
/// notes were all there, so the backup looked like it had worked.
///
/// Shared backups are self-contained ZIPs (format 1). Local automatic backups
/// use format 2 manifests plus immutable `.media/<sha256>` blobs in the backup
/// directory. [portable] materializes those blobs before sharing.
/// Nothing here is encrypted or obfuscated —
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
    final snapshot = snapshotDatabase(database: database, backupDir: backupDir);
    try {
      return createFromSnapshot(
        snapshotPath: snapshot.path,
        mediaDir: mediaDir,
        backupDir: backupDir,
        retention: retention,
      );
    } finally {
      if (snapshot.existsSync()) snapshot.deleteSync();
    }
  }

  /// SQLite makes a consistent snapshot even with a second engine writing.
  /// Compression must only ever read this snapshot, never the live WAL file.
  static File snapshotDatabase({
    required NexDatabase database,
    required String backupDir,
  }) {
    if (database.path == ':memory:') {
      throw StateError('Cannot back up an in-memory database');
    }
    Directory(backupDir).createSync(recursive: true);
    final target = File(
      p.join(backupDir, '.snapshot-${DateTime.now().microsecondsSinceEpoch}'),
    );
    database.db.execute('VACUUM INTO ?', [target.path]);
    return target;
  }

  /// No live database handle: safe to run in a separate compression isolate.
  static File createFromSnapshot({
    required String snapshotPath,
    required String mediaDir,
    required String backupDir,
    int retention = NexDatabase.backupRetention,
    bool compact = false,
  }) {
    final dir = Directory(backupDir)..createSync(recursive: true);
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    for (final stale in dir.listSync(followLinks: false).whereType<File>()) {
      final name = p.basename(stale.path);
      if ((name.startsWith('.snapshot-') ||
              name.startsWith('.restore-source-') ||
              (name.startsWith('nex-') && name.endsWith('.nexbak.partial'))) &&
          stale.lastModifiedSync().isBefore(cutoff)) {
        stale.deleteSync();
      }
    }
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
    final target = File(p.join(dir.path, 'nex-$stamp$extension'));
    final partial = File('${target.path}.partial');
    final media = Directory(mediaDir);
    final files = media.existsSync()
        ? media
              .listSync(recursive: true, followLinks: false)
              .whereType<File>()
              .toList()
        : <File>[];
    final snapshot = sqlite3.open(snapshotPath, mode: OpenMode.readOnly);
    final expected = <String, String>{};
    try {
      for (final row in snapshot.select(
        'SELECT media_uri, media_hash FROM notes WHERE media_uri IS NOT NULL',
      )) {
        final uri = row['media_uri'] as String;
        if (!File(uri).existsSync()) {
          throw StateError('Referenced media is missing');
        }
        if (!p.isWithin(media.absolute.path, File(uri).absolute.path)) {
          throw StateError('Referenced media is outside the library');
        }
        expected[p.normalize(File(uri).absolute.path)] =
            row['media_hash'] as String? ?? '';
      }
    } finally {
      snapshot.dispose();
    }
    final listed = files.map((f) => p.normalize(f.absolute.path)).toSet();
    if (!listed.containsAll(expected.keys)) {
      throw StateError('Referenced media changed during backup');
    }
    final store = BackupMediaStore(backupDir);
    final manifest = <String, String>{};

    final encoder = ZipFileEncoder()..create(partial.path);
    try {
      // Sync, deliberately. `addFile` is a Future in archive 4, and calling
      // it without awaiting produced a zip that closed before anything was
      // written into it — a backup file that exists, weighs nothing, and
      // fails only when someone tries to restore from it.
      addBoundedZipFile(encoder, File(snapshotPath), _dbEntry);
      for (final file in files) {
        // Relative, so restoring into a different sandbox path — which is
        // every reinstall on iOS and most on Android — puts them back in the
        // right place rather than at an absolute path that no longer exists.
        final name = p.url.join(
          'media',
          p.relative(file.path, from: media.path).replaceAll(r'\', '/'),
        );
        // Freeze and verify before compression. An edit/delete racing this
        // operation fails the backup instead of publishing mixed generations.
        final hash = store.retain(
          file,
          expectedHash: expected[p.normalize(file.absolute.path)],
        );
        manifest[name] = hash;
        if (!compact) addBoundedZipFile(encoder, store.file(hash), name);
      }
      final meta = jsonEncode({
        'format': compact ? 2 : 1,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'mediaFiles': files.length,
        if (compact) 'media': manifest,
      });
      final metaBytes = utf8.encode(meta);
      encoder.addArchiveFile(
        ArchiveFile(_metaEntry, metaBytes.length, metaBytes),
      );
      encoder.closeSync();
      partial.renameSync(target.path);
    } catch (_) {
      encoder.closeSync();
      if (partial.existsSync()) partial.deleteSync();
      rethrow;
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
        mediaStore: BackupMediaStore(backup.parent.path),
      );
    } finally {
      input.closeSync();
    }
  }

  /// Writes one archive entry to [path] without holding it whole in memory.
  static void _extract(ArchiveFile entry, String path) {
    extractCheckedZipFile(entry, path);
  }

  static void _restoreFrom({
    required Archive archive,
    required ArchiveFile dbEntry,
    required String liveDbPath,
    required String mediaDir,
    required BackupMediaStore mediaStore,
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

      final manifest = _manifest(archive);
      for (final entry in manifest.entries) {
        final relative = _safeMediaName(entry.key);
        mediaStore.restore(
          entry.value,
          File(p.join(staging.path, 'media', relative)),
        );
      }

      for (final file in archive.files) {
        if (!file.isFile || !file.name.startsWith(_mediaPrefix)) continue;
        if (manifest.containsKey(file.name)) {
          throw const FormatException('Duplicate backup media');
        }
        final relative = file.name
            .substring(_mediaPrefix.length)
            .replaceAll(r'\', '/');
        // A zip is an untrusted file even when this app wrote it. An entry
        // named `../../secrets` would otherwise be written outside the
        // directory it is supposed to land in.
        if (relative.isEmpty ||
            p.url.isAbsolute(relative) ||
            p.windows.isAbsolute(relative) ||
            relative.contains(':') ||
            file.isSymbolicLink ||
            p.url.split(relative).contains('..')) {
          throw const FormatException('Unsafe media path in backup');
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
  /// the bare basename. A missing referenced file fails the restore and rolls
  /// back the live library instead of reporting an incomplete restore as saved.
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
        if (p.isWithin(mediaDir, stored) && File(stored).existsSync()) continue;

        final segments = p.url.split(stored.replaceAll(r'\', '/'));
        File? candidate;
        // From the longest tail down to the basename. The first segment is
        // the root (`/`, or a drive), which is never part of a path relative
        // to the media directory, so the search starts one in.
        for (var take = segments.length - 1; take >= 1; take--) {
          final tail = p.joinAll(segments.sublist(segments.length - take));
          final file = File(p.join(mediaDir, tail));
          if (p.isWithin(p.normalize(mediaDir), p.normalize(file.path)) &&
              file.existsSync()) {
            candidate = file;
            break;
          }
        }
        if (candidate != null) {
          db.execute('UPDATE notes SET media_uri = ? WHERE id = ?', [
            candidate.path,
            row['id']! as String,
          ]);
        } else {
          throw const FormatException('Referenced backup media is missing');
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
    collectUnusedMedia(dir.path);
  }

  /// Preserve recent blobs for concurrent readers. An unreadable manifest stops
  /// collection; it never authorizes deleting potentially referenced media.
  static void collectUnusedMedia(String backupDir) {
    final dir = Directory(backupDir);
    final blobs = BackupMediaStore(backupDir).root;
    if (!blobs.existsSync()) return;
    final referenced = <String>{};
    try {
      for (final file in dir.listSync(followLinks: false).whereType<File>()) {
        if (!file.path.endsWith(extension) &&
            !p.basename(file.path).startsWith('.restore-source-')) {
          continue;
        }
        final input = InputFileStream(file.path);
        try {
          referenced.addAll(_manifest(ZipDecoder().decodeStream(input)).values);
        } finally {
          input.closeSync();
        }
      }
    } catch (_) {
      return;
    }
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    for (final file in blobs.listSync(followLinks: false).whereType<File>()) {
      if (!referenced.contains(p.basename(file.path)) &&
          file.lastModifiedSync().isBefore(cutoff)) {
        file.deleteSync();
      }
    }
  }

  static String _safeMediaName(String name) {
    if (!name.startsWith(_mediaPrefix)) {
      throw const FormatException('Invalid media entry');
    }
    final relative = name.substring(_mediaPrefix.length).replaceAll(r'\', '/');
    if (relative.isEmpty ||
        p.url.isAbsolute(relative) ||
        p.windows.isAbsolute(relative) ||
        relative.contains(':') ||
        p.url.split(relative).contains('..')) {
      throw const FormatException('Unsafe media path');
    }
    return relative;
  }

  static Map<String, String> _manifest(Archive archive) {
    final entries = archive.files.where((f) => f.name == _metaEntry);
    if (entries.isEmpty) return {};
    final meta = entries.single;
    if (meta.size > 4 * 1024 * 1024) {
      throw const FormatException('Backup manifest too large');
    }
    final value = jsonDecode(utf8.decode(meta.content as List<int>)) as Map;
    if (value['format'] == 1) return {};
    if (value['format'] != 2) {
      throw const FormatException('Unknown backup format');
    }
    return Map<String, String>.from(value['media'] as Map);
  }

  /// Turn a local manifest into an ordinary self-contained format-1 archive.
  static String portable(String source, String output) {
    final input = InputFileStream(source);
    final partial = File('$output.partial');
    ZipFileEncoder? encoder;
    Directory? staging;
    try {
      final archive = ZipDecoder().decodeStream(input);
      final manifest = _manifest(archive);
      if (manifest.isEmpty) {
        File(source).copySync(output);
        return output;
      }
      staging = Directory(p.dirname(output)).createTempSync('.nex-portable-');
      encoder = ZipFileEncoder()..create(partial.path);
      final database = archive.files.singleWhere((f) => f.name == _dbEntry);
      final dbFile = File(p.join(staging.path, _dbEntry));
      _extract(database, dbFile.path);
      addBoundedZipFile(encoder, dbFile, _dbEntry);
      final store = BackupMediaStore(p.dirname(source));
      for (final entry in manifest.entries) {
        _safeMediaName(entry.key);
        final verified = File(p.join(staging.path, 'media'));
        store.restore(entry.value, verified);
        addBoundedZipFile(encoder, verified, entry.key);
        verified.deleteSync();
      }
      final bytes = utf8.encode(
        jsonEncode({'format': 1, 'mediaFiles': manifest.length}),
      );
      encoder.addArchiveFile(ArchiveFile(_metaEntry, bytes.length, bytes));
      encoder.closeSync();
      encoder = null;
      partial.renameSync(output);
      return output;
    } finally {
      encoder?.closeSync();
      input.closeSync();
      if (partial.existsSync()) partial.deleteSync();
      if (staging != null && staging.existsSync()) {
        staging.deleteSync(recursive: true);
      }
    }
  }
}
