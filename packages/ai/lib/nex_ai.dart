/// Nex — Optional AI adapters (v3+).
///
/// Optional leaf package. Nothing in the capture path may import this.
/// Deleting this package must leave core/data/client compiling (09-ai.md).
library nex_ai;

export 'package:nex_core/nex_core.dart'
    show
        AIAdapter,
        AiCapabilities,
        AudioRef,
        EnrichmentService,
        ImageRef,
        NullAIAdapter,
        OCRText,
        SemanticHit,
        Summary,
        TagSuggestion,
        Transcript,
        Vector;

export 'on_device_adapter.dart';
