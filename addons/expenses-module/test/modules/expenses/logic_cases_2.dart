part of 'logic_test.dart';

void _logicCases2() {
  group('defensive record reading', () {
    test('a good body round-trips', () {
      final original = tx(
        'round',
        DateTime(2026, 10, 13, 14, 30),
        note: 'a note',
        merchant: 'a shop',
        account: 'cash',
      );
      final body = original.toBody();
      expect(body['schema'], 2);
      final read = ExpenseTx.fromBody('round', body);
      expect(read.valid, isTrue);
      expect(read.id, 'round');
      expect(read.amount, original.amount);
      expect(read.currency, 'IRR');
      expect(read.date, original.date);
      expect(read.note, 'a note');
      expect(read.merchant, 'a shop');
      expect(read.account, 'cash');
      expect(read.categoryId, 'cat-food');
    });

    test('malformed bodies become incomplete records, not crashes', () {
      final noType = ExpenseTx.fromBody('1', {
        'amount': 5,
        'currency': 'IRR',
        'date': '2026-10-01T00:00:00',
      });
      expect(noType.valid, isFalse);
      expect(noType.type, 'expense');
      final badAmount = ExpenseTx.fromBody('2', {
        'type': 'expense',
        'amount': 'x',
        'currency': 'IRR',
        'date': '2026-10-01T00:00:00',
      });
      expect(badAmount.valid, isFalse);
      final noDate = ExpenseTx.fromBody('3', {
        'type': 'expense',
        'amount': 5,
        'currency': 'IRR',
      });
      expect(noDate.valid, isFalse);
      final badDate = ExpenseTx.fromBody('4', {
        'type': 'expense',
        'amount': 5,
        'currency': 'IRR',
        'date': 'not a date',
      });
      expect(
        badDate.valid,
        isFalse,
      ); // a date that fails to parse is incomplete, not epoch
      expect(badDate.date, DateTime.fromMillisecondsSinceEpoch(0));
      final empty = ExpenseTx.fromBody('5', {});
      expect(empty.valid, isFalse);
      expect(empty.amount, 0);
    });

    test('budgets and templates refuse what they cannot hold', () {
      expect(
        ExpenseBudget.fromBody('x', {
          'month': '2026-10',
          'currency': 'IRR',
          'amount': 5,
        }),
        isNotNull,
      );
      expect(
        ExpenseBudget.fromBody('x', {
          'month': '2026-13',
          'currency': 'IRR',
          'amount': 5,
        }),
        isNull,
      );
      expect(
        ExpenseBudget.fromBody('x', {
          'month': '2026-1',
          'currency': 'IRR',
          'amount': 5,
        }),
        isNull,
      );
      expect(
        ExpenseBudget.fromBody('x', {
          'month': '2026-10',
          'currency': 'IRR',
          'amount': -5,
        }),
        isNull,
      );
      expect(
        ExpenseBudget.fromBody('x', {'month': '2026-10', 'currency': 'IRR'}),
        isNull,
      );
      expect(
        ExpenseTemplate.fromBody('t', {
          'label': 'Rent',
          'type': 'expense',
          'amount': 5,
          'currency': 'IRR',
        }),
        isNotNull,
      );
      expect(
        ExpenseTemplate.fromBody('t', {
          'label': 'Rent',
          'type': 'wrong',
          'amount': 5,
          'currency': 'IRR',
        }),
        isNull,
      );
      expect(
        ExpenseTemplate.fromBody('t', {
          'label': '',
          'type': 'expense',
          'amount': 5,
          'currency': 'IRR',
        }),
        isNull,
      );
      expect(
        ExpenseTemplate.fromBody('t', {
          'label': 'Rent',
          'type': 'expense',
          'amount': 0,
          'currency': 'IRR',
        }),
        isNull,
      );
    });

    test('custom categories read and write', () {
      final cat = ExpenseCategory.fromBody('c1', {'label': '  Coffee  '});
      expect(cat!.label, 'Coffee');
      expect(ExpenseCategory.fromBody('c2', {'label': '  '}), isNull);
      expect(ExpenseCategory.fromBody('c3', {}), isNull);
      expect(cat.toBody()['label'], 'Coffee');
      expect(defaultExpenseCategoryIds, contains('cat-other'));
      expect(
        defaultExpenseCategoryIds.toSet(),
        hasLength(defaultExpenseCategoryIds.length),
      );
    });
  });
}
