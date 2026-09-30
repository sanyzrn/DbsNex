import 'package:nex_core/nex_core.dart';
import 'package:sqlite3/sqlite3.dart';

import '../schema/database.dart';
import '../schema/write_lock.dart';
import 'note_repository.dart';

/// SQLite storage for threads — see [NoteThread] for what one is and is not.
///
/// Synchronous, like every repository here; it runs inside the database
/// worker's isolate. A thread never owns a note: every read joins through the
/// membership table and filters deleted notes out at read time, so deleting,
/// restoring or purging a note needs nothing from this class.
class SqliteThreadRepository {
  SqliteThreadRepository(this._db, this._notes, {this.localDeviceId});

  final NexDatabase _db;
  final SqliteNoteRepository _notes;
  final String? localDeviceId;

  Database get db => _db.db;

  static String _now() => DateTime.now().toUtc().toIso8601String();

  /// Every live thread, the most recently active first.
  List<NoteThread> list() {
    final rows = db.select('''
SELECT t.*,
  (SELECT COUNT(*) FROM note_threads nt JOIN notes n ON n.id = nt.note_id
     WHERE nt.thread_id = t.id AND n.deleted_at IS NULL) AS note_count,
  (SELECT MAX(n.created_at) FROM note_threads nt JOIN notes n ON n.id = nt.note_id
     WHERE nt.thread_id = t.id AND n.deleted_at IS NULL) AS last_activity
FROM threads t
WHERE t.deleted_at IS NULL
ORDER BY COALESCE(last_activity, t.updated_at) DESC, t.rowid DESC
''');
    return [for (final row in rows) _fromRow(row)];
  }

  NoteThread? getById(String id) =>
      list().where((thread) => thread.id == id).firstOrNull;

  /// The live threads [noteId] is in, by name.
  List<NoteThread> forNote(String noteId) {
    final ids = {
      for (final row in db.select(
        'SELECT thread_id FROM note_threads WHERE note_id = ?',
        [noteId],
      ))
        row['thread_id'] as String,
    };
    return [
      for (final thread in list())
        if (ids.contains(thread.id)) thread,
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  /// The live notes in [threadId], oldest first: a thread reads as a story.
  List<Note> notes(String threadId) {
    final rows = db.select(
      '''
SELECT n.* FROM notes n
JOIN note_threads nt ON nt.note_id = n.id
WHERE nt.thread_id = ? AND n.deleted_at IS NULL
ORDER BY n.created_at ASC, n.rowid ASC
''',
      [threadId],
    );
    return [
      for (final row in rows)
        Note.fromRow(row, tags: _notes.tagsForNote(row['id'] as String)),
    ];
  }

  /// A new thread named [name], holding [noteIds].
  NoteThread create(String name, {List<String> noteIds = const []}) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError('A thread needs a name');
    final id = newUuidV7();
    final now = _now();
    db.beginImmediate();
    try {
      db.execute(
        'INSERT INTO threads (id, name, created_at, updated_at, device_id) '
        'VALUES (?, ?, ?, ?, ?)',
        [id, trimmed, now, now, localDeviceId ?? ''],
      );
      for (final noteId in noteIds) {
        _add(id, noteId, now);
      }
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
    return getById(id)!;
  }

  void rename(String id, String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError('A thread needs a name');
    db.execute(
      'UPDATE threads SET name = ?, updated_at = ?, rev = rev + 1 '
      'WHERE id = ? AND deleted_at IS NULL',
      [trimmed, _now(), id],
    );
  }

  /// Deletes the thread. Its notes are untouched: they were never in it.
  void delete(String id) {
    final now = _now();
    db.execute(
      'UPDATE threads SET deleted_at = ?, updated_at = ?, rev = rev + 1 '
      'WHERE id = ? AND deleted_at IS NULL',
      [now, now, id],
    );
  }

  void add(String threadId, String noteId) => _add(threadId, noteId, _now());

  void _add(String threadId, String noteId, String now) {
    db.execute(
      'INSERT OR IGNORE INTO note_threads (note_id, thread_id, added_at) '
      'VALUES (?, ?, ?)',
      [noteId, threadId, now],
    );
    db.execute(
      'UPDATE threads SET updated_at = ?, rev = rev + 1 WHERE id = ?',
      [now, threadId],
    );
  }

  void remove(String threadId, String noteId) {
    db.execute('DELETE FROM note_threads WHERE note_id = ? AND thread_id = ?', [
      noteId,
      threadId,
    ]);
  }

  /// How far back a note is looked for when a new one might continue it.
  static const lookback = Duration(days: 45);

  /// How many recent notes are compared, at most.
  static const lookbackLimit = 400;

  /// Whether [noteId] clearly continues a thread, or an earlier note that
  /// could start one. Null — which is most of the time — when nothing is
  /// clear enough to be worth interrupting anybody with.
  ThreadSuggestion? suggest(String noteId) {
    final note = _notes.getById(noteId);
    if (note == null) return null;
    final words = ThreadAffinity.wordsOf(note);
    final since = note.createdAt.toUtc().subtract(lookback).toIso8601String();
    final rows = db.select(
      '''
SELECT * FROM notes
WHERE deleted_at IS NULL AND id != ? AND created_at >= ?
ORDER BY created_at DESC
LIMIT ?
''',
      [noteId, since, lookbackLimit],
    );
    if (rows.isEmpty) return null;

    final memberships = <String, Set<String>>{};
    for (final row in db.select(
      'SELECT nt.note_id, nt.thread_id FROM note_threads nt '
      'JOIN threads t ON t.id = nt.thread_id WHERE t.deleted_at IS NULL',
    )) {
      memberships
          .putIfAbsent(row['note_id'] as String, () => {})
          .add(row['thread_id'] as String);
    }
    final alreadyIn = memberships[noteId] ?? const <String>{};

    final threadScores = <String, double>{};
    Note? bestLoose;
    var bestLooseScore = 0.0;
    for (final row in rows) {
      final other = Note.fromRow(
        row,
        tags: _notes.tagsForNote(row['id'] as String),
      );
      final score = ThreadAffinity.score(note, other, wordsA: words);
      if (score <= 0) continue;
      final threads = memberships[other.id];
      if (threads == null || threads.isEmpty) {
        if (score > bestLooseScore) {
          bestLooseScore = score;
          bestLoose = other;
        }
        continue;
      }
      for (final threadId in threads) {
        if (alreadyIn.contains(threadId)) continue;
        if (score > (threadScores[threadId] ?? 0)) {
          threadScores[threadId] = score;
        }
      }
    }

    final best = threadScores.entries
        .where((entry) => entry.value >= ThreadAffinity.joinScore)
        .fold<MapEntry<String, double>?>(
          null,
          (best, entry) =>
              best == null || entry.value > best.value ? entry : best,
        );
    if (best != null) {
      final thread = getById(best.key);
      if (thread != null) return ThreadSuggestion.join(thread: thread);
    }
    final loose = bestLoose;
    if (loose != null &&
        alreadyIn.isEmpty &&
        bestLooseScore >= ThreadAffinity.startScore) {
      final name = ThreadAffinity.nameFrom(loose);
      if (name.isNotEmpty) {
        return ThreadSuggestion.start(withNoteId: loose.id, name: name);
      }
    }
    return null;
  }

  NoteThread _fromRow(Row row) => NoteThread(
    id: row['id'] as String,
    name: row['name'] as String,
    createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
    updatedAt: DateTime.parse(row['updated_at'] as String).toLocal(),
    noteCount: (row['note_count'] as int?) ?? 0,
    lastActivityAt: switch (row['last_activity']) {
      final String at => DateTime.parse(at).toLocal(),
      _ => null,
    },
  );
}
