import 'currency_scales.dart';
import 'number_input.dart';

const maxMoney = 9007199254740991;

String currencyCode(Object? raw) {
  final code = raw is String ? raw.trim().toUpperCase() : '';
  return RegExp(r'^[A-Z]{3}$').hasMatch(code) ? code : 'IRR';
}

int moneyDigits(String code, [Object? stored]) =>
    stored is int && stored >= 0 && stored <= 4
    ? stored
    : currencyScales[code] ?? 2;

int moneyFactor(int digits) {
  var result = 1;
  for (var i = 0; i < digits; i++) {
    result *= 10;
  }
  return result;
}

/// Exact major-unit input; extra precision is refused, never rounded silently.
/// Commas / Arabic separators must form groups of three. Decimal comma is
/// intentionally refused; '.' and '٫' are unambiguous decimal separators.
int? parseMoney(String raw, int digits) {
  if (digits < 0 || digits > 4) return null;
  final text = normalizeNumber(raw).replaceAll('٫', '.').replaceAll('٬', ',');
  final parts = text.split('.');
  if (parts.length > 2) return null;
  final whole = parts.first;
  if (!RegExp(r'^(?:[0-9]+|[0-9]{1,3}(?:,[0-9]{3})+)$').hasMatch(whole)) {
    return null;
  }
  final fraction = parts.length == 2 ? parts.last : '';
  if (parts.length == 2 &&
      (fraction.isEmpty || !RegExp(r'^[0-9]+$').hasMatch(fraction))) {
    return null;
  }
  if (fraction.length > digits) return null;
  final value = BigInt.tryParse(
    whole.replaceAll(',', '') + fraction.padRight(digits, '0'),
  );
  if (value == null || value > BigInt.from(maxMoney)) return null;
  return value.toInt();
}

String moneyInput(int minor, int digits) {
  final factor = moneyFactor(digits);
  final sign = minor < 0 ? '-' : '';
  final value = minor.abs();
  return '$sign${value ~/ factor}${digits == 0 ? '' : '.${(value % factor).toString().padLeft(digits, '0')}'}';
}

String localDigits(String value, bool persian) => !persian
    ? value
    : value.replaceAllMapped(
        RegExp(r'[0-9]'),
        (m) => '۰۱۲۳۴۵۶۷۸۹'[int.parse(m[0]!)],
      );

String formatNumber(int value, bool persian) {
  final digits = value.abs().toString();
  final groups = <String>[];
  for (var end = digits.length; end > 0; end -= 3) {
    groups.insert(0, digits.substring((end - 3).clamp(0, end), end));
  }
  return localDigits(
    '${value < 0 ? '−' : ''}${groups.join(persian ? '٬' : ',')}',
    persian,
  );
}

String formatMoney(int minor, String currency, int digits, bool persian) {
  final factor = moneyFactor(digits);
  final fraction = digits == 0
      ? ''
      : '${persian ? '٫' : '.'}${localDigits((minor.abs() % factor).toString().padLeft(digits, '0'), persian)}';
  // Isolate the code from the surrounding RTL sentence.
  return '${formatNumber(minor ~/ factor, persian)}$fraction \u2066$currency\u2069';
}

/// Compatibility helper used by existing unit tests and legacy displays.
String formatRials(int rials, bool persian) => formatNumber(rials, persian);

String formatExactMoney(
  BigInt minor,
  String currency,
  int digits,
  bool persian,
) {
  final factor = BigInt.from(moneyFactor(digits));
  final whole = (minor ~/ factor).toString();
  final grouped = whole.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]}${persian ? '٬' : ','}',
  );
  final fraction = digits == 0
      ? ''
      : '${persian ? '٫' : '.'}${(minor % factor).toString().padLeft(digits, '0')}';
  return '${localDigits(grouped + fraction, persian)} \u2066$currency\u2069';
}
