import '../models/note.dart';
import '../models/note_embedding.dart';
import '../models/search_filters.dart';
import '../models/tag.dart';

/// Storage contract for notes and tags.
///
/// Declared in core so the domain services depend on a behaviour rather than on
/// SQLite. packages/data provides the implementation (`SqliteNoteRepository`).
///
/// **Every method is synchronous, and that is deliberate.** The previous
/// version of this file declared seven `Future`-returning methods on the
/// grounds that "the concrete implementation runs on a worker isolate". That
/// inverted the real topology: `package:sqlite3` is a synchronous FFI binding,
/// so the repository *is* synchronous and runs **inside** the isolate,
/// alongside the services declared here. The asynchronous boundary is the
/// isolate message port, which `NexDbWorker` owns on the UI side — it is a
/// client of this contract, not an implementation of it.
///
/// The surface is deliberately narrow: it is what the domain services in this
/// package actually call, nothing more. `SqliteNoteRepository` exposes a
/// superset (sync outbox, backup, export, undelete) that only the storage and
/// application layers need.
abstract interface class NoteRepository {
  Note insert(Note note);

  Note? getById(String id, {bool includeDeleted = false});

  List<Note> listTimeline({int limit, int offset, String? tagId});

  List<Note> search(SearchFilters filters);

  Tag upsertTag({required String name, String? color});

  void attachTag({required String noteId, required String tagId});

  void detachTag({required String noteId, required String tagId});

  List<Tag> listTags();

  void setTagColor({required String tagId, String? color});

  /// AI-derived text. These never overwrite `content` or `mediaUri` (09-ai.md).
  void setTranscriptText(String noteId, String text);

  void setOcrText(String noteId, String text);

  void setSummaryText(String noteId, String text);

  void setEmbedding(String noteId, List<double> values);

  List<double>? getEmbedding(String noteId);

  List<NoteEmbedding> listEmbeddings();
}
