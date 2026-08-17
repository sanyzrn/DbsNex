import 'dart:typed_data';

import '../ids.dart';
import '../models/checklist.dart';
import '../models/link_url.dart';
import '../models/note.dart';
import '../models/search_filters.dart';
import '../models/tag.dart';
import '../ports/note_repository.dart';

/// Pure domain use cases — no storage or UI (Phase 1.2).
class CaptureService {
  CaptureService(this._repo, {required this.deviceId});

  final NoteRepository _repo;
  final String deviceId;

  /// Persist a text capture once it has content (ADR-002). Empty → null (discard).
  Note? submitTextCapture(String content) {
    final trimmed = content; // preserve intentional whitespace; empty = discard
    if (trimmed.isEmpty) return null;
    final now = DateTime.now().toUtc();
    return _repo.insert(
      Note(
        id: newUuidV7(),
        type: NoteType.text,
        content: trimmed,
        createdAt: now,
        updatedAt: now,
        deviceId: deviceId,
        rev: 1,
        syncState: SyncState.pending,
      ),
    );
  }

  /// Persist a checklist. Empty → null (discard), the same as text.
  ///
  /// Takes items rather than a formatted body so the caller never has to know
  /// the on-disk format — [formatChecklist] is the only place that writes it.
  Note? submitChecklistCapture(List<ChecklistItem> items) {
    final body = formatChecklist(items);
    if (body.isEmpty) return null;
    final now = DateTime.now().toUtc();
    return _repo.insert(
      Note(
        id: newUuidV7(),
        type: NoteType.checklist,
        content: body,
        createdAt: now,
        updatedAt: now,
        deviceId: deviceId,
        rev: 1,
        syncState: SyncState.pending,
      ),
    );
  }

  /// Persist a link. Anything that is not a usable URL → null (discard).
  ///
  /// The URL is normalised on the way in — a bare `example.com/x` becomes
  /// `https://example.com/x` — because that is what people paste and what a
  /// share sheet hands over, and a note that cannot be opened is not a link.
  Note? submitLinkCapture(String url) {
    final normalised = normaliseUrl(url);
    if (normalised == null) return null;
    final now = DateTime.now().toUtc();
    return _repo.insert(
      Note(
        id: newUuidV7(),
        type: NoteType.link,
        content: normalised,
        createdAt: now,
        updatedAt: now,
        deviceId: deviceId,
        rev: 1,
        syncState: SyncState.pending,
      ),
    );
  }

  /// Persist a voice capture after recording stops (FR-1.4 / FR-1.7).
  Note submitVoiceCapture({
    required String mediaUri,
    required Uint8List mediaBytes,
    required int durationMs,
  }) {
    final now = DateTime.now().toUtc();
    return _repo.insert(
      Note(
        id: newUuidV7(),
        type: NoteType.voice,
        mediaUri: mediaUri,
        mediaHash: sha256OfBytes(mediaBytes),
        durationMs: durationMs,
        createdAt: now,
        updatedAt: now,
        deviceId: deviceId,
        rev: 1,
        syncState: SyncState.pending,
      ),
    );
  }

  /// Persist a photo capture after confirm (FR-1.5 / FR-1.7).
  Note submitPhotoCapture({
    required String mediaUri,
    required Uint8List mediaBytes,
  }) {
    final now = DateTime.now().toUtc();
    return _repo.insert(
      Note(
        id: newUuidV7(),
        type: NoteType.photo,
        mediaUri: mediaUri,
        mediaHash: sha256OfBytes(mediaBytes),
        createdAt: now,
        updatedAt: now,
        deviceId: deviceId,
        rev: 1,
        syncState: SyncState.pending,
      ),
    );
  }

  /// Persist a generic file attachment (Phase 2 / ADR-008).
  ///
  /// [originalFilename] is stored in [Note.content] for display (basename only).
  /// [mimeType] is stored when known (share-intent / picker).
  Note submitFileCapture({
    required String mediaUri,
    required Uint8List mediaBytes,
    String? originalFilename,
    String? mimeType,
  }) {
    final now = DateTime.now().toUtc();
    return _repo.insert(
      Note(
        id: newUuidV7(),
        type: NoteType.file,
        content: originalFilename,
        mimeType: mimeType,
        mediaUri: mediaUri,
        mediaHash: sha256OfBytes(mediaBytes),
        createdAt: now,
        updatedAt: now,
        deviceId: deviceId,
        rev: 1,
        syncState: SyncState.pending,
      ),
    );
  }
}

class TagService {
  TagService(this._repo);

  final NoteRepository _repo;

  Tag addTag({required String noteId, required String name, String? color}) {
    final tag = _repo.upsertTag(name: name, color: color);
    _repo.attachTag(noteId: noteId, tagId: tag.id);
    return tag;
  }

  void removeTag({required String noteId, required String tagId}) {
    _repo.detachTag(noteId: noteId, tagId: tagId);
  }

  List<Tag> listTags() => _repo.listTags();

  void setColor({required String tagId, String? color}) {
    _repo.setTagColor(tagId: tagId, color: color);
  }
}

class SearchService {
  SearchService(this._repo);

  final NoteRepository _repo;

  List<Note> search(SearchFilters filters) => _repo.search(filters);

  List<Note> timeline({int limit = 50, int offset = 0, String? tagId}) =>
      _repo.listTimeline(limit: limit, offset: offset, tagId: tagId);
}
