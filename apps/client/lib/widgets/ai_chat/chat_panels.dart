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

class ChatHistorySheet extends StatefulWidget {
  const ChatHistorySheet({super.key, required this.history});

  final ChatHistory history;

  static Future<ChatHistoryChoice?> show(
    BuildContext context, {
    required ChatHistory history,
  }) => nexShowSheet<ChatHistoryChoice>(
    context: context,
    builder: (_) => ChatHistorySheet(history: history),
  );

  @override
  State<ChatHistorySheet> createState() => _ChatHistorySheetState();
}

class _ChatHistorySheetState extends State<ChatHistorySheet> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final threads = widget.history.threads;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: nexBottomInset(context)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add_comment_outlined),
              title: Text(l10n.chatNewConversation),
              onTap: () =>
                  Navigator.pop(context, const ChatHistoryChoice(null)),
            ),
            const Divider(height: 1),
            if (threads.isEmpty)
              Padding(
                padding: const EdgeInsets.all(NexSpacing.xl),
                child: Text(
                  l10n.chatHistoryEmpty,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              Flexible(
                // The list fills the panel, so a downward drag over it never
                // reached the sheet's own drag-to-dismiss: a scroll view wins
                // that gesture outright whether or not it has anywhere left
                // to go. This is the same answer the note detail sheet and
                // Settings use.
                child: NexDismissOnOverscroll(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: threads.length,
                    itemBuilder: (context, index) {
                      final thread = threads[index];
                      return ListTile(
                        title: Text(
                          thread.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textDirection: nexDirectionOf(thread.title),
                        ),
                        // The same words the timeline cards use for "2h", so
                        // the two places that show an age agree.
                        subtitle: Text(
                          nexCardStrings(
                            context,
                          ).relativeTime(nexRelativeTimeOf(thread.updatedAt)),
                        ),
                        trailing: IconButton(
                          tooltip: l10n.delete,
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () async {
                            await widget.history.remove(thread.id);
                            if (mounted) setState(() {});
                          },
                        ),
                        onTap: () =>
                            Navigator.pop(context, ChatHistoryChoice(thread)),
                      );
                    },
                  ),
                ),
              ),
            if (threads.isNotEmpty) ...[
              const Divider(height: 1),
              ListTile(
                leading: Icon(
                  Icons.delete_sweep_outlined,
                  color: theme.colorScheme.error,
                ),
                title: Text(
                  l10n.chatClearHistory,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
                // Every conversation, gone for good: asked first (UX-01),
                // the way deleting a model is.
                onTap: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text(l10n.chatClearHistory),
                      content: Text(l10n.chatClearHistoryBody),
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
                  if (confirmed != true) return;
                  await widget.history.clear();
                  if (mounted) setState(() {});
                },
              ),
            ],
          ],
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
