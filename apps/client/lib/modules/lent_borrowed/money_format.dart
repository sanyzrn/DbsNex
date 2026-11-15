import '../module_api.dart' show nexDigits;

import 'currency_scales.dart';
import 'irr_unit.dart';
import 'money_words.dart';
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

String localDigits(String value, bool persian) =>
    !persian ? value : nexDigits(value, persian: true);

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

/// How many decimals the amount of [currency] is *said* with: the currency's
/// own precision, except for the rial — where a toman is ten rials, so a
/// toman amount can need one decimal (1,250.5 toman).
int amountDisplayDigits(String currency, int digits, IrrUnit unit) =>
    currency == 'IRR' ? unit.displayDigits : digits;

/// The amount [minor] as a person reads it: grouped, in the display unit,
/// with that unit said in words — «۵۰٬۰۰۰ تومان», "50,000 tomans",
/// "1,234.56 USD". Iranian amounts never show a Latin code: people say
/// toman or rial, so the module says what they say.
String formatAmount(
  int minor,
  String currency,
  int digits,
  bool persian,
  IrrUnit unit,
) {
  if (currency != 'IRR') {
    // A foreign code stays isolated from an RTL sentence.
    return formatMoney(minor, currency, digits, persian);
  }
  final displayDigits = amountDisplayDigits(currency, digits, unit);
  final factor = moneyFactor(displayDigits);
  final negative = minor < 0;
  final value = minor.abs();
  // A whole toman is «۵۰٬۰۰۰ تومان», not «۵۰٬۰۰۰٫۰ تومان»: the decimal
  // exists only when the stored rials leave a remainder.
  final rest = displayDigits == 0 ? 0 : value % factor;
  final fraction = rest == 0
      ? ''
      : '${persian ? '٫' : '.'}${localDigits(rest.toString().padLeft(displayDigits, '0'), persian)}';
  final label = currencyUnitWord(
    currency,
    unit,
    persian: persian,
    plural: value ~/ factor != 1,
  );
  return '${negative ? '−' : ''}${formatNumber(value ~/ factor, persian)}$fraction $label';
}

/// The same amount in words, under the digits.
String formatAmountWords(
  int minor,
  String currency,
  int digits,
  bool persian,
  IrrUnit unit,
) {
  final displayDigits = amountDisplayDigits(currency, digits, unit);
  // A toman amount is said with one decimal (a toman is ten rials), so the
  // stored rials already read as tomans once [displayDigits] is applied.
  return amountInWords(
    minor: minor,
    digits: displayDigits,
    persian: persian,
    unit: currencyUnitWord(currency, unit, persian: persian),
    unitOne: currencyUnitWord(currency, unit, persian: persian, plural: false),
  );
}

/// Parses what a person typed into stored minor units. The typed number is
/// in the display unit, so a toman entry becomes rials by the toman's ten.
int? parseAmount(String raw, String currency, int digits, IrrUnit unit) {
  final displayDigits = amountDisplayDigits(currency, digits, unit);
  // With one decimal a typed toman is already read as its rials: 50,000
  // tomans parses as 500,000. With whole rials it is the rials themselves.
  final parsed = parseMoney(raw, displayDigits);
  if (parsed == null || parsed > maxMoney) return null;
  return parsed;
}

/// [minor] as the editor's field text, in the display unit and without
/// grouping (the field's formatter adds that).
String amountInput(int minor, String currency, int digits, IrrUnit unit) {
  final displayDigits = amountDisplayDigits(currency, digits, unit);
  final factor = moneyFactor(displayDigits);
  final value = minor.abs();
  final whole = value ~/ factor;
  final fraction = value % factor;
  final sign = minor < 0 ? '-' : '';
  if (displayDigits == 0 || fraction == 0) return '$sign$whole';
  final text = fraction.toString().padLeft(displayDigits, '0');
  final trimmed = text.replaceFirst(RegExp(r'0+$'), '');
  return '$sign$whole.${trimmed.isEmpty ? '0' : trimmed}';
}

/// Compatibility helper used by existing unit tests and legacy displays.
String formatRials(int rials, bool persian) => formatNumber(rials, persian);
