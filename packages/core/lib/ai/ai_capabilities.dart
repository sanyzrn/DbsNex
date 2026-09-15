/// Per-capability toggles (09-ai.md — independently toggleable).
///
/// **Every default is off, and that is the whole point of this class.** It
/// describes what the intelligence layer is permitted to do with somebody's
/// notes, and a permission that is granted by omission is not a permission
/// anybody gave. Two production sites take these defaults — the worker's boot
/// message (`NexDbWorker.spawn`) and [EnrichmentService]'s own constructor —
/// and both used to mean "all six capabilities, everything enabled" for a
/// caller that simply did not pass the argument.
///
/// The user's own settings are unaffected by this: [NexPreferences] names all
/// six explicitly, and answers *on* for a capability nobody has touched,
/// because the switch a person actually flips is the master one and turning
/// it on is meant to turn the layer on. The default here is not that switch.
/// It is what a **caller inside the app** gets for saying nothing, and for a
/// privacy boundary the answer to saying nothing is no.
///
/// [allOn] exists for the callers that genuinely want everything — tests,
/// mostly — so that "all six" stays something written down rather than
/// something inherited.
class AiCapabilities {
  const AiCapabilities({
    this.transcription = false,
    this.ocr = false,
    this.tagSuggestions = false,
    this.semanticSearch = false,
    this.summarization = false,
    this.relatedNotes = false,
  });

  final bool transcription;
  final bool ocr;
  final bool tagSuggestions;
  final bool semanticSearch;
  final bool summarization;
  final bool relatedNotes;

  /// Nothing permitted. Identical to `const AiCapabilities()`, and kept as a
  /// name because "allOff" reads as a decision where an empty constructor
  /// reads as an oversight.
  static const AiCapabilities allOff = AiCapabilities();

  /// Everything permitted.
  ///
  /// Spelled out at the call site is the point: this used to be what an
  /// empty constructor meant, so a caller granted all six by writing nothing
  /// at all.
  static const AiCapabilities allOn = AiCapabilities(
    transcription: true,
    ocr: true,
    tagSuggestions: true,
    semanticSearch: true,
    summarization: true,
    relatedNotes: true,
  );

  AiCapabilities copyWith({
    bool? transcription,
    bool? ocr,
    bool? tagSuggestions,
    bool? semanticSearch,
    bool? summarization,
    bool? relatedNotes,
  }) {
    return AiCapabilities(
      transcription: transcription ?? this.transcription,
      ocr: ocr ?? this.ocr,
      tagSuggestions: tagSuggestions ?? this.tagSuggestions,
      semanticSearch: semanticSearch ?? this.semanticSearch,
      summarization: summarization ?? this.summarization,
      relatedNotes: relatedNotes ?? this.relatedNotes,
    );
  }
}
