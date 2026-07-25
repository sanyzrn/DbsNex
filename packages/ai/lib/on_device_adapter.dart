import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:nex_core/nex_core.dart';

/// Default on-device adapter (09-ai.md — "Default to local").
///
/// Deterministic local heuristics suitable for tests and offline use. No
/// network calls; no note content leaves the device. Real platform STT/OCR
/// engines can replace this behind the same [AIAdapter] contract.
class OnDeviceAIAdapter implements AIAdapter {
  const OnDeviceAIAdapter({this.embeddingDims = 32});

  final int embeddingDims;

  @override
  Future<Transcript>? transcribe(AudioRef audio) {
    return Future(() {
      final seed = audio.mediaHash ??
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
      final seed = image.mediaHash ??
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
    return Future(() {
      final source = note.searchableDerivedText ?? note.content ?? '';
      final tokens = source
          .toLowerCase()
          .split(RegExp(r'[^a-z0-9\u0600-\u06FF]+'))
          .where((t) => t.length >= 4)
          .toSet()
          .take(5)
          .map((t) => TagSuggestion(name: t, score: 0.5))
          .toList();
      return tokens;
    });
  }

  @override
  Future<Summary>? summarize(Note note) {
    return Future(() {
      final source = note.content ??
          note.transcriptText ??
          note.ocrText ??
          '';
      if (source.isEmpty) {
        return const Summary(text: '');
      }
      final trimmed = source.length <= 120
          ? source
          : '${source.substring(0, 117)}...';
      return Summary(text: trimmed);
    });
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
    // L2 normalize
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
///
/// When [cloudOptIn] is false, all methods return null (unavailable) so callers
/// fall back to on-device-only behavior or skip enrichment.
class CloudGatedAIAdapter implements AIAdapter {
  const CloudGatedAIAdapter({
    required this.inner,
    required this.cloudOptIn,
  });

  final AIAdapter inner;
  final bool cloudOptIn;

  @override
  Future<Transcript>? transcribe(AudioRef audio) =>
      cloudOptIn ? inner.transcribe(audio) : null;

  @override
  Future<Vector>? embed(String text) =>
      cloudOptIn ? inner.embed(text) : null;

  @override
  Future<List<TagSuggestion>>? suggestTags(Note note) =>
      cloudOptIn ? inner.suggestTags(note) : null;

  @override
  Future<Summary>? summarize(Note note) =>
      cloudOptIn ? inner.summarize(note) : null;

  @override
  Future<OCRText>? ocr(ImageRef image) =>
      cloudOptIn ? inner.ocr(image) : null;
}
