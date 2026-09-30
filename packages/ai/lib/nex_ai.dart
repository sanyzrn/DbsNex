/// Nex — the on-device AI runtime.
///
/// The removable half of this package. Nothing outside it may import this
/// library except `apps/client/lib/main_ai.dart`, the "ai" Android flavor's
/// entry point (ADR-031), which binds a [ChatAdapter] here. CI's
/// `ai-deletion-proof` job removes this library, its sources and its plugin,
/// and proves core, data, ui and the standard client still build (ADR-035).
///
/// The cloud provider layer is the other library, `cloud.dart`, which the
/// client imports freely.
///
/// This library carries a Flutter plugin — [LiteRtChatAdapter] wraps one,
/// and on-device inference is inherently platform bound. That is why the
/// package sits outside CI's Dart-only matrix, which exists to prove
/// `packages/core` and `packages/data` carry no Flutter dependency.
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
