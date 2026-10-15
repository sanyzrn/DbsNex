import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/expenses/money.dart';

/// The money layer: ISO 4217 minor units, integer-only, per-currency
/// rules, rial/toman entry, and formatting in both digit systems.
void main() {
  group('the currency catalogue', () {
    test('exponents follow ISO 4217', () {
      final byCode = {for (final c in expenseCurrencies) c.code: c};
      expect(byCode['JPY']!.exponent, 0);
      expect(byCode['KWD']!.exponent, 3);
      expect(byCode['USD']!.exponent, 2);
      expect(byCode['EUR']!.exponent, 2);
      expect(byCode['IRR']!.exponent, 2);
    });

    test('lookup and defensive exponent', () {
      expect(expenseCurrencyOf('IRR')!.code, 'IRR');
      expect(expenseCurrencyOf('XYZ'), isNull);
      // The catalogue wins over a stored exponent that disagrees.
      expect(expenseExponentOf('JPY', 2), 0);
      expect(expenseExponentOf('JPY', null), 0);
      // Unknown code with a sane stored exponent keeps it.
      expect(expenseExponentOf('BHD', 3), 3);
      expect(expenseExponentOf('BHD', 'x'), 2);
      expect(expenseExponentOf(null, 99), 2);
    });

    test('names exist in both languages', () {
      for (final c in expenseCurrencies) {
        expect(c.nameEn.trim(), isNotEmpty);
        expect(c.nameFa.trim(), isNotEmpty);
        expect(c.code, matches(RegExp(r'^[A-Z]{3}$')));
      }
    });
  });

  group('parsing amounts', () {
    final irr = expenseCurrencyOf('IRR')!;
    final usd = expenseCurrencyOf('USD')!;
    final jpy = expenseCurrencyOf('JPY')!;
    final kwd = expenseCurrencyOf('KWD')!;

    test('whole and decimal rials', () {
      expect(parseExpenseAmount('1250', irr).minor, 125000);
      expect(parseExpenseAmount('1250.5', irr).minor, 125050);
      expect(parseExpenseAmount('1250.50', irr).minor, 125050);
      expect(parseExpenseAmount('0.01', irr).minor, 1);
      // A comma is accepted as a decimal separator, not grouping.
      expect(parseExpenseAmount('1250,5', irr).minor, 125050);
    });

    test('tomans: one toman is 10 rials is 1000 minor units', () {
      expect(parseTomanAmount('12').minor, 12000);
      expect(parseTomanAmount('12.5').minor, 12500);
      expect(parseTomanAmount('12.55').minor, 12550);
      // The dinar is the floor: a thousandth of a toman.
      expect(parseTomanAmount('12.555').minor, 12555);
      expect(parseTomanAmount('12.5555').error, ExpenseAmountError.tooPrecise);
    });

    test('precision is refused, never rounded', () {
      expect(
        parseExpenseAmount('12.5', jpy).error,
        ExpenseAmountError.tooPrecise,
      );
      expect(
        parseExpenseAmount('12.5555', usd).error,
        ExpenseAmountError.tooPrecise,
      );
      expect(
        parseExpenseAmount('12.5555', kwd).error,
        ExpenseAmountError.tooPrecise,
      );
      // Exactly at the exponent is fine.
      expect(parseExpenseAmount('12.555', kwd).minor, 12555);
    });

    test('junk is refused', () {
      expect(parseExpenseAmount('', usd).error, ExpenseAmountError.empty);
      expect(parseExpenseAmount('   ', usd).error, ExpenseAmountError.empty);
      expect(
        parseExpenseAmount('abc', usd).error,
        ExpenseAmountError.notANumber,
      );
      expect(parseExpenseAmount('-5', usd).error, ExpenseAmountError.negative);
      expect(
        parseExpenseAmount('+5', usd).error,
        ExpenseAmountError.notANumber,
      );
      expect(
        parseExpenseAmount('1 000', usd).error,
        ExpenseAmountError.notANumber,
      );
      expect(
        parseExpenseAmount('1.2.3', usd).error,
        ExpenseAmountError.notANumber,
      );
      expect(
        parseExpenseAmount('12,5,5', irr).error,
        ExpenseAmountError.notANumber,
      );
      expect(
        parseExpenseAmount('1e5', usd).error,
        ExpenseAmountError.notANumber,
      );
      expect(parseExpenseAmount('٥', usd).minor, 500);
    });

    test('zero and magnitude bounds', () {
      expect(parseExpenseAmount('0', usd).error, ExpenseAmountError.zero);
      expect(parseExpenseAmount('0.00', usd).error, ExpenseAmountError.zero);
      expect(parseTomanAmount('0').error, ExpenseAmountError.zero);
      // The bound is on minor units: JPY's exponent is 0, so the
      // bound itself is writable in yen.
      expect(
        parseExpenseAmount('1000000000000000', jpy).minor,
        expenseAmountMax,
      );
      expect(
        parseExpenseAmount('1000000000000001', jpy).error,
        ExpenseAmountError.tooLarge,
      );
      expect(
        parseExpenseAmount('10000000000000000', usd).error,
        ExpenseAmountError.tooLarge,
      );
      expect(expenseAmountInRange(expenseAmountMax), isTrue);
      expect(expenseAmountInRange(expenseAmountMax + 1), isFalse);
      expect(expenseAmountInRange(0), isFalse);
    });
  });

  group('formatting', () {
    test('grouped, code-bearing, in both digit systems', () {
      final irr = expenseCurrencyOf('IRR')!;
      expect(formatExpenseNumber(125000, 2, persian: false), '1,250');
      expect(formatExpenseNumber(125050, 2, persian: false), '1,250.5');
      expect(formatExpenseNumber(12550, 2, persian: false), '125.5');
      expect(formatExpenseNumber(12555, 2, persian: false), '125.55');
      expect(formatExpenseNumber(1200, 0, persian: false), '1,200');
      expect(formatExpenseNumber(12555, 3, persian: false), '12.555');
      // Negative and signed forms.
      expect(formatExpenseNumber(-125000, 2, persian: false), '−1,250');
      expect(
        formatExpenseNumber(125000, 2, persian: false, signed: true),
        '+1,250',
      );
      expect(formatExpenseNumber(-1250, 2, persian: false), '−12.5');
      expect(formatExpenseNumber(0, 2, persian: false), '0');
      // Persian digits and the Arabic thousands separator.
      expect(formatExpenseNumber(125000, 2, persian: true), '۱٬۲۵۰');
      expect(groupDigits('1250000', persian: true), '۱٬۲۵۰٬۰۰۰');
      expect(groupDigits('1250000', persian: false), '1,250,000');
      expect(persianDigits('a1b2'), 'a۱b۲');
      expect(irr.code, 'IRR');
    });

    test('tomans are exact to three decimals', () {
      expect(formatTomanNumber(1250500, persian: false), '1,250.5');
      expect(formatTomanNumber(12000, persian: false), '12');
      expect(formatTomanNumber(1, persian: false), '0.001');
      expect(formatTomanNumber(12555, persian: false), '12.555');
      expect(
        formatTomanNumber(12550, persian: true),
        '۱۲.۵۵'.replaceAll('۵۵', '۵۵'),
      );
    });

    test('the editor round-trips through majorTextOfMinor', () {
      String roundTrip(int minor, int exponent) => parseExpenseAmount(
        majorTextOfMinor(minor, exponent),
        expenseCurrencyOf('USD')!,
      ).minor.toString();
      expect(majorTextOfMinor(1255, 2), '12.55');
      expect(majorTextOfMinor(1250, 2), '12.5');
      expect(majorTextOfMinor(1200, 2), '12');
      expect(majorTextOfMinor(1200, 0), '1200');
      expect(majorTextOfMinor(1, 2), '0.01');
      expect(roundTrip(1255, 2), '1255');
      expect(roundTrip(1250, 2), '1250');
      expect(roundTrip(1200, 2), '1200');
    });
  });

  group('integer percentages', () {
    test('half-up, clamped, zero-safe', () {
      expect(expensePercentOf(0, 100), 0);
      expect(expensePercentOf(50, 0), 0);
      expect(expensePercentOf(50, 100), 50);
      expect(expensePercentOf(1, 3), 33);
      expect(expensePercentOf(2, 3), 67);
      expect(expensePercentOf(349, 1000), 35);
      expect(expensePercentOf(1000, 1000), 100);
      expect(expensePercentOf(1001, 1000), 100);
    });
  });
}
