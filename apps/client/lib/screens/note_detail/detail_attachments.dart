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
    return [
      const SizedBox(height: NexSpacing.md),
      Text(l10n.attachmentsTitle, style: Theme.of(context).textTheme.bodySmall),
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
      await Navigator.of(context).push(
        NexPageRoute<void>(
          builder: (_) => NexPhotoViewer.file(attachment.mediaUri),
          swipeBackEnabled: false,
        ),
      );
      return;
    }
    final result = await nexOpenFile(
      attachment.mediaUri,
      mimeType: attachment.mimeType,
    );
    if (mounted && result != FileOpenOutcome.opened) _toast(l10n.cannotOpen);
  }

  Future<void> _attachmentMenu(NoteAttachment attachment) async {
    final l10n = AppLocalizations.of(context);
    final index = _attachments.indexWhere((a) => a.id == attachment.id);
    final choice = await nexShowSheet<String>(
      context: context,
      builder: (sheet) => NexSheetBody(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: Text(l10n.attachOpen),
              onTap: () => Navigator.pop(sheet, 'open'),
            ),
            ListTile(
              key: const ValueKey('attachment-caption'),
              leading: const Icon(Icons.short_text),
              title: Text(
                attachment.caption == null ? l10n.addCaption : l10n.editCaption,
              ),
              onTap: () => Navigator.pop(sheet, 'caption'),
            ),
            // Dragging is the quick way; these are the way a screen reader
            // has, and the way for anyone who did not know a tile moves.
            if (index > 0)
              ListTile(
                key: const ValueKey('attachment-earlier'),
                leading: const Icon(Icons.arrow_back),
                title: Text(l10n.attachMoveEarlier),
                onTap: () => Navigator.pop(sheet, 'earlier'),
              ),
            if (index >= 0 && index < _attachments.length - 1)
              ListTile(
                key: const ValueKey('attachment-later'),
                leading: const Icon(Icons.arrow_forward),
                title: Text(l10n.attachMoveLater),
                onTap: () => Navigator.pop(sheet, 'later'),
              ),
            ListTile(
              key: const ValueKey('attachment-remove'),
              leading: Icon(
                Icons.remove_circle_outline,
                color: Theme.of(sheet).colorScheme.error,
              ),
              title: Text(
                l10n.attachRemove,
                style: TextStyle(color: Theme.of(sheet).colorScheme.error),
              ),
              onTap: () => Navigator.pop(sheet, 'remove'),
            ),
            const SizedBox(height: NexSpacing.sm),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'earlier' || 'later':
        final note = _note;
        if (note == null || index < 0) return;
        final order = [..._attachments]..removeAt(index);
        order.insert(choice == 'earlier' ? index - 1 : index + 1, attachment);
        await _reorderAttachments(note, order);
      case 'open':
        await _openAttachment(attachment);
      case 'caption':
        final preferences = widget.preferences;
        if (preferences == null) return;
        final caption = await NoteEditorSheet.show(
          context,
          initial: attachment.caption ?? '',
          preferences: preferences,
          draftKey: 'caption-${attachment.id}',
          allowEmpty: true,
        );
        if (caption == null) return;
        await widget.services.setAttachmentCaption(attachment.id, caption);
        preferences.editorDrafts?.clear('caption-${attachment.id}');
        await _reloadAttachments();
      case 'remove':
        await widget.services.removeAttachment(attachment.id);
        await _reloadAttachments();
        if (!mounted) return;
        nexShowBanner(
          context,
          message: l10n.attachRemoved,
          actionLabel: l10n.undo,
          onAction: () => unawaited(() async {
            await widget.services.restoreAttachment(attachment.id);
            await _reloadAttachments();
          }()),
        );
    }
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
        onReorderEnd: (slot) {
          final from = _pickedFrom;
          _pickedFrom = null;
          if (from == null || slot != from) return;
          widget.onHold(attachments[from]);
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
              child: _AttachmentTile(
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

class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({
    required this.attachment,
    required this.side,
    required this.onTap,
  });

  final NoteAttachment attachment;
  final double side;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final name =
        attachment.name ??
        attachment.caption ??
        p.basename(attachment.mediaUri);
    final photo = attachment.kind == AttachmentKind.photo;
    return Semantics(
      button: true,
      label: [
        photo ? AppLocalizations.of(context).photo : name,
        ?attachment.caption,
      ].join('. '),
      child: Material(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(NexRadius.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: side,
            height: side,
            child: photo
                ? Image.file(
                    File(attachment.mediaUri),
                    fit: BoxFit.cover,
                    cacheWidth: (side * ratio).round(),
                    errorBuilder: (_, _, _) =>
                        const Icon(Icons.image_not_supported_outlined),
                  )
                : Padding(
                    padding: const EdgeInsets.all(NexSpacing.sm),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.insert_drive_file_outlined,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: NexSpacing.xs),
                        Text(
                          name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
