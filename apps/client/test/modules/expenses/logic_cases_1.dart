part of 'logic_test.dart';

void _logicCases1() {
  group('month keys', () {
    test('local calendar buckets', () {
      expect(monthKeyOf(DateTime(2026, 1, 31, 23, 30)), '2026-01');
      expect(monthKeyOf(DateTime(2026, 12, 1, 0, 0)), '2026-12');
      expect(monthKeyOf(DateTime(2026, 10, 13, 14, 30)), '2026-10');
    });

    test('rollovers across the year boundary both ways', () {
      expect(nextMonthKey('2026-01'), '2026-02');
      expect(nextMonthKey('2026-11'), '2026-12');
      expect(nextMonthKey('2026-12'), '2027-01');
      expect(previousMonthKey('2026-01'), '2025-12');
      expect(previousMonthKey('2027-01'), '2026-12');
      // The datetime arithmetic underneath handles year carry.
      expect(monthStartOf('2027-01'), DateTime(2027, 1));
      expect(monthStartOf(previousMonthKey('2026-01')!), DateTime(2025, 12));
    });

    test('the edges of the representable range', () {
      expect(nextMonthKey('9999-12'), isNull);
      expect(previousMonthKey('0001-01'), isNull);
      expect(nextMonthKey('9999-11'), '9999-12');
      expect(previousMonthKey('0001-02'), '0001-01');
    });

    test('month distance and its shapes', () {
      final now = DateTime(2026, 10, 13);
      expect(
        monthDistance('2026-10', now).distance,
        ExpenseMonthDistance.current,
      );
      expect(
        monthDistance('2026-09', now).distance,
        ExpenseMonthDistance.previous,
      );
      expect(monthDistance('2026-09', now).months, 1);
      expect(
        monthDistance('2026-08', now).distance,
        ExpenseMonthDistance.earlier,
      );
      expect(monthDistance('2026-08', now).months, 2);
      expect(monthDistance('2025-12', now).months, 10);
      expect(
        monthDistance('2026-11', now).distance,
        ExpenseMonthDistance.later,
      );
      expect(monthDistance('2026-11', now).months, 1);
      expect(monthDistance('2027-01', now).months, 3);
      // The far side never loops.
      expect(monthDistance('1900-01', now).months, 1521);
      expect(
        monthDistance('1900-01', now).distance,
        ExpenseMonthDistance.earlier,
      );
    });

    test('leap years and month lengths', () {
      expect(daysInMonthOf('2024-02'), 29);
      expect(daysInMonthOf('2026-02'), 28);
      expect(daysInMonthOf('2026-04'), 30);
      expect(daysInMonthOf('2026-01'), 31);
    });

    test('month numbers and years', () {
      expect(monthNumberOf('2026-10'), 10);
      expect(yearOf('2026-10'), '2026');
      expect(currentMonthKey(DateTime(2026, 10, 13)), '2026-10');
    });
  });

  group('totals', () {
    test('per currency, never combined', () {
      final totals = expenseTotals([
        tx('a', DateTime(2026, 10, 1), amount: 100000, currency: 'IRR'),
        tx('b', DateTime(2026, 10, 2), amount: 50000, currency: 'IRR'),
        tx(
          'c',
          DateTime(2026, 10, 3),
          type: 'income',
          amount: 1000000,
          currency: 'IRR',
        ),
        tx('d', DateTime(2026, 10, 4), amount: 2500, currency: 'USD'),
        tx(
          'e',
          DateTime(2026, 10, 5),
          amount: 0,
          currency: 'IRR',
          category: null,
        ),
      ]);
      expect(totals, hasLength(2));
      final irr = totals.firstWhere((t) => t.currency == 'IRR');
      expect(irr.expense, BigInt.from(150000));
      expect(irr.income, BigInt.from(1000000));
      expect(irr.net, BigInt.from(850000));
      final usd = totals.firstWhere((t) => t.currency == 'USD');
      expect(usd.expense, BigInt.from(2500));
      expect(usd.income, BigInt.from(0));
      expect(usd.net, BigInt.from(-2500));
    });

    test('negative net is a number, not an exception', () {
      final totals = expenseTotals([
        tx('a', DateTime(2026, 10, 1), amount: 500, currency: 'USD'),
        tx(
          'b',
          DateTime(2026, 10, 1),
          type: 'income',
          amount: 300,
          currency: 'USD',
        ),
      ]);
      expect(totals.single.net, BigInt.from(-200));
    });

    test('empty and invalid records count for nothing', () {
      expect(expenseTotals([]), isEmpty);
      final broken = ExpenseTx.fromBody('x', {'type': 'expense'});
      expect(broken.valid, isFalse);
      expect(expenseTotals([broken]), isEmpty);
      final zeroIncome = ExpenseTx.fromBody('y', {
        'type': 'income',
        'amount': 0,
        'currency': 'IRR',
        'date': '2026-10-01T00:00:00',
      });
      expect(zeroIncome.valid, isTrue);
      expect(expenseTotals([zeroIncome]).single.income, BigInt.from(0));
    });
  });

  group('category breakdown', () {
    test('largest first, one currency at a time', () {
      final slices = expenseCategoryBreakdown([
        tx('a', DateTime(2026, 10, 1), amount: 300, category: 'cat-food'),
        tx('b', DateTime(2026, 10, 2), amount: 700, category: 'cat-transport'),
        tx('c', DateTime(2026, 10, 3), amount: 300, category: 'cat-food'),
        tx(
          'd',
          DateTime(2026, 10, 4),
          amount: 999,
          category: 'cat-food',
          currency: 'USD',
        ),
        tx(
          'e',
          DateTime(2026, 10, 5),
          type: 'income',
          amount: 500,
          category: 'cat-food',
        ),
      ], currency: 'IRR');
      // Largest first: transport 700, food 600.
      expect(slices.map((s) => s.categoryId), ['cat-transport', 'cat-food']);
      expect(slices.first.total, BigInt.from(700));
      expect(slices.last.total, BigInt.from(600));
    });

    test('a missing category lands in other', () {
      final slices = expenseCategoryBreakdown([
        tx('a', DateTime(2026, 10, 1), category: null, amount: 100),
        tx('b', DateTime(2026, 10, 2), category: 'ghost', amount: 50),
      ], currency: 'IRR');
      expect(slices.map((s) => s.categoryId), contains('cat-other'));
      expect(slices.map((s) => s.categoryId), contains('ghost'));
    });
  });

  group('budget statuses', () {
    final records = [
      tx('a', DateTime(2026, 10, 1), amount: 300, category: 'cat-food'),
      tx('b', DateTime(2026, 10, 2), amount: 700, category: 'cat-transport'),
      tx(
        'c',
        DateTime(2026, 10, 3),
        amount: 250,
        category: 'cat-food',
        currency: 'USD',
      ),
      // November spending must not feed an October budget.
      tx('d', DateTime(2026, 11, 1), amount: 500, category: 'cat-food'),
    ];

    test('under, over, and the overall limit', () {
      final statuses = expenseBudgetStatuses(
        [
          const ExpenseBudget(
            month: '2026-10',
            currency: 'IRR',
            amount: 500,
            categoryId: 'cat-food',
          ),
          const ExpenseBudget(
            month: '2026-10',
            currency: 'IRR',
            amount: 500,
            categoryId: 'cat-transport',
          ),
          const ExpenseBudget(month: '2026-10', currency: 'IRR', amount: 2000),
        ],
        '2026-10',
        records,
      );
      expect(statuses, hasLength(3));
      final food = statuses.firstWhere(
        (s) => s.budget.categoryId == 'cat-food',
      );
      expect(food.spent, BigInt.from(300));
      expect(food.left, BigInt.from(200));
      expect(food.overage, BigInt.from(-200));
      expect(food.isOver, isFalse);
      expect(food.progress, closeTo(0.6, 1e-9));
      final transport = statuses.firstWhere(
        (s) => s.budget.categoryId == 'cat-transport',
      );
      expect(transport.spent, BigInt.from(700));
      expect(transport.isOver, isTrue);
      expect(transport.overage, BigInt.from(200));
      expect(transport.progress, 1);
      final overall = statuses.firstWhere((s) => s.budget.categoryId == null);
      expect(
        overall.spent,
        BigInt.from(1000),
      ); // 300 + 700, IRR only, this month only
    });

    test('a zero budget counts everything as over', () {
      final statuses = expenseBudgetStatuses(
        [const ExpenseBudget(month: '2026-10', currency: 'IRR', amount: 0)],
        '2026-10',
        records,
      );
      expect(statuses.single.spent, BigInt.from(1000));
      expect(statuses.single.isOver, isTrue);
      expect(statuses.single.progress, 1);
    });

    test('budgets of other months are simply absent', () {
      final statuses = expenseBudgetStatuses(
        [const ExpenseBudget(month: '2025-01', currency: 'IRR', amount: 999)],
        '2026-10',
        records,
      );
      expect(statuses, isEmpty);
    });

    test('budget ids are deterministic', () {
      expect(
        budgetId('2026-10', 'cat-food', 'IRR'),
        budgetId('2026-10', 'cat-food', 'IRR'),
      );
      expect(
        budgetId('2026-10', 'cat-food', 'IRR'),
        isNot(budgetId('2026-10', null, 'IRR')),
      );
    });
  });

  group('filters and ordering', () {
    test('month scope, including all time', () {
      final all = [
        tx('a', DateTime(2026, 9, 30, 23, 59)),
        tx('b', DateTime(2026, 10, 1)),
        tx('c', DateTime(2026, 10, 31, 23, 59)),
        tx('d', DateTime(2026, 11, 1)),
      ];
      expect(txsInMonth(all, '2026-10'), hasLength(2));
      expect(txsInMonth(all, null), hasLength(4));
    });

    test('search touches note, merchant, account, category, code', () {
      final all = [
        tx('a', DateTime(2026, 10, 1), note: 'Groceries weekly'),
        tx('b', DateTime(2026, 10, 2), merchant: 'Green Grocer'),
        tx('c', DateTime(2026, 10, 3), account: 'cash'),
        tx('d', DateTime(2026, 10, 4), category: 'cat-transport'),
        tx('e', DateTime(2026, 10, 5), currency: 'USD'),
      ];
      String name(String id) => id == 'cat-transport' ? 'Transport' : 'Food';
      expect(searchTxs(all, 'grocer', name), hasLength(2));
      expect(searchTxs(all, 'GROCER', name), hasLength(2));
      expect(searchTxs(all, 'cash', name), hasLength(1));
      expect(searchTxs(all, 'transport', name), hasLength(1));
      expect(searchTxs(all, 'usd', name), hasLength(1));
      expect(searchTxs(all, '  ', name), hasLength(5));
      expect(searchTxs(all, 'nothing', name), isEmpty);
    });

    test('newest first, ids break ties', () {
      final sorted = sortedByDate([
        tx('b', DateTime(2026, 10, 2)),
        tx('a', DateTime(2026, 10, 3)),
        tx('c', DateTime(2026, 10, 2)),
      ]);
      expect(sorted.map((t) => t.id).toList(), ['a', 'c', 'b']);
    });
  });
}
