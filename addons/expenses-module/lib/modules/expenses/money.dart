/// Money for the Expenses module: an ISO 4217 code, its exponent, and
/// amounts held as **integers in minor units** — never floating point.
///
/// The catalogue is deliberately short and country-neutral: a few majors
/// plus the rial, each with the exponent ISO 4217 gives it. Nothing is
/// fetched, converted or guessed: a currency is what the person chose,
/// and totals are only ever summed inside one currency.
///
/// The rial (`IRR`) carries ISO exponent 2, so a stored amount counts
/// dinars (1 rial = 100 dinars) even though nobody prices anything in
/// them. Entry is in whole rials — or, clearly labelled and never the
/// default, whole tomans (1 toman = 10 rials). See the module's README.
library;

import 'local_values.dart';

/// A currency the module knows, chosen by the person explicitly.
class ExpenseCurrency {
  const ExpenseCurrency(this.code, this.exponent, this.nameEn, this.nameFa);

  /// ISO 4217 alphabetic code, upper-case.
  final String code;

  /// Minor units per major unit (JPY 0, USD 2, KWD 3, IRR 2).
  final int exponent;

  final String nameEn;
  final String nameFa;

  /// The name in the chosen language.
  String name(bool persian) => persian ? nameFa : nameEn;
}

/// The currencies offered, in display order.
const expenseCurrencies = <ExpenseCurrency>[
  ExpenseCurrency('IRR', 2, 'Iranian rial', 'ریال ایران'),
  ExpenseCurrency('USD', 2, 'US dollar', 'دلار آمریکا'),
  ExpenseCurrency('EUR', 2, 'Euro', 'یورو'),
  ExpenseCurrency('GBP', 2, 'Pound sterling', 'پوند استرلینگ'),
  ExpenseCurrency('JPY', 0, 'Japanese yen', 'یِن ژاپن'),
  ExpenseCurrency('KWD', 3, 'Kuwaiti dinar', 'دینار کویت'),
  ExpenseCurrency('AED', 2, 'UAE dirham', 'درهم امارات'),
  ExpenseCurrency('SAR', 2, 'Saudi riyal', 'ریال سعودی'),
  ExpenseCurrency('TRY', 2, 'Turkish lira', 'لیر ترکیه'),
  ExpenseCurrency('CHF', 2, 'Swiss franc', 'فرانک سوئیس'),
  ExpenseCurrency('CAD', 2, 'Canadian dollar', 'دلار کانادا'),
  ExpenseCurrency('AUD', 2, 'Australian dollar', 'دلار استرالیا'),
  ExpenseCurrency('CNY', 2, 'Chinese yuan', 'یوان چین'),
  ExpenseCurrency('INR', 2, 'Indian rupee', 'روپیه هند'),
];

/// The currency with [code], or null — a stored record naming one the
/// catalogue no longer lists still shows its code defensively.
ExpenseCurrency? expenseCurrencyOf(String? code) {
  if (code == null) return null;
  for (final c in expenseCurrencies) {
    if (c.code == code) return c;
  }
  return null;
}

/// The exponent to trust for a stored record: the catalogue's word for
/// [code] wins over a stored exponent that disagrees with it, because
/// the catalogue is the truth; unknown codes fall back to the stored
/// exponent when it is sane, else 2.
int expenseExponentOf(String? code, Object? stored) {
  final catalogued = expenseCurrencyOf(code)?.exponent;
  if (catalogued != null) return catalogued;
  if (stored is int && stored >= 0 && stored <= 6) return stored;
  return 2;
}

/// Bounds every amount lives inside: small enough that sums and
/// percentage math cannot overflow, large enough for any real figure
/// (1e15 minor units is a quadrillion of them).
const expenseAmountMax = 1000000000000000; // 1e15
const expenseAmountMin = 1;

/// Why a typed amount was refused — becomes the field's error text.
enum ExpenseAmountError {
  empty,
  notANumber,
  tooPrecise,
  zero,
  negative,
  tooLarge,
}

/// A parsed amount: [minor] when [error] is null.
typedef ExpenseAmountResult = ({int? minor, ExpenseAmountError? error});

/// Parses what a person typed, in **major units** of [currency] —
/// `12.55` for USD, `1200` for JPY — into minor units.
///
/// * Digits, and at most one decimal separator (`,` is accepted too).
/// * More decimals than the exponent is [ExpenseAmountError.tooPrecise]:
///   money is never silently rounded on the way in.
/// * No signs, spaces, grouping or scientific notation.
ExpenseAmountResult parseExpenseAmount(
  String input,
  ExpenseCurrency currency, {
  bool allowZero = false,
}) => _parse(input, currency.exponent, allowZero: allowZero);

/// Parses an amount typed in **tomans** (1 toman = 10 rials) into minor
/// units of IRR: toman × 1000. Up to three decimals are exact — one
/// thousandth of a toman is the dinar — and more is refused, not
/// rounded.
ExpenseAmountResult parseTomanAmount(String input, {bool allowZero = false}) =>
    _parse(input, 3, allowZero: allowZero);

ExpenseAmountResult _parse(
  String input,
  int exponent, {
  bool allowZero = false,
}) {
  final text = LocalValues.ascii(input.trim());
  if (text.isEmpty) return (minor: null, error: ExpenseAmountError.empty);
  if (text.startsWith('-')) {
    return (minor: null, error: ExpenseAmountError.negative);
  }
  if (!RegExp(r'^([0-9]+([.,][0-9]*)?|[.,][0-9]+)$').hasMatch(text)) {
    return (minor: null, error: ExpenseAmountError.notANumber);
  }
  var separators = 0;
  for (final rune in text.runes) {
    if (rune == 0x2E || rune == 0x2C) {
      separators++;
    } else if (rune < 0x30 || rune > 0x39) {
      return (minor: null, error: ExpenseAmountError.notANumber);
    }
  }
  if (separators > 1) {
    return (minor: null, error: ExpenseAmountError.notANumber);
  }
  final normalized = text.replaceAll(',', '.');
  final parts = normalized.split('.');
  final whole = parts[0].isEmpty ? '0' : parts[0];
  final fraction = parts.length > 1 ? parts[1] : '';
  if (fraction.length > exponent) {
    return (minor: null, error: ExpenseAmountError.tooPrecise);
  }
  final digits = whole + fraction.padRight(exponent, '0');
  if (digits.length > 16) {
    return (minor: null, error: ExpenseAmountError.tooLarge);
  }
  final value = int.tryParse(digits) ?? 0;
  if (value == 0 && !allowZero) {
    return (minor: null, error: ExpenseAmountError.zero);
  }
  if (value > expenseAmountMax) {
    return (minor: null, error: ExpenseAmountError.tooLarge);
  }
  return (minor: value, error: null);
}

/// 1 toman = 10 rials = 1000 minor units of IRR.
const tomanMinorFactor = 1000;

/// Groups a plain digit string: `1250000` -> `1,250,000` (en) or
/// `۱٬۲۵۰٬۰۰۰` (fa). Purely textual, so both locales behave identically
/// under test — no NumberFormat.
String groupDigits(String digits, {required bool persian}) {
  final grouped = StringBuffer();
  var count = 0;
  for (var i = digits.length - 1; i >= 0; i--) {
    grouped.write(digits[i]);
    count++;
    if (count % 3 == 0 && i > 0) grouped.write(persian ? '٬' : ',');
  }
  final reversed = grouped.toString().split('').reversed.join('');
  return persian ? persianDigits(reversed) : reversed;
}

/// `123` -> `۱۲۳`. A local equivalent of the app-wide helper, because
/// the module API does not export it (see README Platform requests).
String persianDigits(String text) => text.replaceAllMapped(
  RegExp(r'[0-9]'),
  (m) => '۰۱۲۳۴۵۶۷۸۹'[int.parse(m[0]!)],
);

/// The number part of a money display, no code: `1,250,000`,
/// `12,000`, `12.500`, with `−` for negative. [minor] is in the minor
/// units of a currency with exponent [exponent].
String formatExpenseNumber(
  Object minor,
  int exponent, {
  required bool persian,
  bool signed = false,
}) {
  final exact = exactExpenseInteger(minor);
  final negative = exact.isNegative;
  var digits = exact.abs().toString();
  String text;
  if (exponent == 0) {
    text = groupDigits(digits, persian: persian);
  } else {
    while (digits.length <= exponent) {
      digits = '0$digits';
    }
    final whole = groupDigits(
      digits.substring(0, digits.length - exponent),
      persian: persian,
    );
    final fraction = digits
        .substring(digits.length - exponent)
        .replaceAll(RegExp(r'0+$'), '');
    text = fraction.isEmpty
        ? whole
        : '$whole.${persian ? persianDigits(fraction) : fraction}';
  }
  final sign = negative ? '−' : (signed ? '+' : '');
  return '$sign$text';
}

/// The toman number for an IRR amount, exact: 1000 minor units per
/// toman means three decimals always carry the value precisely.
String formatTomanNumber(int minor, {required bool persian}) =>
    formatExpenseNumber(minor, 3, persian: persian);

/// The text an editor field shows for [minor] units at [exponent]:
/// plain decimal in major units, no grouping, trailing zeros trimmed —
/// `1250.5` for 125050 minor at exponent 2. Round-trips through
/// [parseExpenseAmount].
String majorTextOfMinor(int minor, int exponent) {
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

/// The share of [part] in [total] as an integer 0–100, rounded half up
/// — integer math only, for chart labels and semantics.
BigInt exactExpenseInteger(Object value) =>
    value is BigInt ? value : BigInt.from(value as int);

int expensePercentOf(Object part, Object total) {
  final p = exactExpenseInteger(part), t = exactExpenseInteger(total);
  if (t <= BigInt.zero || p <= BigInt.zero) return 0;
  if (p >= t) return 100;
  return ((p * BigInt.from(100) + t ~/ BigInt.two) ~/ t).toInt().clamp(0, 100);
}

double expenseProgress(Object part, Object total) {
  final p = exactExpenseInteger(part), t = exactExpenseInteger(total);
  if (t <= BigInt.zero) return p > BigInt.zero ? 1 : 0;
  if (p >= t) return 1;
  final scaled = p * BigInt.from(10000) ~/ t;
  return scaled.toInt().clamp(0, 10000) / 10000;
}

bool expenseCurrencyRecordValid(String code, Map<String, Object?> body) {
  final currency = expenseCurrencyOf(code);
  if (currency == null ||
      (body['currency_code'] != null &&
          body['currency'] != null &&
          body['currency_code'] != body['currency'])) {
    return false;
  }
  final exponent = body['currency_exponent'] ?? body['exponent'];
  return exponent == null || exponent == currency.exponent;
}

Map<String, Object?> expenseCurrencyMetadata(String code) => {
  'currency_code': code,
  'currency_exponent': expenseCurrencyOf(code)?.exponent,
};

/// Whether [minor] is an amount the module will store.
bool expenseAmountInRange(int minor) =>
    minor >= expenseAmountMin && minor <= expenseAmountMax;
