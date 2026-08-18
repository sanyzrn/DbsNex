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

  /// Notes with text and no embedding yet, newest first.
  ///
  /// Separate from `listNeedingEnrichment`, which only ever returns media
  /// waiting on a transcript or an OCR read. A text note needs nothing
  /// derived from it — it is already its own text — so it never appeared
  /// there, and the consequence was that a library written before a provider
  /// was configured got no embeddings at all and semantic search silently
  /// found nothing in it forever.
  List<Note> listNeedingEmbedding({int limit});

  /// Sets or clears when a note should come back up.
  void setDueAt(String noteId, DateTime? when);

  /// Notes with a reminder still ahead of them, soonest first.
  ///
  /// What the app re-reads on launch to put the OS alarms back. An alarm is
  /// not durable — a reinstall, a restore from backup, or an Android version
  /// that drops exact alarms all lose them — and the note is, so the note is
  /// the record and the alarm is a copy of it.
  List<Note> listUpcomingReminders({int limit});

  /// Notes the intelligence layer has never been able to read.
  ///
  /// Enrichment runs once, at capture. That leaves every note captured before
  /// a provider was configured — which, since the whole layer is off by
  /// default, is normally the entire library — permanently untranscribed and
  /// unread, with nothing in the app admitting it. This is what a backfill
  /// pass walks.
  ///
  /// Newest first: the note a person is most likely to go looking for is the
  /// one they just captured, not the one from last year.
  List<Note> listNeedingEnrichment({int limit});
}
