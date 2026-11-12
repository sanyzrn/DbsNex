import 'dart:convert';

import 'package:nex_core/nex_core.dart';
import 'package:sqlite3/sqlite3.dart';

import '../schema/database.dart';
import '../schema/write_lock.dart';
import 'note_repository.dart';

/// Notes written now and delivered later — see [ScheduledNote].
///
/// The capture sheet saves on the first keystroke, so by the time someone
/// holds Send to schedule what they wrote, it is already a note. [schedule]
/// takes it back out of the library — the row, its search entry, its tags
/// and embedding by cascade — and keeps the words here; [releaseDue] puts
/// them back as a new note under the same id once the time has come. Both
/// are one transaction each, so a note is always in exactly one place.
///
/// What waits is the whole note, not just its body. A title, the text a
/// model read out of it and the tags it was filed under are kept in
/// [metadata] and [tag_ids] and put back on arrival. They used to be
/// dropped with the row: the note came back looking right — it had its
/// words — while everything else about it had silently gone. The reminder
/// is the one thing deliberately not carried: it was an alarm on a note
/// that is not in the library, and the service cancels it when the note is
/// scheduled.
class SqliteScheduledNoteRepository {
  SqliteScheduledNoteRepository(this._db, this._notes);

  final NexDatabase _db;
  final SqliteNoteRepository _notes;

  Database get db => _db.db;

  /// The note columns worth carrying across the wait. Everything derived
  /// from the words is here because the words do not change while it waits;
  /// `due_at` is not, by design (see the class comment).
  static const _preservedColumns = [
    'title',
    'caption',
    'summary_text',
    'ocr_text',
    'transcript_text',
    'link_excerpt',
    'mime_type',
    'is_urgent',
  ];

  /// Moves the live text note [noteId] out of the library until
  /// [releaseAt]. Null when there is no such note, or it is not text.
  ///
  /// Also null when the note carries attachments. A file cannot wait in the
  /// scheduled table, and deleting the note row would cascade its attachment
  /// rows away and hand the files to the orphan sweep — the note would come
  /// back without its photos and nothing would say so. Refusing is the only
  /// answer that does not lose them until files can wait too.
  ScheduledNote? schedule(String noteId, DateTime releaseAt) => db.together(() {
    final rows = db.select(
      "SELECT * FROM notes "
      "WHERE id = ? AND deleted_at IS NULL AND type = 'text'",
      [noteId],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    final content = row['content'] as String? ?? '';
    if (content.trim().isEmpty) return null;
    final attached = db.select(
      'SELECT 1 FROM note_attachments '
      'WHERE note_id = ? AND deleted_at IS NULL LIMIT 1',
      [noteId],
    );
    if (attached.isNotEmpty) return null;
    final scheduled = ScheduledNote(
      id: noteId,
      content: content,
      releaseAt: releaseAt.toUtc(),
      writtenAt: DateTime.parse(row['created_at'] as String),
    );
    db.execute(
      'INSERT OR REPLACE INTO scheduled_notes '
      '(id, content, release_at, written_at, metadata, tag_ids) '
      'VALUES (?, ?, ?, ?, ?, ?)',
      [
        scheduled.id,
        scheduled.content,
        scheduled.releaseAt.toIso8601String(),
        scheduled.writtenAt.toUtc().toIso8601String(),
        jsonEncode({
          for (final column in _preservedColumns)
            if (row[column] != null) column: row[column],
        }),
        jsonEncode([
          for (final tag in db.select(
            'SELECT tag_id FROM note_tags WHERE note_id = ? ORDER BY rowid',
            [noteId],
          ))
            tag['tag_id'] as String,
        ]),
      ],
    );
    // Gone, not deleted: a soft delete would put the words in the trash,
    // which is one more place to read them before their time. The search row
    // goes by the note's rowid key, while the note row still exists below —
    // a `note_id` delete here scanned the whole index to find the one row.
    _notes.deleteSearchRow(noteId);
    db.execute('DELETE FROM capture_receipts WHERE note_id = ?', [noteId]);
    db.execute('DELETE FROM notes WHERE id = ?', [noteId]);
    return scheduled;
  });

  /// Everything waiting, the soonest first.
  List<ScheduledNote> pending() => [
    for (final row in db.select(
      'SELECT * FROM scheduled_notes ORDER BY release_at, id',
    ))
      _fromRow(row),
  ];

  /// Puts every note whose time has come on the timeline, and returns them.
  ///
  /// Each arrives stamped with its delivery time rather than the moment the
  /// app happened to notice, so a phone that was off at nine still files
  /// nine o'clock's note at nine.
  List<Note> releaseDue(DateTime now) => db.together(() {
    final rows = db.select(
      'SELECT * FROM scheduled_notes WHERE release_at <= ? '
      'ORDER BY release_at, id',
      [now.toUtc().toIso8601String()],
    );
    return [for (final row in rows) _release(_fromRow(row))];
  });

  /// Delivers [id] now, whatever its time. Null when it is not waiting.
  Note? releaseNow(String id, DateTime now) => db.together(() {
    final rows = db.select('SELECT * FROM scheduled_notes WHERE id = ?', [id]);
    if (rows.isEmpty) return null;
    final scheduled = _fromRow(rows.first);
    return _release(
      ScheduledNote(
        id: scheduled.id,
        content: scheduled.content,
        releaseAt: now.toUtc(),
        writtenAt: scheduled.writtenAt,
      ),
    );
  });

  /// Moves [id] to [releaseAt]. False when it is no longer waiting.
  bool reschedule(String id, DateTime releaseAt) {
    db.execute('UPDATE scheduled_notes SET release_at = ? WHERE id = ?', [
      releaseAt.toUtc().toIso8601String(),
      id,
    ]);
    return db.updatedRows > 0;
  }

  /// Throws [id] away for good. It was never in the library, so there is no
  /// trash for it to go to.
  void discard(String id) =>
      db.execute('DELETE FROM scheduled_notes WHERE id = ?', [id]);

  Note _release(ScheduledNote scheduled) {
    // The row is read before it is deleted: it holds what the words alone do
    // not — title, derived text, urgency and tag ids.
    final rows = db.select('SELECT * FROM scheduled_notes WHERE id = ?', [
      scheduled.id,
    ]);
    final waiting = rows.isEmpty ? null : rows.first;
    db.execute('DELETE FROM scheduled_notes WHERE id = ?', [scheduled.id]);
    // The same id cannot be live already — [schedule] removed it — but a
    // restored backup can hold both; the library's copy wins.
    final existing = _notes.getById(scheduled.id, includeDeleted: true);
    if (existing != null) return existing;
    final metadata = _metadata(waiting?['metadata']);
    final note = _notes.insert(
      Note(
        id: scheduled.id,
        type: NoteType.text,
        content: scheduled.content,
        title: _text(metadata, 'title'),
        caption: _text(metadata, 'caption'),
        summaryText: _text(metadata, 'summary_text'),
        ocrText: _text(metadata, 'ocr_text'),
        transcriptText: _text(metadata, 'transcript_text'),
        linkExcerpt: _text(metadata, 'link_excerpt'),
        mimeType: _text(metadata, 'mime_type'),
        isUrgent: metadata['is_urgent'] == 1,
        createdAt: scheduled.releaseAt,
        updatedAt: scheduled.releaseAt,
        deviceId: _notes.localDeviceId ?? '',
        rev: 1,
        syncState: SyncState.pending,
      ),
    );
    _restoreTags(note.id, _tagIds(waiting?['tag_ids']));
    return _notes.getById(note.id)!;
  }

  /// Puts back the tags that still exist. A tag deleted while the note was
  /// waiting is gone for good, which is what deleting it meant.
  void _restoreTags(String noteId, List<String> tagIds) {
    for (final tagId in tagIds) {
      db.execute(
        'INSERT OR IGNORE INTO note_tags (note_id, tag_id) '
        'SELECT ?, id FROM tags WHERE id = ?',
        [noteId, tagId],
      );
    }
  }

  /// Parsed defensively: a row written by a build without these columns, or
  /// a damaged backup, must still deliver the words rather than throw the
  /// note away.
  static Map<String, Object?> _metadata(Object? raw) {
    if (raw is! String || raw.isEmpty) return const {};
    try {
      final value = jsonDecode(raw);
      return value is Map ? Map<String, Object?>.from(value) : const {};
    } on FormatException {
      return const {};
    }
  }

  static List<String> _tagIds(Object? raw) {
    if (raw is! String || raw.isEmpty) return const [];
    try {
      final value = jsonDecode(raw);
      return value is List ? value.whereType<String>().toList() : const [];
    } on FormatException {
      return const [];
    }
  }

  static String? _text(Map<String, Object?> metadata, String key) {
    final value = metadata[key];
    return value is String ? value : null;
  }

  static ScheduledNote _fromRow(Row row) => ScheduledNote(
    id: row['id'] as String,
    content: row['content'] as String,
    releaseAt: DateTime.parse(row['release_at'] as String),
    writtenAt: DateTime.parse(row['written_at'] as String),
  );
}
