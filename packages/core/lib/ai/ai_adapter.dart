import 'dart:typed_data';

import '../models/note.dart';

/// Provider-agnostic AI adapter (06-development.md / 09-ai.md).
///
/// Every method is nullable — a missing capability is "unavailable", not an
/// error. Core never imports a vendor SDK; only this contract.
abstract class AIAdapter {
  Future<Transcript>? transcribe(AudioRef audio);
  Future<Vector>? embed(String text);
  Future<List<TagSuggestion>>? suggestTags(Note note);
  Future<Summary>? summarize(Note note);
  Future<OCRText>? ocr(ImageRef image);
}

/// Local audio reference for transcription (never logged as content).
class AudioRef {
  const AudioRef({
    required this.mediaUri,
    this.mediaHash,
    this.bytes,
  });

  final String mediaUri;
  final String? mediaHash;
  final Uint8List? bytes;
}

/// Local image reference for OCR.
class ImageRef {
  const ImageRef({
    required this.mediaUri,
    this.mediaHash,
    this.bytes,
  });

  final String mediaUri;
  final String? mediaHash;
  final Uint8List? bytes;
}

/// Speech-to-text result — stored as [Note.transcriptText], never overwrites media.
class Transcript {
  const Transcript({required this.text, this.confidence});

  final String text;
  final double? confidence;
}

/// OCR result — stored as [Note.ocrText], never overwrites the photo.
class OCRText {
  const OCRText({required this.text, this.confidence});

  final String text;
  final double? confidence;
}

/// On-demand summary — stored as [Note.summaryText].
class Summary {
  const Summary({required this.text});

  final String text;
}

/// Dense embedding for semantic search / related notes.
class Vector {
  const Vector(this.values);

  final List<double> values;

  int get dimensions => values.length;
}

/// Suggested tag name — never auto-applied; UI must confirm.
class TagSuggestion {
  const TagSuggestion({required this.name, this.score});

  final String name;
  final double? score;
}

/// No-op adapter — every capability is unavailable (AI disabled).
class NullAIAdapter implements AIAdapter {
  const NullAIAdapter();

  @override
  Future<Transcript>? transcribe(AudioRef audio) => null;

  @override
  Future<Vector>? embed(String text) => null;

  @override
  Future<List<TagSuggestion>>? suggestTags(Note note) => null;

  @override
  Future<Summary>? summarize(Note note) => null;

  @override
  Future<OCRText>? ocr(ImageRef image) => null;
}
