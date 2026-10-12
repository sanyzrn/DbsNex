import 'package:nex_core/nex_core.dart';

import 'attachment_repository.dart';

/// Reads the words in photos attached to notes — the attachments' share of
/// the enrichment a photo note gets for its own picture
/// (`docs/14-attachments.md`).
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

  /// Reads one attached photo. Whether it learned anything: false when it
  /// was not a photo, was read before, or nothing here reads images.
  Future<bool> read(String id) async {
    final attachment = _attachments.byId(id);
    if (attachment == null ||
        attachment.deletedAt != null ||
        attachment.kind != AttachmentKind.photo ||
        attachment.ocrText != null) {
      return false;
    }
    Future<String?> ask() => _enrichment.readImage(
      mediaUri: attachment.mediaUri,
      mediaHash: attachment.mediaHash,
    );
    final disclose = _disclose;
    final text = disclose == null
        ? await ask()
        : await disclose(attachment.noteId, ask);
    if (text == null) return false;
    _attachments.setOcrResult(id, text);
    return true;
  }

  /// Reads up to [limit] photos still waiting, newest first, and answers
  /// how many. Stops at the first that fails or that nothing could read —
  /// a dead key, or text reading switched off — rather than learning the
  /// same thing from every photo behind it.
  Future<int> backfill({int limit = 25}) async {
    if (!_enrichment.capabilities.ocr) return 0;
    var done = 0;
    for (final attachment in _attachments.needingOcr(limit: limit)) {
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
