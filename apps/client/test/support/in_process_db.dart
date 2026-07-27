import 'dart:typed_data';

import 'package:nex_client/platform/nex_db.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_data/nex_data.dart';

/// A [NexDb] that runs the real storage stack on the calling isolate.
///
/// `flutter_test` executes test bodies inside a fake-async zone. Real isolate
/// port traffic never resolves there, so awaiting a [NexDbWorker] reply hangs
/// forever — which is exactly what the smoke suite did: all 27 cases reported
/// "did not complete".
///
/// This runs the same repository, the same domain services and the same
/// `LibraryMaintenance` as the worker, just without the isolate hop. What it
/// deliberately does not cover is the hop itself — the isolate's own behaviour
/// is the worker's concern, and that is what the integration suites exercise.
class InProcessDb implements NexDb {
  InProcessDb({required this.dbPath, required this.deviceId})
      : _db = NexDatabase.open(dbPath) {
    _repo = SqliteNoteRepository(_db, localDeviceId: deviceId);
    _capture = CaptureService(_repo, deviceId: deviceId);
    _tags = TagService(_repo);
    _search = SearchService(_repo);
    _maintenance = LibraryMaintenance(_repo);
    _enrichment = EnrichmentService(repo: _repo);
  }

  final String dbPath;
  final String deviceId;

  final NexDatabase _db;
  late final SqliteNoteRepository _repo;
  late final CaptureService _capture;
  late final TagService _tags;
  late final SearchService _search;
  late final LibraryMaintenance _maintenance;
  late final EnrichmentService _enrichment;

  bool _closed = false;

  @override
  Future<List<Note>> timeline({int limit = 200, int offset = 0, String? tagId}) async =>
      _search.timeline(limit: limit, offset: offset, tagId: tagId);

  @override
  Future<List<Note>> loadMore({required int offset, int limit = 50}) async =>
      _search.timeline(limit: limit, offset: offset);

  @override
  Future<List<Note>> search(SearchFilters filters) async => _search.search(filters);

  @override
  Future<Note?> getById(String id) async => _repo.getById(id);

  @override
  Future<Note?> captureText(String content) async =>
      _capture.submitTextCapture(content);

  @override
  Future<Note> captureVoice({
    required String mediaUri,
    required Uint8List mediaBytes,
    required int durationMs,
  }) async =>
      _capture.submitVoiceCapture(
        mediaUri: mediaUri,
        mediaBytes: mediaBytes,
        durationMs: durationMs,
      );

  @override
  Future<Note> capturePhoto({
    required String mediaUri,
    required Uint8List mediaBytes,
  }) async =>
      _capture.submitPhotoCapture(mediaUri: mediaUri, mediaBytes: mediaBytes);

  @override
  Future<Note> captureFile({
    required String mediaUri,
    required Uint8List mediaBytes,
    String? originalFilename,
    String? mimeType,
  }) async =>
      _capture.submitFileCapture(
        mediaUri: mediaUri,
        mediaBytes: mediaBytes,
        originalFilename: originalFilename,
        mimeType: mimeType,
      );

  @override
  Future<void> updateNote(String id, String content) async =>
      _repo.updateContent(id, content);

  @override
  Future<void> deleteNote(String id) async => _repo.softDelete(id);

  @override
  Future<void> undelete(String id) async => _repo.undelete(id);

  @override
  Future<void> setCaption(String id, String caption) async =>
      _repo.setCaption(id, caption);

  @override
  Future<Tag> addTag({
    required String noteId,
    required String name,
    String? color,
  }) async =>
      _tags.addTag(noteId: noteId, name: name, color: color);

  @override
  Future<void> removeTag({
    required String noteId,
    required String tagId,
  }) async =>
      _tags.removeTag(noteId: noteId, tagId: tagId);

  @override
  Future<List<Tag>> listTags() async => _tags.listTags();

  @override
  Future<void> setTagColor({required String tagId, String? color}) async =>
      _tags.setColor(tagId: tagId, color: color);

  @override
  Future<void> backup(String backupDir) async => _repo.backup(backupDir);

  @override
  Future<String> exportArchive({
    required String outputPath,
    required String mediaRoot,
  }) async =>
      (await _repo.exportArchive(outputPath: outputPath, mediaRoot: mediaRoot))
          .path;

  @override
  Future<List<Note>> deletedNotes({int limit = 200}) async =>
      _maintenance.deletedNotes(limit: limit);

  @override
  Future<void> purgeDeletedBefore(DateTime cutoff) async =>
      _maintenance.purgeDeletedBefore(cutoff);

  @override
  Future<List<TagUsage>> tagUsage() async => _maintenance.tagUsage();

  @override
  Future<void> renameTag(String id, String name) async =>
      _maintenance.renameTag(id, name);

  @override
  Future<void> mergeTag({
    required String sourceId,
    required String targetId,
  }) async =>
      _maintenance.mergeTag(sourceId: sourceId, targetId: targetId);

  @override
  Future<void> deleteTag(String id) async => _maintenance.deleteTag(id);

  @override
  Future<List<Note>> anniversary(DateTime now) async =>
      _maintenance.anniversary(now);

  @override
  Future<Note?> nearestMiss(String query) async =>
      _maintenance.nearestMiss(query);

  @override
  Future<StorageSnapshot> storage({
    required String dbPath,
    required String mediaDir,
    required String backupDir,
  }) =>
      _maintenance.storage(dbPath, mediaDir, backupDir);

  @override
  Future<void> enrichNote(String noteId) => _enrichment.enrichNote(noteId);

  @override
  Future<List<TagSuggestion>> suggestTags(String noteId) =>
      _enrichment.suggestTags(noteId);

  @override
  Future<Summary?> summarizeOnDemand(String noteId) =>
      _enrichment.summarizeOnDemand(noteId);

  @override
  Future<List<SemanticHit>> relatedNotes(String noteId, {int limit = 5}) =>
      _enrichment.relatedNotes(noteId, limit: limit);

  @override
  Future<void> setAiCapabilities(AiCapabilities capabilities) async =>
      _enrichment.updateCapabilities(capabilities);

  @override
  Future<SyncResult> sync({required String baseUrl, String? bearerToken}) async {
    final client = SyncClient(
      baseUrl: baseUrl,
      deviceId: deviceId,
      repo: _repo,
      bearerToken: bearerToken,
    );
    try {
      return await client.sync();
    } finally {
      client.close();
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _db.close();
  }
}
