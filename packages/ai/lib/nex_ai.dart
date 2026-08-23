/// Nex — Optional AI adapters (v3+).
///
/// Optional leaf package. Nothing in the capture path may import this.
/// Deleting this package must leave core/data/client compiling (09-ai.md).
///
/// Adapter contracts and the default on-device stub live in `nex_core` so
/// `apps/client` never needs a direct `nex_ai` dependency. This package
/// re-exports them and is the home for future vendor/cloud adapters.
///
/// One deliberate exception (ADR-031): `apps/client/lib/main_ai.dart`, the
/// "ai" Android flavor's entry point, imports this package directly to bind a
/// [ChatAdapter]. CI's `ai-deletion-proof` job enforces that no other file
/// outside this package does the same.
///
/// This package carries a Flutter dependency as of Phase 1 — [LiteRtChatAdapter]
/// wraps a platform plugin, and on-device inference is inherently platform
/// bound. That is why it moved out of CI's Dart-only matrix, which exists to
/// prove `packages/core` and `packages/data` carry no Flutter dependency; this
/// package never made that claim.
library;

export 'src/litert_chat_adapter.dart' show LiteRtChatAdapter;
export 'src/local_chat_placeholder.dart' show PlaceholderLocalChatAdapter;

export 'package:nex_core/nex_core.dart'
    show
        AIAdapter,
        AIAdapterBinding,
        AiCapabilities,
        AudioRef,
        ChatAdapter,
        ChatAdapterBinding,
        ChatMessage,
        ChatResponse,
        ChatRole,
        CloudGatedAIAdapter,
        EnrichmentService,
        ImageRef,
        NullAIAdapter,
        NullChatAdapter,
        nexChatMaxResponseTokens,
        nexChatScopeCeilingPrompt,
        OCRText,
        OnDeviceAIAdapter,
        SemanticHit,
        Summary,
        TagSuggestion,
        Transcript,
        Vector,
        withScopeCeiling;
