import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import '../widgets/nex_toast.dart';

/// Phase 1 general-purpose local chat (09-ai.md). Session-only — nothing
/// here is persisted, and it never touches the note database: memory and
/// tool-calling into Nex's own capabilities are Phase 2, and per the Free
/// vs. Paid Boundary, paid. Free forever, and reachable regardless of the
/// Intelligence master switch, which gates the *cloud* opt-in this never
/// needs — chat never leaves the device.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messages = <ChatMessage>[];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;

  // The binding is set once at process startup (the composition root in
  // main.dart / main_ai.dart) and never changes over this screen's
  // lifetime — computed once here rather than re-checked on every build.
  final _available = ChatAdapterBinding.instance is! NullChatAdapter;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Null covers both "no adapter bound" and "the bound adapter's call
  /// threw" — [ChatAdapter.sendMessage]'s own contract treats unavailable
  /// as "not an error" (same as every `AIAdapter` method), so a thrown
  /// exception is folded into that same not-an-error path here rather than
  /// leaving [_sending] stuck forever, the way `EnrichmentService` already
  /// swallows its own adapter calls' exceptions.
  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    setState(() {
      _messages.add(ChatMessage(role: ChatRole.user, content: text));
      _input.clear();
      _sending = true;
    });
    _scrollToEnd();

    ChatResponse? response;
    try {
      final call = ChatAdapterBinding.instance.sendMessage(
        withScopeCeiling(_messages),
      );
      response = call == null ? null : await call;
    } catch (_) {
      response = null;
    }

    if (!mounted) return;
    setState(() {
      _sending = false;
      if (response != null) {
        _messages.add(
          ChatMessage(role: ChatRole.assistant, content: response!.content),
        );
      }
    });
    if (response == null) {
      messenger.showSnackBar(nexToast(content: Text(l10n.operationFailed)));
    }
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: NexMotion.standard,
        curve: NexMotion.curve,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.chat)),
      body: !_available
          ? NexEmptyState(
              icon: Icons.chat_bubble_outline,
              message: l10n.chatUnavailable,
            )
          : Column(
              children: [
                Expanded(
                  child: _messages.isEmpty
                      ? NexEmptyState(
                          icon: Icons.chat_bubble_outline,
                          message: l10n.chatEmptyHint,
                        )
                      : ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.all(NexSpacing.md),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) =>
                              _MessageBubble(message: _messages[index]),
                        ),
                ),
                if (_sending)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: NexSpacing.sm),
                    child: NexInlineSpinner(),
                  ),
                _Composer(
                  controller: _input,
                  enabled: !_sending,
                  hint: l10n.chatInputHint,
                  sendTooltip: l10n.chatSendTooltip,
                  onSend: () => unawaited(_send()),
                ),
              ],
            ),
    );
  }
}

/// One message, aligned to the reading-direction end for the user's own and
/// the start for the assistant's — [AlignmentDirectional], not left/right,
/// so this reads correctly under the app's Persian (RTL) locale too.
class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.role == ChatRole.user;
    return Align(
      alignment: isUser
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        margin: const EdgeInsets.symmetric(vertical: NexSpacing.xs),
        padding: const EdgeInsets.symmetric(
          horizontal: NexSpacing.md,
          vertical: NexSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: isUser
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(NexRadius.lg),
        ),
        child: Text(
          message.content,
          style: TextStyle(
            color: isUser
                ? theme.colorScheme.onPrimaryContainer
                : theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

/// The message field and send button, pinned to the bottom.
class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.enabled,
    required this.hint,
    required this.sendTooltip,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool enabled;
  final String hint;
  final String sendTooltip;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        NexSpacing.md,
        NexSpacing.sm,
        NexSpacing.md,
        NexSpacing.sm + nexBottomInset(context),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              decoration: InputDecoration(
                hintText: hint,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(NexRadius.lg),
                ),
              ),
            ),
          ),
          const SizedBox(width: NexSpacing.sm),
          IconButton.filled(
            tooltip: sendTooltip,
            onPressed: enabled ? onSend : null,
            icon: const Icon(Icons.send),
          ),
        ],
      ),
    );
  }
}
