/// General-purpose local chat (09-ai.md — Phase 1, free forever).
///
/// Deliberately separate from [AIAdapter]: every `AIAdapter` method derives
/// metadata from one already-saved `Note` for `EnrichmentService`. Chat is
/// freestanding and multi-turn — nothing here reads or writes a note, and
/// Phase 1 keeps no history beyond one session (memory/profile persistence
/// is Phase 2, and per the Free vs. Paid Boundary, paid).
///
/// [sendMessage] is nullable, same convention as every `AIAdapter` method —
/// unavailable is not an error. Callers check for `null` *before* awaiting,
/// exactly like `EnrichmentService` already does for `transcribe`/`ocr`.
abstract class ChatAdapter {
  Future<ChatResponse>? sendMessage(List<ChatMessage> history);

  /// Whether there is anything behind this adapter right now.
  ///
  /// Separate from [sendMessage] returning null because callers need the
  /// answer *before* they build a UI, not after they have asked a question:
  /// whether to offer the assistant at all, and whether "on-device" is a
  /// working choice of provider or a dead end. Asking by sending a message
  /// would mean running inference to find out.
  ///
  /// For a local model this is "the weights are on disk", which can change
  /// while the app is running — a download finishing, or the model being
  /// deleted — so it is a getter and not a field read once at startup.
  bool get available;
}

enum ChatRole { system, user, assistant }

class ChatMessage {
  const ChatMessage({required this.role, required this.content});

  final ChatRole role;
  final String content;
}

/// [refusedOutOfScope] is set when the request exceeded the scope ceiling
/// (see `chat_scope_policy.dart`) and [content] is the explicit "this is
/// outside Nex's current scope" message, not a truncated attempt.
class ChatResponse {
  const ChatResponse({required this.content, this.refusedOutOfScope = false});

  final String content;
  final bool refusedOutOfScope;
}

/// No-op adapter — chat unavailable (AI disabled, or Phase 1 not yet bound
/// on this platform/build). Mirrors [NullAIAdapter]'s role for [AIAdapter].
class NullChatAdapter implements ChatAdapter {
  const NullChatAdapter();

  @override
  bool get available => false;

  @override
  Future<ChatResponse>? sendMessage(List<ChatMessage> history) => null;
}
