/// Per-capability toggles (09-ai.md — independently toggleable).
class AiCapabilities {
  const AiCapabilities({
    this.transcription = true,
    this.ocr = true,
    this.tagSuggestions = true,
    this.semanticSearch = true,
    this.summarization = true,
    this.relatedNotes = true,
  });

  final bool transcription;
  final bool ocr;
  final bool tagSuggestions;
  final bool semanticSearch;
  final bool summarization;
  final bool relatedNotes;

  static const AiCapabilities allOff = AiCapabilities(
    transcription: false,
    ocr: false,
    tagSuggestions: false,
    semanticSearch: false,
    summarization: false,
    relatedNotes: false,
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
