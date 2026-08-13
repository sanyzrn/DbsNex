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
/// "ai" Android flavor's entry point, imports this package directly to bind
/// [PlaceholderLocalChatAdapter]. CI's `ai-deletion-proof` job enforces that
/// no other file outside this package does the same.
library;

export 'src/local_chat_placeholder.dart' show PlaceholderLocalChatAdapter;
export 'src/local_llm_bench_engine.dart' show BenchResult, NexLocalBenchEngine;

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
        OCRText,
        OnDeviceAIAdapter,
        SemanticHit,
        Summary,
        TagSuggestion,
        Transcript,
        Vector;
