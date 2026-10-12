part of '../vault_screen.dart';

/// Private saved messages: a conversation with yourself.
///
/// Laid out like every messenger people already know: bubbles with room
/// between them, grouped by day, the time in the corner, and everything that
/// can be done with one — copy, share, open, delete — a tap away in its own
/// sheet instead of two bare icons under every bubble. A photo opens full
/// screen with zoom, a file opens or is shared, a recording plays in place.
extension _VaultMessages on _VaultScreenState {
  Widget _messages(AppLocalizations l, ThemeData theme) {
    final messages = entries.where((e) => e.kind == VaultKind.message).toList()
      ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    final persian = Localizations.localeOf(context).languageCode == 'fa';
    // Newest at the bottom, the way a conversation reads; the list is built
    // reversed so it opens there and stays there as messages arrive.
    final rows = <Widget>[];
    DateTime? day;
    for (final message in messages) {
      final local = message.updatedAt.toLocal();
      final today = DateTime(local.year, local.month, local.day);
      if (day != today) {
        day = today;
        rows.add(_DayChip(label: _dayLabel(l, today, persian)));
      }
      rows.add(
        _MessageBubble(
          key: ValueKey(message.id),
          entry: message,
          files: _vaultFiles,
          time: nexDigits(
            '${local.hour.toString().padLeft(2, '0')}:'
            '${local.minute.toString().padLeft(2, '0')}',
            persian: persian,
          ),
          copied: copiedField == message.id,
          onActions: busy ? null : () => unawaited(_messageActions(message)),
          onShare: () => unawaited(_shareAttachment(message)),
        ),
      );
    }
    return Column(
      children: [
        Expanded(
          child: messages.isEmpty
              ? _emptyMessages(l, theme)
              : ListView(
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(
                    NexSpacing.md,
                    NexSpacing.md,
                    NexSpacing.md,
                    NexSpacing.sm,
                  ),
                  children: rows.reversed.toList(),
                ),
        ),
        _composer(l, theme),
      ],
    );
  }

  String _dayLabel(AppLocalizations l, DateTime day, bool persian) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final gap = today.difference(day).inDays;
    if (gap == 0) return l.timelineGroupToday;
    if (gap == 1) return l.timelineGroupYesterday;
    return nexDisplayDate(day, solar: persian, persian: persian);
  }

  Widget _emptyMessages(AppLocalizations l, ThemeData theme) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(NexSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.forum_outlined,
            size: 48,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: NexSpacing.md),
          Text(
            l.vaultMessagesEmpty,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
  );

  /// The box, with the attach button on one side and send on the other —
  /// each with room around it, the way the assistant's composer has.
  Widget _composer(AppLocalizations l, ThemeData theme) => Padding(
    padding: const EdgeInsets.fromLTRB(
      NexSpacing.sm,
      NexSpacing.sm,
      NexSpacing.md,
      NexSpacing.md,
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        IconButton(
          tooltip: l.vaultAttach,
          onPressed: busy ? null : () => unawaited(_attach()),
          icon: const Icon(Icons.add_circle_outline),
        ),
        const SizedBox(width: NexSpacing.xs),
        Expanded(
          child: NexTextField(
            controller: messageInput,
            onCopy: PrivateClipboard.copy,
            minLines: 1,
            maxLines: 5,
            maxLength: 10000,
            autocorrect: false,
            enableSuggestions: false,
            enableIMEPersonalizedLearning: false,
            onChanged: (_) => _touch(),
            decoration: InputDecoration(
              counterText: '',
              hintText: l.vaultMessageHint,
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHighest,
              border: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(NexRadius.xl)),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: NexSpacing.md,
                vertical: NexSpacing.sm,
              ),
            ),
          ),
        ),
        const SizedBox(width: NexSpacing.sm),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: messageInput,
          builder: (context, value, _) => IconButton.filled(
            tooltip: l.vaultSave,
            onPressed: busy || value.text.trim().isEmpty
                ? null
                : () => unawaited(_sendText()),
            icon: const Icon(Icons.send_rounded),
          ),
        ),
      ],
    ),
  );

  Future<void> _sendText() async {
    final text = messageInput.text.trim();
    if (text.isEmpty) return;
    final empty = VaultStore.empty(VaultKind.message);
    await _operate(
      () => store.save(
        VaultEntry(
          id: empty.id,
          kind: empty.kind,
          fields: {'text': text},
          updatedAt: empty.updatedAt,
        ),
      ),
    );
    if (mounted && error == null && messageInput.text.trim() == text) {
      messageInput.clear();
    }
  }

  /// Everything one message can do, in one sheet.
  Future<void> _messageActions(VaultEntry entry) async {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final text = entry.value('text');
    final kind = entry.value('fileKind');
    final hasFile = entry.value('file').isNotEmpty;
    final choice = await nexShowSheet<String>(
      context: context,
      builder: (sheet) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: NexSpacing.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (text.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.copy_outlined),
                title: Text(l.copy),
                onTap: () => Navigator.pop(sheet, 'copy'),
              ),
            if (hasFile && kind == 'file')
              ListTile(
                leading: const Icon(Icons.open_in_new),
                title: Text(l.open),
                onTap: () => Navigator.pop(sheet, 'open'),
              ),
            if (hasFile)
              ListTile(
                leading: const Icon(Icons.ios_share_outlined),
                title: Text(l.share),
                subtitle: Text(l.vaultShareLeaves),
                onTap: () => Navigator.pop(sheet, 'share'),
              ),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: theme.colorScheme.error,
              ),
              title: Text(
                l.delete,
                style: TextStyle(color: theme.colorScheme.error),
              ),
              onTap: () => Navigator.pop(sheet, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || !unlocked) return;
    switch (choice) {
      case 'copy':
        await _copy(entry.id, text);
      case 'open':
        await _openAttachment(entry);
      case 'share':
        await _shareAttachment(entry);
      case 'delete':
        final yes = await nexShowDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l.vaultDelete),
            content: NexDialogBody(child: Text(l.vaultDeleteHint)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error,
                  foregroundColor: Theme.of(ctx).colorScheme.onError,
                ),
                child: Text(l.delete),
              ),
            ],
          ),
        );
        if (yes == true && mounted && unlocked) {
          await _operate(() => _deleteMessage(entry));
        }
    }
  }

  /// Hands a decrypted copy of the attachment to another app. The copy is in
  /// the cache, and goes when the vault locks.
  Future<void> _shareAttachment(VaultEntry entry) async {
    _touch();
    try {
      final copy = await _vaultFiles.openCopy(
        entry.value('file'),
        _attachmentName(entry),
      );
      await nexSendFileOut(
        copy.path,
        mimeType: entry.value('fileMime').isEmpty
            ? null
            : entry.value('fileMime'),
      );
    } catch (_) {
      if (mounted) {
        _rebuild(
          () => error = AppLocalizations.of(context).vaultAttachUnreadable,
        );
      }
    }
  }

  Future<void> _openAttachment(VaultEntry entry) async {
    _touch();
    try {
      final copy = await _vaultFiles.openCopy(
        entry.value('file'),
        _attachmentName(entry),
      );
      final outcome = await nexOpenFile(
        copy.path,
        mimeType: entry.value('fileMime').isEmpty
            ? null
            : entry.value('fileMime'),
      );
      if (outcome == FileOpenOutcome.failed) {
        await _shareAttachment(entry);
      }
    } catch (_) {
      if (mounted) {
        _rebuild(
          () => error = AppLocalizations.of(context).vaultAttachUnreadable,
        );
      }
    }
  }

  static String _attachmentName(VaultEntry entry) {
    final name = entry.value('fileName');
    if (name.isNotEmpty) return name;
    return switch (entry.value('fileKind')) {
      'voice' => 'voice.m4a',
      'photo' => 'photo.jpg',
      _ => 'attachment',
    };
  }
}

/// "Today", "Yesterday" or the date, centred between a day's messages.
class _DayChip extends StatelessWidget {
  const _DayChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: NexSpacing.sm),
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(NexRadius.xl),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: NexSpacing.md,
              vertical: NexSpacing.xs,
            ),
            child: Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One message: its attachment, its words and its time, in a bubble with
/// room around it. Tap or hold the bubble for what can be done with it.
class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    super.key,
    required this.entry,
    required this.files,
    required this.time,
    required this.copied,
    required this.onActions,
    required this.onShare,
  });

  final VaultEntry entry;
  final VaultFiles files;
  final String time;
  final bool copied;
  final VoidCallback? onActions;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = entry.value('text');
    final hasFile = entry.value('file').isNotEmpty;
    final photo = hasFile && entry.value('fileKind') == 'photo';
    const corner = Radius.circular(NexRadius.lg);
    return Padding(
      padding: const EdgeInsets.only(bottom: NexSpacing.sm),
      child: Align(
        alignment: AlignmentDirectional.centerEnd,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.8,
          ),
          child: Material(
            color: scheme.secondaryContainer,
            // The corner nearest the edge is the small one: which side the
            // message came from, read at a glance.
            borderRadius: const BorderRadiusDirectional.only(
              topStart: corner,
              topEnd: corner,
              bottomStart: corner,
              bottomEnd: Radius.circular(NexRadius.xs),
            ).resolve(Directionality.of(context)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onActions,
              onLongPress: onActions,
              child: Padding(
                padding: photo
                    ? const EdgeInsets.all(NexSpacing.xs)
                    : const EdgeInsets.fromLTRB(
                        NexSpacing.md,
                        NexSpacing.sm,
                        NexSpacing.md,
                        NexSpacing.xs,
                      ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (hasFile)
                      _VaultAttachmentView(
                        key: ValueKey(entry.value('file')),
                        entry: entry,
                        files: files,
                        onShare: onShare,
                      ),
                    if (text.isNotEmpty)
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          photo ? NexSpacing.sm : 0,
                          hasFile ? NexSpacing.sm : 0,
                          photo ? NexSpacing.sm : 0,
                          0,
                        ),
                        child: Text(
                          text,
                          textDirection: RegExp('[؀-ۿ]').hasMatch(text)
                              ? TextDirection.rtl
                              : TextDirection.ltr,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: scheme.onSecondaryContainer,
                          ),
                        ),
                      ),
                    Padding(
                      padding: EdgeInsetsDirectional.only(
                        top: NexSpacing.xs,
                        end: photo ? NexSpacing.sm : 0,
                        bottom: photo ? NexSpacing.xs : 0,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (copied) ...[
                            Icon(
                              Icons.check,
                              size: 14,
                              color: scheme.onSecondaryContainer,
                            ),
                            const SizedBox(width: NexSpacing.xs),
                          ],
                          Text(
                            time,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSecondaryContainer.withValues(
                                alpha: 0.7,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
