/// The Expenses module's arithmetic: every total, breakdown, budget
/// standing and filter is computed here, in whole rials and integers, from a
/// list of records — no storage, no Flutter, fully unit-testable.
///
/// Two invariants hold throughout:
///
/// * **Only whole rials, one book.** Every figure is rial; there is no
///   second currency and no exchange rate anywhere in this file.
/// * **Invalid records never count.** A malformed body is still listed so
///   the person can fix it, but it is excluded from totals.
library;

import 'package:nex_client/modules/module_api.dart'
    show NexModuleMonth, nexSearchFold;

import 'models.dart';
import 'money.dart';

/// What a month holds: spent, received, and what is left of the income.
class ExpenseTotals {
  const ExpenseTotals({required this.expense, required this.income});

  /// Whole rials.
  final BigInt expense;
  final BigInt income;

  BigInt get net => income - expense;

  /// What is left of the month's income after the month's spending. Only
  /// meaningful when something was entered as income; the screen says so.
  BigInt get left => net;

  bool get hasIncome => income > BigInt.zero;
}

/// Totals over [txs] — valid records only.
ExpenseTotals expenseTotals(Iterable<ExpenseTx> txs) {
  var expense = BigInt.zero, income = BigInt.zero;
  for (final tx in txs) {
    if (!validExpenseTx(tx)) continue;
    if (tx.isIncome) {
      income += BigInt.from(tx.amountRial);
    } else {
      expense += BigInt.from(tx.amountRial);
    }
  }
  return ExpenseTotals(expense: expense, income: income);
}

/// How far apart two spending totals are, as a whole percent, rounded half
/// up — or null when there is nothing honest to compare against.
int? expensePercentChange(BigInt current, BigInt previous) {
  if (previous <= BigInt.zero) return null;
  final diff = current - previous;
  if (diff == BigInt.zero) return 0;
  return ((diff.abs() * BigInt.from(200) + previous) ~/ (previous * BigInt.two))
      .toInt();
}

/// `-1`, `0` or `1`: whether [current] is less than, equal to or more than
/// [previous]. Only the words for it come from the module's strings.
int expenseDirection(BigInt current, BigInt previous) =>
    current == previous ? 0 : (current > previous ? 1 : -1);

/// A month against the month before it, for the whole book.
class ExpenseMonthChange {
  const ExpenseMonthChange({
    required this.previous,
    required this.current,
    required this.percent,
    required this.direction,
  });

  final BigInt previous;
  final BigInt current;

  /// Null when the month before had no spending: a percentage of nothing is
  /// not a number, and the screen then says nothing about it.
  final int? percent;
  final int direction;
}

/// Spending in [month] against the month before, in the same calendar.
ExpenseMonthChange? expenseMonthChange(
  Iterable<ExpenseTx> txs, {
  required NexModuleMonth month,
  required bool solar,
}) {
  final previousMonth = month.shift(-1);
  final previous = expenseTotals(txsInMonth(txs, previousMonth, solar: solar))
      .expense;
  if (previous <= BigInt.zero) return null;
  final current = expenseTotals(txsInMonth(txs, month, solar: solar)).expense;
  return ExpenseMonthChange(
    previous: previous,
    current: current,
    percent: expensePercentChange(current, previous),
    direction: expenseDirection(current, previous),
  );
}

/// One category's slice of a month's spending, with its own change against
/// the month before — the «groceries +18%» the brief asks for.
class ExpenseCategorySlice {
  const ExpenseCategorySlice({
    required this.categoryId,
    required this.total,
    required this.previous,
    required this.percent,
    required this.direction,
  });

  final String categoryId;
  final BigInt total;
  final BigInt previous;

  /// Null when this category had no spending the month before.
  final int? percent;
  final int direction;
}

/// Spending per category in [month], largest first — with each category's
/// own previous-month total. Records with no category land in `cat-other`.
List<ExpenseCategorySlice> expenseCategoryBreakdown(
  Iterable<ExpenseTx> txs, {
  required NexModuleMonth month,
  required bool solar,
}) {
  final current = _categoryTotals(txsInMonth(txs, month, solar: solar));
  final previous = _categoryTotals(
    txsInMonth(txs, month.shift(-1), solar: solar),
  );
  final slices = [
    for (final entry in current.entries)
      ExpenseCategorySlice(
        categoryId: entry.key,
        total: entry.value,
        previous: previous[entry.key] ?? BigInt.zero,
        percent: expensePercentChange(
          entry.value,
          previous[entry.key] ?? BigInt.zero,
        ),
        direction: expenseDirection(
          entry.value,
          previous[entry.key] ?? BigInt.zero,
        ),
      ),
  ];
  slices.sort((a, b) {
    final byTotal = b.total.compareTo(a.total);
    return byTotal != 0 ? byTotal : a.categoryId.compareTo(b.categoryId);
  });
  return slices;
}

Map<String, BigInt> _categoryTotals(Iterable<ExpenseTx> txs) {
  final totals = <String, BigInt>{};
  for (final tx in txs) {
    if (!validExpenseTx(tx) || tx.isIncome) continue;
    final key = tx.categoryId ?? 'cat-other';
    totals[key] = (totals[key] ?? BigInt.zero) + BigInt.from(tx.amountRial);
  }
  return totals;
}

/// A budget's standing against the payments of its own month: the
/// arithmetic is shown, never just the verdict.
class ExpenseBudgetStatus {
  ExpenseBudgetStatus({required this.budget, required this.spent});

  final ExpenseBudget budget;

  /// Expenses of this budget's month and category (all of them when the
  /// budget is the overall limit).
  final BigInt spent;

  BigInt get left => BigInt.from(budget.amountRial) - spent;

  /// Positive when over. "Over" is stated plainly, never alarmingly.
  BigInt get overage => spent - BigInt.from(budget.amountRial);

  bool get isOver => overage > BigInt.zero;

  /// 0–1 progress for the calm bar; 1 when there is no budget amount.
  double get progress => expenseProgress(spent, budget.amountRial);
}

/// The status of every budget belonging to [month], against [txs]. A budget
/// is keyed by its month's first civil day, so the month a person reads is
/// the month it counts.
List<ExpenseBudgetStatus> expenseBudgetStatuses(
  Iterable<ExpenseBudget> budgets,
  NexModuleMonth month,
  Iterable<ExpenseTx> txs,
) {
  final start = monthStartIso(month);
  final byCategory = <String, BigInt>{};
  var all = BigInt.zero;
  for (final tx in txs) {
    if (!validExpenseTx(tx) || tx.isIncome) continue;
    if (!_inMonth(tx.date, month)) continue;
    final amount = BigInt.from(tx.amountRial);
    final key = tx.categoryId ?? 'cat-other';
    byCategory[key] = (byCategory[key] ?? BigInt.zero) + amount;
    all += amount;
  }
  return [
    for (final budget in budgets.where((b) => b.start == start))
      ExpenseBudgetStatus(
        budget: budget,
        spent: budget.categoryId == null
            ? all
            : (byCategory[budget.categoryId!] ?? BigInt.zero),
      ),
  ]..sort((a, b) => a.budget.id.compareTo(b.budget.id));
}

/// Payments in [month] (in the calendar [solar] picks), or all of them when
/// [month] is null.
Iterable<ExpenseTx> txsInMonth(
  Iterable<ExpenseTx> txs,
  NexModuleMonth? month, {
  required bool solar,
}) => month == null ? txs : txs.where((tx) => _inMonth(tx.date, month));

bool _inMonth(DateTime day, NexModuleMonth month) =>
    !day.isBefore(month.first) && day.isBefore(month.shift(1).first);

/// Use the same spelling rules as note search. Lowercase here because
/// expense fields are matched directly rather than through SQLite FTS.
String foldExpenseSearch(String text) => nexSearchFold(text).toLowerCase();

/// Text search across note, merchant, account and the category's own name,
/// plus an optional category and amount range — the three ways the brief
/// names for finding a payment.
Iterable<ExpenseTx> filterTxs(
  Iterable<ExpenseTx> txs, {
  String query = '',
  String? categoryId,
  int? minRial,
  int? maxRial,
  required String Function(String categoryId) categoryName,
}) {
  final q = foldExpenseSearch(query.trim());
  return txs.where((tx) {
    if (categoryId != null && (tx.categoryId ?? 'cat-other') != categoryId) {
      return false;
    }
    if (minRial != null && tx.amountRial < minRial) return false;
    if (maxRial != null && tx.amountRial > maxRial) return false;
    if (q.isEmpty) return true;
    final category = tx.categoryId == null ? '' : categoryName(tx.categoryId!);
    return foldExpenseSearch(tx.note ?? '').contains(q) ||
        foldExpenseSearch(tx.merchant ?? '').contains(q) ||
        foldExpenseSearch(tx.account ?? '').contains(q) ||
        foldExpenseSearch(category).contains(q);
  });
}

/// One day of records, newest day first: the day's own spending and income,
/// and its records newest first. `day` is null for a record whose date could
/// not be read, which is kept visible in its own group instead of being
/// pushed into a real day's total.
class ExpenseDayGroup {
  const ExpenseDayGroup({
    required this.day,
    required this.txs,
    required this.totals,
  });

  final DateTime? day;
  final List<ExpenseTx> txs;
  final ExpenseTotals totals;
}

/// [txs] grouped by the civil day the person reads, newest first, one group
/// per day, with the unreadable ones last.
List<ExpenseDayGroup> expenseDayGroups(Iterable<ExpenseTx> txs) {
  final byDay = <String, List<ExpenseTx>>{};
  final undated = <ExpenseTx>[];
  for (final tx in txs) {
    if (tx.date.year <= 1970) {
      undated.add(tx);
      continue;
    }
    byDay.putIfAbsent(isoDay(tx.date), () => []).add(tx);
  }
  final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
  return [
    for (final key in days)
      ExpenseDayGroup(
        day: DateTime(
          int.parse(key.substring(0, 4)),
          int.parse(key.substring(5, 7)),
          int.parse(key.substring(8, 10)),
        ),
        txs: sortedByDate(byDay[key]!),
        totals: expenseTotals(byDay[key]!),
      ),
    if (undated.isNotEmpty)
      ExpenseDayGroup(
        day: null,
        txs: sortedByDate(undated),
        totals: expenseTotals(undated),
      ),
  ];
}

/// A month of the all-time view: the month a person reads, what it cost and
/// what came in, and its days. `month` is null for the records whose date
/// could not be read.
class ExpenseMonthSection {
  const ExpenseMonthSection({
    required this.month,
    required this.totals,
    required this.days,
  });

  final NexModuleMonth? month;
  final ExpenseTotals totals;
  final List<ExpenseDayGroup> days;
}

/// [txs] grouped by the month a person reads, newest month first, for the
/// all-time view — a year of records is then a handful of months, not one
/// endless list.
List<ExpenseMonthSection> expenseMonthSections(
  Iterable<ExpenseTx> txs, {
  required bool solar,
}) {
  final byMonth = <String, List<ExpenseTx>>{};
  final months = <String, NexModuleMonth>{};
  final undated = <ExpenseTx>[];
  for (final tx in txs) {
    if (tx.date.year <= 1970) {
      undated.add(tx);
      continue;
    }
    final month = NexModuleMonth.of(tx.date, solar: solar);
    final key = monthStartIso(month);
    byMonth.putIfAbsent(key, () => []).add(tx);
    months[key] = month;
  }
  final keys = byMonth.keys.toList()..sort((a, b) => b.compareTo(a));
  return [
    for (final key in keys)
      ExpenseMonthSection(
        month: months[key],
        totals: expenseTotals(byMonth[key]!),
        days: expenseDayGroups(byMonth[key]!),
      ),
    if (undated.isNotEmpty)
      ExpenseMonthSection(
        month: null,
        totals: expenseTotals(undated),
        days: expenseDayGroups(undated),
      ),
  ];
}

/// One month of the trend: the month and what it cost.
class ExpenseTrendPoint {
  const ExpenseTrendPoint({required this.month, required this.spent});

  final NexModuleMonth month;
  final BigInt spent;
}

/// The last [count] months ending at [month], oldest first, with each
/// month's spending — the shape of the year, in one row. A month with
/// nothing entered is a real zero, not a gap.
List<ExpenseTrendPoint> expenseTrend(
  Iterable<ExpenseTx> txs, {
  required NexModuleMonth month,
  required bool solar,
  int count = 6,
}) {
  final buckets = <String, BigInt>{};
  for (final tx in txs) {
    if (!validExpenseTx(tx) || tx.isIncome || tx.date.year <= 1970) continue;
    final key = monthStartIso(NexModuleMonth.of(tx.date, solar: solar));
    buckets[key] = (buckets[key] ?? BigInt.zero) + BigInt.from(tx.amountRial);
  }
  final span = count < 2 ? 2 : count;
  return [
    for (var i = span - 1; i >= 0; i--)
      ExpenseTrendPoint(
        month: month.shift(-i),
        spent: buckets[monthStartIso(month.shift(-i))] ?? BigInt.zero,
      ),
  ];
}

/// Newest first by date; ids break ties so the order is stable.
List<ExpenseTx> sortedByDate(Iterable<ExpenseTx> txs) {
  final list = txs.toList();
  list.sort((a, b) {
    final byDate = b.date.compareTo(a.date);
    if (byDate != 0) return byDate;
    return b.id.compareTo(a.id);
  });
  return list;
}

/// Whether [tx] may be counted: a readable record with a real type, an
/// amount inside the module's bounds, and a date the store could read.
bool validExpenseTx(ExpenseTx tx) =>
    tx.valid &&
    (tx.type == 'income' || tx.type == 'expense') &&
    tx.amountRial >= 0 &&
    tx.amountRial <= expenseAmountMax &&
    tx.date.year > 1970;
