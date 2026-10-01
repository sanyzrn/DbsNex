import 'dart:io' show sleep;

import 'package:sqlite3/sqlite3.dart';

/// Opens every write transaction in the library.
///
/// The share window and the main app hold separate connections to the same
/// file, so two writers meeting is ordinary here, not an error. Each
/// connection's `busy_timeout` already waits for the other one — but only
/// for five seconds per attempt, and on a phone busy flushing its storage (or a
/// shared CI machine doing the same) one short transaction can hold the write
/// lock past that. `BEGIN IMMEDIATE` then failed with "database is locked",
/// and whatever was being written — a shared capture, most often — was lost
/// to a wait that had nearly finished.
///
/// A `BEGIN IMMEDIATE` that fails has taken nothing: no lock, no snapshot, no
/// partial write. So it is always safe to try again, which is what this does
/// for SQLITE_BUSY (and only that) until [patience] is spent. Any other error,
/// including "cannot start a transaction within a transaction", is thrown
/// at once.
///
/// It is also why every write transaction starts here and none starts with a
/// plain `BEGIN`: a deferred transaction that reads before it writes cannot
/// be retried by SQLite at all once another connection has committed in
/// between — the busy handler is skipped and the write fails immediately.
extension NexWriteLock on Database {
  /// How long a writer waits for another connection before giving up.
  static const patience = Duration(seconds: 30);

  void beginImmediate({Duration patience = NexWriteLock.patience}) {
    final waited = Stopwatch()..start();
    var pause = const Duration(milliseconds: 10);
    while (true) {
      try {
        execute('BEGIN IMMEDIATE');
        return;
      } on SqliteException catch (e) {
        if (e.resultCode != SqlError.SQLITE_BUSY ||
            waited.elapsed >= patience) {
          rethrow;
        }
      }
      // Synchronous on purpose, like SQLite's own busy handler: callers run
      // on the database isolate and are about to write, not to draw a frame.
      sleep(pause);
      if (pause < const Duration(milliseconds: 200)) pause *= 2;
    }
  }

  /// Runs [body] as one transaction, so a note and its search row are
  /// written together or not at all.
  ///
  /// A write that updated a note and then its FTS row as two autocommit
  /// statements could be cut between them by the process dying: the note
  /// showed its new text while search kept answering with the old, until
  /// the note was next edited (DATA-02). Inside a transaction already —
  /// an import, a sync page — [body] simply joins it.
  T together<T>(T Function() body) {
    if (!autocommit) return body();
    beginImmediate();
    try {
      final result = body();
      execute('COMMIT');
      return result;
    } catch (_) {
      execute('ROLLBACK');
      rethrow;
    }
  }
}
