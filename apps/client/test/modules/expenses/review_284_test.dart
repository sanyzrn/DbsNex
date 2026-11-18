import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/expenses/logic.dart';
import 'package:nex_client/modules/expenses/models.dart';
import 'package:nex_client/modules/module_api.dart';

/// 2.8.4 review: what the tests this upgrade replaced used to hold, kept.
void main() {
  ExpenseTx spend(String id, int rial, DateTime date) =>
      ExpenseTx(id: id, type: 'expense', amountRial: rial, date: date);

  test('Farvardin compares with Esfand, January with December', () {
    // 1 Farvardin 1405 is 21 March 2026; Esfand 1404 ends the day before.
    final txs = [
      spend('a', 200000, nexGregorianDate(1404, 12, 10)),
      spend('b', 250000, nexGregorianDate(1405, 1, 5)),
      spend('c', 100000, DateTime(2025, 12, 20)),
      spend('d', 50000, DateTime(2026, 1, 3)),
    ];
    final solar = expenseMonthChange(
      txs,
      month: const NexModuleMonth(true, 1405, 1),
      solar: true,
    )!;
    expect(solar.previous, BigInt.from(200000));
    expect(solar.current, BigInt.from(250000));
    expect(solar.percent, 25);
    final civil = expenseMonthChange(
      txs,
      month: const NexModuleMonth(false, 2026, 1),
      solar: false,
    )!;
    expect(civil.previous, BigInt.from(100000));
    expect(civil.percent, 50);
    expect(civil.direction, -1);
  });

  test('totals stay exact past what a 64-bit sum holds', () {
    const most = 1000000000000000; // 10^15 rials, the most one record holds
    final txs = [
      for (var i = 0; i < 10000; i++) spend('t$i', most, DateTime(2026, 11, 1)),
    ];
    expect(expenseTotals(txs).expense, BigInt.from(most) * BigInt.from(10000));
    expect(
      expensePercentChange(BigInt.from(most) * BigInt.two, BigInt.from(most)),
      100,
    );
  });
}
