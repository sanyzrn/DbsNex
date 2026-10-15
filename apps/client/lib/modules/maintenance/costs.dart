/// Money for the Maintenance Log: service costs as integer minor
/// units with an ISO 4217 code and exponent. The same contract the
/// other finance modules hold, kept module-local because the kit
/// forbids imports between siblings — each module owns its copy.
///
/// Nothing converts, nothing fetches: a cost is what the person
/// entered, in the currency they chose. The rial keeps its ISO
/// exponent 2; entry is whole rials or — clearly labelled — whole
/// tomans (1 toman = 10 rials = 1000 minor units).
library;

import 'local_values.dart';

/// A currency a cost can be entered in.
class CostCurrency {
  const CostCurrency(this.code, this.exponent, this.nameEn, this.nameFa);

  /// ISO 4217 alphabetic code, upper-case.
  final String code;

  /// Minor units per major unit (JPY 0, USD 2, KWD 3, IRR 2).
  final int exponent;

  final String nameEn;
  final String nameFa;

  String name(bool persian) => persian ? nameFa : nameEn;
}

/// The currencies offered, in display order.
const costCurrencies = <CostCurrency>[
  CostCurrency('IRR', 2, 'Iranian rial', 'ریال ایران'),
  CostCurrency('USD', 2, 'US dollar', 'دلار آمریکا'),
  CostCurrency('EUR', 2, 'Euro', 'یورو'),
  CostCurrency('GBP', 2, 'Pound sterling', 'پوند استرلینگ'),
  CostCurrency('JPY', 0, 'Japanese yen', 'یِن ژاپن'),
  CostCurrency('KWD', 3, 'Kuwaiti dinar', 'دینار کویت'),
  CostCurrency('AED', 2, 'UAE dirham', 'درهم امارات'),
  CostCurrency('SAR', 2, 'Saudi riyal', 'ریال سعودی'),
  CostCurrency('TRY', 2, 'Turkish lira', 'لیر ترکیه'),
  CostCurrency('CHF', 2, 'Swiss franc', 'فرانک سوئیس'),
  CostCurrency('CAD', 2, 'Canadian dollar', 'دلار کانادا'),
  CostCurrency('AUD', 2, 'Australian dollar', 'دلار استرلیا'),
  CostCurrency('CNY', 2, 'Chinese yuan', 'یوان چین'),
  CostCurrency('INR', 2, 'Indian rupee', 'روپیه هند'),
];

CostCurrency? costCurrencyOf(String? code) {
  if (code == null) return null;
  for (final c in costCurrencies) {
    if (c.code == code) return c;
  }
  return null;
}

/// The exponent to trust for a stored cost.
int costExponentOf(String? code) => costCurrencyOf(code)?.exponent ?? 2;

/// Bounds: 1e15 minor units, same ceiling as the other modules.
const costMax = 1000000000000000;

/// Why a typed cost was refused.
enum CostAmountError {
  empty,
  notANumber,
  tooPrecise,
  zero,
  tooLarge,
  currencyRequired,
}

/// A parsed cost: [minor] when [error] is null.
typedef CostAmountResult = ({int? minor, CostAmountError? error});

/// Parses a cost typed in major units of [currency].
CostAmountResult parseCostAmount(String input, CostCurrency currency) =>
    _parse(input, currency.exponent);

/// Parses a cost typed in **tomans** into minor units of IRR
/// (toman × 1000; three decimals are exact, more is refused).
CostAmountResult parseTomanCost(String input) => _parse(input, 3);

CostAmountResult _parse(String input, int exponent) {
  final text = LocalValues.ascii(input.trim());
  if (text.isEmpty) return (minor: null, error: CostAmountError.empty);
  if (!RegExp(r'^([0-9]+([.,][0-9]*)?|[.,][0-9]+)$').hasMatch(text)) {
    return (minor: null, error: CostAmountError.notANumber);
  }
  var separators = 0;
  for (final rune in text.runes) {
    if (rune == 0x2E || rune == 0x2C) {
      separators++;
    } else if (rune < 0x30 || rune > 0x39) {
      return (minor: null, error: CostAmountError.notANumber);
    }
  }
  if (separators > 1) return (minor: null, error: CostAmountError.notANumber);
  final normalized = text.replaceAll(',', '.');
  final parts = normalized.split('.');
  final whole = parts[0].isEmpty ? '0' : parts[0];
  final fraction = parts.length > 1 ? parts[1] : '';
  if (fraction.length > exponent) {
    return (minor: null, error: CostAmountError.tooPrecise);
  }
  final digits = whole + fraction.padRight(exponent, '0');
  if (digits.length > 16) return (minor: null, error: CostAmountError.tooLarge);
  final value = int.tryParse(digits) ?? 0;
  if (value > costMax) return (minor: null, error: CostAmountError.tooLarge);
  return (minor: value, error: null);
}

/// The number part of a money display, no code, with `−`/`+`.
String formatCostNumber(
  Object minor,
  int exponent, {
  required bool persian,
  bool signed = false,
}) {
  final exact = minor is BigInt ? minor : BigInt.from(minor as int);
  final negative = exact.isNegative;
  var digits = exact.abs().toString();
  String text;
  if (exponent == 0) {
    text = groupLocal(digits, persian);
  } else {
    while (digits.length <= exponent) {
      digits = '0$digits';
    }
    final whole = groupLocal(
      digits.substring(0, digits.length - exponent),
      persian,
    );
    final fraction = digits
        .substring(digits.length - exponent)
        .replaceAll(RegExp(r'0+$'), '');
    text = fraction.isEmpty
        ? whole
        : '$whole.${persian ? persianLocal(fraction) : fraction}';
  }
  final sign = negative ? '−' : (signed ? '+' : '');
  return '$sign$text';
}

/// The editor's prefill text for a stored amount, in major units.
String costMajorText(int minor, int exponent) {
  var digits = minor.abs().toString();
  if (exponent == 0) return digits;
  while (digits.length <= exponent) {
    digits = '0$digits';
  }
  final whole = digits.substring(0, digits.length - exponent);
  final fraction = digits
      .substring(digits.length - exponent)
      .replaceAll(RegExp(r'0+$'), '');
  return fraction.isEmpty ? whole : '$whole.$fraction';
}

String groupLocal(String digits, bool persian) {
  final grouped = StringBuffer();
  var count = 0;
  for (var i = digits.length - 1; i >= 0; i--) {
    grouped.write(digits[i]);
    count++;
    if (count % 3 == 0 && i > 0) grouped.write(persian ? '٬' : ',');
  }
  final reversed = grouped.toString().split('').reversed.join('');
  return persian ? persianLocal(reversed) : reversed;
}

String persianLocal(String text) => text.replaceAllMapped(
  RegExp(r'[0-9]'),
  (m) => '۰۱۲۳۴۵۶۷۸۹'[int.parse(m[0]!)],
);

bool costRecordValid(String? code, Map<String, Object?> body) {
  final currency = costCurrencyOf(code);
  if (currency == null) return false;
  final stored = body['currency_exponent'];
  return (stored == null || stored == currency.exponent) &&
      (body['currency_code'] == null ||
          body['currency'] == null ||
          body['currency_code'] == body['currency']);
}

Map<String, Object?> costMetadata(String code) => {
  'currency_code': code,
  'currency_exponent': costCurrencyOf(code)?.exponent,
};
