import 'dart:math' as math;

import 'package:nex_client/modules/module_api.dart';

/// Reading and writing the numbers a person types and reads.
///
/// A Persian phone keyboard can produce Persian (`۱۲۳`), Arabic (`١٢٣`) or
/// Latin (`123`) digits, and the decimal separator can be the Arabic one
/// (`٫`, U+066B) or a full stop. All of them mean the same number here, and
/// every result is written back in the reader's own digits — «۱۵۴٫۳» for a
/// Persian reader, «154.3» for an English one.

/// The same characters, with every digit written as 0–9.
///
/// Kept public because the date field needs it too: a Persian date typed as
/// «۱۴۰۵/۰۸/۲۲» has to be read the same way a number is.
String converterLatinDigits(String text) {
  final buffer = StringBuffer();
  for (final rune in text.runes) {
    if (rune >= 0x06F0 && rune <= 0x06F9) {
      buffer.writeCharCode(0x30 + rune - 0x06F0);
    } else if (rune >= 0x0660 && rune <= 0x0669) {
      buffer.writeCharCode(0x30 + rune - 0x0660);
    } else {
      buffer.writeCharCode(rune);
    }
  }
  return buffer.toString();
}

/// The number in [raw], or null when it is not one.
///
/// Empty input, a lone sign, two decimal points and letters all answer null:
/// the screen then shows nothing rather than a guess, which is what a person
/// typing «12.» halfway through a number needs.
double? converterParseNumber(String raw) {
  final text = converterLatinDigits(raw)
      .replaceAll('\u2212', '-')
      .replaceAll('\u066B', '.')
      .replaceAll(RegExp(r'[\u066C\u060C,_\s\u00A0]'), '')
      .trim();
  if (text.isEmpty) return null;
  if (!RegExp(r'^[+-]?(\d+(\.\d*)?|\.\d+)$').hasMatch(text)) return null;
  final value = double.tryParse(text);
  if (value == null || !value.isFinite) return null;
  return value;
}

/// [value] as a person reads it — grouped, trimmed, in their own digits.
///
/// The number of decimals follows the size of the number: a length in
/// millimetres stays whole, a mile in millimetres keeps two, and a
/// thousandth of a mile keeps as many as it needs to say something. That is
/// what makes one formatter usable for «70» and for «0.000000621» without
/// either of them reading like a mistake.
String converterFormatNumber(
  double value, {
  required bool persian,
  int? decimals,
}) {
  if (!value.isFinite) return '—';
  if (value == 0) return nexDigits('0', persian: persian);
  var text = value.toStringAsFixed(decimals ?? _decimalsFor(value.abs()));
  if (text.contains('e') || text.contains('E')) {
    text = value.toStringAsExponential(3);
  }
  text = _trimZeros(text);
  text = _group(text);
  if (persian) text = text.replaceAll(',', '\u066C').replaceAll('.', '\u066B');
  return nexDigits(text, persian: persian);
}

int _decimalsFor(double magnitude) {
  if (magnitude >= 1e6) return 2;
  if (magnitude >= 1000) return 3;
  if (magnitude >= 1) return 4;
  // Small numbers keep about three significant digits past their first.
  final leadingZeros = (-math.log(magnitude) / math.ln10).ceil();
  return (leadingZeros + 3).clamp(1, 12);
}

String _trimZeros(String text) {
  if (!text.contains('.')) return text;
  var end = text.length;
  while (end > 0 && text[end - 1] == '0') {
    end--;
  }
  if (end > 0 && text[end - 1] == '.') end--;
  return text.substring(0, end);
}

String _group(String plain) {
  final negative = plain.startsWith('-');
  final body = negative ? plain.substring(1) : plain;
  final dot = body.indexOf('.');
  final whole = dot < 0 ? body : body.substring(0, dot);
  final fraction = dot < 0 ? '' : body.substring(dot);
  final buffer = StringBuffer();
  for (var index = 0; index < whole.length; index++) {
    if (index > 0 && (whole.length - index) % 3 == 0) buffer.write(',');
    buffer.write(whole[index]);
  }
  return '${negative ? '-' : ''}$buffer$fraction';
}
