import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import '../platform/ai_provider.dart';
import '../platform/nex_preferences.dart';

/// The assistant, reached by holding the capture button.
///
/// Opens as a short sheet and is dragged up to full screen — small because it
/// starts as a question and not a place you moved into, and expandable because
/// an answer worth reading needs the room. There is no separate "open the chat
/// screen" step: the same sheet is both.
///
/// Deliberately not wired through `ChatAdapterBinding`. That port is bound
/// only by the `ai` flavour's entry point, so on the shipped build it resolves
/// to `NullChatAdapter` and every message would come back "unavailable" — the
/// exact bug the Settings chat screen has. This talks to the provider the user
/// configured, through the same [CloudAIAdapter] the timeline's headline and
/// digest already use, and honours the same output-language setting.
class AiChatSheet extends StatefulWidget {
  const AiChatSheet({super.key, required this.preferences});

  final NexPreferences preferences;

  /// Whether there is a provider behind this at all. The caller checks before
  /// opening, so nobody is shown a chat that cannot answer.
  static bool availableFor(NexPreferences preferences) =>
      preferences.aiEnabled && preferences.aiProvider.isUsable;

  static Future<void> show(
    BuildContext context, {
    required NexPreferences preferences,
  }) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => AiChatSheet(preferences: preferences),
  );

  @override
  State<AiChatSheet> createState() => _AiChatSheetState();
}

class _AiChatSheetState extends State<AiChatSheet> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _turns = <ChatMessage>[];

  bool _sending = false;

  /// Set when a reply does not arrive, and cleared by the next attempt. Shown
  /// in the thread rather than as a toast: the failure belongs to the message
  /// it answers, and a toast would be gone before it is read.
  String? _failure;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _sending) return;
    final l10n = AppLocalizations.of(context);

    setState(() {
      _turns.add(ChatMessage(role: ChatRole.user, content: trimmed));
      _sending = true;
      _failure = null;
      _input.clear();
    });
    _toBottom();

    final adapter = CloudAIAdapter(
      config: widget.preferences.aiProvider,
      outputLanguage: widget.preferences.aiOutputLanguage,
    );
    String? reply;
    try {
      reply = await adapter.chat(List.of(_turns));
    } catch (_) {
      reply = null;
    } finally {
      adapter.close();
    }
    if (!mounted) return;

    setState(() {
      _sending = false;
      if (reply == null || reply.isEmpty) {
        _failure = l10n.chatFailed;
      } else {
        _turns.add(ChatMessage(role: ChatRole.assistant, content: reply));
      }
    });
    _toBottom();
  }

  /// After the frame that added the message, not before it — the list has to
  /// have grown before there is anywhere new to scroll to.
  void _toBottom() {
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
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      // Starts as a question, not a room you moved into.
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 1,
      // Snaps to the two ends so a half-dragged sheet settles somewhere
      // deliberate instead of wherever the finger let go.
      snap: true,
      snapSizes: const [0.55],
      expand: false,
      builder: (context, sheetScroll) => DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(NexRadius.xl),
          ),
        ),
        child: Column(
          children: [
            // The drag handle doubles as the affordance for "this gets
            // bigger" — it is the only thing suggesting the sheet moves.
            Padding(
              padding: const EdgeInsets.only(top: NexSpacing.sm),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(NexRadius.xs),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                NexSpacing.md,
                NexSpacing.sm,
                NexSpacing.sm,
                0,
              ),
              child: Row(
                children: [
                  Icon(Icons.auto_awesome, color: theme.colorScheme.primary),
                  const Spacer(),
                  IconButton(
                    tooltip: l10n.cancel,
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _turns.isEmpty && _failure == null
                  ? _Suggestions(
                      // The sheet's own scrollable has to be the one
                      // DraggableScrollableSheet handed down, or dragging the
                      // body does not resize the sheet.
                      controller: sheetScroll,
                      onPick: (text) => unawaited(_send(text)),
                    )
                  : _Thread(
                      controller: _scroll,
                      turns: _turns,
                      sending: _sending,
                      failure: _failure,
                    ),
            ),
            _Composer(
              controller: _input,
              sending: _sending,
              onSend: () => unawaited(_send(_input.text)),
            ),
          ],
        ),
      ),
    );
  }
}

/// What the sheet offers before anyone has typed anything.
class _Suggestions extends StatelessWidget {
  const _Suggestions({required this.controller, required this.onPick});

  final ScrollController controller;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final prompts = [
      (Icons.summarize_outlined, l10n.chatPromptSummarise),
      (Icons.checklist_outlined, l10n.chatPromptPlan),
      (Icons.lightbulb_outline, l10n.chatPromptIdeas),
    ];
    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(
        NexSpacing.md,
        NexSpacing.md,
        NexSpacing.md,
        0,
      ),
      children: [
        Text(
          l10n.chatGreeting,
          style: theme.textTheme.headlineSmall?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: NexSpacing.lg),
        for (final (icon, label) in prompts)
          Padding(
            padding: const EdgeInsets.only(bottom: NexSpacing.sm),
            child: Material(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(NexRadius.lg),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => onPick(label),
                child: Padding(
                  padding: const EdgeInsets.all(NexSpacing.md),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(NexRadius.md),
                        ),
                        child: Icon(icon, size: 20),
                      ),
                      const SizedBox(width: NexSpacing.md),
                      Expanded(
                        child: Text(label, style: theme.textTheme.bodyLarge),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The conversation itself.
class _Thread extends StatelessWidget {
  const _Thread({
    required this.controller,
    required this.turns,
    required this.sending,
    required this.failure,
  });

  final ScrollController controller;
  final List<ChatMessage> turns;
  final bool sending;
  final String? failure;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView.builder(
      controller: controller,
      padding: const EdgeInsets.all(NexSpacing.md),
      itemCount: turns.length + (sending || failure != null ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == turns.length) {
          return Align(
            alignment: AlignmentDirectional.centerStart,
            child: Padding(
              padding: const EdgeInsets.only(bottom: NexSpacing.sm),
              child: failure != null
                  ? Text(
                      failure!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    )
                  : const SizedBox(width: 120, child: NexSkeleton(height: 16)),
            ),
          );
        }
        final turn = turns[index];
        final mine = turn.role == ChatRole.user;
        return Align(
          alignment: mine
              ? AlignmentDirectional.centerEnd
              : AlignmentDirectional.centerStart,
          child: Container(
            margin: const EdgeInsets.only(bottom: NexSpacing.sm),
            padding: const EdgeInsets.symmetric(
              horizontal: NexSpacing.md,
              vertical: NexSpacing.sm,
            ),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.78,
            ),
            decoration: BoxDecoration(
              color: mine
                  ? theme.colorScheme.primaryContainer
                  : theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(NexRadius.lg),
            ),
            child: Text(
              turn.content,
              style: theme.textTheme.bodyMedium,
              // Either side may be in either language — the assistant answers
              // in whatever the output-language setting asks for.
              textDirection: nexDirectionOf(turn.content),
            ),
          ),
        );
      },
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        NexSpacing.md,
        NexSpacing.sm,
        NexSpacing.md,
        NexSpacing.md + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              decoration: InputDecoration(
                hintText: l10n.chatHint,
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
          IconButton.filled(
            onPressed: sending ? null : onSend,
            tooltip: l10n.chatSend,
            icon: const Icon(Icons.arrow_upward),
          ),
        ],
      ),
    );
  }
}
