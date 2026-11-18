import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/expenses/models.dart';
import 'package:nex_client/modules/module_api.dart' show NexModuleMonth;

/// The records: whole rials in `amountRial`, readers that keep a malformed
/// record visible instead of dropping it, and the 2.1.x shapes still
/// opening — converted once, never rescaled.
void main() {
  group('reading a payment', () {
    test('a 2.1.x rial payment is read as whole rials', () {
      final tx = ExpenseTx.fromBody('tx-1', {
        'type': 'expense',
        'amount': 125000,
        'currency': 'IRR',
        'currency_exponent': 2,
        'date': '2026-10-14T12:30:00',
        'category': 'cat-groceries',
      });
      expect(tx.valid, isTrue);
      expect(tx.amountRial, 1250);
      expect(tx.categoryId, 'cat-groceries');
    });

    test('a payment in another currency is kept, but not counted', () {
      final tx = ExpenseTx.fromBody('tx-2', {
        'type': 'expense',
        'amount': 1250,
        'currency': 'USD',
        'currency_exponent': 2,
        'date': '2026-10-14T12:30:00',
      });
      expect(tx.valid, isFalse);
      expect(tx.amountRial, 0);
    });

    test('a fraction of a rial is not invented into one', () {
      final tx = ExpenseTx.fromBody('tx-3', {
        'type': 'expense',
        'amount': 125050,
        'currency': 'IRR',
        'date': '2026-10-14T12:30:00',
      });
      expect(tx.valid, isFalse);
    });

    test('a bad date or type is an incomplete record, never a crash', () {
      for (final body in <Map<String, Object?>>[
        {'type': 'expense', 'amountRial': 1000, 'date': 'yesterday'},
        {'type': 'transfer', 'amountRial': 1000, 'date': '2026-10-14'},
        {'type': 'expense', 'amountRial': -4, 'date': '2026-10-14'},
        {'type': 'expense', 'amountRial': 'many', 'date': '2026-10-14'},
      ]) {
        final tx = ExpenseTx.fromBody('tx-x', body);
        expect(tx.valid, isFalse, reason: body.toString());
      }
    });

    test('a schema 3 body round-trips and keeps its unknown fields', () {
      final tx = ExpenseTx.fromBody('tx-4', {
        'type': 'income',
        'amountRial': 25000000,
        'date': '2026-10-14T12:30:00',
        'note': 'Salary',
        'futureField': {'by': 'a later version'},
      });
      expect(tx.valid, isTrue);
      expect(tx.amountRial, 25000000);
      expect(tx.source!['futureField'], {'by': 'a later version'});
      expect(tx.toBody()['schema'], 3);
      expect(tx.toBody()['amountRial'], 25000000);
      expect(tx.toBody().containsKey('amount'), isFalse);
      expect(tx.toBody().containsKey('currency'), isFalse);
    });
  });

  group('budgets', () {
    test('a 2.1.x budget opens as the month it named', () {
      final budget = ExpenseBudget.fromBody('budget-2026-10-all-IRR', {
        'month': '2026-10',
        'currency': 'IRR',
        'amount': 500000000,
        'schema': 2,
      });
      expect(budget, isNotNull);
      expect(budget!.start, '2026-10-01');
      expect(budget.amountRial, 5000000);
      expect(budget.categoryId, isNull);
    });

    test('a budget keeps its month’s first civil day, and its id follows', () {
      const budget = ExpenseBudget(
        start: '2026-10-23',
        categoryId: 'cat-groceries',
        amountRial: 20000000,
      );
      expect(budget.toBody()['start'], '2026-10-23');
      expect(budget.toBody().containsKey('month'), isFalse);
      expect(budget.id, 'budget-2026-10-23-cat-groceries');
      final read = ExpenseBudget.fromBody(budget.id, budget.toBody());
      expect(read!.amountRial, 20000000);
      expect(read.start, '2026-10-23');
    });

    test('a malformed budget is not a budget', () {
      expect(
        ExpenseBudget.fromBody('b', {'start': '2026-02-30', 'amountRial': 5}),
        isNull,
      );
      expect(
        ExpenseBudget.fromBody('b', {'start': '2026-10-01', 'amountRial': -5}),
        isNull,
      );
      expect(
        ExpenseBudget.fromBody('b', {
          'start': '2026-10-01',
          'amountRial': 5,
          'currency': 'USD',
        }),
        isNull,
      );
    });
  });

  group('templates', () {
    test('a recurring template keeps its day and the calendar it is in', () {
      const template = ExpenseTemplate(
        id: 'tpl-1',
        label: 'Rent',
        type: 'expense',
        amountRial: 120000000,
        categoryId: 'cat-rent',
        day: 5,
        calendar: 'jalali',
      );
      final body = template.toBody();
      expect(body['amountRial'], 120000000);
      expect(body['day'], 5);
      expect(body['calendar'], 'jalali');
      final read = ExpenseTemplate.fromBody('tpl-1', body)!;
      expect(read.isRecurring, isTrue);
      expect(read.solar, isTrue);
      expect(read.day, 5);
    });

    test('a plain template has no day, and an impossible one is no day', () {
      final plain = ExpenseTemplate.fromBody('tpl-2', {
        'label': 'Coffee',
        'type': 'expense',
        'amountRial': 500000,
      })!;
      expect(plain.isRecurring, isFalse);
      final odd = ExpenseTemplate.fromBody('tpl-3', {
        'label': 'Coffee',
        'type': 'expense',
        'amountRial': 500000,
        'day': 40,
      })!;
      expect(odd.isRecurring, isFalse);
    });

    test('a 2.1.x template converts its rial amount once', () {
      final read = ExpenseTemplate.fromBody('tpl-4', {
        'label': 'Internet',
        'type': 'expense',
        'amount': 4500000,
        'currency': 'IRR',
      })!;
      expect(read.amountRial, 45000);
      expect(
        ExpenseTemplate.fromBody('tpl-5', {
          'label': 'Dollars',
          'type': 'expense',
          'amount': 100,
          'currency': 'USD',
        }),
        isNull,
      );
    });
  });

  test('the built-in categories are an Iranian household’s, without loss', () {
    expect(defaultExpenseCategoryIds, contains('cat-groceries'));
    expect(defaultExpenseCategoryIds, contains('cat-rent'));
    expect(defaultExpenseCategoryIds, contains('cat-bills'));
    expect(defaultExpenseCategoryIds, contains('cat-transport'));
    expect(defaultExpenseCategoryIds, contains('cat-health'));
    expect(defaultExpenseCategoryIds, contains('cat-children'));
    expect(defaultExpenseCategoryIds, contains('cat-gifts'));
    // The older ids stay, so a payment written with one keeps its category.
    expect(defaultExpenseCategoryIds, contains('cat-food'));
    expect(
      defaultExpenseCategoryIds.toSet().length,
      defaultExpenseCategoryIds.length,
    );
  });

  test('a month’s identity is its first civil day, in either calendar', () {
    final gregorian = NexModuleMonth(false, 2026, 10);
    expect(monthStartIso(gregorian), '2026-10-01');
    // Aban 1405 runs from 23 October to 21 November 2026.
    final first = NexModuleMonth.of(DateTime(2026, 10, 25), solar: true);
    final second = NexModuleMonth.of(DateTime(2026, 11, 10), solar: true);
    expect(monthStartIso(first), monthStartIso(second));
    expect(first.year, 1405);
    expect(isoDay(first.first), monthStartIso(first));
  });
}
