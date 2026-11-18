/// Grouping for a money field, as a person types.
///
/// ``500000`` becomes ``500,000`` while the caret stays where it was, because
/// «five hundred thousand» and «five million» differ by one zero and the
/// grouping is what makes the difference visible. Only the digits and one
/// decimal separator are kept; a letter, a second separator or more decimals
/// than the currency has are dropped rather than turned into a wrong amount.
library;

import '../module_api.dart' show nexDigits;

/// Digits in any of the scripts a person may type, as they are.
bool _isDigit(String char) {
  final code = char.codeUnitAt(0);
  return (code >= 0x30 && code <= 0x39) ||
      (code >= 0x06f0 && code <= 0x06f9) ||
      (code >= 0x0660 && code <= 0x0669);
}

bool _isSeparator(String char) => char == '.' || char == '٫';

/// [raw] with its integer part grouped in threes, at most [decimals] digits
/// after the separator, and nothing else kept. In [persian] the field reads
/// «۱٬۲۰۰٬۰۰۰»: the digits and both separators are the ones a Persian reader
/// expects, and the parsers accept either script on the way back in.
String groupAmountText(String raw, int decimals, {bool persian = false}) {
  final whole = StringBuffer();
  final fraction = StringBuffer();
  var seenSeparator = false;
  for (var i = 0; i < raw.length; i++) {
    final char = raw[i];
    if (_isDigit(char)) {
      if (seenSeparator) {
        if (fraction.length < decimals) fraction.write(char);
      } else {
        whole.write(char);
      }
    } else if (_isSeparator(char) && decimals > 0 && !seenSeparator) {
      seenSeparator = true;
    }
    // Anything else is a typo the amount cannot contain; it is dropped.
  }
  var digits = whole.toString();
  // «007» is «7»: leading zeros are how a wrong amount starts.
  if (digits.length > 1) {
    digits = digits.replaceFirst(RegExp(r'^0+(?=\d)'), '');
  }
  final grouped = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) grouped.write(',');
    grouped.write(digits[i]);
  }
  if (seenSeparator) {
    grouped.write('.');
    grouped.write(fraction.toString());
  }
  final text = grouped.toString();
  return persian
      ? nexDigits(text, persian: true).replaceAll(',', '٬').replaceAll('.', '٫')
      : text;
}

/// How many digits and separators stand before [caret] — the position in the
/// number itself, which survives regrouping.
int _logicalPosition(String text, int caret) {
  var position = 0;
  for (var i = 0; i < caret && i < text.length; i++) {
    final char = text[i];
    if (_isDigit(char) || _isSeparator(char)) position++;
  }
  return position;
}

/// The grouped text and where the caret goes back to.
({String text, int caret}) groupAmountEdit(
  String raw,
  int caret,
  int decimals, {
  bool persian = false,
}) {
  final text = groupAmountText(raw, decimals, persian: persian);
  final wanted = _logicalPosition(raw, caret);
  var seen = 0;
  var offset = 0;
  while (offset < text.length && seen < wanted) {
    final char = text[offset];
    if (_isDigit(char) || _isSeparator(char)) seen++;
    offset++;
  }
  return (text: text, caret: offset);
}

/// The grouping used for display outside a field.
String groupWholeDigits(int value) =>
    groupAmountText(value.abs().toString(), 0);
