import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:nex_core/nex_core.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../schema/database.dart';

/// Suggested starter tags (FR-3.3) — offered, never enforced.
const List<String> suggestedStarterTags = [
  'Idea',
  'Work',
  'Shopping',
  'Learning',
  'Inspiration',
];

/// The suggested tag accent swatches (ADR-021 / design mockup accents).
///
/// Offered first in the colour picker, not enforced: the palette used to be the
/// only colours a tag could take, which meant a user could not encode their own
/// meaning — the very thing ADR-021 says the colour exists for. Any valid
/// `#RRGGBB` is accepted now; these are simply the ones that ship.
const List<String> tagAccentPalette = [
  '#F0A93B',
  '#5B9BF0',
  '#F17FA0',
  '#2FBF8F',
  '#B49AE0',
];

/// Whether a string is a colour a tag may carry: `#RRGGBB`, case-insensitive.
bool isTagAccent(String value) =>
    RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value);

/// What came out of reading an export archive back in.
///
/// [skipped] is not an error: importing the same archive twice should leave the
/// library exactly as it was, and the count is how the UI says so rather than
/// claiming it added notes it did not.
class ImportResult {
  const ImportResult({required this.imported, required this.skipped});

  final int imported;
  final int skipped;
}

// newUuidV7, sha256OfBytes and sha256OfFile moved to packages/core (ids.dart):
// they depend only on uuid and crypto, and keeping them here forced core's
// capture service to import the storage layer just to mint an id.

/// SQLite-backed implementation of the [NoteRepository] port.
///
/// Named for its storage engine because the port it implements owns the plain
/// name. Every method is synchronous — package:sqlite3 is a synchronous FFI
/// binding — so this class is only ever constructed **inside** the database
/// isolate. `NexDbWorker` is what the UI isolate talks to.
class SqliteNoteRepository implements NoteRepository {
  SqliteNoteRepository(this._db, {this.localDeviceId});

  final NexDatabase _db;

  /// When set, local mutations stamp this as `device_id` (sync concurrency).
  final String? localDeviceId;

  Database get db => _db.db;

  @override
  Note insert(Note note) {
    db.execute(
      '''
INSERT INTO notes (
  id, type, content, media_uri, media_hash, duration_ms,
  created_at, updated_at, deleted_at, device_id, rev, sync_state,
  caption, mime_type
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
        note.caption,
        note.mimeType,
      ],
    );
    final searchable = note.searchableDerivedText;
    if (searchable != null && searchable.isNotEmpty) {
      _upsertFts(note.id, searchable);
    }
    return getById(note.id)!;
  }

  void updateContent(String noteId, String content) {
    final now = DateTime.now().toUtc().toIso8601String();
    db.execute(
      '''
UPDATE notes
SET content = ?, updated_at = ?, rev = rev + 1, sync_state = 'pending'
    ${localDeviceId != null ? ', device_id = ?' : ''}
WHERE id = ? AND deleted_at IS NULL
''',
      [
        content,
        now,
        if (localDeviceId != null) localDeviceId,
        noteId,
      ],
    );
    _upsertFts(noteId, content);
  }

  void softDelete(String noteId) {
    final now = DateTime.now().toUtc().toIso8601String();
    db.execute(
      '''
UPDATE notes
SET deleted_at = ?, updated_at = ?, rev = rev + 1, sync_state = 'pending'
    ${localDeviceId != null ? ', device_id = ?' : ''}
WHERE id = ?
''',
      [
        now,
        now,
        if (localDeviceId != null) localDeviceId,
        noteId,
      ],
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
    ${localDeviceId != null ? ', device_id = ?' : ''}
WHERE id = ?
''',
      [
        now,
        if (localDeviceId != null) localDeviceId,
        noteId,
      ],
    );
    final content = rows.first['content'] as String?;
    final type = rows.first['type'] as String?;
    if (type == 'text' && content != null && content.isNotEmpty) {
      _upsertFts(noteId, content);
    }
  }

  @override
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
  ///
  /// When [tagId] is set, only notes with that tag are returned (Timeline
  /// filter chips / FR-4).
  @override
  List<Note> listTimeline({
    int limit = 50,
    int offset = 0,
    String? tagId,
  }) {
    final rows = tagId == null
        ? db.select(
            '''
SELECT * FROM notes
WHERE deleted_at IS NULL
ORDER BY created_at DESC
LIMIT ? OFFSET ?
''',
            [limit, offset],
          )
        : db.select(
            '''
SELECT n.* FROM notes n
INNER JOIN note_tags nt ON nt.note_id = n.id
WHERE n.deleted_at IS NULL AND nt.tag_id = ?
ORDER BY n.created_at DESC
LIMIT ? OFFSET ?
''',
            [tagId, limit, offset],
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

  @override
  Tag upsertTag({required String name, String? color}) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('tag name must not be empty');
    }
    if (color != null && !isTagAccent(color)) {
      throw ArgumentError.value(color, 'color', 'not a #RRGGBB colour');
    }
    final existing = db.select(
      'SELECT * FROM tags WHERE name = ? COLLATE NOCASE',
      [trimmed],
    );
    if (existing.isNotEmpty) {
      // A colour already chosen is never overwritten. It belongs to the tag,
      // decided in the tag manager — not to whichever note was most recently
      // tagged with it. Re-adding "Shopping" in blue to a second note used to
      // repaint every note already carrying the red one.
      //
      // A tag that has no colour yet may still take its first one here, so a
      // seeded starter tag is not stuck colourless forever. Changing an
      // existing colour is `setTagColor`, and it is explicit.
      final id = existing.first['id'];
      if (color != null && existing.first['color'] == null) {
        db.execute('UPDATE tags SET color = ? WHERE id = ?', [color, id]);
      }
      return Tag.fromRow(
        db.select('SELECT * FROM tags WHERE id = ?', [id]).first,
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

  @override
  void attachTag({required String noteId, required String tagId}) {
    db.execute(
      'INSERT OR IGNORE INTO note_tags (note_id, tag_id) VALUES (?, ?)',
      [noteId, tagId],
    );
    _bumpNote(noteId);
  }

  @override
  void detachTag({required String noteId, required String tagId}) {
    db.execute(
      'DELETE FROM note_tags WHERE note_id = ? AND tag_id = ?',
      [noteId, tagId],
    );
    _bumpNote(noteId);
  }

  @override
  List<Tag> listTags() {
    final rows = db.select('SELECT * FROM tags ORDER BY name COLLATE NOCASE');
    return rows.map(Tag.fromRow).toList();
  }

  /// Outbox: notes still pending sync (including tombstones).
  List<Note> listPending({bool includeDeleted = false}) {
    final rows = db.select(
      '''
SELECT * FROM notes
WHERE sync_state = 'pending'
ORDER BY updated_at ASC
''',
    );
    return rows
        .map((r) => Note.fromRow(r, tags: tagsForNote(r['id']! as String)))
        .where((n) => includeDeleted || !n.isDeleted)
        .toList();
  }

  void markSynced(String noteId) {
    db.execute(
      "UPDATE notes SET sync_state = 'synced' WHERE id = ?",
      [noteId],
    );
  }

  /// Test/helper: set content with an explicit `updated_at` (sync matrix).
  void updateContentAt(String noteId, String content, DateTime updatedAt) {
    db.execute(
      '''
UPDATE notes
SET content = ?, updated_at = ?, rev = rev + 1, sync_state = 'pending'
    ${localDeviceId != null ? ', device_id = ?' : ''}
WHERE id = ? AND deleted_at IS NULL
''',
      [
        content,
        updatedAt.toUtc().toIso8601String(),
        if (localDeviceId != null) localDeviceId,
        noteId,
      ],
    );
    _upsertFts(noteId, content);
  }

  Tag upsertTagFromSync({
    required String id,
    required String name,
    String? color,
    required DateTime createdAt,
  }) {
    final existing = db.select('SELECT * FROM tags WHERE id = ?', [id]);
    if (existing.isNotEmpty) {
      db.execute(
        'UPDATE tags SET name = ?, color = COALESCE(?, color) WHERE id = ?',
        [name, color, id],
      );
      return Tag.fromRow(
        db.select('SELECT * FROM tags WHERE id = ?', [id]).first,
      );
    }
    final byName = db.select(
      'SELECT * FROM tags WHERE name = ? COLLATE NOCASE',
      [name],
    );
    if (byName.isNotEmpty) {
      final localId = byName.first['id']! as String;
      if (localId != id) {
        // Remap local id → server id so note_tags from pull resolve.
        db.execute('UPDATE note_tags SET tag_id = ? WHERE tag_id = ?', [
          id,
          localId,
        ]);
        db.execute('DELETE FROM tags WHERE id = ?', [localId]);
        db.execute(
          'INSERT INTO tags (id, name, color, created_at) VALUES (?, ?, ?, ?)',
          [
            id,
            name,
            color ?? byName.first['color'],
            createdAt.toUtc().toIso8601String(),
          ],
        );
      }
      return Tag.fromRow(db.select('SELECT * FROM tags WHERE id = ?', [id]).first);
    }
    db.execute(
      'INSERT INTO tags (id, name, color, created_at) VALUES (?, ?, ?, ?)',
      [id, name, color, createdAt.toUtc().toIso8601String()],
    );
    return Tag.fromRow(db.select('SELECT * FROM tags WHERE id = ?', [id]).first);
  }

  /// Apply a server-merged note as local truth (does not mark pending).
  void applyRemoteNote({
    required String id,
    required NoteType type,
    String? content,
    String? mediaUri,
    String? mediaHash,
    int? durationMs,
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? deletedAt,
    required String deviceId,
    required int rev,
    required List<String> tagIds,
  }) {
    final existing = db.select('SELECT id FROM notes WHERE id = ?', [id]);
    if (existing.isEmpty) {
      db.execute(
        '''
INSERT INTO notes (
  id, type, content, media_uri, media_hash, duration_ms,
  created_at, updated_at, deleted_at, device_id, rev, sync_state
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'synced')
''',
        [
          id,
          type.wireName,
          content,
          mediaUri,
          mediaHash,
          durationMs,
          createdAt.toUtc().toIso8601String(),
          updatedAt.toUtc().toIso8601String(),
          deletedAt?.toUtc().toIso8601String(),
          deviceId,
          rev,
        ],
      );
    } else {
      db.execute(
        '''
UPDATE notes SET
  type = ?, content = ?, media_uri = ?, media_hash = ?, duration_ms = ?,
  created_at = ?, updated_at = ?, deleted_at = ?, device_id = ?, rev = ?,
  sync_state = 'synced'
WHERE id = ?
''',
        [
          type.wireName,
          content,
          mediaUri,
          mediaHash,
          durationMs,
          createdAt.toUtc().toIso8601String(),
          updatedAt.toUtc().toIso8601String(),
          deletedAt?.toUtc().toIso8601String(),
          deviceId,
          rev,
          id,
        ],
      );
    }
    db.execute('DELETE FROM notes_fts WHERE note_id = ?', [id]);
    if (type == NoteType.text && content != null && content.isNotEmpty && deletedAt == null) {
      _upsertFts(id, content);
    }
    db.execute('DELETE FROM note_tags WHERE note_id = ?', [id]);
    for (final tagId in tagIds) {
      db.execute(
        'INSERT OR IGNORE INTO note_tags (note_id, tag_id) VALUES (?, ?)',
        [id, tagId],
      );
    }
  }

  @override
  void setTagColor({required String tagId, String? color}) {
    if (color != null && !isTagAccent(color)) {
      throw ArgumentError.value(color, 'color', 'not a #RRGGBB colour');
    }
    db.execute('UPDATE tags SET color = ? WHERE id = ?', [color, tagId]);
  }

  /// Persist AI transcript alongside the voice note (09-ai.md — non-destructive).
  @override
  void setTranscriptText(String noteId, String text) {
    db.execute(
      'UPDATE notes SET transcript_text = ? WHERE id = ?',
      [text, noteId],
    );
    if (text.isNotEmpty) _upsertFts(noteId, text);
  }

  /// Persist AI OCR text alongside the photo note.
  @override
  void setOcrText(String noteId, String text) {
    db.execute(
      'UPDATE notes SET ocr_text = ? WHERE id = ?',
      [text, noteId],
    );
    if (text.isNotEmpty) _upsertFts(noteId, text);
  }

  @override
  void setSummaryText(String noteId, String text) {
    db.execute(
      'UPDATE notes SET summary_text = ? WHERE id = ?',
      [text, noteId],
    );
  }

  /// Optional post-capture caption on photo/voice/file (distinct from OCR/transcript).
  void setCaption(String noteId, String? caption) {
    final now = DateTime.now().toUtc().toIso8601String();
    final trimmed = caption?.trim();
    final value = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    db.execute(
      '''
UPDATE notes
SET caption = ?, updated_at = ?, rev = rev + 1, sync_state = 'pending'
    ${localDeviceId != null ? ', device_id = ?' : ''}
WHERE id = ? AND deleted_at IS NULL
''',
      [
        value,
        now,
        if (localDeviceId != null) localDeviceId,
        noteId,
      ],
    );
    final note = getById(noteId);
    final searchable = note?.searchableDerivedText;
    if (searchable != null && searchable.isNotEmpty) {
      _upsertFts(noteId, searchable);
    } else if (note?.type != NoteType.text) {
      db.execute('DELETE FROM notes_fts WHERE note_id = ?', [noteId]);
    }
  }

  @override
  void setEmbedding(String noteId, List<double> values) {
    final json = '[${values.join(',')}]';
    final now = DateTime.now().toUtc().toIso8601String();
    db.execute(
      '''
INSERT INTO note_embeddings (note_id, dims, values_json, updated_at)
VALUES (?, ?, ?, ?)
ON CONFLICT(note_id) DO UPDATE SET
  dims = excluded.dims,
  values_json = excluded.values_json,
  updated_at = excluded.updated_at
''',
      [noteId, values.length, json, now],
    );
  }

  @override
  List<double>? getEmbedding(String noteId) {
    final rows = db.select(
      'SELECT values_json FROM note_embeddings WHERE note_id = ?',
      [noteId],
    );
    if (rows.isEmpty) return null;
    return _parseVector(rows.first['values_json']! as String);
  }

  @override
  List<NoteEmbedding> listEmbeddings() {
    final rows = db.select(
      'SELECT note_id, values_json FROM note_embeddings',
    );
    return [
      for (final r in rows)
        NoteEmbedding(
          noteId: r['note_id']! as String,
          values: _parseVector(r['values_json']! as String),
        ),
    ];
  }

  List<double> _parseVector(String json) {
    final trimmed = json.trim();
    if (!trimmed.startsWith('[') || !trimmed.endsWith(']')) return const [];
    final inner = trimmed.substring(1, trimmed.length - 1).trim();
    if (inner.isEmpty) return const [];
    return inner.split(',').map((s) => double.parse(s.trim())).toList();
  }

  /// FR-4 search: FTS on text content + AI-derived transcript/OCR when present.
  @override
  List<Note> search(SearchFilters filters) {
    final where = <String>['n.deleted_at IS NULL'];
    final args = <Object?>[];

    final q = filters.query.trim();
    if (q.isNotEmpty) {
      // Match via FTS: text bodies, plus voice transcripts / photo OCR when present.
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

  /// Reads an export archive back into the library.
  ///
  /// The counterpart to [exportArchive], and the reason an export is worth
  /// having: without this, an archive was a one-way write that nothing could
  /// read back, and the only recoverable copy of a library was the automatic
  /// local backup — which lives on the very device the user might have lost.
  ///
  /// Additive by design. A note whose id is already here is left exactly as it
  /// is rather than overwritten: importing an old archive must never roll a
  /// note back to a previous state, so re-importing the same file twice is a
  /// no-op. Media travels with the archive and is written under [mediaRoot],
  /// and the stored path is rewritten to that new location — a path from
  /// another device means nothing here.
  Future<ImportResult> importArchive({
    required File archiveFile,
    required String mediaRoot,
  }) async {
    final bytes = await archiveFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final jsonFile = archive.findFile('notes.json');
    if (jsonFile == null) {
      throw const FormatException('not a Nex export: notes.json is missing');
    }
    final payload =
        jsonDecode(utf8.decode(jsonFile.content as List<int>)) as Map<String, dynamic>;

    for (final raw in (payload['tags'] as List? ?? const [])) {
      final tag = raw as Map<String, dynamic>;
      upsertTagFromSync(
        id: tag['id']! as String,
        name: tag['name']! as String,
        color: tag['color'] as String?,
        createdAt: DateTime.parse(tag['created_at']! as String),
      );
    }

    var imported = 0;
    var skipped = 0;
    for (final raw in (payload['notes'] as List? ?? const [])) {
      final json = raw as Map<String, dynamic>;
      final note = Note.fromRow(json);
      if (db.select('SELECT id FROM notes WHERE id = ?', [note.id]).isNotEmpty) {
        skipped++;
        continue;
      }

      String? mediaUri;
      if (note.mediaUri != null) {
        final name = p.basename(note.mediaUri!);
        final entry = archive.findFile('media/$name');
        if (entry != null) {
          final target = File(p.join(mediaRoot, name));
          target.parent.createSync(recursive: true);
          target.writeAsBytesSync(entry.content as List<int>);
          mediaUri = target.path;
        }
        // No media in the archive: the note still comes in, with its text and
        // its tags. Losing the whole note over a missing attachment would be a
        // worse trade than losing the attachment.
      }

      applyRemoteNote(
        id: note.id,
        type: note.type,
        content: note.content,
        mediaUri: mediaUri,
        mediaHash: note.mediaHash,
        durationMs: note.durationMs,
        createdAt: note.createdAt,
        updatedAt: note.updatedAt,
        deletedAt: note.deletedAt,
        deviceId: note.deviceId,
        rev: note.rev,
        tagIds: [
          for (final tag in (json['tags'] as List? ?? const []))
            (tag as Map<String, dynamic>)['id']! as String,
        ],
      );
      // applyRemoteNote carries no captions, transcripts or summaries — they
      // are not part of the sync wire — so they are written back here.
      _restoreEnrichment(note);
      imported++;
    }
    return ImportResult(imported: imported, skipped: skipped);
  }

  void _restoreEnrichment(Note note) {
    if (note.caption == null &&
        note.transcriptText == null &&
        note.ocrText == null &&
        note.summaryText == null &&
        note.mimeType == null) {
      return;
    }
    db.execute(
      '''
UPDATE notes
SET caption = ?, transcript_text = ?, ocr_text = ?, summary_text = ?,
    mime_type = ?
WHERE id = ?
''',
      [
        note.caption,
        note.transcriptText,
        note.ocrText,
        note.summaryText,
        note.mimeType,
        note.id,
      ],
    );
    final searchable = note.searchableDerivedText;
    if (searchable != null && note.deletedAt == null) {
      _upsertFts(note.id, searchable);
    }
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
    ${localDeviceId != null ? ', device_id = ?' : ''}
WHERE id = ?
''',
      [
        now,
        if (localDeviceId != null) localDeviceId,
        noteId,
      ],
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

  /// Build an FTS5 MATCH query: quote tokens so ZWNJ-split Persian words match,
  /// and make the final token a prefix so results narrow as the user types.
  ///
  /// Every token used to be an exact match, which meant nothing was found until
  /// a whole word had been typed — FR-4.7 requires results to update
  /// incrementally. Only the last token gets `*`: the earlier ones are words the
  /// user finished typing and meant literally, while the trailing one is still
  /// mid-keystroke.
  String _ftsQuery(String raw) {
    final cleaned = raw
        .replaceAll('"', ' ')
        .replaceAll('*', ' ')
        .trim();
    if (cleaned.isEmpty) return '""';
    final tokens = cleaned.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    if (tokens.isEmpty) return '""';
    return [
      for (var i = 0; i < tokens.length; i++)
        i == tokens.length - 1 ? '"${tokens[i]}"*' : '"${tokens[i]}"',
    ].join(' ');
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
        if (note.transcriptText != null) {
          buffer.writeln('Transcript: ${note.transcriptText}');
        }
      case NoteType.photo:
        buffer.writeln('_Photo note_');
        if (note.mediaUri != null) {
          buffer.writeln('![photo](../media/${p.basename(note.mediaUri!)})');
        }
        if (note.ocrText != null) {
          buffer.writeln('OCR: ${note.ocrText}');
        }
      case NoteType.file:
        buffer.writeln('_File attachment_');
        if (note.mediaUri != null) {
          buffer.writeln('File: ${p.basename(note.mediaUri!)}');
        }
    }
    return buffer.toString();
  }
}
