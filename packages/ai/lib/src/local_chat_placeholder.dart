import 'package:nex_core/nex_core.dart';

/// Phase 1 placeholder for the "ai" Android flavor's [ChatAdapter] binding —
/// proves the flavor/entry-point/CI wiring compiles end-to-end (09-ai.md,
/// ADR-031). **Not backed by a real model.** The actual `llama_cpp_dart`-
/// backed implementation is separate future work, still blocked on the
/// Phase 0 phone benchmark (tokens/sec, thermal throttling) actually
/// happening.
class PlaceholderLocalChatAdapter implements ChatAdapter {
  const PlaceholderLocalChatAdapter();

  @override
  Future<ChatResponse>? sendMessage(List<ChatMessage> history) {
    return Future.value(
      const ChatResponse(
        content:
            "Local AI isn't wired up yet on this build — this is a Phase 1 "
            'placeholder. See docs/09-ai.md.',
      ),
    );
  }
}
