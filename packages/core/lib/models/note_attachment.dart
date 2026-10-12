/// What kind of file an attachment is — see `docs/14-attachments.md`.
enum AttachmentKind {
  photo('photo'),
  voice('voice'),
  file('file');

  const AttachmentKind(this.wireName);

  final String wireName;

  static AttachmentKind fromWire(String value) => values.firstWhere(
    (kind) => kind.wireName == value,
    orElse: () => throw FormatException('unknown attachment kind: $value'),
  );
}

/// A file a note carries after its own — the second photo, the attached PDF.
///
/// A note's own file stays on the note (`Note.mediaUri`), as it always has:
/// it is attachment 0, and this table starts at position 1. A text note has
/// no file of its own, so all of its attachments are here. Reading a note's
/// files is "its own, then these by [position]".
///
/// Shaped for sync from the start — [rev], [deviceId] and a tombstone in
/// [deletedAt] — although attachments only join sync with the files
/// themselves (roadmap item 11).
class NoteAttachment {
  const NoteAttachment({
    required this.id,
    required this.noteId,
    required this.position,
    required this.kind,
    required this.mediaUri,
    required this.mediaHash,
    required this.createdAt,
    required this.updatedAt,
    required this.deviceId,
    required this.rev,
    this.name,
    this.mimeType,
    this.durationMs,
    this.caption,
    this.ocrText,
    this.transcriptText,
    this.deletedAt,
  });

  final String id;
  final String noteId;

  /// From 1; position 0 is the note's own file.
  final int position;
  final AttachmentKind kind;
  final String mediaUri;

  /// The file's content address, as for a note's own file.
  final String mediaHash;

  /// The file's own name as it arrived ("invoice-march.pdf"), for display;
  /// the stored file has a name of the app's choosing.
  final String? name;
  final String? mimeType;
  final int? durationMs;

  /// What this one picture or file is — each can say its own.
  final String? caption;

  /// Text read from this picture, and spoken in this clip: derived text
  /// belongs to its file, not to the note.
  final String? ocrText;
  final String? transcriptText;

  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final String deviceId;
  final int rev;

  /// Everything about this file that search should find.
  String get searchText => [
    caption,
    ocrText,
    transcriptText,
  ].whereType<String>().where((s) => s.trim().isNotEmpty).join('\n');

  Map<String, Object?> toJson() => {
    'id': id,
    'note_id': noteId,
    'position': position,
    'kind': kind.wireName,
    'media_uri': mediaUri,
    'media_hash': mediaHash,
    'name': name,
    'mime_type': mimeType,
    'duration_ms': durationMs,
    'caption': caption,
    'ocr_text': ocrText,
    'transcript_text': transcriptText,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'deleted_at': deletedAt?.toUtc().toIso8601String(),
    'device_id': deviceId,
    'rev': rev,
  };

  factory NoteAttachment.fromRow(Map<String, Object?> row) => NoteAttachment(
    id: row['id']! as String,
    noteId: row['note_id']! as String,
    position: row['position']! as int,
    kind: AttachmentKind.fromWire(row['kind']! as String),
    mediaUri: row['media_uri']! as String,
    mediaHash: row['media_hash']! as String,
    name: row['name'] as String?,
    mimeType: row['mime_type'] as String?,
    durationMs: row['duration_ms'] as int?,
    caption: row['caption'] as String?,
    ocrText: row['ocr_text'] as String?,
    transcriptText: row['transcript_text'] as String?,
    createdAt: DateTime.parse(row['created_at']! as String).toUtc(),
    updatedAt: DateTime.parse(row['updated_at']! as String).toUtc(),
    deletedAt: switch (row['deleted_at']) {
      final String at => DateTime.parse(at).toUtc(),
      _ => null,
    },
    deviceId: row['device_id']! as String,
    rev: row['rev']! as int,
  );
}
