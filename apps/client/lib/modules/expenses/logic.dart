/// The Expenses module's arithmetic: every total, breakdown, budget
/// status and filter is computed here, in integers, from a list of
/// records — no storage, no Flutter, fully unit-testable.
///
/// Two invariants hold throughout:
///
/// * **Currencies are never combined.** Every total is per currency; a
///   net figure exists only inside one currency. There is no exchange
///   rate and none is implied.
/// * **Invalid records never count.** A malformed body is still listed
///   so the person can fix it, but it is excluded from totals.
library;

import 'models.dart';
import 'money.dart';

/// Totals for one currency: expense, income, net.
class ExpenseCurrencyTotals {
  ExpenseCurrencyTotals({
    required this.currency,
    required this.expense,
    required this.income,
  });

  final String currency;
  final BigInt expense;
  final BigInt income;

  BigInt get net => income - expense;
}

/// Totals per currency, ordered by first appearance of the currency in
/// the records given. Empty when there is nothing to count.
List<ExpenseCurrencyTotals> expenseTotals(Iterable<ExpenseTx> txs) {
  final order = <String>[];
  final expense = <String, BigInt>{};
  final income = <String, BigInt>{};
  for (final tx in txs) {
    if (!validExpenseTx(tx)) continue;
    if (!order.contains(tx.currency)) order.add(tx.currency);
    if (tx.isIncome) {
      income[tx.currency] =
          (income[tx.currency] ?? BigInt.zero) + BigInt.from(tx.amount);
    } else {
      expense[tx.currency] =
          (expense[tx.currency] ?? BigInt.zero) + BigInt.from(tx.amount);
    }
  }
  return [
    for (final currency in order)
      ExpenseCurrencyTotals(
        currency: currency,
        expense: expense[currency] ?? BigInt.zero,
        income: income[currency] ?? BigInt.zero,
      ),
  ];
}

/// What was spent in [month] in one currency, against the month before it —
/// the comparison people mean by «am I spending more?». Null when the month
/// before has no spending in that currency: there is nothing honest to
/// compare to, and a percentage of nothing is not a number.
({BigInt previous, int? percent, int direction})? expenseMonthChange(
  Iterable<ExpenseTx> txs,
  String month, {
  required String currency,
}) {
  final before = previousMonthKey(month);
  if (before == null) return null;
  BigInt spent(String key) {
    var total = BigInt.zero;
    for (final tx in txs) {
      if (!validExpenseTx(tx) || tx.isIncome || tx.currency != currency) {
        continue;
      }
      if (monthKeyOf(tx.date) == key) total += BigInt.from(tx.amount);
    }
    return total;
  }

  final previous = spent(before);
  if (previous <= BigInt.zero) return null;
  final current = spent(month);
  final diff = current - previous;
  // Rounded to the nearest whole percent, away from zero on a half.
  final percent =
      ((diff.abs() * BigInt.from(200) + previous) ~/ (previous * BigInt.two))
          .toInt();
  return (
    previous: previous,
    percent: percent,
    direction: percent == 0 ? 0 : (diff.isNegative ? -1 : 1),
  );
}

/// One category's slice of a month's spending.
class ExpenseCategorySlice {
  ExpenseCategorySlice({required this.categoryId, required this.total});

  final String categoryId;
  final BigInt total;
}

/// Spending per category, in one currency, largest first. Records with
/// no category land in `cat-other`'s bucket by id — the screen maps a
/// missing category to the default "Other" when it shows it.
List<ExpenseCategorySlice> expenseCategoryBreakdown(
  Iterable<ExpenseTx> txs, {
  required String currency,
}) {
  final totals = <String, BigInt>{};
  for (final tx in txs) {
    if (!validExpenseTx(tx) || tx.isIncome || tx.currency != currency) continue;
    final key = tx.categoryId ?? 'cat-other';
    totals[key] = (totals[key] ?? BigInt.zero) + BigInt.from(tx.amount);
  }
  final slices = [
    for (final entry in totals.entries)
      ExpenseCategorySlice(categoryId: entry.key, total: entry.value),
  ];
  slices.sort((a, b) => b.total.compareTo(a.total));
  return slices;
}

/// A budget's standing against the records of its own month and
/// currency: the arithmetic is shown, never just the verdict.
class ExpenseBudgetStatus {
  ExpenseBudgetStatus({required this.budget, required this.spent});

  final ExpenseBudget budget;

  /// Expenses of this budget's month, currency and category (all of
  /// them when the budget is the overall limit).
  final BigInt spent;

  BigInt get left => BigInt.from(budget.amount) - spent;

  /// Positive when over. "Over" is stated plainly, never alarmingly.
  BigInt get overage => spent - BigInt.from(budget.amount);

  bool get isOver => overage > BigInt.zero;

  /// 0–1 progress for the calm bar; 1 when there is no budget amount.
  double get progress => expenseProgress(spent, budget.amount);
}

/// The status of every budget for [month], against [txs] — only records
/// of the same month and currency are counted, so a dollar budget is
/// never fed rial spending.
List<ExpenseBudgetStatus> expenseBudgetStatuses(
  Iterable<ExpenseBudget> budgets,
  String month,
  Iterable<ExpenseTx> txs,
) {
  final byCurrencyCategory = <String, BigInt>{};
  for (final tx in txs) {
    if (!validExpenseTx(tx) || tx.isIncome) continue;
    if (monthKeyOf(tx.date) != month) continue;
    final key = '${tx.currency}|${tx.categoryId ?? 'cat-other'}';
    byCurrencyCategory[key] =
        (byCurrencyCategory[key] ?? BigInt.zero) + BigInt.from(tx.amount);
    final overallKey = '${tx.currency}|all';
    byCurrencyCategory[overallKey] =
        (byCurrencyCategory[overallKey] ?? BigInt.zero) +
        BigInt.from(tx.amount);
  }
  return [
    for (final budget in budgets.where((b) => b.month == month))
      ExpenseBudgetStatus(
        budget: budget,
        spent:
            byCurrencyCategory['${budget.currency}|${budget.categoryId ?? 'all'}'] ??
            BigInt.zero,
      ),
  ]..sort((a, b) => a.budget.id.compareTo(b.budget.id));
}

/// Records in a month, or all of them when [month] is null.
Iterable<ExpenseTx> txsInMonth(Iterable<ExpenseTx> txs, String? month) =>
    month == null ? txs : txs.where((tx) => monthKeyOf(tx.date) == month);

/// Text search across note, merchant, account and the category's own
/// name. Case-insensitive for Latin; Persian matches as typed.
Iterable<ExpenseTx> searchTxs(
  Iterable<ExpenseTx> txs,
  String query,
  String Function(String categoryId) categoryName,
) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return txs;
  return txs.where((tx) {
    final category = tx.categoryId == null ? '' : categoryName(tx.categoryId!);
    return tx.note?.toLowerCase().contains(q) == true ||
        tx.merchant?.toLowerCase().contains(q) == true ||
        tx.account?.toLowerCase().contains(q) == true ||
        category.toLowerCase().contains(q) == true ||
        tx.currency.toLowerCase().contains(q);
  });
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

/// How a month stands relative to another (usually now) — the screen
/// picks the words from the module's strings; this carries only the
/// arithmetic.
enum ExpenseMonthDistance { current, previous, earlier, later }

/// Which bucket [key] falls into relative to [now], and how many
/// months away it is when that number matters.
({ExpenseMonthDistance distance, int months}) monthDistance(
  String key,
  DateTime now,
) {
  final current = monthKeyOf(now);
  if (key == current) {
    return (distance: ExpenseMonthDistance.current, months: 0);
  }
  final previous = previousMonthKey(current);
  if (previous != null && key == previous) {
    return (distance: ExpenseMonthDistance.previous, months: 1);
  }
  final a = monthStartOf(key), b = monthStartOf(current);
  final difference = (b.year - a.year) * 12 + b.month - a.month;
  return (
    distance: difference > 0
        ? ExpenseMonthDistance.earlier
        : ExpenseMonthDistance.later,
    months: difference.abs(),
  );
}

/// The month number 1–12 of a month key — the strings own the names.
int monthNumberOf(String key) => int.parse(key.split('-')[1]);

/// The four-digit year of a month key, as it is written.
String yearOf(String key) => key.split('-')[0];

/// The month containing [now], as a key.
String currentMonthKey(DateTime now) => monthKeyOf(now);

/// Days in a month of [key] — February honours leap years.
int daysInMonthOf(String key) {
  final start = monthStartOf(key);
  return DateTime.utc(start.year, start.month + 1, 0).day;
}

bool validExpenseTx(ExpenseTx tx) =>
    tx.valid &&
    (tx.type == 'income' || tx.type == 'expense') &&
    tx.amount >= 0 &&
    tx.amount <= expenseAmountMax &&
    expenseCurrencyOf(tx.currency) != null;
