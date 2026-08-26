import 'dart:convert';
import 'dart:io';
import 'dart:math' show Random;

import 'package:archive/archive.dart';
import 'package:nex_core/nex_core.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../schema/backup_archive.dart';
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

final _accentRandom = Random();

/// A random pick off [tagAccentPalette], for a new tag nobody coloured.
String _randomAccent() =>
    tagAccentPalette[_accentRandom.nextInt(tagAccentPalette.length)];

/// Whether a string is a colour a tag may carry: `#RRGGBB`, case-insensitive.
bool isTagAccent(String value) => RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value);

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
  caption, title, link_excerpt, mime_type
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
        note.title,
        note.linkExcerpt,
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
      [content, now, if (localDeviceId != null) localDeviceId, noteId],
    );
    _upsertFts(noteId, content);
  }

  /// Pins [noteId], unpinning whatever else was pinned first — only one note
  /// is ever pinned at a time. Touches only `pinned_at`: this is local
  /// device state, not a change worth pushing to sync.
  void pinNote(String noteId) {
    final now = DateTime.now().toUtc().toIso8601String();
    db.execute('BEGIN IMMEDIATE');
    try {
      db.execute(
        'UPDATE notes SET pinned_at = NULL WHERE pinned_at IS NOT NULL AND id != ?',
        [noteId],
      );
      db.execute('UPDATE notes SET pinned_at = ? WHERE id = ?', [now, noteId]);
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  void unpinNote(String noteId) =>
      db.execute('UPDATE notes SET pinned_at = NULL WHERE id = ?', [noteId]);

  /// The id of the one note currently pinned, if any. Pinning never touches
  /// `updated_at` (see [pinNote]), so the pinned note is not necessarily
  /// inside any timeline page — this is the only reliable way to ask.
  String? pinnedNoteId() {
    final rows = db.select(
      'SELECT id FROM notes WHERE pinned_at IS NOT NULL AND deleted_at IS NULL LIMIT 1',
    );
    return rows.isEmpty ? null : rows.first['id'] as String;
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
      [now, now, if (localDeviceId != null) localDeviceId, noteId],
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
      [now, if (localDeviceId != null) localDeviceId, noteId],
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

  /// Timeline page, most recently touched first (FR-2.2 / FR-2.5).
  ///
  /// Ordered by `updated_at`, not `created_at`: editing a note's content,
  /// caption or tags bumps it, and a note you just changed belongs at the
  /// top of what you are looking at, not wherever it was originally written.
  ///
  /// The pinned note (at most one) always leads. Behind it, notes nobody has
  /// manually placed sort by recency same as ever; notes that *have* been
  /// dragged into place in Rearrange mode follow, in that manual order —
  /// which is why a fresh capture still surfaces at the top instead of
  /// waiting at the bottom of an arrangement it was never part of.
  ///
  /// When [tagId] is set, only notes with that tag are returned (Timeline
  /// filter chips / FR-4).
  @override
  List<Note> listTimeline({int limit = 50, int offset = 0, String? tagId}) {
    // Pinned first, then newest. `sort_order` is deliberately absent: manual
    // arrangement is gone, and the timeline is grouped by date on screen —
    // Today, Yesterday, Last week — which only reads as a history if the rows
    // under each heading actually belong to it. A hand-placed note would drop
    // into whichever group it landed next to and make the heading a lie.
    //
    // The column stays. Dropping it means a migration on every existing
    // database to remove something that now simply goes unread.
    const order = '''
ORDER BY
  (pinned_at IS NOT NULL) DESC,
  updated_at DESC
''';
    final rows = tagId == null
        ? db.select(
            '''
SELECT * FROM notes
WHERE deleted_at IS NULL
$order
LIMIT ? OFFSET ?
''',
            [limit, offset],
          )
        : db.select(
            '''
SELECT n.* FROM notes n
INNER JOIN note_tags nt ON nt.note_id = n.id
WHERE n.deleted_at IS NULL AND nt.tag_id = ?
$order
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
        db.execute(
          "UPDATE tags SET color = ?, sync_state = 'pending' WHERE id = ?",
          [color, id],
        );
      }
      return Tag.fromRow(
        db.select('SELECT * FROM tags WHERE id = ?', [id]).first,
      );
    }
    final tag = Tag(
      id: newUuidV7(),
      name: trimmed,
      // A brand new tag with nobody having picked a colour for it yet still
      // gets one — a random pick off the same starter palette the colour
      // picker offers first — rather than sitting grey until somebody
      // opens the tag manager. `setTagColor` remains the explicit way back
      // to no colour at all.
      color: color ?? _randomAccent(),
      createdAt: DateTime.now().toUtc(),
    );
    db.execute(
      'INSERT INTO tags (id, name, color, created_at) VALUES (?, ?, ?, ?)',
      [tag.id, tag.name, tag.color, tag.createdAt.toUtc().toIso8601String()],
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
    db.execute('DELETE FROM note_tags WHERE note_id = ? AND tag_id = ?', [
      noteId,
      tagId,
    ]);
    _bumpNote(noteId);
  }

  @override
  List<Tag> listTags() {
    final rows = db.select('SELECT * FROM tags ORDER BY name COLLATE NOCASE');
    return rows.map(Tag.fromRow).toList();
  }

  /// Outbox: notes still pending sync (including tombstones).
  List<Note> listPending({bool includeDeleted = false}) {
    final rows = db.select('''
SELECT * FROM notes
WHERE sync_state = 'pending'
ORDER BY updated_at ASC
''');
    return rows
        .map((r) => Note.fromRow(r, tags: tagsForNote(r['id']! as String)))
        .where((n) => includeDeleted || !n.isDeleted)
        .toList();
  }

  /// Clears a note from the outbox, adopting the server's revision.
  ///
  /// [serverRev] is not optional decoration: `rev` is server-authoritative, and
  /// a client that keeps its own number after an accepted write will push a
  /// stale revision next time and have it rejected. Only ever called for ids
  /// the server actually acknowledged — see [SyncClient].
  void markSynced(String noteId, {int? serverRev}) {
    if (serverRev == null) {
      db.execute("UPDATE notes SET sync_state = 'synced' WHERE id = ?", [
        noteId,
      ]);
      return;
    }
    db.execute("UPDATE notes SET sync_state = 'synced', rev = ? WHERE id = ?", [
      serverRev,
      noteId,
    ]);
  }

  /// Outbox: tags still pending sync.
  List<Tag> listPendingTags() {
    final rows = db.select(
      "SELECT * FROM tags WHERE sync_state = 'pending' ORDER BY name COLLATE NOCASE",
    );
    return rows.map(Tag.fromRow).toList();
  }

  void markTagsSynced(Iterable<String> tagIds) {
    for (final id in tagIds) {
      db.execute("UPDATE tags SET sync_state = 'synced' WHERE id = ?", [id]);
    }
  }

  /// Folds this device's tag ids into the ones the server made canonical.
  ///
  /// Tag identity on the server is `(user_id, lower(name))`, because two
  /// devices offline both mint a UUID for `#ideas` and only one can win. The
  /// server reports the outcome as a remap and the client used to throw it
  /// away, so the loser kept its local id forever: every push re-sent it, the
  /// server re-remapped it, and the response was discarded again — a loop that
  /// never converged, with two `#ideas` tags on screen and pulled note↔tag
  /// joins pointing at ids that did not exist locally.
  ///
  /// One transaction, and the losing row goes before the canonical one is
  /// written: `tags.name` is UNIQUE, so the two cannot coexist.
  void applyTagRemap(List<({String clientId, String canonicalId})> pairs) {
    final real = [
      for (final pair in pairs)
        if (pair.clientId != pair.canonicalId) pair,
    ];
    if (real.isEmpty) return;
    db.execute('BEGIN');
    try {
      for (final pair in real) {
        final losing = db.select('SELECT * FROM tags WHERE id = ?', [
          pair.clientId,
        ]);
        if (losing.isEmpty) continue;
        final row = losing.first;

        // Read the joins before touching the tag row. `note_tags.tag_id` is
        // ON DELETE CASCADE, so deleting the losing tag takes its joins with
        // it — repointing them afterwards finds nothing and the notes come out
        // untagged. They have to be carried across by hand.
        final noteIds = [
          for (final join in db.select(
            'SELECT note_id FROM note_tags WHERE tag_id = ?',
            [pair.clientId],
          ))
            join['note_id']! as String,
        ];

        // The losing row goes first: `tags.name` is UNIQUE, so the canonical
        // row cannot take the name while the loser still holds it.
        db.execute('DELETE FROM tags WHERE id = ?', [pair.clientId]);
        final existing = db.select('SELECT id FROM tags WHERE id = ?', [
          pair.canonicalId,
        ]);
        if (existing.isEmpty) {
          db.execute(
            '''
INSERT INTO tags (id, name, color, created_at, sync_state)
VALUES (?, ?, ?, ?, 'synced')
''',
            [pair.canonicalId, row['name'], row['color'], row['created_at']],
          );
        }
        for (final noteId in noteIds) {
          // OR IGNORE: a note already carrying the canonical tag would
          // otherwise violate the composite primary key.
          db.execute(
            'INSERT OR IGNORE INTO note_tags (note_id, tag_id) VALUES (?, ?)',
            [noteId, pair.canonicalId],
          );
        }
      }
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  /// The pull watermark, surviving process restarts.
  ///
  /// It used to live only in a field on the sync client, so even once the
  /// field name was right every cold launch restarted the pull from sequence
  /// zero and re-downloaded the whole corpus.
  String? get syncCursor {
    final rows = db.select(
      "SELECT value FROM nex_meta WHERE key = 'sync_cursor'",
    );
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  set syncCursor(String? value) {
    if (value == null) {
      db.execute("DELETE FROM nex_meta WHERE key = 'sync_cursor'");
      return;
    }
    db.execute(
      "INSERT INTO nex_meta (key, value) VALUES ('sync_cursor', ?) "
      'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
      [value],
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
        "UPDATE tags SET name = ?, color = COALESCE(?, color), "
        "sync_state = 'synced' WHERE id = ?",
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
          '''
INSERT INTO tags (id, name, color, created_at, sync_state)
VALUES (?, ?, ?, ?, 'synced')
''',
          [
            id,
            name,
            color ?? byName.first['color'],
            createdAt.toUtc().toIso8601String(),
          ],
        );
      }
      return Tag.fromRow(
        db.select('SELECT * FROM tags WHERE id = ?', [id]).first,
      );
    }
    // Straight from the server, so it is already in step with it — pushing it
    // back would mint a new sequence and re-broadcast it to every peer.
    db.execute(
      '''
INSERT INTO tags (id, name, color, created_at, sync_state)
VALUES (?, ?, ?, ?, 'synced')
''',
      [id, name, color, createdAt.toUtc().toIso8601String()],
    );
    return Tag.fromRow(
      db.select('SELECT * FROM tags WHERE id = ?', [id]).first,
    );
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
    if (type == NoteType.text &&
        content != null &&
        content.isNotEmpty &&
        deletedAt == null) {
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
    db.execute(
      "UPDATE tags SET color = ?, sync_state = 'pending' WHERE id = ?",
      [color, tagId],
    );
  }

  /// Persist AI transcript alongside the voice note (09-ai.md — non-destructive).
  @override
  void setTranscriptText(String noteId, String text) {
    db.execute('UPDATE notes SET transcript_text = ? WHERE id = ?', [
      text,
      noteId,
    ]);
    if (text.isNotEmpty) _upsertFts(noteId, text);
  }

  /// Persist AI OCR text alongside the photo note.
  @override
  void setOcrText(String noteId, String text) {
    db.execute('UPDATE notes SET ocr_text = ? WHERE id = ?', [text, noteId]);
    if (text.isNotEmpty) _upsertFts(noteId, text);
  }

  @override
  void setSummaryText(String noteId, String text) {
    db.execute('UPDATE notes SET summary_text = ? WHERE id = ?', [
      text,
      noteId,
    ]);
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
      [value, now, if (localDeviceId != null) localDeviceId, noteId],
    );
    final note = getById(noteId);
    final searchable = note?.searchableDerivedText;
    if (searchable != null && searchable.isNotEmpty) {
      _upsertFts(noteId, searchable);
    } else if (note?.type != NoteType.text) {
      db.execute('DELETE FROM notes_fts WHERE note_id = ?', [noteId]);
    }
  }

  /// The note's optional headline. Empty clears it, so the same control both
  /// names a note and un-names it.
  void setTitle(String noteId, String? title) {
    final now = DateTime.now().toUtc().toIso8601String();
    final trimmed = title?.trim();
    final value = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    db.execute(
      '''
UPDATE notes
SET title = ?, updated_at = ?, rev = rev + 1, sync_state = 'pending'
    ${localDeviceId != null ? ', device_id = ?' : ''}
WHERE id = ? AND deleted_at IS NULL
''',
      [value, now, if (localDeviceId != null) localDeviceId, noteId],
    );
    _reindex(noteId);
  }

  /// A link note's fetched metadata, written together because they arrive
  /// together and either both apply or neither does.
  ///
  /// Not a user edit: the revision is bumped so the change syncs, but a null
  /// argument leaves that field alone rather than clearing it — a page that
  /// stops answering should not erase what was read from it the first time.
  void setLinkMetadata(String noteId, {String? title, String? excerpt}) {
    if (title == null && excerpt == null) return;
    final now = DateTime.now().toUtc().toIso8601String();
    db.execute(
      '''
UPDATE notes
SET title = COALESCE(?, title),
    link_excerpt = COALESCE(?, link_excerpt),
    updated_at = ?, rev = rev + 1, sync_state = 'pending'
WHERE id = ? AND deleted_at IS NULL
''',
      [title?.trim(), excerpt?.trim(), now, noteId],
    );
    _reindex(noteId);
  }

  /// Ticks or unticks one line of a checklist, by position.
  ///
  /// Read-modify-write on the note's own `content`, which is where a
  /// checklist's items live (see `models/checklist.dart`) — so this rides the
  /// same revision, sync and search machinery as editing any other note body,
  /// with nothing checklist-shaped in the storage layer at all.
  ///
  /// Silently does nothing for an index that is no longer there: a stale tap
  /// from a list that changed underneath is not an error worth surfacing.
  void toggleChecklistItem(String noteId, int index) {
    final note = getById(noteId);
    if (note == null || note.type != NoteType.checklist) return;
    final items = [...note.checklistItems];
    if (index < 0 || index >= items.length) return;
    items[index] = items[index].toggled();
    updateContent(noteId, formatChecklist(items));
  }

  /// Re-derives this note's search row from whatever it now holds.
  void _reindex(String noteId) {
    final note = getById(noteId);
    final searchable = note?.searchableDerivedText;
    if (searchable != null && searchable.isNotEmpty) {
      _upsertFts(noteId, searchable);
    } else {
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
  void setDueAt(
    String noteId,
    DateTime? when, {
    NoteRepeat repeat = NoteRepeat.once,
  }) {
    db.execute(
      // Not a rev bump and not an updated_at touch: a reminder is a thing
      // the user asked the app to do, not an edit to what the note says, and
      // re-sorting the timeline because someone set an alarm would move a
      // note they were not writing to.
      'UPDATE notes SET due_at = ?, due_repeat = ? WHERE id = ?',
      [
        when?.toUtc().toIso8601String(),
        // Cleared alongside the time. A repeat left behind on a note with no
        // reminder is a rule with nothing to apply to, and it would come back
        // the next time one was set.
        when == null ? null : repeat.wireName,
        noteId,
      ],
    );
  }

  @override
  List<Note> listUpcomingReminders({int limit = 200}) {
    final rows = db.select(
      '''
SELECT * FROM notes
WHERE deleted_at IS NULL AND due_at IS NOT NULL AND due_at > ?
ORDER BY due_at ASC
LIMIT ?
''',
      [DateTime.now().toUtc().toIso8601String(), limit],
    );
    return rows
        .map((r) => Note.fromRow(r, tags: tagsForNote(r['id']! as String)))
        .toList();
  }

  @override
  List<Note> listNeedingEmbedding({int limit = 25}) {
    // Anything with words in it: a note's own text, a caption, a transcript,
    // an OCR read, or a link's headline. A photo with nothing derived from it
    // yet is excluded rather than embedded as an empty string — it will come
    // back round once enrichment has read it.
    final rows = db.select(
      '''
SELECT n.* FROM notes n
LEFT JOIN note_embeddings e ON e.note_id = n.id
WHERE n.deleted_at IS NULL
  AND e.note_id IS NULL
  AND (
    COALESCE(TRIM(n.content), '') <> ''
    OR COALESCE(TRIM(n.transcript_text), '') <> ''
    OR COALESCE(TRIM(n.ocr_text), '') <> ''
    OR COALESCE(TRIM(n.title), '') <> ''
  )
ORDER BY n.created_at DESC
LIMIT ?
''',
      [limit],
    );
    return rows
        .map((r) => Note.fromRow(r, tags: tagsForNote(r['id']! as String)))
        .toList();
  }

  @override
  List<NoteEmbedding> listEmbeddings() {
    final rows = db.select('SELECT note_id, values_json FROM note_embeddings');
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

    final sql =
        '''
SELECT n.* FROM notes n
WHERE ${where.join(' AND ')}
ORDER BY n.created_at DESC
''';
    final rows = db.select(sql, args);
    return rows
        .map((r) => Note.fromRow(r, tags: tagsForNote(r['id']! as String)))
        .toList();
  }

  @override
  List<Note> listNeedingEnrichment({int limit = 50}) {
    // Only media whose text was never derived. A text note is already its own
    // text, and a summary that came back empty is a legitimate answer — asking
    // again on every pass would spend a request to learn the same thing.
    final rows = db.select(
      '''
SELECT * FROM notes
WHERE deleted_at IS NULL
  AND media_uri IS NOT NULL
  AND (
    (type = 'voice' AND transcript_text IS NULL)
    OR (type = 'photo' AND ocr_text IS NULL)
  )
ORDER BY created_at DESC
LIMIT ?
''',
      [limit],
    );
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
        jsonDecode(utf8.decode(jsonFile.content as List<int>))
            as Map<String, dynamic>;

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
      if (db.select('SELECT id FROM notes WHERE id = ?', [
        note.id,
      ]).isNotEmpty) {
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
      // applyRemoteNote carries no captions, transcripts, summaries, titles
      // or link excerpts — none of them are part of the sync wire — so they
      // are written back here.
      //
      // Titles and link excerpts are on that list deliberately, alongside the
      // caption they most resemble. What *does* cross the wire is `content`,
      // which is where a checklist keeps its items and a link keeps its URL —
      // so both of those new types sync as completely as a text note does,
      // and it is only the annotation on top that stays local until the wire
      // grows a field for it.
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
        note.title == null &&
        note.linkExcerpt == null &&
        note.mimeType == null) {
      return;
    }
    db.execute(
      '''
UPDATE notes
SET caption = ?, transcript_text = ?, ocr_text = ?, summary_text = ?,
    title = ?, link_excerpt = ?, mime_type = ?
WHERE id = ?
''',
      [
        note.caption,
        note.transcriptText,
        note.ocrText,
        note.summaryText,
        note.title,
        note.linkExcerpt,
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

  /// Writes a complete backup — the database and every media file.
  ///
  /// [mediaDir] is required rather than optional: making it optional is how
  /// the media came to be left out of a backup in the first place, and a
  /// caller that genuinely has no media can pass a directory that does not
  /// exist.
  File backup(String backupDir, {required String mediaDir}) =>
      NexBackupArchive.create(
        database: _db,
        mediaDir: mediaDir,
        backupDir: backupDir,
      );

  void _bumpNote(String noteId) {
    final now = DateTime.now().toUtc().toIso8601String();
    db.execute(
      '''
UPDATE notes
SET updated_at = ?, rev = rev + 1, sync_state = 'pending'
    ${localDeviceId != null ? ', device_id = ?' : ''}
WHERE id = ?
''',
      [now, if (localDeviceId != null) localDeviceId, noteId],
    );
  }

  void _upsertFts(String noteId, String content) {
    db.execute('DELETE FROM notes_fts WHERE note_id = ?', [noteId]);
    if (content.isEmpty) return;
    db.execute('INSERT INTO notes_fts (note_id, content) VALUES (?, ?)', [
      noteId,
      content,
    ]);
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
    final cleaned = raw.replaceAll('"', ' ').replaceAll('*', ' ').trim();
    if (cleaned.isEmpty) return '""';
    final tokens = cleaned
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
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
      ..writeln('tags: [${note.tags.map((t) => t.name).join(', ')}]')
      ..writeln('---')
      ..writeln();
    // As a heading rather than another frontmatter key: a title is the one
    // piece of this the reader of an exported file is meant to see.
    if (note.title != null) {
      buffer
        ..writeln('# ${note.title}')
        ..writeln();
    }
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
      // Written out as the markdown task list it already is, so an exported
      // checklist opens as a working checklist in any markdown editor rather
      // than as a description of one.
      case NoteType.checklist:
        buffer.writeln(note.content ?? '');
      case NoteType.link:
        final url = note.linkUrl;
        if (url != null) buffer.writeln('<$url>');
        if (note.linkExcerpt != null) {
          buffer
            ..writeln()
            ..writeln(note.linkExcerpt);
        }
        if (note.summaryText != null) {
          buffer
            ..writeln()
            ..writeln('Summary: ${note.summaryText}');
        }
    }
    return buffer.toString();
  }
}
