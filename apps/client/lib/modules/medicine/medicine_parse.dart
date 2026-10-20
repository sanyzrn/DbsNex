import 'local_values.dart';

/// Reading back what the editor's fields hold, kept apart so it can be
/// tested on its own. Nothing here guesses: a value that does not parse
/// says so through its sentinel rather than becoming something plausible.
class MedicineParse {
  const MedicineParse._();

  /// A stand-in the editor compares against: a real parse can never
  /// produce it, so "equal to [invalid]" means "did not parse".
  static final DateTime invalid = DateTime(1800);

  /// A count as written: null when the text is empty (the number stays
  /// the person's own to keep), or the whole number it holds.
  static int? count(String written) {
    final text = written.trim();
    if (text.isEmpty) {
      return null;
    }
    return LocalValues.writtenCount(text);
  }

  /// The expiry date as written, or null when there is none. A year
  /// outside 1900–2100 is [invalid] rather than guessed into something
  /// plausible.
  static DateTime? expiry(String written) {
    if (written.trim().isEmpty) {
      return null;
    }
    return LocalValues.day(written) ?? invalid;
  }
}
