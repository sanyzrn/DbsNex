import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/expenses/expenses_widgets.dart';
import 'package:nex_client/modules/expenses/logic.dart';
import 'package:nex_client/modules/expenses/models.dart';
import 'package:nex_client/modules/module_api.dart';

ExpenseTx tx(
  String id,
  DateTime date,
  int amount, {
  String type = 'expense',
  String currency = 'USD',
}) => ExpenseTx(
  id: id,
  type: type,
  amount: amount,
  currency: currency,
  date: date,
  categoryId: 'cat-food',
);

void main() {
  group('this month against last, in one currency', () {
    final txs = [
      tx('a', DateTime(2026, 9, 5), 10000),
      tx('b', DateTime(2026, 9, 20), 10000),
      tx('c', DateTime(2026, 10, 3), 25000),
      // income is not spending
      tx('d', DateTime(2026, 9, 7), 99999, type: 'income'),
      // another currency is another story
      tx('e', DateTime(2026, 9, 7), 5, currency: 'EUR'),
    ];

    test('more: 25,000 against 20,000 is 25% more', () {
      final change = expenseMonthChange(txs, '2026-10', currency: 'USD');
      expect(change!.previous, BigInt.from(20000));
      expect(change.percent, 25);
      expect(change.direction, 1);
    });

    test('less, and the same', () {
      final less = expenseMonthChange(txs, '2026-09', currency: 'USD');
      // September 20,000 against August (nothing) — no comparison at all.
      expect(less, isNull);
      final lower = expenseMonthChange(
        [
          tx('x', DateTime(2026, 9, 1), 20000),
          tx('y', DateTime(2026, 10, 1), 15000),
        ],
        '2026-10',
        currency: 'USD',
      );
      expect(lower!.percent, 25);
      expect(lower.direction, -1);
      final same = expenseMonthChange(
        [
          tx('x', DateTime(2026, 9, 1), 20000),
          tx('y', DateTime(2026, 10, 1), 20000),
        ],
        '2026-10',
        currency: 'USD',
      );
      expect(same!.direction, 0);
    });

    test('nothing last month is not a percentage', () {
      expect(expenseMonthChange(txs, '2026-10', currency: 'GBP'), isNull);
      expect(expenseMonthChange(const [], '2026-10', currency: 'USD'), isNull);
    });

    test('January compares with December of the year before', () {
      final change = expenseMonthChange(
        [
          tx('x', DateTime(2025, 12, 31), 1000),
          tx('y', DateTime(2026, 1, 1), 1500),
        ],
        '2026-01',
        currency: 'USD',
      );
      expect(change!.percent, 50);
    });

    test('rounds to the nearest percent and never overflows', () {
      final change = expenseMonthChange(
        [tx('x', DateTime(2026, 9, 1), 3), tx('y', DateTime(2026, 10, 1), 4)],
        '2026-10',
        currency: 'USD',
      );
      expect(change!.percent, 33);
    });
  });

  testWidgets('the totals panel says it in words', (tester) async {
    Future<void> show(
      ({BigInt previous, int? percent, int direction})? change,
    ) => tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ExpensesTotalsPanel(
            totals: ExpenseCurrencyTotals(
              currency: 'USD',
              expense: BigInt.from(25000),
              income: BigInt.zero,
            ),
            change: change,
          ),
        ),
      ),
    );
    await show((previous: BigInt.from(20000), percent: 25, direction: 1));
    expect(find.textContaining('25% more'), findsOneWidget);
    await show(null);
    expect(find.byKey(const ValueKey('expenses-month-change')), findsNothing);
  });
}
