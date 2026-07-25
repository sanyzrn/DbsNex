import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import '../schema/database.dart';
import '../schema/models.dart';

const _uuid = Uuid();

/// Suggested starter tags (FR-3.3) — offered, never enforced.
const List<String> suggestedStarterTags = [
  'Idea',
  'Work',
  'Shopping',
  'Learning',
  'Inspiration',
];

/// Constrained tag accent palette (ADR-021 / design mockup accents).
const List<String> tagAccentPalette = [
  '#F0A93B',
  '#5B9BF0',
  '#F17FA0',
  '#2FBF8F',
  '#B49AE0',
];

String newUuidV7() => _uuid.v7();

String sha256OfBytes(Uint8List bytes) => sha256.convert(bytes).toString();

String? sha256OfFile(String? path) {
  if (path == null) return null;
  final file = File(path);
  if (!file.existsSync()) return null;
  return sha256OfBytes(file.readAsBytesSync());
}

class NoteRepository {
  NoteRepository(this._db);

  final NexDatabase _db;

  Database get db => _db.db;

  Note insert(Note note) {
    db.execute(
      '''
INSERT INTO notes (
  id, type, content, media_uri, media_hash, duration_ms,
  created_at, updated_at, deleted_at, device_id, rev, sync_state
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
''',
      [
        note.id,
        note.type.wireName,
        note.content,
        note.mediaUri,
        note.mediaHash,
        note.durationMs,
        note.createdAt.toUtc().toIso8601String(),
        note.updatedAt.toUtc().toIso8601String(),
        note.deletedAt?.toUtc().toIso8601String(),
        note.deviceId,
        note.rev,
        note.syncState.wireName,
      ],
    );
    if (note.type == NoteType.text &&
        note.content != null &&
        note.content!.isNotEmpty) {
      _upsertFts(note.id, note.content!);
    }
    return getById(note.id)!;
  }

  void updateContent(String noteId, String content) {
    final now = DateTime.now().toUtc().toIso8601String();
    db.execute(
      '''
UPDATE notes
SET content = ?, updated_at = ?, rev = rev + 1, sync_state = 'pending'
WHERE id = ? AND deleted_at IS NULL
''',
      [content, now, noteId],
    );
    _upsertFts(noteId, content);
  }

  void softDelete(String noteId) {
    final now = DateTime.now().toUtc().toIso8601String();
    db.execute(
      '''
UPDATE notes
SET deleted_at = ?, updated_at = ?, rev = rev + 1, sync_state = 'pending'
WHERE id = ?
''',
      [now, now, noteId],
    );
    db.execute('DELETE FROM notes_fts WHERE note_id = ?', [noteId]);
  }

  /// Undo a soft-delete within the toast window (FR-2.6).
  void undelete(String noteId) {
    final now = DateTime.now().toUtc().toIso8601String();
    final rows = db.select('SELECT * FROM notes WHERE id = ?', [noteId]);
    if (rows.isEmpty) return;
    db.execute(
      '''
UPDATE notes
SET deleted_at = NULL, updated_at = ?, rev = rev + 1, sync_state = 'pending'
WHERE id = ?
''',
      [now, noteId],
    );
    final content = rows.first['content'] as String?;
    final type = rows.first['type'] as String?;
    if (type == 'text' && content != null && content.isNotEmpty) {
      _upsertFts(noteId, content);
    }
  }

  Note? getById(String id, {bool includeDeleted = false}) {
    final rows = db.select(
      '''
SELECT * FROM notes
WHERE id = ?
  ${includeDeleted ? '' : 'AND deleted_at IS NULL'}
''',
      [id],
    );
    if (rows.isEmpty) return null;
    return Note.fromRow(rows.first, tags: tagsForNote(id));
  }

  /// Reverse-chronological timeline page (FR-2.2 / FR-2.5).
  List<Note> listTimeline({int limit = 50, int offset = 0}) {
    final rows = db.select(
      '''
SELECT * FROM notes
WHERE deleted_at IS NULL
ORDER BY created_at DESC
LIMIT ? OFFSET ?
''',
      [limit, offset],
    );
    return rows
        .map((r) => Note.fromRow(r, tags: tagsForNote(r['id']! as String)))
        .toList();
  }

  List<Tag> tagsForNote(String noteId) {
    final rows = db.select(
      '''
SELECT t.* FROM tags t
INNER JOIN note_tags nt ON nt.tag_id = t.id
WHERE nt.note_id = ?
ORDER BY t.name COLLATE NOCASE
''',
      [noteId],
    );
    return rows.map(Tag.fromRow).toList();
  }

  Tag upsertTag({required String name, String? color}) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('tag name must not be empty');
    }
    if (color != null && !tagAccentPalette.contains(color)) {
      throw ArgumentError.value(color, 'color', 'not in tagAccentPalette');
    }
    final existing = db.select(
      'SELECT * FROM tags WHERE name = ? COLLATE NOCASE',
      [trimmed],
    );
    if (existing.isNotEmpty) {
      if (color != null) {
        db.execute('UPDATE tags SET color = ? WHERE id = ?', [
          color,
          existing.first['id'],
        ]);
      }
      return Tag.fromRow(
        db.select('SELECT * FROM tags WHERE id = ?', [existing.first['id']]).first,
      );
    }
    final tag = Tag(
      id: newUuidV7(),
      name: trimmed,
      color: color,
      createdAt: DateTime.now().toUtc(),
    );
    db.execute(
      'INSERT INTO tags (id, name, color, created_at) VALUES (?, ?, ?, ?)',
      [
        tag.id,
        tag.name,
        tag.color,
        tag.createdAt.toUtc().toIso8601String(),
      ],
    );
    return tag;
  }

  void attachTag({required String noteId, required String tagId}) {
    db.execute(
      'INSERT OR IGNORE INTO note_tags (note_id, tag_id) VALUES (?, ?)',
      [noteId, tagId],
    );
    _bumpNote(noteId);
  }

  void detachTag({required String noteId, required String tagId}) {
    db.execute(
      'DELETE FROM note_tags WHERE note_id = ? AND tag_id = ?',
      [noteId, tagId],
    );
    _bumpNote(noteId);
  }

  List<Tag> listTags() {
    final rows = db.select('SELECT * FROM tags ORDER BY name COLLATE NOCASE');
    return rows.map(Tag.fromRow).toList();
  }

  void setTagColor({required String tagId, String? color}) {
    if (color != null && !tagAccentPalette.contains(color)) {
      throw ArgumentError.value(color, 'color', 'not in tagAccentPalette');
    }
    db.execute('UPDATE tags SET color = ? WHERE id = ?', [color, tagId]);
  }

  /// FR-4 search: FTS on text content + tag/date/type filters on one surface.
  List<Note> search(SearchFilters filters) {
    final where = <String>['n.deleted_at IS NULL'];
    final args = <Object?>[];

    final q = filters.query.trim();
    if (q.isNotEmpty) {
      // Match text notes via FTS; voice/photo never match by keyword (FR-4.6).
      where.add('''
n.id IN (
  SELECT note_id FROM notes_fts WHERE notes_fts MATCH ?
)
''');
      args.add(_ftsQuery(q));
    }

    if (filters.tagIds.isNotEmpty) {
      final placeholders = List.filled(filters.tagIds.length, '?').join(',');
      where.add('''
n.id IN (
  SELECT note_id FROM note_tags WHERE tag_id IN ($placeholders)
  GROUP BY note_id
  HAVING COUNT(DISTINCT tag_id) = ?
)
''');
      args.addAll(filters.tagIds);
      args.add(filters.tagIds.length);
    }

    if (filters.createdFrom != null) {
      where.add('n.created_at >= ?');
      args.add(filters.createdFrom!.toUtc().toIso8601String());
    }
    if (filters.createdTo != null) {
      where.add('n.created_at <= ?');
      args.add(filters.createdTo!.toUtc().toIso8601String());
    }

    if (filters.types.isNotEmpty) {
      final placeholders = List.filled(filters.types.length, '?').join(',');
      where.add('n.type IN ($placeholders)');
      args.addAll(filters.types.map((t) => t.wireName));
    }

    final sql = '''
SELECT n.* FROM notes n
WHERE ${where.join(' AND ')}
ORDER BY n.created_at DESC
''';
    final rows = db.select(sql, args);
    return rows
        .map((r) => Note.fromRow(r, tags: tagsForNote(r['id']! as String)))
        .toList();
  }

  /// Export archive: JSON + Markdown + media (FR-6 / ADR-025).
  Future<File> exportArchive({
    required String outputPath,
    required String mediaRoot,
  }) async {
    final notes = db.select('SELECT * FROM notes WHERE deleted_at IS NULL');
    final tags = listTags();
    final noteModels = notes
        .map((r) => Note.fromRow(r, tags: tagsForNote(r['id']! as String)))
        .toList();

    final archive = Archive();
    final jsonPayload = jsonEncode({
      'version': 1,
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'notes': noteModels.map((n) => n.toJson()).toList(),
      'tags': tags.map((t) => t.toJson()).toList(),
    });
    archive.addFile(
      ArchiveFile('notes.json', jsonPayload.length, utf8.encode(jsonPayload)),
    );

    for (final note in noteModels) {
      final md = _markdownFor(note);
      final bytes = utf8.encode(md);
      archive.addFile(
        ArchiveFile('markdown/${note.id}.md', bytes.length, bytes),
      );
      if (note.mediaUri != null) {
        final src = File(note.mediaUri!);
        if (src.existsSync()) {
          final name = p.basename(note.mediaUri!);
          final data = src.readAsBytesSync();
          archive.addFile(ArchiveFile('media/$name', data.length, data));
        }
      }
    }

    final encoded = ZipEncoder().encode(archive);
    final out = File(outputPath);
    out.parent.createSync(recursive: true);
    out.writeAsBytesSync(encoded);
    return out;
  }

  /// Reads an export archive and returns the parsed notes/tags JSON payload.
  static Map<String, dynamic> readExportJson(File archiveFile) {
    final bytes = archiveFile.readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);
    final jsonFile = archive.findFile('notes.json');
    if (jsonFile == null) {
      throw StateError('export archive missing notes.json');
    }
    return jsonDecode(utf8.decode(jsonFile.content as List<int>))
        as Map<String, dynamic>;
  }

  File backup(String backupDir) => _db.createBackup(backupDir);

  void _bumpNote(String noteId) {
    final now = DateTime.now().toUtc().toIso8601String();
    db.execute(
      '''
UPDATE notes
SET updated_at = ?, rev = rev + 1, sync_state = 'pending'
WHERE id = ?
''',
      [now, noteId],
    );
  }

  void _upsertFts(String noteId, String content) {
    db.execute('DELETE FROM notes_fts WHERE note_id = ?', [noteId]);
    if (content.isEmpty) return;
    db.execute(
      'INSERT INTO notes_fts (note_id, content) VALUES (?, ?)',
      [noteId, content],
    );
  }

  /// Build an FTS5 MATCH query: quote tokens so ZWNJ-split Persian words match.
  String _ftsQuery(String raw) {
    final cleaned = raw
        .replaceAll('"', ' ')
        .replaceAll('*', ' ')
        .trim();
    if (cleaned.isEmpty) return '""';
    final tokens = cleaned
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .map((t) => '"$t"')
        .join(' ');
    return tokens;
  }

  String _markdownFor(Note note) {
    final buffer = StringBuffer()
      ..writeln('---')
      ..writeln('id: ${note.id}')
      ..writeln('type: ${note.type.wireName}')
      ..writeln('created_at: ${note.createdAt.toUtc().toIso8601String()}')
      ..writeln(
        'tags: [${note.tags.map((t) => t.name).join(', ')}]',
      )
      ..writeln('---')
      ..writeln();
    switch (note.type) {
      case NoteType.text:
        buffer.writeln(note.content ?? '');
      case NoteType.voice:
        buffer.writeln('_Voice note_');
        if (note.durationMs != null) {
          buffer.writeln('Duration: ${note.durationMs} ms');
        }
        if (note.mediaUri != null) {
          buffer.writeln('Media: ${p.basename(note.mediaUri!)}');
        }
      case NoteType.photo:
        buffer.writeln('_Photo note_');
        if (note.mediaUri != null) {
          buffer.writeln('![photo](../media/${p.basename(note.mediaUri!)})');
        }
    }
    return buffer.toString();
  }
}
