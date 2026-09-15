import '../models/note.dart';

import 'ai_adapter.dart';

/// Default on-device adapter (09-ai.md — "Default to local").
///
/// Lives in `packages/core` so apps/client can wire it via DI without depending
/// on optional `packages/ai`. Deterministic local heuristics; no network.
class OnDeviceAIAdapter implements AIAdapter {
  const OnDeviceAIAdapter();

  /// Tokens that are never useful as tags (content-type names, filler, stubs).
  static const Set<String> _stopwords = {
    'photo',
    'text',
    'voice',
    'file',
    'note',
    'notes',
    'transcript',
    'spoken',
    'content',
    'readable',
    'label',
    'image',
    'audio',
    'with',
    'from',
    'this',
    'that',
    'have',
    'been',
    'were',
    'will',
    'your',
    'about',
    'into',
    'just',
    'like',
    'than',
    'then',
    'them',
    'they',
    'what',
    'when',
    'where',
    'which',
    'while',
    'would',
    'could',
    'should',
  };

  @override
  Future<Transcript>? transcribe(AudioRef audio) {
    // Deliberately unavailable. This adapter is the offline fallback —
    // heuristics over text the note already has — and it has no way to hear
    // audio. It used to answer with a seeded fake sentence ("voice transcript
    // 69cfdd… spoken note content"), which the enrichment service then
    // stored, indexed and offered to the assistant as a real transcript: a
    // fabricated record indistinguishable from a transcription, written into
    // the one note type whose words the user never typed. Null is the honest
    // answer; the enrichment service marks the slot empty so it is not
    // retried forever.
    return null;
  }

  @override
  Future<OCRText>? ocr(ImageRef image) {
    // See [transcribe]: no way to read images, and no fabricated text in
    // their place.
    return null;
  }

  @override
  Future<Vector>? embed(String text) {
    // Deliberately unavailable, for the same reason [transcribe] and [ocr]
    // are — and this one shipped, which the other two did not.
    //
    // It used to answer with 32 doubles derived from the SHA-256 of the text:
    // deterministic, correctly normalised, and carrying no similarity
    // structure whatsoever. Two notes about the same subject scored no closer
    // than two unrelated ones, and changing a single character produced a
    // completely different vector. The comment above it called this "good
    // enough for cosine demos", which was true — a demo is where it was.
    //
    // What made it a defect rather than a placeholder is where the numbers
    // went. They were stored, and then surfaced under their own heading in
    // search — `l10n.semanticMatches` — whenever a keyword search came back
    // empty. Reachable with no provider configured at all, because the worker
    // falls back to this adapter whenever the provider config is unusable. So
    // somebody searched, found nothing, and was shown "semantic matches: 3"
    // under a label asserting the app had understood their notes. That is the
    // failure docs/09-ai.md's own rule exists to prevent: semantic results
    // must be distinguishable from keyword ones "so users can calibrate trust
    // appropriately". They were distinguishable. What was being distinguished
    // was noise.
    //
    // Null is the honest answer. `embed` is nullable by contract, semantic
    // search over a library with no vectors returns nothing rather than
    // breaking, and the backfill's own "stop when nothing was written" check
    // means this costs one query per pass rather than a loop.
    return null;
  }

  @override
  Future<List<TagSuggestion>>? suggestTags(Note note) {
    return Future(() => suggestTagNames(note));
  }

  /// Pure helper for tests — keyword suggestions, never auto-applied.
  static List<TagSuggestion> suggestTagNames(Note note) {
    final source = note.searchableDerivedText ?? note.content ?? '';
    final tokens = source
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9\u0600-\u06FF]+'))
        .where(_isMeaningfulTagToken)
        .toSet()
        .take(5)
        .map((t) => TagSuggestion(name: t, score: 0.5))
        .toList();
    return tokens;
  }

  /// Reject hash-like IDs, short tokens, stopwords, and pure digits.
  static bool _isMeaningfulTagToken(String token) {
    if (token.length < 5) return false;
    if (_stopwords.contains(token)) return false;
    if (RegExp(r'^\d+$').hasMatch(token)) return false;
    // Hex / hash fragments (e.g. media_hash prefixes like "69cfddd4").
    if (RegExp(r'^[0-9a-f]{6,}$').hasMatch(token)) return false;
    if (RegExp(r'^[0-9a-f]{4,}[0-9]+[0-9a-f]*$').hasMatch(token) &&
        RegExp(r'\d').hasMatch(token) &&
        RegExp(r'[a-f]').hasMatch(token) &&
        token.length >= 6) {
      return false;
    }
    return true;
  }

  @override
  Future<Summary>? summarize(Note note) {
    return Future(() {
      final source = (note.content ?? note.transcriptText ?? note.ocrText ?? '')
          .trim();
      if (source.length < 80) {
        // Too short to meaningfully summarize — leave empty so UI can hide it.
        return const Summary(text: '');
      }
      return Summary(text: _compressSummary(source));
    });
  }

  /// Extractive stub: first sentence-ish clause, capped shorter than source.
  static String _compressSummary(String source) {
    final normalized = source.replaceAll(RegExp(r'\s+'), ' ').trim();
    final sentenceEnd = RegExp(r'[.!?][\s]|[\n]');
    final match = sentenceEnd.firstMatch(normalized);
    String head;
    if (match != null && match.start > 20) {
      head = normalized.substring(0, match.start + 1).trim();
    } else {
      final cut = normalized.length < 90 ? normalized.length : 90;
      head = normalized.substring(0, cut).trim();
      if (cut < normalized.length) head = '$head…';
    }
    // Guarantee visibly shorter than source when source is long.
    if (head.length >= normalized.length) {
      final cut = (normalized.length * 0.45).floor().clamp(40, 120);
      head = '${normalized.substring(0, cut).trim()}…';
    }
    return head;
  }

}

/// Gates cloud-backed adapters behind explicit per-capability opt-in (09-ai.md).
class CloudGatedAIAdapter implements AIAdapter {
  const CloudGatedAIAdapter({required this.inner, required this.cloudOptIn});

  final AIAdapter inner;
  final bool cloudOptIn;

  @override
  Future<Transcript>? transcribe(AudioRef audio) =>
      cloudOptIn ? inner.transcribe(audio) : null;

  @override
  Future<Vector>? embed(String text) => cloudOptIn ? inner.embed(text) : null;

  @override
  Future<List<TagSuggestion>>? suggestTags(Note note) =>
      cloudOptIn ? inner.suggestTags(note) : null;

  @override
  Future<Summary>? summarize(Note note) =>
      cloudOptIn ? inner.summarize(note) : null;

  @override
  Future<OCRText>? ocr(ImageRef image) => cloudOptIn ? inner.ocr(image) : null;
}
