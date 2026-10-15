/// The records the Expenses module keeps, and how they are read back.
///
/// Everything is JSON in the module's own `NexModuleStore`, one kind per
/// shape, every timestamp ISO 8601. Readers are defensive: a record with
/// a missing or malformed field is kept — visible, fixable, deletable —
/// but never silently counted in totals. See the README's Records
/// section for the schemas and the migration rules.
library;

import 'money.dart';
import 'local_values.dart';

/// A payment the person chose to write down. `expense` or `income`.
///
/// This is a voluntary manual book: nothing syncs, nothing is inferred.
/// A transfer is not modelled in v1 (see README Decisions), and a loan
/// repayment tracked elsewhere never becomes an expense here, because
/// the module cannot read other modules' data.
class ExpenseTx {
  ExpenseTx({
    required this.id,
    required this.type,
    required this.amount,
    required this.currency,
    required this.date,
    this.categoryId,
    this.note,
    this.merchant,
    this.account,
    this.valid = true,
    this.source,
  });

  /// `expense` or `income`.
  final String type;

  bool get isIncome => type == 'income';
  bool get isExpense => type != 'income';

  /// Integer minor units of [currency] — see `money.dart`.
  final int amount;

  final String currency;

  /// Local calendar date+time the person says it happened. Stored as
  /// ISO 8601; month buckets use the local calendar, not UTC.
  final DateTime date;

  final String? categoryId;
  final String? note;
  final String? merchant;

  /// A plain label like "cash" or "main card" — text only, never bank
  /// credentials.
  final String? account;

  /// The record's id within kind `tx`.
  final String id;

  /// False when the stored body was malformed: shown in the list as an
  /// incomplete record, excluded from every total.
  final bool valid;
  final Map<String, Object?>? source;

  Map<String, Object?> toBody() => {
    'type': type,
    'amount': amount,
    'currency': currency,
    ...expenseCurrencyMetadata(currency),
    'date': date.toIso8601String(),
    if (categoryId != null) 'category': categoryId,
    if (note != null && note!.isNotEmpty) 'note': note,
    if (merchant != null && merchant!.isNotEmpty) 'merchant': merchant,
    if (account != null && account!.isNotEmpty) 'account': account,
    'schema': 2,
  };

  /// Reads a stored body. A bad amount, type or date makes an
  /// incomplete record (valid: false) rather than a crash or a silent
  /// drop — the person can still open, fix or delete it.
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
    final rawAmount = body['amount'];
    var amount = 0;
    if (rawAmount is int && rawAmount >= 0 && rawAmount <= expenseAmountMax) {
      amount = rawAmount;
    } else {
      valid = false;
    }
    final currency =
        _stringOf(body, 'currency_code') ?? _stringOf(body, 'currency') ?? '';
    if (!expenseCurrencyRecordValid(currency, body)) valid = false;
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
      amount: amount,
      currency: currency,
      date: date,
      categoryId: _stringOf(body, 'category'),
      note: _stringOf(body, 'note'),
      merchant: _stringOf(body, 'merchant'),
      account: _stringOf(body, 'account'),
      valid: valid,
      source: Map.of(body),
    );
  }
}

/// A category the person added. The eleven defaults — food, transport
/// and so on — are not records at all: they are synthesized from the
/// module's strings (`cat-food`, `cat-transport`, …) so their words
/// live where every word lives, and deleting the module's data cannot
/// lose them. Only a person's own categories are stored, under kind
/// `cat`, shown in whichever language the app is in.
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

/// The default categories' stable ids, in display order — their labels
/// come from the module's strings under the same key.
const defaultExpenseCategoryIds = <String>[
  'cat-food',
  'cat-transport',
  'cat-home',
  'cat-bills',
  'cat-health',
  'cat-fun',
  'cat-clothes',
  'cat-gifts',
  'cat-education',
  'cat-salary',
  'cat-other',
];

/// A manual monthly budget: one category in one currency for one month,
/// or the overall monthly limit when [categoryId] is null.
///
/// Unspent budget does **not** roll over, and changing a budget never
/// touches transactions. Totals are per currency, so a budget belongs
/// to one currency too.
class ExpenseBudget {
  const ExpenseBudget({
    required this.month,
    required this.currency,
    required this.amount,
    this.categoryId,
  });

  /// `YYYY-MM`, local calendar.
  final String month;

  /// Null: the overall monthly limit.
  final String? categoryId;

  final String currency;

  /// Integer minor units.
  final int amount;

  String get id => budgetId(month, categoryId, currency);

  Map<String, Object?> toBody() => {
    'month': month,
    'currency': currency,
    ...expenseCurrencyMetadata(currency),
    'amount': amount,
    if (categoryId != null) 'category': categoryId,
    'schema': 2,
  };

  static ExpenseBudget? fromBody(String id, Map<String, Object?> body) {
    final month = body['month'];
    final currency = body['currency_code'] ?? body['currency'];
    final amount = body['amount'];
    if (month is! String ||
        currency is! String ||
        amount is! int ||
        amount < 0 ||
        amount > expenseAmountMax ||
        !expenseCurrencyRecordValid(currency, body)) {
      return null;
    }
    if (!isValidMonthKey(month)) return null;
    final category = body['category'];
    return ExpenseBudget(
      month: month,
      currency: currency,
      amount: amount,
      categoryId: category is String ? category : null,
    );
  }
}

/// The deterministic record id for a budget — one record per
/// month × category (or overall) × currency.
String budgetId(String month, String? categoryId, String currency) =>
    'budget-$month-${categoryId ?? 'all'}-$currency';

/// A reusable entry the person confirms — never a background charge.
class ExpenseTemplate {
  const ExpenseTemplate({
    required this.id,
    required this.label,
    required this.type,
    required this.amount,
    required this.currency,
    this.categoryId,
    this.note,
    this.merchant,
  });

  final String id;
  final String label;
  final String type;
  final int amount;
  final String currency;
  final String? categoryId;
  final String? note;
  final String? merchant;

  Map<String, Object?> toBody() => {
    'label': label,
    'type': type,
    'amount': amount,
    'currency': currency,
    ...expenseCurrencyMetadata(currency),
    if (categoryId != null) 'category': categoryId,
    if (note != null && note!.isNotEmpty) 'note': note,
    if (merchant != null && merchant!.isNotEmpty) 'merchant': merchant,
    'schema': 2,
  };

  static ExpenseTemplate? fromBody(String id, Map<String, Object?> body) {
    final label = body['label'];
    final type = body['type'];
    final amount = body['amount'];
    final currency = body['currency_code'] ?? body['currency'];
    if (label is! String ||
        label.trim().isEmpty ||
        type is! String ||
        (type != 'expense' && type != 'income') ||
        amount is! int ||
        amount <= 0 ||
        currency is! String ||
        amount > expenseAmountMax ||
        !expenseCurrencyRecordValid(currency, body)) {
      return null;
    }
    return ExpenseTemplate(
      id: id,
      label: label,
      type: type,
      amount: amount,
      currency: currency,
      categoryId: _stringOf(body, 'category'),
      note: _stringOf(body, 'note'),
      merchant: _stringOf(body, 'merchant'),
    );
  }
}

/// `YYYY-MM` for a local [date] — the bucket every aggregate is keyed
/// by. Local, not UTC: a payment at 23:30 on the 31st belongs to that
/// month for the person who made it.
String monthKeyOf(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}';

/// The first moment of a month key.
DateTime monthStartOf(String key) {
  final parts = key.split('-');
  return DateTime(int.parse(parts[0]), int.parse(parts[1]));
}

/// Whether [key] is a real month key.
bool isValidMonthKey(String key) =>
    RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(key) &&
    int.parse(key.substring(0, 4)) > 0;

/// The month key after [key] — January rolls to the next year, and the
/// year rolls at 9999 to nothing.
String? nextMonthKey(String key) {
  if (!isValidMonthKey(key)) return null;
  final start = monthStartOf(key);
  // Only December of the final representable year has no next month.
  if (start.year == 9999 && start.month == 12) return null;
  final next = DateTime(start.year, start.month + 1);
  return monthKeyOf(next);
}

/// The month key before [key] — December rolls back a year.
String? previousMonthKey(String key) {
  if (!isValidMonthKey(key)) return null;
  final start = monthStartOf(key);
  // Only January of year 1 has no previous month.
  if (start.year == 1 && start.month == 1) return null;
  final previous = DateTime(start.year, start.month - 1);
  return monthKeyOf(previous);
}

/// A string field of a body, or null — promotion-safe on every reader.
String? _stringOf(Map<String, Object?> body, String key) {
  final value = body[key];
  return value is String ? value : null;
}
