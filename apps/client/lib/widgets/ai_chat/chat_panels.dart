part of '../ai_chat_sheet.dart';

/// What the history button opens: every saved conversation, newest first.
///
/// Returns the thread to reopen, wrapped — a bare `ChatThread?` cannot tell
/// "the user picked nothing" from "the user asked for a new conversation",
/// and those do opposite things.
@immutable
class ChatHistoryChoice {
  const ChatHistoryChoice(this.thread);

  /// Null means: start a fresh conversation.
  final ChatThread? thread;
}

class ChatHistorySheet extends StatelessWidget {
  const ChatHistorySheet({
    super.key,
    required this.history,
    this.activeThreadId,
  });

  final ChatHistory history;
  final String? activeThreadId;

  static Future<ChatHistoryChoice?> show(
    BuildContext context, {
    required ChatHistory history,
    String? activeThreadId,
  }) => nexShowSheet<ChatHistoryChoice>(
    context: context,
    builder: (_) =>
        ChatHistorySheet(history: history, activeThreadId: activeThreadId),
  );

  Future<void> _clear(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await nexShowDialog<bool>(
      context: context,
      builder: (context) => NexAlertDialog(
        title: Text(l10n.chatClearHistory),
        content: NexDialogBody(child: Text(l10n.chatClearHistoryBody)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed == true) await history.clear();
  }

  String _group(ChatThread thread, DateTime today, AppLocalizations l10n) {
    final day = DateUtils.dateOnly(thread.updatedAt.toLocal());
    if (!day.isBefore(today)) return l10n.timelineGroupToday;
    if (day == DateTime(today.year, today.month, today.day - 1)) {
      return l10n.timelineGroupYesterday;
    }
    if (!day.isBefore(DateTime(today.year, today.month, today.day - 7))) {
      return l10n.timelineGroupWeek;
    }
    return l10n.timelineGroupOlder;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: history,
    builder: (context, _) {
      final l10n = AppLocalizations.of(context);
      final theme = Theme.of(context);
      final threads = history.threads;
      final rows = <Object>[];
      final today = DateUtils.dateOnly(DateTime.now());
      String? previous;
      for (final thread in threads) {
        final group = _group(thread, today, l10n);
        if (group != previous) rows.add(group);
        rows.add(thread);
        previous = group;
      }
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.82,
        ),
        child: Padding(
          padding: EdgeInsets.only(bottom: nexBottomInset(context)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.only(
                  start: NexSpacing.md,
                  end: NexSpacing.sm,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.chatHistory,
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: l10n.chatClearHistory,
                      onPressed: threads.isEmpty
                          ? null
                          : () => unawaited(_clear(context)),
                      icon: const Icon(Icons.delete_sweep_outlined),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: NexSpacing.md,
                  vertical: NexSpacing.sm,
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: () =>
                        Navigator.pop(context, const ChatHistoryChoice(null)),
                    icon: const Icon(Icons.add_comment_outlined),
                    label: Text(l10n.chatNewConversation),
                  ),
                ),
              ),
              if (threads.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(NexSpacing.xl),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.forum_outlined,
                        size: 36,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: NexSpacing.md),
                      Text(
                        l10n.chatHistoryEmpty,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Flexible(
                  child: NexDismissOnOverscroll(
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(
                        NexSpacing.md,
                        0,
                        NexSpacing.md,
                        NexSpacing.md,
                      ),
                      itemCount: rows.length,
                      itemBuilder: (context, index) {
                        final row = rows[index];
                        if (row is String) {
                          return Padding(
                            padding: const EdgeInsets.only(
                              top: NexSpacing.md,
                              bottom: NexSpacing.sm,
                            ),
                            child: Text(
                              row,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          );
                        }
                        final thread = row as ChatThread;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: NexSpacing.sm),
                          child: _HistoryThreadRow(
                            thread: thread,
                            selected: thread.id == activeThreadId,
                            onOpen: () => Navigator.pop(
                              context,
                              ChatHistoryChoice(thread),
                            ),
                            onDelete: () =>
                                unawaited(history.remove(thread.id)),
                          ),
                        );
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// A local preview, never an extra model request or a change to saved text.
class _HistoryThreadRow extends StatelessWidget {
  const _HistoryThreadRow({
    required this.thread,
    required this.selected,
    required this.onOpen,
    required this.onDelete,
  });
  final ChatThread thread;
  final bool selected;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  String _preview(String text) => NexMarkdownText.preview(
    String.fromCharCodes(text.runes.take(400)),
  ).replaceAll(RegExp(r'\s+'), ' ').trim();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final answer = thread.messages.reversed
        .where(
          (m) => m.role == ChatRole.assistant && m.content.trim().isNotEmpty,
        )
        .firstOrNull;
    final preview = answer == null ? '' : _preview(answer.content);
    return Semantics(
      selected: selected,
      child: NexSurface(
        key: ValueKey('history-thread-${thread.id}'),
        color: selected
            ? Color.alphaBlend(
                theme.colorScheme.primary.withValues(alpha: 0.08),
                theme.colorScheme.surfaceContainerLow,
              )
            : theme.colorScheme.surfaceContainerLow,
        child: InkWell(
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(
              start: NexSpacing.md,
              top: NexSpacing.sm,
              bottom: NexSpacing.sm,
            ),
            child: Row(
              children: [
                ExcludeSemantics(
                  child: Icon(
                    selected ? Icons.chat_bubble : Icons.chat_bubble_outline,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: NexSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      NexTextSurface(
                        _preview(thread.title),
                        maxLines: 2,
                        style: theme.textTheme.titleSmall,
                      ),
                      if (preview.isNotEmpty) ...[
                        const SizedBox(height: NexSpacing.xs),
                        NexTextSurface(
                          preview,
                          maxLines: 2,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: NexSpacing.sm),
                      Text(
                        nexCardStrings(
                          context,
                        ).relativeTime(nexRelativeTimeOf(thread.updatedAt)),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                NexPopupMenuButton<String>(
                  tooltip: l10n.moreActions,
                  onSelected: (_) => onDelete(),
                  itemBuilder: (_) => [
                    nexMenuItem(
                      value: 'delete',
                      icon: Icons.delete_outline,
                      label: l10n.delete,
                      destructive: true,
                    ),
                  ],
                  icon: const Icon(Icons.more_horiz),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The assistant's own settings, opened from inside the chat.
///
/// Same controls as the Settings row, on the surface where they are actually
/// being judged — the answer that was too long is still on screen behind this
/// while the length is being changed. It sits *over* the conversation rather
/// than replacing it, which is the difference between this and history.
class AssistantSettingsPanel extends StatelessWidget {
  const AssistantSettingsPanel({super.key, required this.preferences});

  final NexPreferences preferences;

  static Future<void> show(
    BuildContext context, {
    required NexPreferences preferences,
  }) => showModalBottomSheet<void>(
    sheetAnimationStyle: NexMotion.sheet,
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => AssistantSettingsPanel(preferences: preferences),
  );

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      snap: true,
      builder: (context, scroll) => NexDismissOnOverscroll(
        child: AssistantSettingsBody(
          preferences: preferences,
          // The sheet's own scrollable, or dragging the settings would not
          // resize the panel holding them.
          controller: scroll,
          padding: EdgeInsets.fromLTRB(
            NexSpacing.md,
            NexSpacing.sm,
            NexSpacing.md,
            NexSpacing.lg + nexBottomInset(context),
          ),
        ),
      ),
    );
  }
}
