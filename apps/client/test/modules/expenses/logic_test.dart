import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/expenses/logic.dart';
import 'package:nex_client/modules/expenses/models.dart';
import 'package:nex_client/modules/module_api.dart' show NexModuleMonth;

/// Totals, the month a person reads (Jalali or Gregorian), each category
/// against last month, budgets, filters and search — integer in, integer
/// out, no storage and no Flutter.
ExpenseTx tx(
  String id,
  DateTime date, {
  String type = 'expense',
  int amountRial = 1000,
  String? category = 'cat-groceries',
  String? note,
  String? merchant,
  String? account,
  bool valid = true,
}) => ExpenseTx(
  id: id,
  type: type,
  amountRial: amountRial,
  date: date,
  categoryId: category,
  note: note,
  merchant: merchant,
  account: account,
  valid: valid,
);

String nameOf(String id) => switch (id) {
  'cat-groceries' => 'Groceries',
  'cat-rent' => 'Rent',
  _ => 'Other',
};

void main() {
  group('totals', () {
    test('spent, received and what is left', () {
      final totals = expenseTotals([
        tx('a', DateTime(2026, 10, 2), amountRial: 200000),
        tx('b', DateTime(2026, 10, 3), amountRial: 50000),
        tx('c', DateTime(2026, 10, 4), type: 'income', amountRial: 1000000),
      ]);
      expect(totals.expense, BigInt.from(250000));
      expect(totals.income, BigInt.from(1000000));
      expect(totals.left, BigInt.from(750000));
      expect(totals.hasIncome, isTrue);
    });

    test('an incomplete record is never counted', () {
      final totals = expenseTotals([
        tx('a', DateTime(2026, 10, 2), amountRial: 200000),
        tx('b', DateTime(2026, 10, 3), amountRial: 900000, valid: false),
      ]);
      expect(totals.expense, BigInt.from(200000));
    });

    test('a month spent past its income is arithmetic, not an alarm', () {
      final totals = expenseTotals([
        tx('a', DateTime(2026, 10, 2), amountRial: 500000),
        tx('b', DateTime(2026, 10, 4), type: 'income', amountRial: 100000),
      ]);
      expect(totals.left, BigInt.from(-400000));
    });
  });

  group('the month the person reads', () {
    test('a Gregorian month holds its own days only', () {
      final month = NexModuleMonth(false, 2026, 10);
      final inside = txsInMonth(
        [
          tx('a', DateTime(2026, 9, 30, 23, 59)),
          tx('b', DateTime(2026, 10, 1)),
          tx('c', DateTime(2026, 10, 31, 23, 59)),
          tx('d', DateTime(2026, 11, 1)),
        ],
        month,
        solar: false,
      ).map((t) => t.id);
      expect(inside, ['b', 'c']);
    });

    test('a Jalali month runs on its own civil days', () {
      // Aban 1405: 23 October – 21 November 2026.
      final month = NexModuleMonth.of(DateTime(2026, 10, 25), solar: true);
      final inside = txsInMonth(
        [
          tx('before', DateTime(2026, 10, 22, 23, 59)),
          tx('first', DateTime(2026, 10, 23)),
          tx('last', DateTime(2026, 11, 21, 23, 59)),
          tx('after', DateTime(2026, 11, 22)),
        ],
        month,
        solar: true,
      ).map((t) => t.id);
      expect(inside, ['first', 'last']);
    });

    test('all time is every record', () {
      expect(
        txsInMonth([tx('a', DateTime(2020, 1, 1))], null, solar: false).length,
        1,
      );
    });
  });

  group('this month against last', () {
    test('the whole month, and each category, with its own percent', () {
      final month = NexModuleMonth(false, 2026, 10);
      final txs = [
        tx('a', DateTime(2026, 10, 3), amountRial: 118000),
        tx('b', DateTime(2026, 9, 3), amountRial: 100000),
        tx(
          'c',
          DateTime(2026, 10, 5),
          category: 'cat-rent',
          amountRial: 500000,
        ),
      ];
      final change = expenseMonthChange(txs, month: month, solar: false)!;
      expect(change.previous, BigInt.from(100000));
      expect(change.current, BigInt.from(618000));
      expect(change.percent, 518);
      expect(change.direction, 1);
      final slices = expenseCategoryBreakdown(txs, month: month, solar: false);
      expect(slices.first.categoryId, 'cat-rent');
      final groceries = slices.firstWhere(
        (s) => s.categoryId == 'cat-groceries',
      );
      expect(groceries.percent, 18);
      expect(groceries.direction, 1);
      expect(groceries.previous, BigInt.from(100000));
      final rent = slices.firstWhere((s) => s.categoryId == 'cat-rent');
      expect(rent.percent, isNull, reason: 'no last month to compare to');
    });

    test('a percentage of nothing is not a number', () {
      final month = NexModuleMonth(false, 2026, 10);
      expect(
        expenseMonthChange(
          [tx('a', DateTime(2026, 10, 3))],
          month: month,
          solar: false,
        ),
        isNull,
      );
    });

    test('less, the same, and the rounding of a half', () {
      expect(expensePercentChange(BigInt.from(80), BigInt.from(100)), 20);
      expect(expenseDirection(BigInt.from(80), BigInt.from(100)), -1);
      expect(expensePercentChange(BigInt.from(100), BigInt.from(100)), 0);
      expect(expenseDirection(BigInt.from(100), BigInt.from(100)), 0);
      expect(expensePercentChange(BigInt.from(1), BigInt.from(3)), 67);
    });

    test('income is not spending in a breakdown', () {
      final month = NexModuleMonth(false, 2026, 10);
      final slices = expenseCategoryBreakdown(
        [
          tx('a', DateTime(2026, 10, 3), amountRial: 100),
          tx(
            'b',
            DateTime(2026, 10, 3),
            type: 'income',
            category: 'cat-salary',
            amountRial: 900,
          ),
        ],
        month: month,
        solar: false,
      );
      expect(slices.map((s) => s.categoryId), ['cat-groceries']);
    });
  });

  group('budgets', () {
    final month = NexModuleMonth(false, 2026, 10);
    final start = monthStartIso(month);

    test('spent, left and over, per category and overall', () {
      final statuses = expenseBudgetStatuses(
        [
          const ExpenseBudget(start: '2026-10-01', amountRial: 1000000),
          const ExpenseBudget(
            start: '2026-10-01',
            categoryId: 'cat-groceries',
            amountRial: 300000,
          ),
        ],
        month,
        [
          tx('a', DateTime(2026, 10, 2), amountRial: 250000),
          tx(
            'b',
            DateTime(2026, 10, 3),
            category: 'cat-rent',
            amountRial: 500000,
          ),
          tx(
            'c',
            DateTime(2026, 9, 3),
            category: 'cat-groceries',
            amountRial: 1,
          ),
        ],
      );
      expect(statuses.length, 2);
      final groceries = statuses.firstWhere(
        (s) => s.budget.categoryId == 'cat-groceries',
      );
      expect(groceries.spent, BigInt.from(250000));
      expect(groceries.left, BigInt.from(50000));
      expect(groceries.isOver, isFalse);
      final overall = statuses.firstWhere((s) => s.budget.categoryId == null);
      expect(overall.spent, BigInt.from(750000));
      expect(overall.left, BigInt.from(250000));
    });

    test('a budget belongs to its own month and says so plainly when over', () {
      final statuses = expenseBudgetStatuses(
        [ExpenseBudget(start: start, amountRial: 100)],
        month,
        [tx('a', DateTime(2026, 10, 2), amountRial: 150)],
      );
      expect(statuses.single.isOver, isTrue);
      expect(statuses.single.overage, BigInt.from(50));
      expect(statuses.single.progress, 1);
      expect(
        expenseBudgetStatuses(
          [const ExpenseBudget(start: '2026-11-01', amountRial: 100)],
          month,
          [tx('a', DateTime(2026, 10, 2), amountRial: 150)],
        ),
        isEmpty,
      );
    });

    test('a zero budget with no spending shows no progress', () {
      final statuses = expenseBudgetStatuses(
        [ExpenseBudget(start: start, amountRial: 0)],
        month,
        const [],
      );
      expect(statuses.single.progress, 0);
    });
  });

  group('finding a payment', () {
    final txs = [
      tx(
        'a',
        DateTime(2026, 10, 2),
        amountRial: 250000,
        note: 'weekly shop',
        merchant: 'Corner shop',
        account: 'cash',
      ),
      tx(
        'b',
        DateTime(2026, 10, 3),
        category: 'cat-rent',
        amountRial: 12000000,
      ),
      tx('c', DateTime(2026, 10, 4), category: 'cat-other', amountRial: 5000),
    ];

    test('by words, in any of the fields it could be in', () {
      expect(
        filterTxs(txs, query: 'shop', categoryName: nameOf).map((t) => t.id),
        ['a'],
      );
      expect(
        filterTxs(txs, query: 'rent', categoryName: nameOf).map((t) => t.id),
        ['b'],
      );
      expect(
        filterTxs(txs, query: 'cash', categoryName: nameOf).map((t) => t.id),
        ['a'],
      );
    });

    test('by category', () {
      expect(
        filterTxs(
          txs,
          categoryId: 'cat-rent',
          categoryName: nameOf,
        ).map((t) => t.id),
        ['b'],
      );
    });

    test('by amount range, inclusive at both ends', () {
      expect(
        filterTxs(
          txs,
          minRial: 5000,
          maxRial: 250000,
          categoryName: nameOf,
        ).map((t) => t.id),
        ['a', 'c'],
      );
    });

    test('newest first, with a stable tie-break', () {
      final sorted = sortedByDate([
        tx('a', DateTime(2026, 10, 2)),
        tx('b', DateTime(2026, 10, 4)),
        tx('c', DateTime(2026, 10, 4)),
      ]);
      expect(sorted.map((t) => t.id), ['c', 'b', 'a']);
    });
  });
}
