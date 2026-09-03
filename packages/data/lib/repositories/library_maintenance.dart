import 'dart:io';
import 'dart:math' as math;

import 'package:nex_core/nex_core.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' show Database;

import 'note_repository.dart';

/// Library maintenance: the trash view, the tag manager and the storage
/// breakdown.
///
/// This lived in apps/client as `PolishService` and reached straight into
/// `repo.db` to run raw SQL — on the UI isolate, which is what the database
/// worker exists to prevent. It is storage code, so it belongs in the storage
/// layer, and it is constructed inside the worker isolate alongside the
/// repository it drives.
///
/// Typed against [SqliteNoteRepository] rather than the [NoteRepository] port:
/// it needs the raw handle, which the port deliberately does not expose.
class LibraryMaintenance {
  LibraryMaintenance(this.repo, {this.mediaRoot});
  final SqliteNoteRepository repo;

  /// The directory attachment files live in. When set, purges unlink the
  /// files a purged note pointed at — a "delete forever" that left the
  /// recording on disk forever was neither a delete nor forever, and it was
  /// also a privacy hole: the row was gone, the bytes were not.
  ///
  /// Null (tests of the SQL behaviour only) keeps the old behaviour of rows
  /// without files.
  final String? mediaRoot;

  List<Note> deletedNotes({int limit = 200}) => repo.db
      .select(
        'SELECT * FROM notes WHERE deleted_at IS NOT NULL ORDER BY deleted_at DESC LIMIT ?',
        [limit],
      )
      .map(
        (row) => Note.fromRow(row, tags: repo.tagsForNote(row['id'] as String)),
      )
      .toList();

  void purgeDeletedBefore(DateTime cutoff) {
    final uris = _mediaUris(
      'SELECT media_uri FROM notes WHERE deleted_at IS NOT NULL AND deleted_at < ?',
      [cutoff.toUtc().toIso8601String()],
    );
    repo.db.execute(
      'DELETE FROM notes WHERE deleted_at IS NOT NULL AND deleted_at < ?',
      [cutoff.toUtc().toIso8601String()],
    );
    _unlinkMedia(uris);
  }

  /// Permanently removes one note from the trash — rows, tags, embeddings
  /// (by cascade) and the attachment file itself.
  ///
  /// Guarded on `deleted_at IS NOT NULL` so this can never reach a live note:
  /// the only path to it is the trash screen, and a note that was restored
  /// between the tap and the call must survive.
  void purgeNote(String id) {
    final rows = repo.db.select(
      'SELECT media_uri FROM notes WHERE id = ? AND deleted_at IS NOT NULL',
      [id],
    );
    if (rows.isEmpty) return;
    repo.db.execute(
      'DELETE FROM notes WHERE id = ? AND deleted_at IS NOT NULL',
      [id],
    );
    _unlinkMedia([
      for (final row in rows)
        if (row['media_uri'] is String) row['media_uri']! as String,
    ]);
  }

  /// Empties the trash.
  void purgeAllDeleted() {
    final uris = _mediaUris(
      'SELECT media_uri FROM notes WHERE deleted_at IS NOT NULL',
      const [],
    );
    repo.db.execute('DELETE FROM notes WHERE deleted_at IS NOT NULL');
    _unlinkMedia(uris);
  }

  List<String> _mediaUris(String sql, List<Object?> args) => db
      .select(sql, args)
      .map((row) => row['media_uri'] as String?)
      .whereType<String>()
      .toList();

  Database get db => repo.db;

  /// Deletes attachment files a purge just orphaned. Best-effort: a file
  /// that cannot be removed (a stuck handle, a transient EACCES) must not
  /// turn a finished purge into a thrown one — the row is already gone, and
  /// [sweepOrphanMedia] picks unreferenced strays up later.
  void _unlinkMedia(List<String> uris) {
    for (final uri in uris) {
      try {
        final file = File(uri);
        if (_isInsideMediaRoot(uri) && file.existsSync()) file.deleteSync();
      } catch (_) {
        // Left for the sweep.
      }
    }
  }

  /// A file is only ever deleted when it is inside [mediaRoot]. The path in
  /// a note row was written by this app, but purging is destructive enough
  /// that a corrupted or hand-edited row pointing somewhere else (a shared
  /// download, a camera directory) must fail to delete rather than succeed.
  bool _isInsideMediaRoot(String path) {
    final root = mediaRoot;
    if (root == null) return false;
    final canonical = p.normalize(path);
    final rootCanonical = p.normalize(root);
    return canonical == rootCanonical ||
        canonical.startsWith('$rootCanonical${p.separator}');
  }

  /// Removes media files no note references anymore.
  ///
  /// The safety net under the purge paths: a file whose unlink failed, one
  /// left behind by a capture whose insert failed, a pre-fix leftover from a
  /// purge that only deleted rows. Files younger than an hour are left alone
  /// so a capture mid-flight (file written first, row inserted second) can
  /// never be swept out from under its own note.
  ///
  /// The root only, never a subdirectory of it, and that is the whole of the
  /// safety here rather than a detail of it. Every note's media is written
  /// flat into this directory — `photo-…`, `voice-…`, `media-…`, `keep-…` —
  /// so a file in a subdirectory was put there by something that is not a
  /// note, and this has no business forming an opinion about it.
  ///
  /// It swept recursively once, and the app keeps the user's profile picture
  /// in `profile/` under this root. No note references it, it was more than an
  /// hour old, and so it was deleted — silently, a day after the release that
  /// gave this method a caller. Whoever changes this back owes the next
  /// person an answer about that.
  ///
  /// Returns how many files were removed.
  int sweepOrphanMedia({String? mediaDir, Duration minAge = const Duration(hours: 1)}) {
    final root = mediaDir ?? mediaRoot;
    if (root == null) return 0;
    final dir = Directory(root);
    if (!dir.existsSync()) return 0;

    final referenced = {
      for (final row in repo.db.select(
        'SELECT media_uri FROM notes WHERE media_uri IS NOT NULL',
      ))
        p.normalize(row['media_uri']! as String),
    };

    final cutoff = DateTime.now().subtract(minAge);
    var removed = 0;
    final entities = dir.listSync(followLinks: false);
    for (final entity in entities) {
      if (entity is! File) continue;
      final normalized = p.normalize(entity.path);
      if (referenced.contains(normalized)) continue;
      try {
        if (entity.statSync().modified.isAfter(cutoff)) continue;
        entity.deleteSync();
        removed++;
      } catch (_) {
        // Unreadable or undeletable: leave it for the next pass.
      }
    }
    return removed;
  }

  // A trashed note (deleted_at set) keeps its note_tags row until it is
  // purged — only a hard delete cascades that away — so counting nt.note_id
  // itself still counted a tag as "in use" by a note nobody can see anymore,
  // until the trash was emptied. Counting n.id instead, joined on
  // deleted_at IS NULL, means only a note actually on the timeline counts.
  List<TagUsage> tagUsage() => repo.db
      .select('''
    SELECT t.*, COUNT(n.id) AS usage_count
    FROM tags t
    LEFT JOIN note_tags nt ON nt.tag_id = t.id
    LEFT JOIN notes n ON n.id = nt.note_id AND n.deleted_at IS NULL
    GROUP BY t.id ORDER BY usage_count DESC, t.name COLLATE NOCASE
  ''')
      .map((row) => TagUsage(Tag.fromRow(row), row['usage_count'] as int))
      .toList();

  void renameTag(String id, String name) {
    final value = name.trim();
    if (value.isEmpty) throw ArgumentError('Tag name cannot be empty');
    repo.db.execute('UPDATE tags SET name = ? WHERE id = ?', [value, id]);
  }

  void mergeTag({required String sourceId, required String targetId}) {
    repo.db.execute('BEGIN IMMEDIATE');
    try {
      repo.db.execute(
        '''
        INSERT OR IGNORE INTO note_tags (note_id, tag_id)
        SELECT note_id, ? FROM note_tags WHERE tag_id = ?
      ''',
        [targetId, sourceId],
      );
      repo.db.execute('DELETE FROM tags WHERE id = ?', [sourceId]);
      repo.db.execute('COMMIT');
    } catch (_) {
      repo.db.execute('ROLLBACK');
      rethrow;
    }
  }

  void deleteTag(String id) =>
      repo.db.execute('DELETE FROM tags WHERE id = ?', [id]);

  Note? nearestMiss(String query) {
    final needle = _normal(query);
    if (needle.isEmpty) return null;
    Note? best;
    var score = 0.0;
    for (final row in repo.db.select(
      '''SELECT * FROM notes WHERE deleted_at IS NULL
                                        AND content IS NOT NULL ORDER BY created_at DESC LIMIT 500''',
    )) {
      final note = Note.fromRow(
        row,
        tags: repo.tagsForNote(row['id'] as String),
      );
      final candidate = _dice(
        needle,
        _normal(note.searchableDerivedText ?? ''),
      );
      if (candidate > score) {
        score = candidate;
        best = note;
      }
    }
    return score >= 0.22 ? best : null;
  }

  static String _normal(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .trim();

  static double _dice(String a, String b) {
    if (a.length < 2 || b.length < 2) return a == b ? 1 : 0;
    final pairs = <String, int>{};
    for (var i = 0; i < a.length - 1; i++) {
      final pair = a.substring(i, i + 2);
      pairs[pair] = (pairs[pair] ?? 0) + 1;
    }
    var overlap = 0;
    for (var i = 0; i < b.length - 1; i++) {
      final pair = b.substring(i, i + 2);
      final count = pairs[pair] ?? 0;
      if (count > 0) {
        overlap++;
        pairs[pair] = count - 1;
      }
    }
    return (2 * overlap) / math.max(1, a.length + b.length - 2);
  }

  Future<StorageSnapshot> storage(
    String dbPath,
    String mediaDir,
    String backupDir,
  ) async {
    Future<int> bytes(String path) async {
      final dir = Directory(path);
      if (!dir.existsSync()) return 0;
      var total = 0;
      await for (final entity in dir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File) total += await entity.length();
      }
      return total;
    }

    /// The media directory, split the way a person thinks about it.
    ///
    /// One "Media" figure answered "what is taking the space" with "your
    /// stuff", which is not an answer — a library that is 300 MB of voice
    /// notes and one that is 300 MB of photos want different things done
    /// about them. Split by extension because that is what the capture paths
    /// write: there is no per-file record in the database to join against.
    Future<(int images, int audio, int other)> media(String path) async {
      final dir = Directory(path);
      if (!dir.existsSync()) return (0, 0, 0);
      var images = 0;
      var audio = 0;
      var other = 0;
      await for (final entity in dir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        final size = await entity.length();
        final extension = p.extension(entity.path).toLowerCase();
        if (const {
          '.jpg',
          '.jpeg',
          '.png',
          '.webp',
          '.heic',
          '.gif',
        }.contains(extension)) {
          images += size;
        } else if (const {
          '.m4a',
          '.aac',
          '.mp3',
          '.wav',
          '.ogg',
          '.opus',
        }.contains(extension)) {
          audio += size;
        } else {
          other += size;
        }
      }
      return (images, audio, other);
    }

    final notes =
        repo.db
                .select(
                  'SELECT COUNT(*) AS count FROM notes WHERE deleted_at IS NULL',
                )
                .first['count']
            as int;
    final (images, audio, otherMedia) = await media(mediaDir);
    return StorageSnapshot(
      notes: notes,
      database: File(dbPath).existsSync() ? await File(dbPath).length() : 0,
      images: images,
      audio: audio,
      otherMedia: otherMedia,
      backups: await bytes(backupDir),
    );
  }
}

class TagUsage {
  const TagUsage(this.tag, this.count);
  final Tag tag;
  final int count;
}

/// What the library is made of, in bytes, by the thing that made it.
///
/// [models] is filled in by the caller rather than measured here: an
/// offline model lives in the app's support directory, which this repository
/// has no business knowing about, and it is also the single largest thing
/// most installations will ever hold — a storage figure that leaves out two
/// gigabytes is worse than no figure.
class StorageSnapshot {
  const StorageSnapshot({
    required this.notes,
    required this.database,
    required this.images,
    required this.audio,
    required this.otherMedia,
    required this.backups,
    this.models = 0,
  });

  /// How many notes there are — a count, not a size.
  final int notes;

  final int database;
  final int images;
  final int audio;

  /// Anything in the media directory that is neither a picture nor a
  /// recording: an imported document, a file from a share sheet.
  final int otherMedia;

  final int backups;

  /// The offline model, when one is installed.
  final int models;

  int get media => images + audio + otherMedia;

  int get total => database + media + backups + models;

  StorageSnapshot withModels(int bytes) => StorageSnapshot(
    notes: notes,
    database: database,
    images: images,
    audio: audio,
    otherMedia: otherMedia,
    backups: backups,
    models: bytes,
  );
}
