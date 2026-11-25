part of '../note_detail_sheet.dart';

/// The files a note carries after its own — `docs/14-attachments.md`.
///
/// A row of tiles under the note's body: each photo as itself, each file as
/// its kind and name, and a last tile to attach another. A tap opens one —
/// a photo full screen, a file in whatever opens it — and a hold offers its
/// caption and removing it, with an Undo.
extension _DetailAttachments on _NoteDetailSheetState {
  /// Notes that can carry files: text and links gain them, photo and file
  /// notes gain more. A checklist and a voice note do not,
  /// yet (docs/14-attachments.md, "Later").
  bool _canAttach(Note note) =>
      !note.isSetAside() &&
      switch (note.type) {
        NoteType.text ||
        NoteType.link ||
        NoteType.photo ||
        NoteType.file ||
        NoteType.video => true,
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
    final preview = _attachments
        .where((a) => a.id == _previewAttachmentId)
        .firstOrNull;
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
      if (preview != null) ...[
        const SizedBox(height: NexSpacing.sm),
        Row(
          children: [
            Expanded(
              child: Text(
                preview.name ?? p.basename(preview.mediaUri),
                style: theme.textTheme.labelLarge,
              ),
            ),
            IconButton(
              key: const ValueKey('attachment-preview-close'),
              tooltip: l10n.closeLabel,
              onPressed: () => _rebuild(() => _previewAttachmentId = null),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        KeyedSubtree(
          key: ValueKey('attachment-reader-${preview.id}'),
          child: AttachmentTile.lookOf(preview) == AttachmentLook.video
              ? NexVideoPlayer(
                  path: preview.mediaUri,
                  onOpen: () => unawaited(_openAttachmentExternally(preview)),
                )
              : NexPdfReader(
                  path: preview.mediaUri,
                  onOpen: () => unawaited(_openAttachmentExternally(preview)),
                ),
        ),
      ],
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

  /// The bytes the note's attachments take on disk, for the strip's
  /// heading. Stated once per change of the list, not once per rebuild:
  /// this used to stat every file synchronously on every build, and a
  /// dozen attachments made every sheet repaint pay a dozen disk reads on
  /// the UI isolate. The cache fields live on the sheet's state
  /// (`_attachmentBytesOf`, `_attachmentBytesTotal`), because an extension
  /// cannot hold them.
  int _attachmentBytes() {
    final attachments = _attachments;
    if (identical(_attachmentBytesOf, attachments)) {
      return _attachmentBytesTotal;
    }
    var total = 0;
    for (final attachment in attachments) {
      try {
        final file = File(attachment.mediaUri);
        if (file.existsSync()) total += file.lengthSync();
      } catch (_) {
        // A file that cannot be stated right now counts as nothing; the
        // number is for a heading, not an audit.
      }
    }
    _attachmentBytesOf = attachments;
    _attachmentBytesTotal = total;
    return total;
  }

  Future<void> _reloadAttachments() async {
    final attachments = await widget.services.attachmentsFor(widget.noteId);
    if (mounted) _rebuild(() => _attachments = attachments);
  }

  /// Camera, photos and videos (several at once) or a file — the same ways a
  /// note is captured, now onto this one. Media and File stay separate: the
  /// picker shows only photos and videos, and the file manager keeps taking
  /// everything else.
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
              key: const ValueKey('attach-media'),
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(l10n.attachChooseMedia),
              onTap: () => Navigator.pop(sheet, 'media'),
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
    var landed = false;
    try {
      switch (choice) {
        case 'camera':
          // A photo on a tap, a recording on a hold — the same panel the
          // timeline opens. A recording is attached as a video file, so the
          // strip shows its frame and its player opens it; only a real image
          // becomes a photo attachment.
          final shot = await nexTakeShot(context, video: true);
          if (shot == null) return;
          // Copied and hashed from the file, never read whole into memory —
          // the same straight path the timeline's photo capture takes
          // (PERF-07).
          landed =
              await widget.services.attachFile(
                note.id,
                shot.file.path,
                kind: shot.isVideo ? AttachmentKind.file : AttachmentKind.photo,
                name: shot.isVideo ? p.basename(shot.file.path) : null,
                mimeType:
                    shot.file.mimeType ?? (shot.isVideo ? 'video/mp4' : null),
                refresh: false,
              ) !=
              null;
        case 'voice':
          landed = await _attachVoice(note.id);
        case 'media':
          final chosen = await nexPickMedia(
            context,
            picker: widget.services.mediaPicker,
          );
          for (final picked in chosen.media) {
            // Copied and hashed from the file, never read whole into
            // memory: a multi-photo pick can be a dozen pictures, and each
            // used to make two full copies of itself on this loop (read
            // into the heap, then an isolate copy to hash) — plus a full
            // timeline re-read per photo. The timeline's photo path stopped
            // paying that in 2.6.10 (PERF-07); this is the same path,
            // arrived at from the note.
            //
            // A video keeps its own name and goes on as a file attachment,
            // so the strip shows its frame and its player opens it; only a
            // real image becomes a photo attachment.
            final video = picked.isVideo;
            landed =
                await widget.services.attachFile(
                      note.id,
                      picked.path,
                      kind: video ? AttachmentKind.file : AttachmentKind.photo,
                      name: video ? picked.name : null,
                      mimeType: picked.mimeType,
                      // The one refresh below the loop covers the whole batch.
                      refresh: false,
                    ) !=
                    null ||
                landed;
          }
        default:
          final picked = await nexPickAttachment(context);
          if (picked == null) return;
          final isImage =
              NexFileKinds.of(path: picked.path, mimeType: picked.mimeType) ==
              NexFileKind.image;
          landed =
              await widget.services.attachFile(
                note.id,
                picked.path,
                kind: isImage ? AttachmentKind.photo : AttachmentKind.file,
                name: picked.filename,
                mimeType: picked.mimeType,
                refresh: false,
              ) !=
              null;
      }
    } catch (_) {
      if (mounted) _toast(l10n.attachFailed);
    }
    // One refresh for the whole batch — the card's paperclip count is the
    // only thing outside this sheet that changed, and the strip itself
    // re-reads below. The attachments are already durable: a failed
    // refresh must not be reported as a failed attach.
    if (landed) {
      try {
        await widget.services.refreshTimeline();
      } catch (_) {}
    }
    await _reloadAttachments();
  }

  /// A spoken aside on a note — what the receipt was for, what was said in
  /// the meeting the whiteboard is from. Recorded with the same sheet as a
  /// voice note, and attached once it is kept.
  ///
  /// Recorded straight into the media folder, the way a voice note is
  /// ([NexVoiceSpool]): the clip used to be written to a temporary folder
  /// and copied from there, so a full disk between the two took the
  /// recording with it — the temp folder was deleted in a `finally` whether
  /// the copy had landed or not, and the meeting's words went with it.
  /// Written where it belongs, a clip whose attach fails stays on disk
  /// under the sweep's hour of grace, where Retry can find it. Whether the
  /// clip landed.
  Future<bool> _attachVoice(String noteId) async {
    final l10n = AppLocalizations.of(context);
    final recorder = AudioRecorder();
    try {
      if (!await recorder.hasPermission()) {
        if (mounted) _toast(l10n.micDenied);
        return false;
      }
      final spool = await NexVoiceSpool.start(
        recorder,
        widget.services.mediaDir,
      );
      if (!mounted) {
        await spool.discard();
        return false;
      }
      final started = Stopwatch()..start();
      final keep = await nexShowSheet<bool>(
        context: context,
        dismissible: false,
        builder: (_) => RecordingSheet(recorder: recorder),
      );
      final recorded = keep == true ? await spool.stop() : null;
      if (keep != true) await spool.discard();
      started.stop();
      if (recorded == null) return false;
      final hash = await sha256OfFile(recorded);
      if (hash == null) {
        throw StateError('the recording could not be read back');
      }
      final attached = await widget.services.attachStored(
        noteId,
        mediaUri: recorded,
        mediaHash: hash,
        kind: AttachmentKind.voice,
        mimeType: 'audio/mp4',
        durationMs: started.elapsedMilliseconds,
        refresh: false,
      );
      return attached != null;
    } finally {
      await recorder.dispose();
    }
  }

  Future<void> _openAttachment(NoteAttachment attachment) async {
    final l10n = AppLocalizations.of(context);
    if (!File(attachment.mediaUri).existsSync()) {
      _toast(l10n.mediaUnavailable);
      return;
    }
    // What the file is, not what its row was once labelled: a PDF stored as a
    // photo by an older build must not be handed to the photo gallery, and a
    // video stored the same way must open its player.
    switch (AttachmentTile.lookOf(attachment)) {
      case AttachmentLook.photo:
        final note = _note;
        if (note != null) await _openGallery(note, at: attachment.mediaUri);
      case AttachmentLook.voice:
        await VoiceClipSheet.show(context, attachment: attachment);
      case AttachmentLook.video || AttachmentLook.pdf:
        await _player?.pause();
        if (mounted) _rebuild(() => _previewAttachmentId = attachment.id);
      default:
        await _openAttachmentExternally(attachment);
    }
  }

  Future<void> _openAttachmentExternally(NoteAttachment attachment) async {
    final result = await nexOpenFile(
      attachment.mediaUri,
      mimeType: attachment.mimeType,
    );
    if (mounted && result != FileOpenOutcome.opened) {
      _toast(AppLocalizations.of(context).cannotOpen);
    }
  }

  /// Every photo the note holds — its own first, then each attached one in
  /// order — opened at [at].
  Future<void> _openGallery(Note note, {required String at}) async {
    final own = note.type == NoteType.photo ? note.mediaUri : null;
    final photos = [
      if (own != null && File(own).existsSync())
        NexGalleryPhoto(own, caption: note.caption),
      for (final attachment in _attachments)
        if (AttachmentTile.lookOf(attachment) == AttachmentLook.photo &&
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
        onReorderItem: (from, to) {
          final next = [...attachments];
          final moving = next.removeAt(from);
          next.insert(to, moving);
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
