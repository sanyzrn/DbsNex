import 'package:nex_core/nex_core.dart';
import 'package:test/test.dart';

/// What the intelligence layer is permitted to do with somebody's notes, and
/// what it is permitted to do when nobody said.
///
/// The answer used to be "everything". Each of the six flags defaulted to
/// true, so two production sites that take the default — the database
/// worker's boot message and [EnrichmentService]'s own constructor — granted
/// all six capabilities to a caller who simply did not pass the argument.
/// A permission granted by omission is not a permission anybody gave.
void main() {
  test('saying nothing grants nothing', () {
    const silent = AiCapabilities();
    expect(silent.transcription, isFalse);
    expect(silent.ocr, isFalse);
    expect(silent.tagSuggestions, isFalse);
    expect(silent.semanticSearch, isFalse);
    expect(silent.summarization, isFalse);
    expect(silent.relatedNotes, isFalse);
  });

  test('naming one capability grants one capability', () {
    // The other half of the same rule, and the one a default of `true` hid:
    // `AiCapabilities(semanticSearch: true)` used to mean "semantic search,
    // and also transcription, OCR, tag suggestions, summaries and related
    // notes".
    const one = AiCapabilities(semanticSearch: true);
    expect(one.semanticSearch, isTrue);
    expect(one.transcription, isFalse);
    expect(one.ocr, isFalse);
    expect(one.tagSuggestions, isFalse);
    expect(one.summarization, isFalse);
    expect(one.relatedNotes, isFalse);
  });

  test('allOff is what an empty constructor now means', () {
    const off = AiCapabilities.allOff;
    expect(off.transcription, isFalse);
    expect(off.relatedNotes, isFalse);
  });

  test('allOn has to be asked for by name', () {
    const on = AiCapabilities.allOn;
    expect(on.transcription, isTrue);
    expect(on.ocr, isTrue);
    expect(on.tagSuggestions, isTrue);
    expect(on.semanticSearch, isTrue);
    expect(on.summarization, isTrue);
    expect(on.relatedNotes, isTrue);
  });

  test('copyWith turns one flag and leaves the rest', () {
    final one = AiCapabilities.allOn.copyWith(ocr: false);
    expect(one.ocr, isFalse);
    expect(one.transcription, isTrue);
  });
}
