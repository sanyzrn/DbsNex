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
/// takes it out of every view — timeline, search, shelves, the brief — by
/// setting the note's `scheduled_until` and dropping its search row;
/// [releaseDue] delivers it at its time, stamped with the moment it was due
/// rather than the moment this device happened to notice. Both are one
/// transaction each, so a note is always in exactly one state.
///
/// The row itself never leaves the library. It used to be deleted outright,
/// which is the one thing this design exists to correct: a row deleted
/// without a tombstone is a row the next sync pull puts back — the note
/// stopped waiting the moment any sync ran, arrived twice, and lost its
/// held-back content to the copy the server still had. Waiting is now an
/// arrangement of a live row — the same shape as set-aside, local to this
/// device, carried by every backup and never at odds with sync. Its
/// *arrival* is a real edit (new timestamps, rev, outbox), so it travels to
/// every peer and re-files itself under its own day there.
///
/// Waiting rows written by the older design — the note deleted, its words
/// kept in the `scheduled_notes` table — are still delivered by that table,
/// through the release path they were written for. That population only
/// shrinks, and nothing new joins it.
///
/// The reminder is the one thing deliberately not carried by any of this: it
/// was an alarm on a note that is not arriving, and the service cancels it
/// when the note is scheduled.
class SqliteScheduledNoteRepository {
  SqliteScheduledNoteRepository(this._db, this._notes);

  final NexDatabase _db;
  final SqliteNoteRepository _notes;

  Database get db => _db.db;

  /// Takes the live text note [noteId] out of every view until [releaseAt].
  /// Null when there is no such note, it is not text, its words are empty, or
  /// it carries attachments — a file cannot be hidden half-way, and removing
  /// the note row (as the old design did) would hand the files to the orphan
  /// sweep; refusing is still the only answer that does not lose them.
  ScheduledNote? schedule(String noteId, DateTime releaseAt) => db.together(() {
    final rows = db.select(
      "SELECT * FROM notes "
      "WHERE id = ? AND deleted_at IS NULL AND scheduled_until IS NULL "
      "AND type = 'text'",
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
    // An arrangement, not an edit: no rev, no outbox, no `updated_at` — the
    // note has not said anything different, and which of *this device's*
    // views hide it is nobody else's business, the same reasoning set-aside
    // is written under. The reminder and the pin go with it: an alarm on a
    // note that is not arriving is a surprise later, and a hidden note must
    // not hold one of the five slots on a home it is not on.
    db.execute(
      'UPDATE notes SET scheduled_until = ?, due_at = NULL, due_repeat = NULL, '
      'reminder_acked_at = NULL, pinned_at = NULL WHERE id = ?',
      [scheduled.releaseAt.toIso8601String(), noteId],
    );
    // Hidden from search the way it is hidden from the timeline: the index
    // row goes now and is re-derived from the whole note on arrival, so a
    // checklist, a title or a link excerpt becomes findable again the day
    // it becomes visible again.
    _notes.deleteSearchRow(noteId);
    return scheduled;
  });

  /// Everything waiting, the soonest first — both kinds: notes hidden by
  /// their own row's flag, and the older table's rows.
  List<ScheduledNote> pending() {
    final waiting =
        <ScheduledNote>[
          for (final row in db.select('SELECT * FROM scheduled_notes'))
            _fromRow(row),
          for (final row in db.select(
            'SELECT id, content, created_at, scheduled_until FROM notes '
            'WHERE scheduled_until IS NOT NULL AND deleted_at IS NULL',
          ))
            ScheduledNote(
              id: row['id']! as String,
              content: row['content'] as String? ?? '',
              releaseAt: DateTime.parse(row['scheduled_until']! as String),
              writtenAt: DateTime.parse(row['created_at']! as String),
            ),
        ]..sort((a, b) {
          final byTime = a.releaseAt.compareTo(b.releaseAt);
          if (byTime != 0) return byTime;
          return a.id.compareTo(b.id);
        });
    return waiting;
  }

  /// Puts every note whose time has come on the timeline, and returns them.
  ///
  /// Each arrives stamped with its delivery time rather than the moment the
  /// app happened to notice, so a phone that was off at nine still files
  /// nine o'clock's note at nine.
  List<Note> releaseDue(DateTime now) => db.together(() {
    final arrived = [
      for (final row in db.select(
        'SELECT * FROM scheduled_notes WHERE release_at <= ? '
        'ORDER BY release_at, id',
        [now.toUtc().toIso8601String()],
      ))
        _release(_fromRow(row)),
    ];
    for (final row in db.select(
      'SELECT id, scheduled_until FROM notes '
      'WHERE scheduled_until IS NOT NULL AND scheduled_until <= ? '
      'AND deleted_at IS NULL ORDER BY scheduled_until, id',
      [now.toUtc().toIso8601String()],
    )) {
      final note = _notes.releaseWaiting(
        row['id']! as String,
        DateTime.parse(row['scheduled_until']! as String),
      );
      if (note != null) arrived.add(note);
    }
    return arrived;
  });

  /// Delivers [id] now, whatever its time. Null when it is not waiting.
  Note? releaseNow(String id, DateTime now) => db.together(() {
    final rows = db.select('SELECT * FROM scheduled_notes WHERE id = ?', [id]);
    if (rows.isNotEmpty) {
      final scheduled = _fromRow(rows.first);
      return _release(
        ScheduledNote(
          id: scheduled.id,
          content: scheduled.content,
          releaseAt: now.toUtc(),
          writtenAt: scheduled.writtenAt,
        ),
      );
    }
    return _notes.releaseWaiting(id, now.toUtc());
  });

  /// Moves [id] to [releaseAt]. False when it is no longer waiting.
  bool reschedule(String id, DateTime releaseAt) {
    db.execute(
      'UPDATE notes SET scheduled_until = ? '
      'WHERE id = ? AND scheduled_until IS NOT NULL AND deleted_at IS NULL',
      [releaseAt.toUtc().toIso8601String(), id],
    );
    if (db.updatedRows > 0) return true;
    db.execute('UPDATE scheduled_notes SET release_at = ? WHERE id = ?', [
      releaseAt.toUtc().toIso8601String(),
      id,
    ]);
    return db.updatedRows > 0;
  }

  /// Throws [id] away for good.
  ///
  /// A note waiting by its own row is a live note, and it goes the way every
  /// live note goes — deleted, in the trash, undoable until the retention
  /// sweep takes it — rather than vanishing without a trace the way the old
  /// design's hard delete vanished it. The old table's row is still removed
  /// outright, its note row having gone with it years ago.
  void discard(String id) => db.together(() {
    db.execute('DELETE FROM scheduled_notes WHERE id = ?', [id]);
    _notes.softDelete(id);
    // The flag goes with the note: a discarded note is deleted, and no query
    // should be able to find it waiting underneath its tombstone.
    db.execute('UPDATE notes SET scheduled_until = NULL WHERE id = ?', [id]);
  });

  Note _release(ScheduledNote scheduled) {
    // The row is read before it is deleted: it holds what the words alone do
    // not — title, derived text, urgency and tag ids.
    final rows = db.select('SELECT * FROM scheduled_notes WHERE id = ?', [
      scheduled.id,
    ]);
    final waiting = rows.isEmpty ? null : rows.first;
    db.execute('DELETE FROM scheduled_notes WHERE id = ?', [scheduled.id]);
    // The same id cannot be live already — the old design removed the row
    // when it took the note out — but a restored backup can hold both; the
    // library's copy wins.
    final existing = _notes.getById(scheduled.id, includeDeleted: true);
    if (existing != null && existing.deletedAt == null) return existing;
    if (existing != null) {
      // A tombstone with the same id — the backup held the note's own words,
      // which are the words the waiting copy was made of. The row comes back
      // from the dead rather than being duplicated beside its own ghost.
      _notes.undelete(scheduled.id);
      return _notes.getById(scheduled.id)!;
    }
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
