part of '../note_detail_sheet.dart';

/// The files a note carries after its own — `docs/14-attachments.md`.
///
/// A row of tiles under the note's body: each photo as itself, each file as
/// its kind and name, and a last tile to attach another. A tap opens one —
/// a photo full screen, a file in whatever opens it — and a hold offers its
/// caption and removing it, with an Undo.
extension _DetailAttachments on _NoteDetailSheetState {
  /// Notes that can carry files: text gains them, photo and file notes gain
  /// more of their own kind. A checklist, a link and a voice note do not,
  /// yet (docs/14-attachments.md, "Later").
  bool _canAttach(Note note) => switch (note.type) {
    NoteType.text || NoteType.photo || NoteType.file => true,
    _ => false,
  };

  /// The tiles, once there is something to show. A note with no
  /// attachments shows none of this: an empty tile on every text note would
  /// be the loudest thing on the sheet, so the way in is [_attachChip],
  /// beside the tag button, until the first file arrives.
  List<Widget> _attachmentStrip(
    BuildContext context,
    Note note,
    AppLocalizations l10n,
  ) {
    if (_attachments.isEmpty) return const [];
    final theme = Theme.of(context);
    return [
      const SizedBox(height: NexSpacing.md),
      Row(
        children: [
          Text(l10n.attachmentsTitle, style: theme.textTheme.bodySmall),
          const Spacer(),
          // How many, and how much room they take: the two things anyone
          // tidying a phone wants to know about a note's files.
          Text(
            nexDigits(
              '${_attachments.length} · ${nexFormatBytes(_attachmentBytes())}',
              persian: l10n.localeName == 'fa',
            ),
            key: const ValueKey('attachments-summary'),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      const SizedBox(height: NexSpacing.xs),
      _AttachmentStrip(
        attachments: _attachments,
        canAdd: _canAttach(note),
        onAdd: () => unawaited(_addAttachment(note)),
        onOpen: (attachment) => unawaited(_openAttachment(attachment)),
        onHold: (attachment) => unawaited(_attachmentMenu(attachment)),
        onReorder: (order) => unawaited(_reorderAttachments(note, order)),
      ),
    ];
  }

  /// The first way in, among the tags: a note with files already has the
  /// add tile at the end of its strip.
  Widget? _attachChip(Note note, AppLocalizations l10n) {
    if (!_canAttach(note) || _attachments.isNotEmpty) return null;
    return ActionChip(
      key: const ValueKey('attachment-add'),
      avatar: const Icon(Icons.attach_file, size: 16),
      label: Text(l10n.attach),
      tooltip: l10n.attachAdd,
      onPressed: () => unawaited(_addAttachment(note)),
    );
  }

  Future<void> _reorderAttachments(
    Note note,
    List<NoteAttachment> order,
  ) async {
    await widget.services.reorderAttachments(note.id, [
      for (final attachment in order) attachment.id,
    ]);
    await _reloadAttachments();
  }

  int _attachmentBytes() => _attachments.fold(0, (sum, attachment) {
    final file = File(attachment.mediaUri);
    return sum + (file.existsSync() ? file.lengthSync() : 0);
  });

  Future<void> _reloadAttachments() async {
    final attachments = await widget.services.attachmentsFor(widget.noteId);
    if (mounted) _rebuild(() => _attachments = attachments);
  }

  /// Camera, photos (several at once) or a file — the same three ways a
  /// note is captured, now onto this one.
  Future<void> _addAttachment(Note note) async {
    final l10n = AppLocalizations.of(context);
    final choice = await nexShowSheet<String>(
      context: context,
      builder: (sheet) => NexSheetBody(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                NexSpacing.md,
                NexSpacing.sm,
                NexSpacing.md,
                NexSpacing.sm,
              ),
              child: Text(
                l10n.attachAdd,
                style: Theme.of(sheet).textTheme.titleLarge,
              ),
            ),
            ListTile(
              key: const ValueKey('attach-camera'),
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(l10n.attachTakePhoto),
              onTap: () => Navigator.pop(sheet, 'camera'),
            ),
            ListTile(
              key: const ValueKey('attach-photos'),
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(l10n.attachChoosePhotos),
              onTap: () => Navigator.pop(sheet, 'photos'),
            ),
            ListTile(
              key: const ValueKey('attach-voice'),
              leading: const Icon(Icons.mic_none),
              title: Text(l10n.attachRecordVoice),
              onTap: () => Navigator.pop(sheet, 'voice'),
            ),
            ListTile(
              key: const ValueKey('attach-file'),
              leading: const Icon(Icons.attach_file),
              title: Text(l10n.attachChooseFile),
              onTap: () => Navigator.pop(sheet, 'file'),
            ),
            const SizedBox(height: NexSpacing.sm),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    try {
      switch (choice) {
        case 'camera':
          final shot = await nexTakePhoto(context);
          if (shot == null) return;
          await _attachPhoto(note.id, await shot.readAsBytes(), shot.path);
        case 'voice':
          await _attachVoice(note.id);
        case 'photos':
          for (final picked in await ImagePicker().pickMultiImage()) {
            await _attachPhoto(
              note.id,
              await picked.readAsBytes(),
              picked.path,
            );
          }
        default:
          final picked = await OsCaptureBridge.pickFile();
          if (picked == null) return;
          final isImage =
              NexFileKinds.of(path: picked.path, mimeType: picked.mimeType) ==
              NexFileKind.image;
          await widget.services.attachFile(
            note.id,
            picked.path,
            kind: isImage ? AttachmentKind.photo : AttachmentKind.file,
            name: picked.filename,
            mimeType: picked.mimeType,
          );
      }
    } catch (_) {
      if (mounted) _toast(l10n.attachFailed);
    }
    await _reloadAttachments();
  }

  /// A spoken aside on a note — what the receipt was for, what was said in
  /// the meeting the whiteboard is from. Recorded with the same sheet as a
  /// voice note, and attached once it is kept.
  Future<void> _attachVoice(String noteId) async {
    final l10n = AppLocalizations.of(context);
    final recorder = AudioRecorder();
    try {
      if (!await recorder.hasPermission()) {
        if (mounted) _toast(l10n.micDenied);
        return;
      }
      final folder = await Directory.systemTemp.createTemp('nex-clip-');
      final path = p.join(folder.path, 'voice.m4a');
      final started = Stopwatch()..start();
      await recorder.start(const RecordConfig(), path: path);
      if (!mounted) return;
      final keep = await nexShowSheet<bool>(
        context: context,
        dismissible: false,
        builder: (_) => RecordingSheet(recorder: recorder),
      );
      final recorded = await recorder.stop();
      started.stop();
      try {
        final file = File(recorded ?? path);
        if (keep != true || !file.existsSync()) return;
        await widget.services.attachFile(
          noteId,
          file.path,
          kind: AttachmentKind.voice,
          mimeType: 'audio/mp4',
          durationMs: started.elapsedMilliseconds,
        );
      } finally {
        await folder.delete(recursive: true);
      }
    } finally {
      await recorder.dispose();
    }
  }

  Future<void> _attachPhoto(String noteId, Uint8List bytes, String path) async {
    final extension = p.extension(path).isNotEmpty
        ? p.extension(path)
        : photoExtension(bytes);
    await widget.services.attachBytes(
      noteId,
      bytes,
      kind: AttachmentKind.photo,
      extension: extension,
      mimeType: extension.toLowerCase() == '.png' ? 'image/png' : 'image/jpeg',
    );
  }

  Future<void> _openAttachment(NoteAttachment attachment) async {
    final l10n = AppLocalizations.of(context);
    if (!File(attachment.mediaUri).existsSync()) {
      _toast(l10n.mediaUnavailable);
      return;
    }
    if (attachment.kind == AttachmentKind.photo) {
      final note = _note;
      if (note != null) await _openGallery(note, at: attachment.mediaUri);
      return;
    }
    if (attachment.kind == AttachmentKind.voice) {
      await VoiceClipSheet.show(context, attachment: attachment);
      return;
    }
    final result = await nexOpenFile(
      attachment.mediaUri,
      mimeType: attachment.mimeType,
    );
    if (mounted && result != FileOpenOutcome.opened) _toast(l10n.cannotOpen);
  }

  /// Every photo the note holds — its own first, then each attached one in
  /// order — opened at [at].
  Future<void> _openGallery(Note note, {required String at}) async {
    final own = note.type == NoteType.photo ? note.mediaUri : null;
    final photos = [
      if (own != null && File(own).existsSync())
        NexGalleryPhoto(own, caption: note.caption),
      for (final attachment in _attachments)
        if (attachment.kind == AttachmentKind.photo &&
            File(attachment.mediaUri).existsSync())
          NexGalleryPhoto(attachment.mediaUri, caption: attachment.caption),
    ];
    if (photos.isEmpty) return;
    await Navigator.of(context).push(
      NexPageRoute<void>(
        builder: (_) => NexPhotoGallery(
          photos: photos,
          initial: math.max(0, photos.indexWhere((p) => p.path == at)),
        ),
        swipeBackEnabled: false,
      ),
    );
  }
}

/// The row of attachment tiles, and the tile that adds one.
///
/// A hold picks a tile up. Moved, it goes where it is dropped; let go where
/// it was, and the hold was a question, so its menu opens — the same hold
/// that always opened it.
class _AttachmentStrip extends StatefulWidget {
  const _AttachmentStrip({
    required this.attachments,
    required this.canAdd,
    required this.onAdd,
    required this.onOpen,
    required this.onHold,
    required this.onReorder,
  });

  final List<NoteAttachment> attachments;
  final bool canAdd;
  final VoidCallback onAdd;
  final ValueChanged<NoteAttachment> onOpen;
  final ValueChanged<NoteAttachment> onHold;

  /// The attachments in their new order.
  final ValueChanged<List<NoteAttachment>> onReorder;

  static const _side = 88.0;

  /// How long a dropped tile takes to fly back into its place — Flutter's
  /// own drop animation, plus a frame.
  static const _settle = Duration(milliseconds: 270);

  @override
  State<_AttachmentStrip> createState() => _AttachmentStripState();
}

class _AttachmentStripState extends State<_AttachmentStrip> {
  /// Shown while a move is saved, so the tile stays where it was dropped
  /// instead of jumping back until the reload arrives.
  List<NoteAttachment>? _moved;

  /// Where the held tile was picked up from.
  int? _pickedFrom;

  @override
  void didUpdateWidget(_AttachmentStrip old) {
    super.didUpdateWidget(old);
    if (old.attachments != widget.attachments) _moved = null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final attachments = _moved ?? widget.attachments;
    const side = _AttachmentStrip._side;
    return SizedBox(
      height: side,
      child: ReorderableListView.builder(
        scrollDirection: Axis.horizontal,
        buildDefaultDragHandles: false,
        itemCount: attachments.length,
        onReorderStart: (index) => _pickedFrom = index,
        onReorder: (from, to) {
          final next = [...attachments];
          final moving = next.removeAt(from);
          next.insert(to > from ? to - 1 : to, moving);
          setState(() => _moved = next);
          widget.onReorder(next);
        },
        // Told the slot it was dropped in, before the move itself: the slot
        // it was picked up from means it never went anywhere.
        //
        // The menu waits for the lifted tile to settle back: it flies home in
        // the list's own overlay, and a sheet opened at once had the tile
        // pass over it on the way.
        onReorderEnd: (slot) {
          final from = _pickedFrom;
          _pickedFrom = null;
          if (from == null || slot != from) return;
          final held = attachments[from];
          unawaited(
            Future<void>.delayed(_AttachmentStrip._settle, () {
              if (mounted) widget.onHold(held);
            }),
          );
        },
        proxyDecorator: (child, index, animation) => AnimatedBuilder(
          animation: animation,
          builder: (context, child) => Transform.scale(
            scale: 1 + 0.06 * NexMotion.curve.transform(animation.value),
            child: Material(
              color: Colors.transparent,
              elevation: 6 * animation.value,
              borderRadius: BorderRadius.circular(NexRadius.md),
              child: child,
            ),
          ),
          child: child,
        ),
        itemBuilder: (context, index) {
          final attachment = attachments[index];
          return ReorderableDelayedDragStartListener(
            key: ValueKey('attachment-${attachment.id}'),
            index: index,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(end: NexSpacing.sm),
              child: AttachmentTile(
                attachment: attachment,
                side: side,
                onTap: () => widget.onOpen(attachment),
              ),
            ),
          );
        },
        footer: widget.canAdd
            ? Tooltip(
                message: l10n.attachAdd,
                child: Material(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(NexRadius.md),
                    side: BorderSide(color: scheme.outlineVariant),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    key: const ValueKey('attachment-add'),
                    onTap: widget.onAdd,
                    child: SizedBox(
                      width: side,
                      height: side,
                      child: Semantics(
                        button: true,
                        label: l10n.attachAdd,
                        child: Icon(
                          Icons.add_photo_alternate_outlined,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
              )
            : null,
      ),
    );
  }
}
