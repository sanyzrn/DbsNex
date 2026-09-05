
import '../ids.dart';
import '../import/note_import.dart';
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
    required String mediaHash,
    required int durationMs,
  }) {
    final now = DateTime.now().toUtc();
    return _repo.insert(
      Note(
        id: newUuidV7(),
        type: NoteType.voice,
        mediaUri: mediaUri,
        mediaHash: mediaHash,
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
    required String mediaHash,
  }) {
    final now = DateTime.now().toUtc();
    return _repo.insert(
      Note(
        id: newUuidV7(),
        type: NoteType.photo,
        mediaUri: mediaUri,
        mediaHash: mediaHash,
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
    required String mediaHash,
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
        mediaHash: mediaHash,
        createdAt: now,
        updatedAt: now,
        deviceId: deviceId,
        rev: 1,
        syncState: SyncState.pending,
      ),
    );
  }

  /// Writes a whole import in one go, keeping each note's own date.
  ///
  /// Not a loop over [submitTextCapture] from the caller's side, for two
  /// reasons. The capture path stamps `DateTime.now()`, which would date a
  /// decade of somebody's notes to the minute they moved apps and make the
  /// timeline useless; and every note would be a separate hop across the
  /// isolate port, so an import of two thousand notes would be two thousand
  /// round trips plus one per tag.
  ///
  /// Everything else is the ordinary capture contract: new ids, revision 1,
  /// pending sync. An imported note is a note this device wrote — it has no
  /// history on any server, and pretending otherwise would push conflicts.
  /// [mediaFor] answers where an imported note's photo was written, for the
  /// caller that could open the archive. Without it every note is text, which
  /// is what this did before photos were brought across at all.
  List<Note> importNotes(
    List<ImportedNote> imported, {
    String? Function(ImportedNote note)? mediaFor,
  }) {
    final written = <Note>[];
    for (final source in imported) {
      final body = source.text.trim();
      final media = mediaFor?.call(source);
      // A note with no words used to be nothing to import. With a photo behind
      // it, it is a photo — which is most of what people keep in Keep.
      if (body.isEmpty && media == null) continue;
      // Falls back to now only where the export gave no date. Clamped to the
      // present because a note dated in the future pins itself to the top of
      // the timeline forever.
      final now = DateTime.now().toUtc();
      final at = source.createdAt == null || source.createdAt!.isAfter(now)
          ? now
          : source.createdAt!.toUtc();
      final note = _repo.insert(
        Note(
          id: newUuidV7(),
          type: source.type,
          // Kept even on a photo note. A Keep note is often a picture with a
          // line under it, and dropping the line to fit our note types would
          // lose the half the person actually wrote.
          content: body,
          mediaUri: media,
          title: source.title,
          createdAt: at,
          updatedAt: at,
          deviceId: deviceId,
          rev: 1,
          syncState: SyncState.pending,
        ),
      );
      for (final name in source.tags) {
        final trimmed = name.trim();
        if (trimmed.isEmpty) continue;
        // `upsertTag` is what makes two notes carrying the same label share
        // one tag rather than minting one each — and what makes a label that
        // already exists in Nex merge with it instead of duplicating.
        final tag = _repo.upsertTag(name: trimmed);
        _repo.attachTag(noteId: note.id, tagId: tag.id);
      }
      written.add(note);
    }
    return written;
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
