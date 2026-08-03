import 'dart:typed_data';

import 'package:nex_core/nex_core.dart';
import 'package:nex_data/nex_data.dart';

/// The asynchronous database surface the app talks to.
///
/// In production this is [NexDbWorker], which forwards every call to a
/// dedicated isolate. The interface exists so it is not the *only* option:
/// `flutter_test` runs test bodies inside a fake-async zone, where real isolate
/// port traffic never resolves and awaiting a worker reply hangs forever. Tests
/// supply an in-process implementation instead.
///
/// Everything here returns a Future even where an implementation could answer
/// synchronously — the contract is the isolate boundary, not any one backend.
abstract interface class NexDb {
  Future<List<Note>> timeline({int limit, int offset, String? tagId});

  Future<List<Note>> loadMore({required int offset, int limit});

  Future<List<Note>> search(SearchFilters filters);

  Future<Note?> getById(String id);

  Future<Note?> captureText(String content);

  Future<Note> captureVoice({
    required String mediaUri,
    required Uint8List mediaBytes,
    required int durationMs,
  });

  Future<Note> capturePhoto({
    required String mediaUri,
    required Uint8List mediaBytes,
  });

  Future<Note> captureFile({
    required String mediaUri,
    required Uint8List mediaBytes,
    String? originalFilename,
    String? mimeType,
  });

  Future<void> updateNote(String id, String content);

  Future<void> deleteNote(String id);

  Future<void> undelete(String id);

  Future<void> setCaption(String id, String caption);

  Future<void> pinNote(String id);

  Future<void> unpinNote(String id);

  /// The id of the one note currently pinned, if any.
  Future<String?> pinnedNoteId();

  /// Stamps every id in [orderedIds] with its index as a manual position —
  /// the whole set a Rearrange drag was performed against (see
  /// [SqliteNoteRepository.reorderNotes]).
  Future<void> reorderNotes(List<String> orderedIds);

  Future<Tag> addTag({
    required String noteId,
    required String name,
    String? color,
  });

  Future<void> removeTag({required String noteId, required String tagId});

  /// Creates a tag that is not attached to any note yet. `upsertTag` is
  /// idempotent on name, so re-adding an existing tag returns it unchanged.
  Future<Tag> createTag(String name, {String? color});

  Future<List<Tag>> listTags();

  Future<void> setTagColor({required String tagId, String? color});

  Future<void> backup(String backupDir);

  Future<String> exportArchive({
    required String outputPath,
    required String mediaRoot,
  });

  Future<ImportResult> importArchive({
    required String archivePath,
    required String mediaRoot,
  });

  Future<List<Note>> deletedNotes({int limit});

  Future<void> purgeDeletedBefore(DateTime cutoff);

  /// Permanently removes one trashed note.
  Future<void> purgeNote(String id);

  /// Empties the trash.
  Future<void> purgeAllDeleted();

  Future<List<TagUsage>> tagUsage();

  Future<void> renameTag(String id, String name);

  Future<void> mergeTag({required String sourceId, required String targetId});

  Future<void> deleteTag(String id);

  Future<Note?> nearestMiss(String query);

  Future<StorageSnapshot> storage({
    required String dbPath,
    required String mediaDir,
    required String backupDir,
  });

  Future<void> enrichNote(String noteId);

  /// Enriches notes captured before the intelligence layer could read them.
  Future<int> backfillEnrichment({int limit});

  Future<List<TagSuggestion>> suggestTags(String noteId);

  Future<Summary?> summarizeOnDemand(String noteId);

  Future<List<SemanticHit>> relatedNotes(String noteId, {int limit});

  /// Notes ranked by embedding similarity to [query], meaning-based rather
  /// than keyword-based. Empty whenever the capability is off or no provider
  /// is configured to embed with — see [EnrichmentService.semanticSearch].
  Future<List<SemanticHit>> semanticSearch(String query, {int limit});

  Future<void> setAiCapabilities(AiCapabilities capabilities);

  /// Points the enrichment service at a provider.
  ///
  /// Takes the configuration rather than a built adapter: the adapter owns an
  /// HTTP client, which cannot be sent across the isolate boundary, so the
  /// worker constructs it on its own side.
  Future<void> setAiProvider(Map<String, String> config);

  Future<SyncResult> sync({required String baseUrl, String? bearerToken});

  Future<void> close();
}
