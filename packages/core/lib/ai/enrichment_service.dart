import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../models/note.dart';
import '../ports/note_repository.dart';

import 'ai_adapter.dart';
import 'ai_capabilities.dart';

/// Post-capture enrichment orchestrator (09-ai.md).
///
/// Never called from the capture hot path. Failures leave the note unchanged.
class EnrichmentService {
  EnrichmentService({
    required NoteRepository repo,
    AIAdapter adapter = const NullAIAdapter(),
    AiCapabilities capabilities = const AiCapabilities(),
  }) : _repo = repo,
       _adapter = adapter,
       _capabilities = capabilities;

  final NoteRepository _repo;
  AIAdapter _adapter;
  AiCapabilities _capabilities;

  void updateAdapter(AIAdapter adapter) => _adapter = adapter;

  void updateCapabilities(AiCapabilities capabilities) =>
      _capabilities = capabilities;

  AiCapabilities get capabilities => _capabilities;

  /// Run enabled enrichment for a single note. Safe to call fire-and-forget.
  Future<void> enrichNote(String noteId) async {
    final note = _repo.getById(noteId);
    if (note == null) return;

    try {
      if (_capabilities.transcription && note.type == NoteType.voice) {
        await _transcribe(note);
      }
      if (_capabilities.ocr && note.type == NoteType.photo) {
        await _ocr(note);
      }
      if (_capabilities.summarization &&
          note.type == NoteType.text &&
          (note.content?.length ?? 0) > 80) {
        await _summarize(note);
      }
      if (_capabilities.semanticSearch || _capabilities.relatedNotes) {
        await _embed(note);
      }
      // Tag suggestions are fetched on demand via [suggestTags] — never auto-applied.
    } catch (_) {
      // AI errors are non-blocking (06-development.md). Leave note as-is.
    }
  }

  /// Enriches notes that were captured before there was anything to read them.
  ///
  /// Enrichment is a capture-time step, so turning the intelligence layer on
  /// used to change nothing about the library that already existed: every
  /// recording made before that moment stayed untranscribed forever, and the
  /// app never said so. This walks the backlog instead.
  ///
  /// Sequential on purpose. A provider that has just been configured is
  /// usually a free tier, and firing fifty requests at once is the reliable
  /// way to be rate-limited into failing all of them. It stops at the first
  /// note that produces nothing at all, which is what a dead key or an
  /// exhausted quota looks like from here — continuing would spend the rest of
  /// the backlog learning the same thing.
  ///
  /// Returns how many notes it managed to enrich.
  Future<int> backfill({int limit = 25}) async {
    final embedded = await _backfillEmbeddings(limit: limit);
    if (!_capabilities.transcription && !_capabilities.ocr) return embedded;
    final pending = _repo.listNeedingEnrichment(limit: limit);
    var done = embedded;
    for (final note in pending) {
      try {
        await enrichNote(note.id);
      } catch (_) {
        break;
      }
      final after = _repo.getById(note.id);
      final gained = note.type == NoteType.voice
          ? after?.transcriptText != null
          : after?.ocrText != null;
      if (!gained) break;
      done++;
    }
    return done;
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
      final source = (note.content ?? note.transcriptText ?? note.ocrText ?? '')
          .trim();
      if (summary.text.trim().isEmpty ||
          summary.text.trim() == source ||
          summary.text.trim().length >= source.length) {
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
  static const _minSemanticSimilarity = 0.3;

  /// Semantic search by meaning. Results are separate from keyword FTS.
  Future<List<SemanticHit>> semanticSearch(
    String query, {
    int limit = 20,
  }) async {
    if (!_capabilities.semanticSearch) return const [];
    final q = query.trim();
    if (q.isEmpty) return const [];
    final call = _adapter.embed(q);
    if (call == null) return const [];
    try {
      final queryVec = await call;
      final rows = _repo.listEmbeddings();
      final scored = <SemanticHit>[];
      for (final row in rows) {
        final sim = _cosine(queryVec.values, row.values);
        if (sim.isNaN || sim < _minSemanticSimilarity) continue;
        scored.add(SemanticHit(noteId: row.noteId, score: sim));
      }
      scored.sort((a, b) => b.score.compareTo(a.score));
      return scored.take(limit).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<SemanticHit>> relatedNotes(String noteId, {int limit = 5}) async {
    if (!_capabilities.relatedNotes) return const [];
    final emb = _repo.getEmbedding(noteId);
    if (emb == null) return const [];
    final rows = _repo.listEmbeddings().where((e) => e.noteId != noteId);
    final scored = <SemanticHit>[];
    for (final row in rows) {
      final sim = _cosine(emb, row.values);
      if (sim.isNaN) continue;
      scored.add(SemanticHit(noteId: row.noteId, score: sim));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(limit).toList();
  }

  Future<void> _transcribe(Note note) async {
    final uri = note.mediaUri;
    if (uri == null) return;
    Uint8List? bytes;
    final file = File(uri);
    if (file.existsSync()) bytes = file.readAsBytesSync();
    final call = _adapter.transcribe(
      AudioRef(mediaUri: uri, mediaHash: note.mediaHash, bytes: bytes),
    );
    if (call == null) return;
    final result = await call;
    _repo.setTranscriptText(note.id, result.text);
  }

  Future<void> _ocr(Note note) async {
    final uri = note.mediaUri;
    if (uri == null) return;
    Uint8List? bytes;
    final file = File(uri);
    if (file.existsSync()) bytes = file.readAsBytesSync();
    final call = _adapter.ocr(
      ImageRef(mediaUri: uri, mediaHash: note.mediaHash, bytes: bytes),
    );
    if (call == null) return;
    final result = await call;
    _repo.setOcrText(note.id, result.text);
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
    _repo.setSummaryText(note.id, result.text);
  }

  Future<void> _embed(Note note) async {
    final text = _searchableText(note);
    if (text.trim().isEmpty) return;
    final call = _adapter.embed(text);
    if (call == null) return;
    final vector = await call;
    _repo.setEmbedding(note.id, vector.values);
  }

  /// What a note means, for embedding. Deliberately not [Note.displayText] —
  /// that answers "what does the card show", which a title takes over, and an
  /// embedding wants the substance rather than the label.
  String _searchableText(Note note) {
    switch (note.type) {
      case NoteType.text:
        return note.content ?? '';
      case NoteType.voice:
        return note.transcriptText ?? '';
      case NoteType.photo:
        return note.ocrText ?? '';
      case NoteType.file:
        return note.content ?? '';
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

  double _cosine(List<double> a, List<double> b) {
    final n = a.length < b.length ? a.length : b.length;
    if (n == 0) return double.nan;
    var dot = 0.0, na = 0.0, nb = 0.0;
    for (var i = 0; i < n; i++) {
      dot += a[i] * b[i];
      na += a[i] * a[i];
      nb += b[i] * b[i];
    }
    if (na == 0 || nb == 0) return double.nan;
    return dot / (math.sqrt(na) * math.sqrt(nb));
  }
}

class SemanticHit {
  const SemanticHit({required this.noteId, required this.score});

  final String noteId;
  final double score;
}
