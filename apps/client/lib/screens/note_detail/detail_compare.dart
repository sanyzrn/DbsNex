part of '../note_detail_sheet.dart';

/// Whether two reads of a note's threads say the same thing, in the order
/// the chips row shows them.
bool _sameThreads(List<NoteThread> a, List<NoteThread> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    final x = a[i];
    final y = b[i];
    if (x.id != y.id ||
        x.name != y.name ||
        x.noteCount != y.noteCount ||
        x.createdAt != y.createdAt ||
        x.updatedAt != y.updatedAt ||
        x.lastActivityAt != y.lastActivityAt) {
      return false;
    }
  }
  return true;
}

/// Whether two reads of a note's attachments say the same thing, in the
/// order the strip shows them. `rev` and `updatedAt` ride along with every
/// write; the rest are what a row draws.
bool _sameAttachments(List<NoteAttachment> a, List<NoteAttachment> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    final x = a[i];
    final y = b[i];
    if (x.id != y.id ||
        x.position != y.position ||
        x.kind != y.kind ||
        x.mediaUri != y.mediaUri ||
        x.mediaHash != y.mediaHash ||
        x.noteId != y.noteId ||
        x.name != y.name ||
        x.mimeType != y.mimeType ||
        x.durationMs != y.durationMs ||
        x.caption != y.caption ||
        x.ocrText != y.ocrText ||
        x.transcriptText != y.transcriptText ||
        x.createdAt != y.createdAt ||
        x.deviceId != y.deviceId ||
        x.rev != y.rev ||
        x.updatedAt != y.updatedAt ||
        x.deletedAt != y.deletedAt) {
      return false;
    }
  }
  return true;
}
