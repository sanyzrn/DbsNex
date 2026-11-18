/// Money for Expenses: **whole rials**, in one field (`amountRial`), and the
/// unit a person says the number in — tomans or rials.
///
/// There is one currency in this module. The brief is an Iranian household
/// book: what was spent, in the money the person earns, without exchange
/// rates, without a second total per currency and without a currency picker
/// standing between them and the amount. `docs/18-module-kit.md`, rule 2,
/// asks for the same thing: stored once, as a whole number of rials, in a
/// field whose name ends in `Rial`.
///
/// The unit is how the amount is *said*, never how it is kept. A toman is ten
/// rials, so a toman amount may carry one decimal (a tenth of a toman is one
/// rial) and a rial amount carries none. Switching the unit re-expresses the
/// same money — it never changes it.
library;

import '../module_api.dart' show nexDigits;

/// How a person says an amount.
enum ExpenseUnit {
  rial,
  toman;

  String get key => this == toman ? 'toman' : 'rial';

  /// A missing or malformed choice reads as toman, the module's default: the
  /// same answer a fresh installation gives, and how people price things.
  static ExpenseUnit fromKey(Object? raw) =>
      raw == 'rial' ? ExpenseUnit.rial : ExpenseUnit.toman;

  /// Rials in one of this unit. A toman is ten rials.
  int get rialsPerUnit => this == toman ? 10 : 1;

  /// Decimals the unit is said with: a tenth of a toman is one rial, and
  /// there is nothing smaller than a rial.
  int get decimals => this == toman ? 1 : 0;
}

/// Bounds every amount lives inside: 1e15 rials is a thousand trillion, well
/// past any household figure and far below the point where sums would need
/// more than 64 bits.
const expenseAmountMax = 1000000000000000;
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

/// A parsed amount: [rials] when [error] is null.
typedef ExpenseAmountResult = ({int? rials, ExpenseAmountError? error});

/// Parses what a person typed, in [unit], into **whole rials**.
///
/// * Latin, Persian and Arabic-Indic digits.
/// * Grouping separators (`,` and `٬`) and spaces are layout, not value.
/// * At most one decimal separator (`.` or `٫`), and at most the unit's own
///   decimals: money is never silently rounded on the way in.
/// * No signs, letters or scientific notation.
ExpenseAmountResult parseExpenseAmount(
  String input,
  ExpenseUnit unit, {
  bool allowZero = false,
}) {
  final text = _ascii(input).trim();
  if (text.isEmpty) return (rials: null, error: ExpenseAmountError.empty);
  if (text.startsWith('-')) {
    return (rials: null, error: ExpenseAmountError.negative);
  }
  final cleaned = text
      .replaceAll(',', '')
      .replaceAll('٬', '')
      .replaceAll(' ', '')
      .replaceAll('\u200c', '');
  if (!RegExp(r'^([0-9]+([.٫][0-9]*)?|[.٫][0-9]+)$').hasMatch(cleaned)) {
    return (rials: null, error: ExpenseAmountError.notANumber);
  }
  final parts = cleaned.split(RegExp(r'[.٫]'));
  if (parts.length > 2) {
    return (rials: null, error: ExpenseAmountError.notANumber);
  }
  final whole = parts[0].isEmpty ? '0' : parts[0];
  var fraction = parts.length > 1 ? parts[1] : '';
  if (fraction.length > unit.decimals) {
    // «1.50» tomans is «1.5»: zeros past the unit's precision ask for no
    // precision at all, and are dropped; a real digit there is refused.
    final excess = fraction.substring(unit.decimals);
    if (excess.replaceAll(RegExp(r'0+$'), '').isEmpty) {
      fraction = fraction.substring(0, unit.decimals);
    } else {
      return (rials: null, error: ExpenseAmountError.tooPrecise);
    }
  }
  final wholeValue = BigInt.tryParse(whole);
  if (wholeValue == null) {
    return (rials: null, error: ExpenseAmountError.notANumber);
  }
  final fractionValue = fraction.isEmpty ? BigInt.zero : BigInt.parse(fraction);
  final rials = wholeValue * BigInt.from(unit.rialsPerUnit) + fractionValue;
  if (rials > BigInt.from(expenseAmountMax)) {
    return (rials: null, error: ExpenseAmountError.tooLarge);
  }
  if (rials == BigInt.zero && !allowZero) {
    return (rials: null, error: ExpenseAmountError.zero);
  }
  return (rials: rials.toInt(), error: null);
}

String _ascii(String text) => text
    .replaceAllMapped(RegExp(r'[۰-۹٠-٩]'), (m) {
      final code = m[0]!.codeUnitAt(0);
      return '${code >= 0x6f0 ? code - 0x6f0 : code - 0x660}';
    })
    .replaceAll('−', '-')
    .replaceAll('٫', '.')
    .replaceAll('٬', ',');

/// Groups a whole number: `1250000` -> `1,250,000` (en) or
/// `۱٬۲۵۰٬۰۰۰` (fa). Purely textual, so both locales behave identically
/// under test — no `NumberFormat`.
String groupDigits(int value, {required bool persian}) {
  final digits = value.abs().toString();
  final grouped = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) {
      grouped.write(persian ? '٬' : ',');
    }
    grouped.write(digits[i]);
  }
  final text = grouped.toString();
  final signed = value < 0 ? '−$text' : text;
  return persian ? persianDigits(signed) : signed;
}

/// Persian digits for a number or word — the module's local wrapper on the
/// app-wide helper, as the module API exports it.
String persianDigits(String text) => nexDigits(text, persian: true);

/// The name of the unit, said as a person says it.
String expenseUnitWord(
  ExpenseUnit unit, {
  required bool persian,
  bool plural = true,
}) {
  if (persian) return unit == ExpenseUnit.toman ? 'تومان' : 'ریال';
  if (unit == ExpenseUnit.toman) return plural ? 'tomans' : 'toman';
  return plural ? 'rials' : 'rial';
}

/// The number of [rials] in [unit], grouped, with no unit word and no
/// decimals that carry nothing: `1,250,000`, `12,000`, `12.5`.
String formatExpenseNumber(
  int rials,
  ExpenseUnit unit, {
  required bool persian,
  bool signed = false,
}) {
  final value = rials.abs();
  final whole = value ~/ unit.rialsPerUnit;
  final rest = value % unit.rialsPerUnit;
  final number = groupDigits(whole, persian: persian);
  final fraction = rest == 0
      ? ''
      : '${persian ? '٫' : '.'}${persian ? persianDigits('$rest') : rest}';
  final sign = rials < 0 ? '−' : (signed ? '+' : '');
  return '$sign$number$fraction';
}

/// The amount as a person reads it: `۱٬۲۵۰٬۰۰۰ تومان`, `12,500 tomans`,
/// `۳۵۰٬۰۰۰ ریال`.
String formatExpenseAmount(
  int rials,
  ExpenseUnit unit, {
  required bool persian,
  bool signed = false,
}) =>
    '${formatExpenseNumber(rials, unit, persian: persian, signed: signed)} '
    '${expenseUnitWord(unit, persian: persian)}';

/// The text an amount field shows for [rials] in [unit]: plain, without
/// grouping (the field groups as it is typed), and with no trailing zero.
String expenseAmountInput(int rials, ExpenseUnit unit) {
  final value = rials.abs();
  final whole = value ~/ unit.rialsPerUnit;
  final rest = value % unit.rialsPerUnit;
  final sign = rials < 0 ? '-' : '';
  return rest == 0 ? '$sign$whole' : '$sign$whole.$rest';
}

/// The share of [part] in [total] as an integer 0–100, rounded half up —
/// integer math only, for chart labels and semantics.
int expensePercentOf(Object part, Object total) {
  final p = _exact(part), t = _exact(total);
  if (t <= BigInt.zero || p <= BigInt.zero) return 0;
  if (p >= t) return 100;
  return ((p * BigInt.from(100) + t ~/ BigInt.two) ~/ t).toInt().clamp(0, 100);
}

/// 0–1 progress for a calm bar, integer math, never outside the bar.
double expenseProgress(Object part, Object total) {
  final p = _exact(part), t = _exact(total);
  if (t <= BigInt.zero) return p > BigInt.zero ? 1 : 0;
  if (p >= t) return 1;
  return (p * BigInt.from(10000) ~/ t).toInt().clamp(0, 10000) / 10000;
}

BigInt _exact(Object value) =>
    value is BigInt ? value : BigInt.from(value as int);

/// Whether [rials] is an amount a new record may store.
bool expenseAmountInRange(int rials) =>
    rials >= expenseAmountMin && rials <= expenseAmountMax;
