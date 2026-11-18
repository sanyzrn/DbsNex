/// The records the Expenses module keeps, and how they are read back.
///
/// Everything is JSON in the module's own `NexModuleStore`, one kind per
/// shape, every timestamp ISO 8601. Amounts are whole rials in `amountRial`
/// (`docs/18-module-kit.md`, rule 2). Readers are defensive: a record with a
/// missing or malformed field is kept — visible, fixable, deletable — but
/// never silently counted in totals. Records written by the 2.1.x versions
/// (a currency code, an amount in that currency's minor units) still open:
/// a whole-rial amount in the rial is read exactly, and anything else is
/// shown as an incomplete record for the person to repair. See the README's
/// Records section.
library;

import 'package:nex_client/modules/module_api.dart' show NexModuleMonth;

import 'local_values.dart';
import 'money.dart';

/// A payment the person chose to write down. `expense` or `income`.
///
/// This is a voluntary manual book: nothing syncs, nothing is inferred. A
/// loan repayment tracked elsewhere never becomes an expense here, because
/// the module cannot read other modules' data.
class ExpenseTx {
  ExpenseTx({
    required this.id,
    required this.type,
    required this.amountRial,
    required this.date,
    this.categoryId,
    this.note,
    this.merchant,
    this.account,
    this.templateId,
    this.period,
    this.valid = true,
    this.source,
  });

  /// `expense` or `income`.
  final String type;

  bool get isIncome => type == 'income';
  bool get isExpense => type != 'income';

  /// Whole rials — never a fraction, never tomans, never a currency's minor
  /// unit. See `money.dart`.
  final int amountRial;

  /// Local calendar date+time the person says it happened. Stored as
  /// ISO 8601; month buckets use the calendar the person reads.
  final DateTime date;

  final String? categoryId;
  final String? note;
  final String? merchant;

  /// A plain label like "cash" or "main card" — text only, never bank
  /// credentials.
  final String? account;

  /// The recurring template this payment came from, when it came from one.
  final String? templateId;

  /// The first day of the month this payment settles, for a payment logged
  /// from a recurring template — the one thing that tells «this month's rent
  /// is already written down» from «it is not».
  final String? period;

  /// The record's id within kind `tx`.
  final String id;

  /// False when the stored body was malformed: shown in the list as an
  /// incomplete record, excluded from every total.
  final bool valid;

  /// The body as it was read, so a save can carry fields this version does
  /// not know (`docs/18-module-kit.md`, rule 5).
  final Map<String, Object?>? source;

  Map<String, Object?> toBody() => {
    'type': type,
    'amountRial': amountRial,
    'date': date.toIso8601String(),
    if (categoryId != null) 'category': categoryId,
    if (note != null && note!.isNotEmpty) 'note': note,
    if (merchant != null && merchant!.isNotEmpty) 'merchant': merchant,
    if (account != null && account!.isNotEmpty) 'account': account,
    if (templateId != null) 'templateId': templateId,
    if (period != null) 'period': period,
    'schema': 3,
  };

  /// Reads a stored body. A bad type, amount or date makes an incomplete
  /// record (valid: false) rather than a crash or a silent drop — the person
  /// can still open, fix or delete it.
  static ExpenseTx fromBody(String id, Map<String, Object?> body) {
    var valid = true;
    final type = switch (body['type']) {
      'expense' => 'expense',
      'income' => 'income',
      _ => 'expense',
    };
    if (body['type'] != 'expense' && body['type'] != 'income') {
      valid = false;
    }
    final stored = body['amountRial'];
    var amountRial = 0;
    if (stored is int && stored >= 0 && stored <= expenseAmountMax) {
      amountRial = stored;
    } else {
      final legacy = legacyAmountRial(body);
      if (legacy != null) {
        amountRial = legacy;
      } else {
        valid = false;
      }
    }
    DateTime? date;
    final rawDate = body['date'];
    if (rawDate is String) {
      date = LocalValues.stamp(rawDate)?.toLocal();
    }
    if (date == null) {
      valid = false;
      date = DateTime.fromMillisecondsSinceEpoch(0);
    }
    return ExpenseTx(
      id: id,
      type: type,
      amountRial: amountRial,
      date: date,
      categoryId: _stringOf(body, 'category'),
      note: _stringOf(body, 'note'),
      merchant: _stringOf(body, 'merchant'),
      account: _stringOf(body, 'account'),
      templateId: _stringOf(body, 'templateId'),
      period: _stringOf(body, 'period'),
      valid: valid,
      source: Map.of(body),
    );
  }
}

/// A whole-rial amount from a pre-3 body: minor units of a currency.
///
/// Only the rial is read, and only when the stored minor units are exactly
/// whole rials (the rial's ISO exponent is 2, so 100 minor units are one
/// rial). Nothing is rescaled or invented: a record in another currency, or
/// one holding a fraction of a rial, becomes an incomplete record for the
/// person to repair.
int? legacyAmountRial(Map<String, Object?> body) {
  final raw = body['amount'];
  if (raw is! int || raw < 0) return null;
  final code = body['currency_code'] ?? body['currency'] ?? 'IRR';
  if (code != 'IRR') return null;
  final exponent = body['currency_exponent'] ?? body['exponent'];
  if (exponent != null && exponent != 2) return null;
  if (raw % 100 != 0) return null;
  final rials = raw ~/ 100;
  return rials <= expenseAmountMax ? rials : null;
}

/// A category the person added. The built-in ones — groceries, rent and so
/// on — are not records at all: they are synthesized from the module's
/// strings (`cat-groceries`, `cat-rent`, …) so their words live where every
/// word lives, and deleting the module's data cannot lose them. Only a
/// person's own categories are stored, under kind `cat`, shown in whichever
/// language the app is in.
class ExpenseCategory {
  const ExpenseCategory({required this.id, required this.label});

  final String id;

  /// The name the person typed, used in both languages.
  final String label;

  static ExpenseCategory? fromBody(String id, Map<String, Object?> body) {
    final label = body['label'];
    if (label is! String || label.trim().isEmpty) return null;
    return ExpenseCategory(id: id, label: label.trim());
  }

  Map<String, Object?> toBody() => {'label': label, 'schema': 1};
}

/// The built-in categories' stable ids, in display order — their labels come
/// from the module's strings under the same key. Groceries, rent and
/// children lead, because the brief's household is an Iranian one; the older
/// ids stay, so a payment written with one keeps its category.
const defaultExpenseCategoryIds = <String>[
  'cat-groceries',
  'cat-food',
  'cat-rent',
  'cat-home',
  'cat-bills',
  'cat-transport',
  'cat-health',
  'cat-children',
  'cat-education',
  'cat-clothes',
  'cat-gifts',
  'cat-fun',
  'cat-salary',
  'cat-other',
];

/// A manual monthly budget: one category for one month, or the overall
/// monthly limit when [categoryId] is null.
///
/// A budget belongs to the month a person reads — a Jalali month in Persian,
/// a Gregorian one in English — so it is keyed by that month's **first civil
/// day** ([start]), not by a month name or a calendar of its own. Unspent
/// budget does **not** roll over, and changing a budget never touches
/// payments.
class ExpenseBudget {
  const ExpenseBudget({
    required this.start,
    required this.amountRial,
    this.categoryId,
  });

  /// The month's first civil day, `YYYY-MM-DD`.
  final String start;

  /// Null: the overall monthly limit.
  final String? categoryId;

  /// Whole rials.
  final int amountRial;

  String get id => budgetId(start, categoryId);

  Map<String, Object?> toBody() => {
    'start': start,
    'amountRial': amountRial,
    if (categoryId != null) 'category': categoryId,
    'schema': 3,
  };

  static ExpenseBudget? fromBody(String id, Map<String, Object?> body) {
    var start = _isoDayOf(body['start']);
    if (start == null) {
      // A 2.1.x budget keyed by its Gregorian month.
      final month = body['month'];
      if (month is String && isValidMonthKey(month)) start = '$month-01';
    }
    if (start == null) return null;
    final stored = body['amountRial'];
    final amount = stored is int
        ? (stored >= 0 && stored <= expenseAmountMax ? stored : null)
        : legacyAmountRial(body);
    if (amount == null) return null;
    if (body['currency'] is String && body['currency'] != 'IRR') return null;
    final category = body['category'];
    return ExpenseBudget(
      start: start,
      amountRial: amount,
      categoryId: category is String ? category : null,
    );
  }
}

/// The deterministic record id for a budget — one record per month ×
/// category (or overall).
String budgetId(String start, String? categoryId) =>
    'budget-$start-${categoryId ?? 'all'}';

/// A reusable entry the person confirms — never a background charge.
///
/// A template with a [day] is a **recurring** payment: rent, the internet,
/// a subscription. It is offered on its day; it is never written by itself
/// (`docs/prompts/module-briefs/expenses.md`). The calendar the day belongs
/// to is kept with it, so «the 5th» means the 5th of the month the person
/// set it in, even if the app's calendar is changed later.
class ExpenseTemplate {
  const ExpenseTemplate({
    required this.id,
    required this.label,
    required this.type,
    required this.amountRial,
    this.categoryId,
    this.note,
    this.merchant,
    this.day,
    this.calendar,
  });

  final String id;
  final String label;
  final String type;

  /// Whole rials.
  final int amountRial;
  final String? categoryId;
  final String? note;
  final String? merchant;

  /// The day of the month it falls due, 1–31, or null for a plain template.
  final int? day;

  /// `jalali` or `gregorian`: which month [day] counts in.
  final String? calendar;

  bool get isRecurring => day != null;

  /// The calendar the recurring day is counted in.
  bool get solar => calendar == 'jalali';

  Map<String, Object?> toBody() => {
    'label': label,
    'type': type,
    'amountRial': amountRial,
    if (categoryId != null) 'category': categoryId,
    if (note != null && note!.isNotEmpty) 'note': note,
    if (merchant != null && merchant!.isNotEmpty) 'merchant': merchant,
    if (day != null) 'day': day,
    if (day != null) 'calendar': solar ? 'jalali' : 'gregorian',
    'schema': 3,
  };

  static ExpenseTemplate? fromBody(String id, Map<String, Object?> body) {
    final label = body['label'];
    final type = body['type'];
    if (label is! String ||
        label.trim().isEmpty ||
        type is! String ||
        (type != 'expense' && type != 'income')) {
      return null;
    }
    final stored = body['amountRial'];
    final amount = stored is int
        ? (stored > 0 && stored <= expenseAmountMax ? stored : null)
        : legacyAmountRial(body);
    if (amount == null) return null;
    if (body['currency'] is String && body['currency'] != 'IRR') return null;
    final rawDay = body['day'];
    final day = rawDay is int && rawDay >= 1 && rawDay <= 31 ? rawDay : null;
    return ExpenseTemplate(
      id: id,
      label: label.trim(),
      type: type,
      amountRial: amount,
      categoryId: _stringOf(body, 'category'),
      note: _stringOf(body, 'note'),
      merchant: _stringOf(body, 'merchant'),
      day: day,
      calendar: day == null
          ? null
          : (body['calendar'] == 'jalali' ? 'jalali' : 'gregorian'),
    );
  }
}

/// A civil day as `YYYY-MM-DD` — the storage form of a month's identity and
/// of a recurring payment's period. Civil, so it means the same day in every
/// calendar a person may read.
String isoDay(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// The first civil day of [month], as stored.
String monthStartIso(NexModuleMonth month) => isoDay(month.first);

/// The month [date] falls in, in the calendar [solar] picks.
NexModuleMonth expenseMonthOf(DateTime date, {required bool solar}) =>
    NexModuleMonth.of(date, solar: solar);

/// Whether [key] is a real `YYYY-MM` month key (a 2.1.x budget's form).
bool isValidMonthKey(String key) =>
    RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(key) &&
    int.parse(key.substring(0, 4)) > 0;

String? _isoDayOf(Object? raw) {
  if (raw is! String) return null;
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(raw);
  if (match == null) return null;
  final year = int.parse(match[1]!), month = int.parse(match[2]!);
  final day = int.parse(match[3]!);
  if (!LocalValues.realDay(year, month, day)) return null;
  return raw;
}

/// A string field of a body, or null — promotion-safe on every reader.
String? _stringOf(Map<String, Object?> body, String key) {
  final value = body[key];
  return value is String ? value : null;
}
