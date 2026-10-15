import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/expenses/models.dart';
import 'package:nex_client/modules/expenses/money.dart';
import 'package:nex_client/modules/expenses/logic.dart';

void main() {
  test(
    'Persian/Arabic decimals, zero budget and negative input are explicit',
    () {
      expect(
        parseExpenseAmount('۱۲٫۵۰', expenseCurrencyOf('USD')!).minor,
        1250,
      );
      expect(
        parseExpenseAmount('١٢٫٥٥٥', expenseCurrencyOf('KWD')!).minor,
        12555,
      );
      expect(parseExpenseAmount('۱۲', expenseCurrencyOf('JPY')!).minor, 12);
      expect(parseTomanAmount('۰٫۰۰۱').minor, 1);
      expect(parseTomanAmount('۰', allowZero: true).minor, 0);
      expect(
        parseExpenseAmount(
          '۰',
          expenseCurrencyOf('USD')!,
          allowZero: true,
        ).minor,
        0,
      );
      expect(
        parseExpenseAmount('−۱', expenseCurrencyOf('USD')!).error,
        ExpenseAmountError.negative,
      );
      for (final value in ['.', '٫', ',', '1e2', '۱٬۰۰۰', 'NaN']) {
        expect(
          parseExpenseAmount(value, expenseCurrencyOf('USD')!).error,
          isNotNull,
        );
      }
    },
  );
  test('currency and exponent travel with every saved financial shape', () {
    for (final code in ['IRR', 'USD', 'EUR', 'GBP', 'JPY', 'KWD']) {
      final transaction = ExpenseTx(
        id: 'r',
        type: 'income',
        amount: 123,
        currency: code,
        date: DateTime(2026, 10, 14),
      );
      final body = transaction.toBody();
      expect(body['currency_code'], code);
      expect(body['currency_exponent'], expenseCurrencyOf(code)!.exponent);
      expect(ExpenseTx.fromBody('r', body).amount, 123);
      expect(
        ExpenseBudget(
          month: '2026-10',
          currency: code,
          amount: 0,
        ).toBody()['currency_exponent'],
        expenseCurrencyOf(code)!.exponent,
      );
      expect(
        ExpenseTemplate(
          id: 't',
          label: 'A',
          type: 'expense',
          amount: 123,
          currency: code,
        ).toBody()['currency_code'],
        code,
      );
    }
  });
  test(
    'unsupported, conflicting and malformed records never become expenses',
    () {
      final good = {
        'type': 'expense',
        'amount': 100,
        'currency': 'USD',
        'date': '2026-10-14',
      };
      for (final changes in [
        {'type': 'transfer'},
        {'currency': 'XYZ'},
        {'currency_code': 'JPY'},
        {'currency_exponent': 3},
        {'amount': expenseAmountMax + 1},
        {'amount': double.nan},
        {'date': '2026-02-30'},
        {'date': '2026-10-14T24:00:00'},
        {'date': '2026-10-14T00:00:00+25:00'},
      ]) {
        final record = ExpenseTx.fromBody('r', {...good, ...changes});
        expect(record.valid, isFalse, reason: changes.toString());
        expect(expenseTotals([record]), isEmpty);
      }
    },
  );
  test('aggregate and percentage stay exact beyond signed 64-bit sums', () {
    final records = List.generate(
      10000,
      (i) => ExpenseTx(
        id: '$i',
        type: 'expense',
        amount: expenseAmountMax,
        currency: 'USD',
        date: DateTime(2026, 10, 14),
      ),
    );
    final total = expenseTotals(records).single;
    final exact = BigInt.parse('10000000000000000000');
    expect(total.expense, exact);
    expect(total.net, -exact);
    expect(
      formatExpenseNumber(total.expense, 2, persian: false),
      '100,000,000,000,000,000',
    );
    expect(expensePercentOf(exact, exact), 100);
    expect(
      expenseCategoryBreakdown(records, currency: 'USD').single.total,
      exact,
    );
    final budget = ExpenseBudget(month: '2026-10', currency: 'USD', amount: 1);
    expect(
      expenseBudgetStatuses([budget], '2026-10', records).single.overage,
      exact - BigInt.one,
    );
  });
  test(
    'offset timestamp is bucketed in the local calendar and impossible dates refused',
    () {
      final local = DateTime(2026, 11, 1, 0, 30);
      final record = ExpenseTx.fromBody('r', {
        'type': 'expense',
        'amount': 100,
        'currency': 'USD',
        'date': local.toUtc().toIso8601String(),
      });
      expect(record.valid, isTrue);
      expect(monthKeyOf(record.date), '2026-11');
      expect(previousMonthKey('0000-01'), isNull);
      expect(nextMonthKey('broken'), isNull);
      expect(daysInMonthOf('2024-03'), 31);
      expect(monthDistance('1900-01', DateTime(2026, 10, 14)).months, 1521);
    },
  );
}
