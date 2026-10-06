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
class SqliteScheduledNoteRepository {
  SqliteScheduledNoteRepository(this._db, this._notes);

  final NexDatabase _db;
  final SqliteNoteRepository _notes;

  Database get db => _db.db;

  /// Moves the live text note [noteId] out of the library until
  /// [releaseAt]. Null when there is no such note, or it is not text.
  ScheduledNote? schedule(String noteId, DateTime releaseAt) => db.together(() {
    final rows = db.select(
      "SELECT content, created_at FROM notes "
      "WHERE id = ? AND deleted_at IS NULL AND type = 'text'",
      [noteId],
    );
    if (rows.isEmpty) return null;
    final content = rows.first['content'] as String? ?? '';
    if (content.trim().isEmpty) return null;
    final scheduled = ScheduledNote(
      id: noteId,
      content: content,
      releaseAt: releaseAt.toUtc(),
      writtenAt: DateTime.parse(rows.first['created_at'] as String),
    );
    db.execute(
      'INSERT OR REPLACE INTO scheduled_notes '
      '(id, content, release_at, written_at) VALUES (?, ?, ?, ?)',
      [
        scheduled.id,
        scheduled.content,
        scheduled.releaseAt.toIso8601String(),
        scheduled.writtenAt.toUtc().toIso8601String(),
      ],
    );
    // Gone, not deleted: a soft delete would put the words in the trash,
    // which is one more place to read them before their time.
    db.execute('DELETE FROM notes_fts WHERE note_id = ?', [noteId]);
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
    db.execute('DELETE FROM scheduled_notes WHERE id = ?', [scheduled.id]);
    // The same id cannot be live already — [schedule] removed it — but a
    // restored backup can hold both; the library's copy wins.
    final existing = _notes.getById(scheduled.id, includeDeleted: true);
    if (existing != null) return existing;
    return _notes.insert(
      Note(
        id: scheduled.id,
        type: NoteType.text,
        content: scheduled.content,
        createdAt: scheduled.releaseAt,
        updatedAt: scheduled.releaseAt,
        deviceId: _notes.localDeviceId ?? '',
        rev: 1,
        syncState: SyncState.pending,
      ),
    );
  }

  static ScheduledNote _fromRow(Row row) => ScheduledNote(
    id: row['id'] as String,
    content: row['content'] as String,
    releaseAt: DateTime.parse(row['release_at'] as String),
    writtenAt: DateTime.parse(row['written_at'] as String),
  );
}
