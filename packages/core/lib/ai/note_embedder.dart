/// A model that turns text into vectors and does nothing else.
///
/// Separate from [AIAdapter.embed] because an embedding model is asked two
/// different questions, and the better ones are told which: a note is
/// embedded as a *document*, a search as a *query*, and EmbeddingGemma
/// (the on-device search model) is trained with a different prompt for
/// each. One `embed(text)` cannot say which of the two it is being asked.
///
/// When one is set, [EnrichmentService] uses it for every vector — notes,
/// searches, related notes — instead of the provider's, whichever provider
/// that is. That is the point of having one: search by meaning that works
/// with no provider, no key and no signal, and that never sends a note
/// anywhere to be read.
abstract class NoteEmbedder {
  /// Which vector space this embedder writes. Stored vectors from any other
  /// space are thrown away when this one takes over — see
  /// `NoteRepository.setEmbeddingSpace`.
  String get space;

  /// The cosine similarity below which a search hit from this model is
  /// noise. Each model has its own: EmbeddingGemma's scores "rarely drop
  /// below 0.5" even for unrelated text (Google's own inference notes), so
  /// the cloud models' 0.3 let every note through as a match (AI-05, AI-12).
  double get minSimilarity;

  /// The vector for a note's text.
  Future<List<double>> embedDocument(String text);

  /// The vector for something typed into search.
  Future<List<double>> embedQuery(String text);
}
