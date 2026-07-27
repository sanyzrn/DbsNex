/// A note's semantic embedding vector.
///
/// Lives in core because [NoteRepository.listEmbeddings] returns it and the
/// enrichment service consumes it; the storage layer only persists it.
class NoteEmbedding {
  const NoteEmbedding({required this.noteId, required this.values});

  final String noteId;
  final List<double> values;
}
