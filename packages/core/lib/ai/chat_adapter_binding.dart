import 'chat_adapter.dart';

/// Process-wide chat adapter binding — same shape as [AIAdapterBinding],
/// kept separate because [ChatAdapter] is its own concern (09-ai.md — Phase 1).
///
/// Core never imports `packages/ai`. A composition root binds a real
/// implementation; until then [instance] is [NullChatAdapter] so the rest of
/// the app keeps working with chat unavailable.
class ChatAdapterBinding {
  ChatAdapterBinding._();

  static ChatAdapter _instance = const NullChatAdapter();

  static ChatAdapter get instance => _instance;

  static void bind(ChatAdapter adapter) {
    _instance = adapter;
  }

  /// Restores the no-chat default (tests / after deleting packages/ai).
  static void reset() {
    _instance = const NullChatAdapter();
  }
}
