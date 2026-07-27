/// Nex — Optional AI adapters (v3+).
///
/// Optional leaf package. Nothing in the capture path may import this.
/// Deleting this package must leave core/data/client compiling (09-ai.md).
///
/// Adapter contracts and the default on-device stub live in `nex_core` so
/// `apps/client` never needs a direct `nex_ai` dependency. This package
/// re-exports them and is the home for future vendor/cloud adapters.
library;

export 'package:nex_core/nex_core.dart'
    show
        AIAdapter,
        AIAdapterBinding,
        AiCapabilities,
        AudioRef,
        CloudGatedAIAdapter,
        EnrichmentService,
        ImageRef,
        NullAIAdapter,
        OCRText,
        OnDeviceAIAdapter,
        SemanticHit,
        Summary,
        TagSuggestion,
        Transcript,
        Vector;
