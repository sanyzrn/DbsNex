part of 'db_worker.dart';

/// Attachments through the worker — `docs/14-attachments.md`. The calling
/// side first, then what the worker does with each command.
mixin _DbAttachments {
  Future<T> _send<T>(_DbCommand command, [Map<String, Object?> args]);

  Future<List<NoteAttachment>> attachmentsFor(String noteId) =>
      _send<List<NoteAttachment>>(_DbCommand.attachmentsFor, {
        'noteId': noteId,
      });

  Future<NoteAttachment?> attachmentAdd(
    String noteId, {
    required AttachmentKind kind,
    required String mediaUri,
    required String mediaHash,
    String? name,
    String? mimeType,
    int? durationMs,
    String? caption,
  }) => _send<NoteAttachment?>(_DbCommand.attachmentAdd, {
    'noteId': noteId,
    'kind': kind.wireName,
    'mediaUri': mediaUri,
    'mediaHash': mediaHash,
    'name': name,
    'mimeType': mimeType,
    'durationMs': durationMs,
    'caption': caption,
  });

  Future<bool> attachmentUpdateImage(
    String id,
    String mediaUri,
    String mediaHash,
    String expectedMediaHash,
  ) => _send<bool>(_DbCommand.attachmentUpdateImage, {
    'id': id,
    'mediaUri': mediaUri,
    'mediaHash': mediaHash,
    'expectedMediaHash': expectedMediaHash,
  });

  Future<void> attachmentRemove(String id) =>
      _send<void>(_DbCommand.attachmentRemove, {'id': id});

  Future<bool> attachmentRestore(String id) =>
      _send<bool>(_DbCommand.attachmentRestore, {'id': id});

  Future<void> attachmentReorder(String noteId, List<String> orderedIds) =>
      _send<void>(_DbCommand.attachmentReorder, {
        'noteId': noteId,
        'ids': orderedIds,
      });

  Future<void> attachmentSetCaption(String id, String? caption) =>
      _send<void>(_DbCommand.attachmentSetCaption, {'id': id, 'text': caption});

  Future<void> attachmentSetOcr(String id, String? text) =>
      _send<void>(_DbCommand.attachmentSetOcr, {'id': id, 'text': text});

  Future<bool> attachmentReadText(String id, {bool refresh = false}) =>
      _send<bool>(_DbCommand.attachmentReadText, {
        'id': id,
        'refresh': refresh,
      });

  Future<void> attachmentRename(String id, String? name) =>
      _send<void>(_DbCommand.attachmentRename, {'id': id, 'text': name});

  Future<Note?> attachmentDetach(String id) =>
      _send<Note?>(_DbCommand.attachmentDetach, {'id': id});

  Future<bool> attachmentPromote(String id) =>
      _send<bool>(_DbCommand.attachmentPromote, {'id': id});
}

/// The worker side: one attachment command, answered from [attachments].
Object? _attachmentCommand(
  SqliteAttachmentRepository attachments,
  _DbCommand command,
  Object? Function(String key) arg,
) => switch (command) {
  _DbCommand.attachmentsFor => attachments.forNote(arg('noteId')! as String),
  _DbCommand.attachmentAdd => attachments.add(
    arg('noteId')! as String,
    kind: AttachmentKind.fromWire(arg('kind')! as String),
    mediaUri: arg('mediaUri')! as String,
    mediaHash: arg('mediaHash')! as String,
    name: arg('name') as String?,
    mimeType: arg('mimeType') as String?,
    durationMs: arg('durationMs') as int?,
    caption: arg('caption') as String?,
  ),
  _DbCommand.attachmentUpdateImage => attachments.updateImageMedia(
    arg('id')! as String,
    arg('mediaUri')! as String,
    arg('mediaHash')! as String,
    expectedMediaHash: arg('expectedMediaHash')! as String,
  ),
  _DbCommand.attachmentRemove => NexDbWorker._voided(
    () => attachments.remove(arg('id')! as String),
  ),
  _DbCommand.attachmentRestore => attachments.restore(arg('id')! as String),
  _DbCommand.attachmentReorder => NexDbWorker._voided(
    () => attachments.reorder(
      arg('noteId')! as String,
      (arg('ids')! as List).cast<String>(),
    ),
  ),
  _DbCommand.attachmentRename => NexDbWorker._voided(
    () => attachments.rename(arg('id')! as String, arg('text') as String?),
  ),
  _DbCommand.attachmentDetach => attachments.detach(arg('id')! as String),
  _DbCommand.attachmentPromote => attachments.promote(arg('id')! as String),
  _DbCommand.attachmentSetCaption => NexDbWorker._voided(
    () => attachments.setCaption(arg('id')! as String, arg('text') as String?),
  ),
  _ => NexDbWorker._voided(
    () => attachments.setOcrText(arg('id')! as String, arg('text') as String?),
  ),
};
