/// Iranian IBANs (شبا): `IR` followed by 24 digits, checked with mod 97.
///
/// The IBAN is the number people share when a card is not wanted; it is
/// public by design, like the card number. Nothing here is fetched: the
/// check is the same ISO 13616 arithmetic every bank uses.
library;

import 'card_number.dart';

/// Latin `IR` and 24 digits, with spaces or Persian digits folded away.
String ibanNormalize(String raw) {
  final digits = cardDigits(raw);
  return digits.length == 24 ? 'IR$digits' : '';
}

/// Whether [raw] is a well-formed Iranian IBAN whose mod-97 remainder is 1.
bool ibanOk(String raw) {
  final value = ibanNormalize(raw);
  if (value.length != 26) return false;
  // Move the first four characters to the end, then read letters as numbers
  // (I = 18, R = 27) and take the remainder as we go, so no huge number is
  // ever built.
  final rearranged = '${value.substring(4)}${value.substring(0, 4)}';
  final buffer = StringBuffer();
  for (final rune in rearranged.runes) {
    final char = String.fromCharCode(rune);
    final code = char.codeUnitAt(0);
    if (code >= 0x30 && code <= 0x39) {
      buffer.writeCharCode(code);
    } else if (code >= 0x41 && code <= 0x5A) {
      buffer.write(code - 0x41 + 10);
    } else {
      return false;
    }
  }
  var remainder = 0;
  for (final digit in buffer.toString().split('')) {
    remainder = (remainder * 10 + int.parse(digit)) % 97;
  }
  return remainder == 1;
}

/// `IR12 3456 7890 1234 5678 9012 34` — groups of four, for reading.
String groupIban(String raw) {
  final value = ibanNormalize(raw);
  if (value.isEmpty) {
    final cleaned = raw.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
    return _groups(cleaned);
  }
  return _groups(value);
}

String _groups(String value) {
  final parts = <String>[];
  for (var start = 0; start < value.length; start += 4) {
    parts.add(value.substring(start, (start + 4).clamp(0, value.length)));
  }
  return parts.join(' ');
}
