import 'local_values.dart';

/// Reading back what the editor's fields hold, kept apart so it can be
/// tested on its own. Nothing here guesses: a value that does not parse
/// says so through its sentinel rather than becoming something plausible.
class WarrantyParse {
  const WarrantyParse._();

  /// A stand-in the editor compares against: a real parse can never
  /// produce it, so "equal to [invalid]" means "did not parse".
  static final DateTime invalid = DateTime(1800);

  /// A count as written: null when the field is empty, or the whole
  /// number it holds.
  static int? count(String written) {
    final text = written.trim();
    if (text.isEmpty) {
      return null;
    }
    return LocalValues.writtenCount(text);
  }

  /// A date as written (y/m/d), or null when there is none. A year
  /// outside 1900–2100 is [invalid] rather than guessed into something
  /// plausible.
  static DateTime? date(String written) {
    if (written.trim().isEmpty) {
      return null;
    }
    return LocalValues.day(written) ?? invalid;
  }

  /// A date as the editor's field holds it: zero padded, exactly as the
  /// shared calendar button writes it.
  static String dateText(DateTime value) =>
      '${value.year}/${LocalValues.two(value.month)}/${LocalValues.two(value.day)}';

  /// The rials an amount stands for, given the unit it was typed in.
  /// Half-tomans are refused, not rounded.
  static int? rials(String written, {required bool inTomans}) {
    final text = LocalValues.ascii(written.trim());
    if (!inTomans) {
      return count(text);
    }
    final match = RegExp(r'^(\d+)(?:\.(\d))?$').firstMatch(text);
    if (match == null) {
      return null;
    }
    final value =
        BigInt.parse(match[1]!) * BigInt.from(10) +
        BigInt.parse(match[2] ?? '0');
    return value <= BigInt.from(LocalValues.maxExact) ? value.toInt() : null;
  }
}
