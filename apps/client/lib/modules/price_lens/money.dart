/// Money for the Price Lens: package prices as integer minor units
/// with an ISO 4217 code and exponent — the same contract the other
/// finance modules hold, module-local because the kit forbids sibling
/// imports.
///
/// The rial keeps its ISO exponent 2; entry is whole rials or —
/// clearly labelled, off by default — whole tomans (1 toman = 10
/// rials = 1000 minor units). Nothing converts, nothing fetches, and
/// offers in different currencies are never compared.
library;

import 'local_values.dart';

/// A currency a price can be entered in.
class PriceCurrency {
  const PriceCurrency(this.code, this.exponent, this.nameEn, this.nameFa);

  /// ISO 4217 alphabetic code, upper-case.
  final String code;

  /// Minor units per major unit (JPY 0, USD 2, KWD 3, IRR 2).
  final int exponent;

  final String nameEn;
  final String nameFa;

  String name(bool persian) => persian ? nameFa : nameEn;
}

/// The currencies offered, in display order.
const priceCurrencies = <PriceCurrency>[
  PriceCurrency('IRR', 2, 'Iranian rial', 'ریال ایران'),
  PriceCurrency('USD', 2, 'US dollar', 'دلار آمریکا'),
  PriceCurrency('EUR', 2, 'Euro', 'یورو'),
  PriceCurrency('GBP', 2, 'Pound sterling', 'پوند استرلینگ'),
  PriceCurrency('JPY', 0, 'Japanese yen', 'یِن ژاپن'),
  PriceCurrency('KWD', 3, 'Kuwaiti dinar', 'دینار کویت'),
  PriceCurrency('AED', 2, 'UAE dirham', 'درهم امارات'),
  PriceCurrency('SAR', 2, 'Saudi riyal', 'ریال سعودی'),
  PriceCurrency('TRY', 2, 'Turkish lira', 'لیر ترکیه'),
  PriceCurrency('CHF', 2, 'Swiss franc', 'فرانک سوئیس'),
  PriceCurrency('CAD', 2, 'Canadian dollar', 'دلار کانادا'),
  PriceCurrency('AUD', 2, 'Australian dollar', 'دلار استرالیا'),
  PriceCurrency('CNY', 2, 'Chinese yuan', 'یوان چین'),
  PriceCurrency('INR', 2, 'Indian rupee', 'روپیه هند'),
];

PriceCurrency? priceCurrencyOf(String? code) {
  if (code == null) return null;
  for (final c in priceCurrencies) {
    if (c.code == code) return c;
  }
  return null;
}

/// The exponent to trust for a stored price.
int priceExponentOf(String? code) => priceCurrencyOf(code)?.exponent ?? 2;

/// Bounds: 1e15 minor units, the ceiling every module here shares.
const priceMax = 1000000000000000;

/// Why a typed price was refused.
enum PriceAmountError { empty, notANumber, tooLarge, tooPrecise }

/// A parsed price: [minor] when [error] is null.
typedef PriceAmountResult = ({int? minor, PriceAmountError? error});

/// Parses a price typed in major units of [currency].
PriceAmountResult parsePriceAmount(String input, PriceCurrency currency) =>
    _parse(input, currency.exponent);

/// Parses a price typed in **tomans** into minor units of IRR.
PriceAmountResult parseTomanPrice(String input) => _parse(input, 3);

PriceAmountResult _parse(String input, int exponent) {
  final text = LocalValues.ascii(input.trim());
  if (text.isNotEmpty &&
      !RegExp(r'^([0-9]+([.,][0-9]*)?|[.,][0-9]+)$').hasMatch(text)) {
    return (minor: null, error: PriceAmountError.notANumber);
  }
  if (text.isEmpty) return (minor: null, error: PriceAmountError.empty);
  var separators = 0;
  for (final rune in text.runes) {
    if (rune == 0x2E || rune == 0x2C) {
      separators++;
    } else if (rune < 0x30 || rune > 0x39) {
      return (minor: null, error: PriceAmountError.notANumber);
    }
  }
  if (separators > 1) return (minor: null, error: PriceAmountError.notANumber);
  final normalized = text.replaceAll(',', '.');
  final parts = normalized.split('.');
  final whole = parts[0].isEmpty ? '0' : parts[0];
  final fraction = parts.length > 1 ? parts[1] : '';
  if (fraction.length > exponent) {
    return (minor: null, error: PriceAmountError.tooPrecise);
  }
  final digits = whole + fraction.padRight(exponent, '0');
  if (digits.length > 16) {
    return (minor: null, error: PriceAmountError.tooLarge);
  }
  final value = int.tryParse(digits) ?? 0;
  if (value > priceMax) {
    return (minor: null, error: PriceAmountError.tooLarge);
  }
  return (minor: value, error: null);
}

/// The number part of a money display, no code, with `−`.
String formatPriceNumber(int minor, int exponent, {required bool persian}) {
  final negative = minor < 0;
  var digits = minor.abs().toString();
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
  return negative ? '−$text' : text;
}

/// The editor's prefill text for a stored amount, in major units.
String priceMajorText(int minor, int exponent) {
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

Map<String, Object?> priceMetadata(String code) => {
  'currency_code': code,
  'currency_exponent': priceCurrencyOf(code)?.exponent,
};
bool priceMetadataValid(Map<String, Object?> b) {
  final code = b['currency_code'] ?? b['currency'];
  if (code is! String || priceCurrencyOf(code) == null) return false;
  if (b['currency'] != null && b['currency'] != code) return false;
  final exp = b['currency_exponent'];
  return exp == null || (exp is int && exp == priceCurrencyOf(code)!.exponent);
}
