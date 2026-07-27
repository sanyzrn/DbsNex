import 'dart:io';
import 'dart:math' as math;

import 'package:nex_core/nex_core.dart';

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
  const LibraryMaintenance(this.repo);
  final SqliteNoteRepository repo;

  List<Note> deletedNotes({int limit = 200}) => repo.db
      .select('SELECT * FROM notes WHERE deleted_at IS NOT NULL ORDER BY deleted_at DESC LIMIT ?', [limit])
      .map((row) => Note.fromRow(row, tags: repo.tagsForNote(row['id'] as String)))
      .toList();

  void purgeDeletedBefore(DateTime cutoff) => repo.db.execute(
        'DELETE FROM notes WHERE deleted_at IS NOT NULL AND deleted_at < ?',
        [cutoff.toUtc().toIso8601String()],
      );

  /// Permanently removes one note from the trash.
  ///
  /// Guarded on `deleted_at IS NOT NULL` so this can never reach a live note:
  /// the only path to it is the trash screen, and a note that was restored
  /// between the tap and the call must survive.
  void purgeNote(String id) => repo.db.execute(
        'DELETE FROM notes WHERE id = ? AND deleted_at IS NOT NULL',
        [id],
      );

  /// Empties the trash.
  void purgeAllDeleted() =>
      repo.db.execute('DELETE FROM notes WHERE deleted_at IS NOT NULL');

  List<TagUsage> tagUsage() => repo.db.select('''
    SELECT t.*, COUNT(nt.note_id) AS usage_count
    FROM tags t LEFT JOIN note_tags nt ON nt.tag_id = t.id
    GROUP BY t.id ORDER BY usage_count DESC, t.name COLLATE NOCASE
  ''').map((row) => TagUsage(Tag.fromRow(row), row['usage_count'] as int)).toList();

  void renameTag(String id, String name) {
    final value = name.trim();
    if (value.isEmpty) throw ArgumentError('Tag name cannot be empty');
    repo.db.execute('UPDATE tags SET name = ? WHERE id = ?', [value, id]);
  }

  void mergeTag({required String sourceId, required String targetId}) {
    repo.db.execute('BEGIN IMMEDIATE');
    try {
      repo.db.execute('''
        INSERT OR IGNORE INTO note_tags (note_id, tag_id)
        SELECT note_id, ? FROM note_tags WHERE tag_id = ?
      ''', [targetId, sourceId]);
      repo.db.execute('DELETE FROM tags WHERE id = ?', [sourceId]);
      repo.db.execute('COMMIT');
    } catch (_) {
      repo.db.execute('ROLLBACK');
      rethrow;
    }
  }

  void deleteTag(String id) => repo.db.execute('DELETE FROM tags WHERE id = ?', [id]);

  List<Note> anniversary(DateTime now) {
    final start = DateTime.utc(now.year - 1, now.month, now.day);
    final end = start.add(const Duration(days: 1));
    return repo.db.select('''SELECT * FROM notes WHERE deleted_at IS NULL
      AND created_at >= ? AND created_at < ? ORDER BY created_at DESC''',
      [start.toIso8601String(), end.toIso8601String()])
      .map((row) => Note.fromRow(row, tags: repo.tagsForNote(row['id'] as String)))
      .toList();
  }

  Note? nearestMiss(String query) {
    final needle = _normal(query);
    if (needle.isEmpty) return null;
    Note? best;
    var score = 0.0;
    for (final row in repo.db.select('''SELECT * FROM notes WHERE deleted_at IS NULL
                                        AND content IS NOT NULL ORDER BY created_at DESC LIMIT 500''')) {
      final note = Note.fromRow(row, tags: repo.tagsForNote(row['id'] as String));
      final candidate = _dice(needle, _normal(note.searchableDerivedText ?? ''));
      if (candidate > score) { score = candidate; best = note; }
    }
    return score >= 0.22 ? best : null;
  }

  static String _normal(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ').trim();

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
      if (count > 0) { overlap++; pairs[pair] = count - 1; }
    }
    return (2 * overlap) / math.max(1, a.length + b.length - 2);
  }

  Future<StorageSnapshot> storage(String dbPath, String mediaDir, String backupDir) async {
    Future<int> bytes(String path) async {
      final dir = Directory(path);
      if (!dir.existsSync()) return 0;
      var total = 0;
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) total += await entity.length();
      }
      return total;
    }
    final notes = repo.db.select(
      'SELECT COUNT(*) AS count FROM notes WHERE deleted_at IS NULL',
    ).first['count'] as int;
    return StorageSnapshot(
      notes: notes,
      database: File(dbPath).existsSync() ? await File(dbPath).length() : 0,
      media: await bytes(mediaDir),
      backups: await bytes(backupDir),
    );
  }
}

class TagUsage {
  const TagUsage(this.tag, this.count);
  final Tag tag;
  final int count;
}

class StorageSnapshot {
  const StorageSnapshot({required this.notes, required this.database, required this.media, required this.backups});
  final int notes;
  final int database;
  final int media;
  final int backups;
  int get total => database + media + backups;
}