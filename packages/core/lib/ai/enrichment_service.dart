import 'dart:io';

import '../models/note.dart';
import '../ports/note_repository.dart';

import 'ai_adapter.dart';
import 'ai_capabilities.dart';
import 'note_embedder.dart';

/// Post-capture enrichment orchestrator (09-ai.md).
///
/// Never called from the capture hot path. Failures leave the note unchanged.
class EnrichmentService {
  EnrichmentService({
    required NoteRepository repo,
    AIAdapter adapter = const NullAIAdapter(),
    AiCapabilities capabilities = AiCapabilities.allOff,
  }) : _repo = repo,
       _adapter = adapter,
       _capabilities = capabilities;

  final NoteRepository _repo;
  AIAdapter _adapter;
  AiCapabilities _capabilities;

  void updateAdapter(AIAdapter adapter) {
    _adapter = adapter;
    // A different provider is a different vector space.
    _queryGeneration++;
    _queryVectors.clear();
  }

  /// The model every vector comes from while one is set, in place of the
  /// provider's — see [NoteEmbedder]. Null hands embedding back to the
  /// adapter.
  NoteEmbedder? _embedder;

  void updateEmbedder(NoteEmbedder? embedder) {
    _embedder = embedder;
    // Its own space, so the cached query vectors are from another one.
    _queryGeneration++;
    _queryVectors.clear();
  }

  /// The last few queries' embeddings. A search runs as the reader types and
  /// again when they refine it; asking the provider for "boiler" three times
  /// in a row would spend a request, and its latency, to learn nothing new.
  final _queryVectors = <String, List<double>>{};
  static const _queryVectorCache = 32;
  int _queryGeneration = 0;

  Future<List<double>?> _queryVector(String query) async {
    final cached = _queryVectors.remove(query);
    if (cached != null) return _queryVectors[query] = cached;
    final generation = _queryGeneration;
    final List<double> vector;
    if (_embedder case final embedder?) {
      vector = await embedder.embedQuery(query);
    } else {
      final call = _adapter.embed(query);
      if (call == null) return null;
      vector = (await call).values;
    }
    if (generation != _queryGeneration ||
        !_capabilities.semanticSearch && !_capabilities.relatedNotes ||
        vector.isEmpty) {
      return null;
    }
    _queryVectors[query] = vector;
    while (_queryVectors.length > _queryVectorCache) {
      _queryVectors.remove(_queryVectors.keys.first);
    }
    return vector;
  }

  void updateCapabilities(AiCapabilities capabilities) =>
      _capabilities = capabilities;

  AiCapabilities get capabilities => _capabilities;

  /// Run enabled enrichment for a single note. Safe to call fire-and-forget.
  Future<void> enrichNote(String noteId) async {
    final note = _repo.getById(noteId);
    if (note == null) return;

    try {
      // Media is read only after an explicit action. Capture, launch and a
      // provider change must not upload a photo or recording in the background.
      if (_capabilities.summarization &&
          note.type == NoteType.text &&
          (note.content?.length ?? 0) > 80) {
        await _summarize(note);
      }
      if (_capabilities.semanticSearch || _capabilities.relatedNotes) {
        // Re-read before embedding, not the note this method started with:
        // transcription or OCR may have just landed the very text an embedding
        // needs, and the in-memory copy predates it. Without the refresh, a
        // freshly transcribed voice note embedded as nothing and only entered
        // semantic search when some later backfill happened to re-run.
        final refreshed = _repo.getById(noteId) ?? note;
        await _embed(refreshed);
      }
      // Tag suggestions are fetched on demand via [suggestTags] — never auto-applied.
    } catch (_) {
      // AI errors are non-blocking (06-development.md). Leave note as-is.
      // A thrown [AiUnavailableException] in particular leaves every slot it
      // touches unwritten, so the note is retried rather than retired.
    }
  }

  /// Backfills search embeddings from text already available in the library.
  /// Media reading is explicit; enabling a provider must not upload the backlog.
  Future<int> backfill({int limit = 25}) async {
    return _backfillEmbeddings(limit: limit);
  }

  final _mediaReads = <String, Future<String?>>{};

  /// Explicit image reading or audio transcription, coalesced per note.
  /// Preserve any earlier result on failure and reject a result for media
  /// replaced or deleted while the provider was working.
  Future<String?> readMediaOnDemand(String noteId) async {
    final pending = _mediaReads[noteId];
    if (pending != null) return pending;
    final request = _readMedia(noteId);
    _mediaReads[noteId] = request;
    try {
      return await request;
    } finally {
      if (identical(_mediaReads[noteId], request)) _mediaReads.remove(noteId);
    }
  }

  Future<String?> _readMedia(String noteId) async {
    final note = _repo.getById(noteId);
    final uri = note?.mediaUri;
    if (note == null || uri == null) return null;
    final image = note.isImageMedia;
    final audio = note.isAudioMedia;
    if (!image && !audio) return null;
    try {
      final text = image
          ? await readImage(mediaUri: uri, mediaHash: note.mediaHash)
          : await transcribeAudio(mediaUri: uri, mediaHash: note.mediaHash);
      if (text == null) return null;
      final current = _repo.getById(noteId);
      if (current == null ||
          current.mediaUri != uri ||
          current.mediaHash != note.mediaHash) {
        return null;
      }
      if (image) {
        _repo.setOcrText(noteId, text);
      } else {
        _repo.setTranscriptText(noteId, text);
      }
      if (_capabilities.semanticSearch || _capabilities.relatedNotes) {
        try {
          await _embed(_repo.getById(noteId) ?? current);
        } catch (_) {
          // A search failure must not turn a saved result into a failed read.
        }
      }
      return text;
    } catch (_) {
      return null;
    }
  }

  /// Embeds the notes that have text and no vector yet.
  ///
  /// Its own pass because the enrichment backlog is a different set: that one
  /// is media waiting to be read, this one is everything waiting to be
  /// findable by meaning. Written notes were in neither — they need nothing
  /// derived, so they never appeared in the enrichment backlog, and nothing
  /// else ever embedded them. A library captured before a provider existed
  /// therefore had no vectors at all, and semantic search over it returned
  /// nothing, forever, without ever looking wrong.
  ///
  /// Stops at the first failure, like the pass below and for the same reason:
  /// a dead key or an exhausted quota answers every remaining note the same
  /// way, and spending the quota to find that out twenty-five times is worse
  /// than stopping.
  /// Embeds up to [limit] notes that have no vector yet, and nothing else —
  /// no transcripts, no text read out of photos. What a new vector space
  /// needs: the on-device search model taking over throws every vector away,
  /// and only these have to come back.
  Future<int> backfillEmbeddings({int limit = 25}) =>
      _backfillEmbeddings(limit: limit);

  Future<int> _backfillEmbeddings({required int limit}) async {
    if (!_capabilities.semanticSearch && !_capabilities.relatedNotes) return 0;
    var done = 0;
    for (final note in _repo.listNeedingEmbedding(limit: limit)) {
      try {
        await _embed(note);
      } catch (_) {
        break;
      }
      if (_repo.getEmbedding(note.id) == null) break;
      done++;
    }
    return done;
  }

  Future<List<TagSuggestion>> suggestTags(String noteId) async {
    if (!_capabilities.tagSuggestions) return const [];
    final note = _repo.getById(noteId);
    if (note == null) return const [];
    final call = _adapter.suggestTags(note);
    if (call == null) return const [];
    try {
      return await call;
    } catch (_) {
      return const [];
    }
  }

  Future<Summary?> summarizeOnDemand(String noteId) async {
    if (!_capabilities.summarization) return null;
    final note = _repo.getById(noteId);
    if (note == null) return null;
    final call = _adapter.summarize(note);
    if (call == null) return null;
    try {
      final summary = await call;
      // Never persist a pass-through "summary" identical to the source.
      final source = (note.aiSourceText ?? '').trim();
      if (summary.text.trim().isEmpty ||
          summary.text.trim() == source ||
          summary.text.trim().length >= source.length) {
        return null;
      }
      final current = _repo.getById(noteId);
      if (current == null || current.aiSourceText != note.aiSourceText) {
        return null;
      }
      _repo.setSummaryText(noteId, summary.text);
      return summary;
    } catch (_) {
      return null;
    }
  }

  /// Below this cosine similarity, a hit is noise rather than a match — an
  /// unfiltered top-N would otherwise hand back the whole library, ranked,
  /// for any query, since nothing here stops a search for "invoice" from
  /// still returning a note about breakfast in last place.
  ///
  /// The cloud models' floor. The on-device model sets its own through
  /// [NoteEmbedder.minSimilarity], because its scores sit higher for the
  /// same unrelated pair.
  static const _minSemanticSimilarity = 0.3;

  double get _floor => _embedder?.minSimilarity ?? _minSemanticSimilarity;

  /// Semantic search by meaning. Results are separate from keyword FTS.
  Future<List<SemanticHit>> semanticSearch(
    String query, {
    int limit = 20,
  }) async {
    if (!_capabilities.semanticSearch) return const [];
    final q = query.trim();
    if (q.isEmpty) return const [];
    try {
      final queryVec = await _queryVector(q);
      if (queryVec == null) return const [];
      // Only what stands out for this query against the whole library. A
      // meaning search answers every query, related or not, and by plain
      // similarity the same short, generic notes — a list of hashtags, a
      // two-word reminder — came up for "car", "calendar" and a name alike
      // (the owner's screenshots, 1.99.81).
      return [
        for (final hit in _repo.nearestEmbeddings(
          queryVec,
          limit: limit,
          minScore: _floor,
          standout: true,
        ))
          SemanticHit(noteId: hit.noteId, score: hit.score),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<List<SemanticHit>> relatedNotes(String noteId, {int limit = 5}) async {
    if (!_capabilities.relatedNotes) return const [];
    final emb = _repo.getEmbedding(noteId);
    if (emb == null || emb.isEmpty) return const [];
    return [
      for (final hit in _repo.nearestEmbeddings(
        emb,
        limit: limit,
        minScore: -1,
        excludeNoteId: noteId,
      ))
        SemanticHit(noteId: hit.noteId, score: hit.score),
    ];
  }

  /// Reads the words in a photo that is not a note of its own — one
  /// attached to a note (`docs/14-attachments.md`).
  ///
  /// Null when reading text in photos is off, or nothing on this adapter
  /// reads images: neither is an answer worth keeping. Otherwise the words,
  /// or an empty string for a photo with none. What the adapter throws is
  /// thrown, so the caller can stop instead of spending a dead key on the
  /// rest of the queue.
  Future<String?> readImage({
    required String mediaUri,
    String? mediaHash,
  }) async {
    if (!_capabilities.ocr) return null;
    final file = File(mediaUri);
    final call = _adapter.ocr(
      ImageRef(
        mediaUri: mediaUri,
        mediaHash: mediaHash,
        bytes: file.existsSync() ? file.readAsBytesSync() : null,
      ),
    );
    if (call == null) return null;
    return (await call).text.trim();
  }

  /// Transcribes a recording that is not a note of its own — a voice clip
  /// attached to one. Null when transcription is off or nothing here hears
  /// audio; otherwise the words, or an empty string for none. What the
  /// adapter throws is thrown, as for [readImage].
  Future<String?> transcribeAudio({
    required String mediaUri,
    String? mediaHash,
  }) async {
    if (!_capabilities.transcription) return null;
    final file = File(mediaUri);
    final call = _adapter.transcribe(
      AudioRef(
        mediaUri: mediaUri,
        mediaHash: mediaHash,
        bytes: file.existsSync() ? file.readAsBytesSync() : null,
      ),
    );
    if (call == null) return null;
    return (await call).text.trim();
  }

  Future<void> _summarize(Note note) async {
    final call = _adapter.summarize(note);
    if (call == null) return;
    final result = await call;
    final source = (note.content ?? '').trim();
    if (result.text.trim().isEmpty ||
        result.text.trim() == source ||
        result.text.trim().length >= source.length) {
      return;
    }
    final current = _repo.getById(note.id);
    if (current == null || current.content != note.content) return;
    _repo.setSummaryText(note.id, result.text);
  }

  /// The most of a note's text sent to be embedded.
  static const embedCharacterLimit = 4000;

  Future<void> _embed(Note note) async {
    final full = _searchableText(note);
    if (full.trim().isEmpty) return;
    // What a note is about is in its opening, and a provider refuses an
    // input past its limit (AI-06): one very long note answered 400 every
    // time and stopped the whole backfill behind it. The on-device model
    // takes the same cut.
    final text = full.length > embedCharacterLimit
        ? full.substring(0, embedCharacterLimit)
        : full;
    // A failure propagates without writing a row: the note stays in the
    // embedding backlog and is retried. Storing an empty vector on failure
    // is how one rate-limited request made a note permanently invisible to
    // semantic search — and to related notes — forever.
    final Vector vector;
    final embedderAsked = _embedder;
    final adapterAsked = _adapter;
    if (_embedder case final embedder?) {
      vector = Vector(await embedder.embedDocument(text));
    } else {
      final call = _adapter.embed(text);
      if (call == null) return;
      vector = await call;
    }
    // The answer is for the text and the model it was asked of (AI-09). A
    // note edited, deleted or moved to another vector space while the
    // request ran keeps no vector from it: the backlog asks again for what
    // the note says now, of the model in use now.
    if (!identical(_embedder, embedderAsked) ||
        !identical(_adapter, adapterAsked)) {
      return;
    }
    final now = _repo.getById(note.id);
    if (now == null || _searchableText(now) != full) return;
    if (vector.values.isNotEmpty) {
      _repo.setEmbedding(note.id, vector.values);
    } else {
      // A provider that answered with an empty embedding has said, in
      // effect, "there is no vector for this". Record the zero-width marker
      // so the note stops being retried; the similarity math already skips
      // empty vectors, so nothing false can be derived from it.
      _repo.setEmbedding(note.id, const <double>[]);
    }
  }

  /// What a note means, for embedding. Deliberately not [Note.displayText] —
  /// that answers "what does the card show", which a title takes over, and an
  /// embedding wants the substance rather than the label.
  String _searchableText(Note note) {
    String joined(List<String?> parts) => parts
        .whereType<String>()
        .where((text) => text.trim().isNotEmpty)
        .toSet()
        .join('\n');
    switch (note.type) {
      case NoteType.text:
        return note.content ?? '';
      case NoteType.voice:
        return joined([note.transcriptText, note.caption, note.title]);
      case NoteType.photo:
        return joined([note.ocrText, note.caption, note.title]);
      case NoteType.file:
        final body = joined([
          note.ocrText,
          note.transcriptText,
          note.caption,
          note.title,
        ]);
        return body.isEmpty ? note.content ?? '' : body;
      // The items without their markers: a list of things to do is about the
      // things, not about which of them happen to be ticked right now.
      case NoteType.checklist:
        return note.checklistItems.map((item) => item.text).join('\n');
      // What the page is about, never the URL — a bare URL embeds as
      // punctuation and drags every link note toward every other one.
      case NoteType.link:
        return [
          note.title,
          note.linkExcerpt,
          note.summaryText,
        ].whereType<String>().where((s) => s.trim().isNotEmpty).join('\n');
    }
  }
}

class SemanticHit {
  const SemanticHit({required this.noteId, required this.score});

  final String noteId;
  final double score;
}
