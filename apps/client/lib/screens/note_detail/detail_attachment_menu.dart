part of '../note_detail_sheet.dart';

/// What can be done with one attached file, from a hold on its tile.
///
/// The file first — its picture or kind, its name, its size — so the sheet
/// says which one it is about; then what to do with it, the everyday things
/// first: open it, give it words, send or save it on its own, rename it.
/// Then what reshapes the note: make a photo the note's own, move it, take
/// it out as a note of its own, or remove it.
extension _DetailAttachmentMenu on _NoteDetailSheetState {
  Future<void> _attachmentMenu(NoteAttachment attachment) async {
    final l10n = AppLocalizations.of(context);
    final note = _note;
    if (note == null) return;
    final index = _attachments.indexWhere((a) => a.id == attachment.id);
    final look = AttachmentTile.lookOf(attachment);
    final file = File(attachment.mediaUri);
    final size = file.existsSync() ? file.lengthSync() : 0;
    final persian = l10n.localeName == 'fa';
    final canPromote =
        note.type == NoteType.photo &&
        note.mediaUri != null &&
        attachment.kind == AttachmentKind.photo;
    final choice = await nexShowSheet<String>(
      context: context,
      builder: (sheet) {
        final theme = Theme.of(sheet);
        ListTile action(
          String key,
          IconData icon,
          String label, {
          bool danger = false,
        }) => ListTile(
          key: ValueKey('attachment-$key'),
          leading: Icon(icon, color: danger ? theme.colorScheme.error : null),
          title: Text(
            label,
            style: danger ? TextStyle(color: theme.colorScheme.error) : null,
          ),
          onTap: () => Navigator.pop(sheet, key),
        );
        return NexSheetBody(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    NexSpacing.md,
                    NexSpacing.xs,
                    NexSpacing.md,
                    NexSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      ExcludeSemantics(
                        child: AttachmentTile(
                          attachment: attachment,
                          side: 56,
                          onTap: () => Navigator.pop(sheet, 'open'),
                        ),
                      ),
                      const SizedBox(width: NexSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              attachment.name ??
                                  attachment.caption ??
                                  switch (look) {
                                    AttachmentLook.photo => l10n.photo,
                                    AttachmentLook.voice => l10n.attachVoice,
                                    _ => p.basename(attachment.mediaUri),
                                  },
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              nexDigits(nexFormatBytes(size), persian: persian),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                action('open', Icons.open_in_new, l10n.attachOpen),
                if (look == AttachmentLook.photo)
                  action('edit', Icons.edit_outlined, l10n.edit),
                action(
                  'caption',
                  Icons.short_text,
                  attachment.caption == null
                      ? l10n.addCaption
                      : l10n.editCaption,
                ),
                action('share', Icons.ios_share, l10n.share),
                action('save', Icons.download_outlined, l10n.saveToDevice),
                if (attachment.kind == AttachmentKind.file)
                  action(
                    'rename',
                    Icons.drive_file_rename_outline,
                    l10n.rename,
                  ),
                if (canPromote)
                  action('main', Icons.wallpaper_outlined, l10n.attachMakeMain),
                // Dragging is the quick way; these are the way a screen
                // reader has, and the way for anyone who did not know a tile
                // moves.
                if (index > 0)
                  action('earlier', Icons.arrow_back, l10n.attachMoveEarlier),
                if (index >= 0 && index < _attachments.length - 1)
                  action('later', Icons.arrow_forward, l10n.attachMoveLater),
                action('detach', Icons.call_split, l10n.attachDetach),
                action(
                  'remove',
                  Icons.remove_circle_outline,
                  l10n.attachRemove,
                  danger: true,
                ),
                const SizedBox(height: NexSpacing.sm),
              ],
            ),
          ),
        );
      },
    );
    if (!mounted || choice == null) return;
    await _attachmentAction(note, attachment, index, choice);
  }

  Future<void> _attachmentAction(
    Note note,
    NoteAttachment attachment,
    int index,
    String choice,
  ) async {
    final l10n = AppLocalizations.of(context);
    final services = widget.services;
    switch (choice) {
      case 'earlier' || 'later':
        if (index < 0) return;
        final order = [..._attachments]..removeAt(index);
        order.insert(choice == 'earlier' ? index - 1 : index + 1, attachment);
        await _reorderAttachments(note, order);
      case 'open':
        await _openAttachment(attachment);
      case 'edit':
        await _editAttachmentImage(attachment);
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
        await services.setAttachmentCaption(attachment.id, caption);
        preferences.editorDrafts?.clear('caption-${attachment.id}');
        await _reloadAttachments();
      case 'share':
        if (!await nexShareAttachment(attachment) && mounted) {
          _toast(l10n.mediaUnavailable);
        }
      case 'save':
        final outcome = await nexSaveAttachmentToDevice(attachment);
        if (!mounted) return;
        switch (outcome) {
          case SaveOutcome.saved:
            nexShowBanner(context, message: l10n.savedToDevice);
          case SaveOutcome.failed:
            nexShowBanner(
              context,
              message: l10n.saveToDeviceFailed,
              kind: NexBannerKind.failed,
            );
          case SaveOutcome.cancelled:
            break;
        }
      case 'rename':
        final name = await nexAskFileName(
          context,
          current: attachment.name ?? p.basename(attachment.mediaUri),
        );
        if (name == null) return;
        await services.renameAttachment(attachment.id, name);
        await _reloadAttachments();
      case 'main':
        if (!await services.promoteAttachment(note.id, attachment.id)) return;
        await _reload();
        if (!mounted) return;
        nexShowBanner(context, message: l10n.attachMadeMain);
      case 'detach':
        final made = await services.detachAttachment(attachment.id);
        await _reloadAttachments();
        if (!mounted || made == null) return;
        nexShowBanner(context, message: l10n.attachDetached);
      case 'remove':
        await services.removeAttachment(attachment.id);
        await _reloadAttachments();
        if (!mounted) return;
        nexShowBanner(
          context,
          message: l10n.attachRemoved,
          actionLabel: l10n.undo,
          onAction: () => unawaited(() async {
            await services.restoreAttachment(attachment.id);
            await _reloadAttachments();
          }()),
        );
    }
  }

  Future<void> _editAttachmentImage(NoteAttachment attachment) async {
    final draftKey = 'attachment-photo-${attachment.id}';
    try {
      final original = await File(attachment.mediaUri).readAsBytes();
      if (!mounted) return;
      final edited = await Navigator.of(context).push<Uint8List>(
        NexPageRoute(
          swipeBackEnabled: false,
          builder: (_) => PhotoCropScreen(
            image: original,
            drafts: widget.preferences?.editorDrafts,
            draftKey: draftKey,
          ),
        ),
      );
      if (edited == null || !mounted) return;
      final encoded = await compute(encodeEditedPhoto, (
        bytes: edited,
        wasJpeg:
            original.length > 2 && original[0] == 0xff && original[1] == 0xd8,
      ));
      if (!await widget.services.updateAttachmentImage(attachment, encoded)) {
        throw StateError('Attachment changed while editing');
      }
      widget.preferences?.editorDrafts?.clear('$draftKey-crop');
      widget.preferences?.editorDrafts?.clear('$draftKey-annotation');
      await _reloadAttachments();
    } catch (_) {
      if (mounted) {
        nexShowBanner(
          context,
          message: AppLocalizations.of(context).editPhotoFailed,
          kind: NexBannerKind.failed,
        );
      }
    }
  }
}
