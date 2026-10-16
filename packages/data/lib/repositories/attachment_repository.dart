import 'package:nex_core/nex_core.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:path/path.dart' as p;

import '../schema/write_lock.dart';
import 'note_repository.dart';

/// The files a note carries after its own — `docs/14-attachments.md`.
///
/// A note's own file stays on the note, untouched; this holds the rest, from
/// position 1. Every change re-derives the note's search row, so a word in
/// any attachment's caption or OCR finds the note, and marks the note as
/// edited. Removing an attachment leaves a tombstone, for sync later; its
/// file goes when nothing references it any more (LibraryMaintenance).
///
/// Synchronous, like every repository here; it runs inside the database
/// worker's isolate.
class SqliteAttachmentRepository {
  SqliteAttachmentRepository(this._notes, {required this.localDeviceId});

  final SqliteNoteRepository _notes;
  final String localDeviceId;

  Database get db => _notes.db;

  /// [noteId]'s attachments, in order. Not the note's own file.
  List<NoteAttachment> forNote(String noteId) => [
    for (final row in db.select(
      'SELECT * FROM note_attachments '
      'WHERE note_id = ? AND deleted_at IS NULL ORDER BY position, created_at',
      [noteId],
    ))
      NoteAttachment.fromRow(row),
  ];

  bool parentExists(String noteId) => _notes.getById(noteId) != null;

  /// How many attachments each of [noteIds] has — what a card's `+3` reads.
  /// Notes with none are left out.
  Map<String, int> countsFor(Iterable<String> noteIds) =>
      _notes.attachmentCounts(noteIds.toSet().toList());

  /// Puts a file, already stored under the media root, at the end of
  /// [noteId]'s attachments. Null when the note is not there.
  NoteAttachment? add(
    String noteId, {
    required AttachmentKind kind,
    required String mediaUri,
    required String mediaHash,
    String? name,
    String? mimeType,
    int? durationMs,
    String? caption,
    DateTime? now,
  }) => db.together(() {
    final exists = db.select('SELECT 1 FROM notes WHERE id = ?', [noteId]);
    if (exists.isEmpty) return null;
    final last =
        db.select(
              'SELECT MAX(position) AS p FROM note_attachments '
              'WHERE note_id = ? AND deleted_at IS NULL',
              [noteId],
            ).first['p']
            as int?;
    final at = (now ?? DateTime.now()).toUtc();
    final attachment = NoteAttachment(
      id: newUuidV7(),
      noteId: noteId,
      position: (last ?? 0) + 1,
      kind: kind,
      mediaUri: mediaUri,
      mediaHash: mediaHash,
      name: name,
      mimeType: mimeType,
      durationMs: durationMs,
      caption: caption,
      createdAt: at,
      updatedAt: at,
      deviceId: localDeviceId,
      rev: 1,
    );
    _insert(attachment);
    _notes.attachmentsChanged(noteId);
    return attachment;
  });

  /// A new file replaces this attachment's pixels. Shared originals stay on
  /// disk for reference-aware maintenance. Reset derived text atomically so
  /// search cannot retain words from the old image.
  bool updateImageMedia(
    String id,
    String mediaUri,
    String mediaHash, {
    required String expectedMediaHash,
  }) => db.together(() {
    final a = byId(id);
    if (a == null ||
        a.deletedAt != null ||
        a.mediaHash != expectedMediaHash ||
        db.select('SELECT 1 FROM notes WHERE id = ? AND deleted_at IS NULL', [
          a.noteId,
        ]).isEmpty ||
        (a.kind != AttachmentKind.photo &&
            !(a.kind == AttachmentKind.file &&
                NexFileKinds.of(path: a.mediaUri, mimeType: a.mimeType) ==
                    NexFileKind.image))) {
      return false;
    }
    final ext = p.extension(mediaUri).toLowerCase();
    final name = a.name;
    db.execute(
      'UPDATE note_attachments SET media_uri = ?, media_hash = ?, mime_type = ?, '
      'name = ?, ocr_text = NULL, transcript_text = NULL, updated_at = ?, '
      "rev = rev + 1, device_id = ?, sync_state = 'pending' WHERE id = ?",
      [
        mediaUri,
        mediaHash,
        ext == '.jpg' ? 'image/jpeg' : 'image/png',
        name == null || p.extension(name).isEmpty
            ? name
            : '${p.withoutExtension(name)}$ext',
        DateTime.now().toUtc().toIso8601String(),
        localDeviceId,
        id,
      ],
    );
    _notes.forgetEmbedding(a.noteId);
    _notes.attachmentsChanged(a.noteId);
    return true;
  });

  void setCaption(String id, String? caption) =>
      _update(id, 'caption', _blankToNull(caption));

  void setOcrText(String id, String? text) =>
      _update(id, 'ocr_text', _blankToNull(text));

  /// What reading a photo's words found: the words, or an empty string for
  /// "read, and there are none" — kept, unlike a blank caption, so the photo
  /// is not read again on every pass.
  void setOcrResult(String id, String text) => db.together(() {
    final noteId = _noteOf(id);
    if (noteId == null) return;
    db.execute(
      'UPDATE note_attachments SET ocr_text = ? '
      'WHERE id = ? AND deleted_at IS NULL',
      [text.trim(), id],
    );
    _notes.attachmentTextRead(noteId);
  });

  /// The name a file attachment is shown, shared and saved under. Blank
  /// goes back to the file's own.
  void rename(String id, String? name) =>
      _update(id, 'name', _blankToNull(name));

  /// Takes [id] off its note and makes it a note of its own — a photo, a
  /// voice note or a file, with its caption and whatever was read from it —
  /// when it deserves its own tags, reminder or thread. The file is shared,
  /// not copied: the media sweep counts references in both tables. Null
  /// when there is no such attachment.
  Note? detach(String id) => db.together(() {
    final attachment = byId(id);
    if (attachment == null || attachment.deletedAt != null) return null;
    final capture = CaptureService(_notes, deviceId: localDeviceId);
    final note = switch (attachment.kind) {
      AttachmentKind.photo => capture.submitPhotoCapture(
        mediaUri: attachment.mediaUri,
        mediaHash: attachment.mediaHash,
      ),
      AttachmentKind.voice => capture.submitVoiceCapture(
        mediaUri: attachment.mediaUri,
        mediaHash: attachment.mediaHash,
        durationMs: attachment.durationMs ?? 0,
      ),
      AttachmentKind.file => capture.submitFileCapture(
        mediaUri: attachment.mediaUri,
        mediaHash: attachment.mediaHash,
        originalFilename: attachment.name,
        mimeType: attachment.mimeType,
      ),
    };
    if (attachment.caption case final caption?) {
      _notes.setCaption(note.id, caption);
    }
    if (attachment.ocrText case final text?) _notes.setOcrText(note.id, text);
    if (attachment.transcriptText case final text?) {
      _notes.setTranscriptText(note.id, text);
    }
    remove(id);
    return _notes.getById(note.id);
  });

  /// Makes [id], a photo, its photo note's own photo, and the note's photo
  /// an attachment in its place: the cover of a set of photos is whichever
  /// one says most. Each photo keeps its own caption and the words read in
  /// it. False when [id] is not a photo on a photo note.
  bool promote(String id) => db.together(() {
    final attachment = byId(id);
    if (attachment == null ||
        attachment.deletedAt != null ||
        attachment.kind != AttachmentKind.photo) {
      return false;
    }
    final rows = db.select(
      'SELECT type, media_uri, media_hash, mime_type, caption, ocr_text '
      'FROM notes WHERE id = ? AND deleted_at IS NULL',
      [attachment.noteId],
    );
    if (rows.isEmpty) return false;
    final own = rows.first;
    if (own['type'] != 'photo' ||
        own['media_uri'] == null ||
        own['media_hash'] == null) {
      return false;
    }
    db.execute(
      'UPDATE notes SET media_uri = ?, media_hash = ?, mime_type = ?, '
      'caption = ?, ocr_text = ? WHERE id = ?',
      [
        attachment.mediaUri,
        attachment.mediaHash,
        attachment.mimeType,
        attachment.caption,
        attachment.ocrText,
        attachment.noteId,
      ],
    );
    db.execute(
      'UPDATE note_attachments SET media_uri = ?, media_hash = ?, '
      'mime_type = ?, caption = ?, ocr_text = ?, updated_at = ?, '
      "rev = rev + 1, device_id = ?, sync_state = 'pending' WHERE id = ?",
      [
        own['media_uri'],
        own['media_hash'],
        own['mime_type'],
        own['caption'],
        own['ocr_text'],
        DateTime.now().toUtc().toIso8601String(),
        localDeviceId,
        id,
      ],
    );
    // What the note means has changed with its picture: read again.
    _notes.forgetEmbedding(attachment.noteId);
    _notes.attachmentsChanged(attachment.noteId);
    return true;
  });

  /// What transcribing a voice clip found, kept as [setOcrResult] keeps
  /// what was read in a photo: an empty string means "heard, and nothing
  /// said", so the clip is not sent again.
  void setTranscriptResult(String id, String text) => db.together(() {
    final noteId = _noteOf(id);
    if (noteId == null) return;
    db.execute(
      'UPDATE note_attachments SET transcript_text = ? '
      'WHERE id = ? AND deleted_at IS NULL',
      [text.trim(), id],
    );
    _notes.attachmentTextRead(noteId);
  });

  NoteAttachment? byId(String id) {
    final rows = db.select('SELECT * FROM note_attachments WHERE id = ?', [id]);
    return rows.isEmpty ? null : NoteAttachment.fromRow(rows.first);
  }

  /// Photos whose words have not been read yet and voice clips not yet
  /// transcribed, on live notes, newest first: what was just attached is
  /// what someone is about to search for.
  List<NoteAttachment> needingText({int limit = 25}) => [
    for (final row in db.select(
      '''
SELECT a.* FROM note_attachments a
JOIN notes n ON n.id = a.note_id AND n.deleted_at IS NULL
WHERE a.deleted_at IS NULL AND (
  (a.kind = 'photo' AND a.ocr_text IS NULL) OR
  (a.kind = 'voice' AND a.transcript_text IS NULL)
)
ORDER BY a.created_at DESC
LIMIT ?
''',
      [limit],
    ))
      NoteAttachment.fromRow(row),
  ];

  void setTranscript(String id, String? text) =>
      _update(id, 'transcript_text', _blankToNull(text));

  /// Takes [id] off its note. A tombstone stays for sync; the file goes in
  /// the next media sweep if nothing else points at it.
  void remove(String id) => db.together(() {
    final noteId = _noteOf(id);
    if (noteId == null) return;
    final now = DateTime.now().toUtc().toIso8601String();
    db.execute(
      'UPDATE note_attachments SET deleted_at = ?, updated_at = ?, '
      "rev = rev + 1, device_id = ?, sync_state = 'pending' "
      'WHERE id = ? AND deleted_at IS NULL',
      [now, now, localDeviceId, id],
    );
    _notes.attachmentsChanged(noteId);
  });

  /// Puts a removed attachment back, as it was, at the end — the Undo after
  /// removing one. Returns whether there was one to put back.
  bool restore(String id) => db.together(() {
    final rows = db.select(
      'SELECT note_id FROM note_attachments '
      'WHERE id = ? AND deleted_at IS NOT NULL',
      [id],
    );
    if (rows.isEmpty) return false;
    final noteId = rows.first['note_id']! as String;
    final last =
        db.select(
              'SELECT MAX(position) AS p FROM note_attachments '
              'WHERE note_id = ? AND deleted_at IS NULL',
              [noteId],
            ).first['p']
            as int?;
    db.execute(
      'UPDATE note_attachments SET deleted_at = NULL, position = ?, '
      "updated_at = ?, rev = rev + 1, device_id = ?, sync_state = 'pending' "
      'WHERE id = ?',
      [
        (last ?? 0) + 1,
        DateTime.now().toUtc().toIso8601String(),
        localDeviceId,
        id,
      ],
    );
    _notes.attachmentsChanged(noteId);
    return true;
  });

  /// Puts [noteId]'s attachments in the order of [orderedIds]; any not
  /// listed keep their relative order after them.
  void reorder(String noteId, List<String> orderedIds) => db.together(() {
    final current = forNote(noteId).map((a) => a.id).toList();
    final order = [
      for (final id in orderedIds)
        if (current.contains(id)) id,
      for (final id in current)
        if (!orderedIds.contains(id)) id,
    ];
    final now = DateTime.now().toUtc().toIso8601String();
    for (var i = 0; i < order.length; i++) {
      db.execute(
        'UPDATE note_attachments SET position = ?, updated_at = ?, '
        "rev = rev + 1, sync_state = 'pending' WHERE id = ? AND position != ?",
        [i + 1, now, order[i], i + 1],
      );
    }
    _notes.attachmentsChanged(noteId);
  });

  /// Every live attachment of every live note — what an export carries.
  List<NoteAttachment> allLive() => [
    for (final row in db.select('''
SELECT a.* FROM note_attachments a
JOIN notes n ON n.id = a.note_id AND n.deleted_at IS NULL
WHERE a.deleted_at IS NULL
ORDER BY a.note_id, a.position
'''))
      NoteAttachment.fromRow(row),
  ];

  /// Writes [attachment] as it is, unless one with its id is already here
  /// or its note is not — the import's additive rule. Returns whether it
  /// was written. Does not re-derive the note's search row: the caller
  /// does, once per note.
  bool insertIfAbsent(NoteAttachment attachment) {
    if (db.select('SELECT 1 FROM note_attachments WHERE id = ?', [
      attachment.id,
    ]).isNotEmpty) {
      return false;
    }
    if (db.select('SELECT 1 FROM notes WHERE id = ?', [
      attachment.noteId,
    ]).isEmpty) {
      return false;
    }
    _insert(attachment);
    return true;
  }

  void _insert(NoteAttachment a) => db.execute(
    '''
INSERT INTO note_attachments (
  id, note_id, position, kind, media_uri, media_hash, name, mime_type,
  duration_ms, caption, ocr_text, transcript_text, created_at, updated_at,
  deleted_at, device_id, rev, sync_state
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending')
''',
    [
      a.id,
      a.noteId,
      a.position,
      a.kind.wireName,
      a.mediaUri,
      a.mediaHash,
      a.name,
      a.mimeType,
      a.durationMs,
      a.caption,
      a.ocrText,
      a.transcriptText,
      a.createdAt.toUtc().toIso8601String(),
      a.updatedAt.toUtc().toIso8601String(),
      a.deletedAt?.toUtc().toIso8601String(),
      a.deviceId,
      a.rev,
    ],
  );

  void _update(String id, String column, String? value) => db.together(() {
    final noteId = _noteOf(id);
    if (noteId == null) return;
    db.execute(
      'UPDATE note_attachments SET $column = ?, updated_at = ?, '
      "rev = rev + 1, device_id = ?, sync_state = 'pending' "
      'WHERE id = ? AND deleted_at IS NULL',
      [value, DateTime.now().toUtc().toIso8601String(), localDeviceId, id],
    );
    _notes.attachmentsChanged(noteId);
  });

  String? _noteOf(String id) {
    final rows = db.select(
      'SELECT note_id FROM note_attachments WHERE id = ? AND deleted_at IS NULL',
      [id],
    );
    return rows.isEmpty ? null : rows.first['note_id']! as String;
  }

  static String? _blankToNull(String? value) =>
      value == null || value.trim().isEmpty ? null : value;
}
