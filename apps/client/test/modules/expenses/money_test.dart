import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/expenses/money.dart';
import 'package:nex_client/modules/expenses/money_input.dart';

/// Money is whole rials, said in tomans or rials: what a person types in
/// either script, what the field groups while they type, and what every
/// screen then prints — all exact, never floating point, never rounded.
void main() {
  group('typed amounts', () {
    test('tomans are ten rials, and a tenth of a toman is one rial', () {
      expect(parseExpenseAmount('1250000', ExpenseUnit.toman).rials, 12500000);
      expect(parseExpenseAmount('12.5', ExpenseUnit.toman).rials, 125);
      expect(parseExpenseAmount('0.1', ExpenseUnit.toman).rials, 1);
      expect(parseExpenseAmount('12750000', ExpenseUnit.rial).rials, 12750000);
    });

    test('Persian, Arabic and Latin digits all read the same', () {
      expect(parseExpenseAmount('۱۲٬۵۰۰', ExpenseUnit.toman).rials, 125000);
      expect(parseExpenseAmount('١٢٥٠٠', ExpenseUnit.toman).rials, 125000);
      expect(parseExpenseAmount('۱۲۵۰', ExpenseUnit.rial).rials, 1250);
    });

    test('grouping is layout, and a trailing zero in the fraction is free', () {
      expect(parseExpenseAmount('1,250,000', ExpenseUnit.rial).rials, 1250000);
      expect(parseExpenseAmount('1 250 000', ExpenseUnit.rial).rials, 1250000);
      expect(parseExpenseAmount('1.50', ExpenseUnit.toman).rials, 15);
      expect(parseExpenseAmount('1٫5', ExpenseUnit.toman).rials, 15);
    });

    test('a rial has no smaller part, and nothing is silently rounded', () {
      expect(
        parseExpenseAmount('12.5', ExpenseUnit.rial).error,
        ExpenseAmountError.tooPrecise,
      );
      expect(
        parseExpenseAmount('0.09', ExpenseUnit.toman).error,
        ExpenseAmountError.tooPrecise,
      );
    });

    test(
      'empty, negative, zero, letters and the bound are refused by name',
      () {
        expect(
          parseExpenseAmount('', ExpenseUnit.toman).error,
          ExpenseAmountError.empty,
        );
        expect(
          parseExpenseAmount('-5', ExpenseUnit.toman).error,
          ExpenseAmountError.negative,
        );
        expect(
          parseExpenseAmount('−5', ExpenseUnit.toman).error,
          ExpenseAmountError.negative,
        );
        expect(
          parseExpenseAmount('0', ExpenseUnit.toman).error,
          ExpenseAmountError.zero,
        );
        expect(
          parseExpenseAmount('0', ExpenseUnit.toman, allowZero: true).rials,
          0,
        );
        expect(
          parseExpenseAmount('12a', ExpenseUnit.toman).error,
          ExpenseAmountError.notANumber,
        );
        expect(
          parseExpenseAmount('1e6', ExpenseUnit.toman).error,
          ExpenseAmountError.notANumber,
        );
        expect(
          parseExpenseAmount('9999999999999999', ExpenseUnit.toman).error,
          ExpenseAmountError.tooLarge,
        );
      },
    );

    test('the field’s own text round-trips exactly', () {
      for (final rials in [1, 9, 10, 125, 120, 1250000, expenseAmountMax]) {
        for (final unit in ExpenseUnit.values) {
          if (unit == ExpenseUnit.rial && rials % 10 != 0) continue;
          final text = expenseAmountInput(rials, unit);
          expect(parseExpenseAmount(text, unit).rials, rials, reason: text);
        }
      }
      expect(expenseAmountInput(125, ExpenseUnit.toman), '12.5');
      expect(expenseAmountInput(120, ExpenseUnit.toman), '12');
      expect(expenseAmountInput(1250, ExpenseUnit.rial), '1250');
    });
  });

  group('grouping as typed', () {
    test('groups threes and keeps the caret where it was', () {
      final grouped = groupAmountEdit('1250000', 7, 0);
      expect(grouped.text, '1,250,000');
      expect(grouped.caret, 9);
    });

    test('Persian digits and separators on the Persian side', () {
      expect(groupAmountEdit('1250000', 7, 0, persian: true).text, '۱٬۲۵۰٬۰۰۰');
      expect(groupAmountEdit('12.5', 4, 1, persian: true).text, '۱۲٫۵');
    });

    test('letters are dropped, not turned into money', () {
      expect(groupAmountEdit('12a5', 4, 1).text, '125');
      expect(groupAmountEdit('007', 3, 0).text, '7');
      expect(groupAmountEdit('1.2.3', 5, 1).text, '1.2');
    });

    test('a rial field refuses a separator by dropping it', () {
      expect(groupAmountEdit('12.5', 4, 0).text, '125');
    });
  });

  group('saying an amount', () {
    test('states the total in the unit chosen, grouped', () {
      expect(
        formatExpenseAmount(12500000, ExpenseUnit.toman, persian: false),
        '1,250,000 tomans',
      );
      expect(
        formatExpenseAmount(12500000, ExpenseUnit.rial, persian: false),
        '12,500,000 rials',
      );
      expect(
        formatExpenseAmount(12500000, ExpenseUnit.toman, persian: true),
        '۱٬۲۵۰٬۰۰۰ تومان',
      );
      expect(
        formatExpenseAmount(1250, ExpenseUnit.rial, persian: true),
        '۱٬۲۵۰ ریال',
      );
    });

    test('no empty decimals, and the toman’s tenth shows when it carries', () {
      expect(
        formatExpenseNumber(12000000, ExpenseUnit.toman, persian: false),
        '1,200,000',
      );
      expect(
        formatExpenseNumber(125, ExpenseUnit.toman, persian: false),
        '12.5',
      );
      expect(
        formatExpenseNumber(-125, ExpenseUnit.toman, persian: false),
        '−12.5',
      );
      expect(
        formatExpenseNumber(
          125,
          ExpenseUnit.toman,
          persian: false,
          signed: true,
        ),
        '+12.5',
      );
    });
  });

  test('shares and bars are integer math', () {
    expect(expensePercentOf(BigInt.from(18), BigInt.from(100)), 18);
    expect(expensePercentOf(BigInt.from(0), BigInt.from(0)), 0);
    expect(expensePercentOf(BigInt.from(200), BigInt.from(100)), 100);
    expect(expenseProgress(BigInt.from(50), BigInt.from(100)), 0.5);
    expect(expenseProgress(BigInt.from(150), BigInt.from(100)), 1);
    expect(expenseProgress(BigInt.from(0), BigInt.from(0)), 0);
  });

  test('only whole rials in the module’s bounds are storable', () {
    expect(expenseAmountInRange(0), isFalse);
    expect(expenseAmountInRange(1), isTrue);
    expect(expenseAmountInRange(expenseAmountMax), isTrue);
    expect(expenseAmountInRange(expenseAmountMax + 1), isFalse);
  });
}
