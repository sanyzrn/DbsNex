import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import '../models/note.dart';

import 'ai_adapter.dart';

/// Default on-device adapter (09-ai.md — "Default to local").
///
/// Lives in `packages/core` so apps/client can wire it via DI without depending
/// on optional `packages/ai`. Deterministic local heuristics; no network.
class OnDeviceAIAdapter implements AIAdapter {
  const OnDeviceAIAdapter({this.embeddingDims = 32});

  final int embeddingDims;

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
    return Future(() {
      final seed =
          audio.mediaHash ??
          sha256.convert(utf8.encode(audio.mediaUri)).toString();
      // Stable stub transcript so FTS/search tests are deterministic.
      final text =
          'voice transcript ${seed.substring(0, 8)} spoken note content';
      return Transcript(text: text, confidence: 0.42);
    });
  }

  @override
  Future<OCRText>? ocr(ImageRef image) {
    return Future(() {
      final seed =
          image.mediaHash ??
          sha256.convert(utf8.encode(image.mediaUri)).toString();
      final text = 'photo text ${seed.substring(0, 8)} readable label';
      return OCRText(text: text, confidence: 0.4);
    });
  }

  @override
  Future<Vector>? embed(String text) {
    return Future(() => Vector(_hashEmbed(text, embeddingDims)));
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

  /// Tiny deterministic embedding from SHA-256 — good enough for cosine demos.
  static List<double> _hashEmbed(String text, int dims) {
    final digest = sha256.convert(utf8.encode(text.toLowerCase().trim()));
    final bytes = Uint8List.fromList(digest.bytes);
    final out = List<double>.filled(dims, 0);
    for (var i = 0; i < dims; i++) {
      final b = bytes[i % bytes.length];
      out[i] = (b / 255.0) * 2 - 1;
    }
    var norm = 0.0;
    for (final v in out) {
      norm += v * v;
    }
    norm = math.sqrt(norm);
    if (norm > 0) {
      for (var i = 0; i < dims; i++) {
        out[i] /= norm;
      }
    }
    return out;
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
