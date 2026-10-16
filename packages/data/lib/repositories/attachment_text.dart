import 'package:nex_core/nex_core.dart';

import 'attachment_repository.dart';

/// Reads the words in photos attached to notes, and transcribes attached
/// voice clips — the attachments' share of the enrichment a photo or voice
/// note gets for its own file (`docs/14-attachments.md`).
///
/// What it finds goes into the attachment's `ocr_text`, which the note's
/// search row already carries, so a word in the third photo of a receipt
/// finds the receipt. Only when reading text in photos is on, and only
/// photos: a PDF or a document attached to a note is not an image.
class AttachmentTextReader {
  AttachmentTextReader(
    this._attachments,
    this._enrichment, {
    Future<String?> Function(String noteId, Future<String?> Function() read)?
    disclose,
  }) : _disclose = disclose;

  final SqliteAttachmentRepository _attachments;
  final EnrichmentService _enrichment;

  /// Wraps each request with the note it is about, for the disclosure log.
  final Future<String?> Function(
    String noteId,
    Future<String?> Function() read,
  )?
  _disclose;

  /// Reads one attached photo, or transcribes one attached voice clip.
  /// Whether it learned anything: false when it is neither, was read
  /// before, or nothing here reads it.
  Future<bool> read(String id, {bool refresh = false}) async {
    final attachment = _attachments.byId(id);
    if (attachment == null ||
        attachment.deletedAt != null ||
        !_attachments.parentExists(attachment.noteId)) {
      return false;
    }
    final kind = NexFileKinds.of(
      path: attachment.mediaUri,
      mimeType: attachment.mimeType,
    );
    final photo =
        attachment.kind == AttachmentKind.photo || kind == NexFileKind.image;
    final voice =
        attachment.kind == AttachmentKind.voice || kind == NexFileKind.audio;
    if (!(photo && (refresh || attachment.ocrText == null)) &&
        !(voice && (refresh || attachment.transcriptText == null))) {
      return false;
    }
    Future<String?> ask() => photo
        ? _enrichment.readImage(
            mediaUri: attachment.mediaUri,
            mediaHash: attachment.mediaHash,
          )
        : _enrichment.transcribeAudio(
            mediaUri: attachment.mediaUri,
            mediaHash: attachment.mediaHash,
          );
    final disclose = _disclose;
    final text = disclose == null
        ? await ask()
        : await disclose(attachment.noteId, ask);
    if (text == null) return false;
    // The editor can replace (or remove) the image while a provider reads it.
    // Never put the old image's words back onto its replacement.
    final current = _attachments.byId(id);
    if (current == null ||
        current.deletedAt != null ||
        !_attachments.parentExists(attachment.noteId) ||
        current.mediaHash != attachment.mediaHash ||
        current.mediaUri != attachment.mediaUri) {
      return false;
    }
    if (photo) {
      _attachments.setOcrResult(id, text);
    } else {
      _attachments.setTranscriptResult(id, text);
    }
    return true;
  }

  /// Reads up to [limit] photos still waiting, newest first, and answers
  /// how many. Stops at the first that fails or that nothing could read —
  /// a dead key, or text reading switched off — rather than learning the
  /// same thing from every photo behind it.
  Future<int> backfill({int limit = 25}) async {
    final can = _enrichment.capabilities;
    if (!can.ocr && !can.transcription) return 0;
    var done = 0;
    for (final attachment in _attachments.needingText(limit: limit)) {
      // Not a reason to stop: with text in photos on and transcription off,
      // a voice clip waiting in the queue says nothing about the photos.
      final off = attachment.kind == AttachmentKind.photo
          ? !can.ocr
          : !can.transcription;
      if (off) continue;
      try {
        if (!await read(attachment.id)) break;
      } catch (_) {
        break;
      }
      done++;
    }
    return done;
  }
}
