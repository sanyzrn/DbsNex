import '../models/note.dart';

/// Storage contract for notes.
///
/// Declared in core so the application and the AI/enrichment services depend on
/// a behaviour, not on SQLite. packages/data provides the implementation.
///
/// Every method is asynchronous by design: the concrete implementation runs on
/// a worker isolate (package:sqlite3 is a synchronous FFI binding, so a direct
/// call blocks whichever isolate makes it).
abstract interface class NoteRepository {
  Future<Note> insert(Note note);

  Future<Note?> byId(String id);

  Future<void> updateContent(String id, String content);

  /// Soft delete. Tombstones propagate through sync; the payload is erased by
  /// the merge layer, not retained behind a flag.
  Future<void> softDelete(String id);

  Future<List<Note>> timeline({int limit, int offset});

  Future<List<Note>> search(String query);

  Future<void> setTags(String noteId, List<String> tagNames);

  /// Copies the live database to a timestamped file inside [backupDir].
  Future<void> backup(String backupDir);

  /// Writes a portable archive and returns its path.
  Future<String> exportArchive({
    required String outputPath,
    required String mediaRoot,
  });
}
