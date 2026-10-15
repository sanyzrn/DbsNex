part of 'lens_test.dart';

void _lensCases1() {
  group('Fraction', () {
    test('equality is cross-multiplication, not field equality', () {
      expect(const Fraction(3, 4), const Fraction(6, 8));
      expect(const Fraction(3, 4) == const Fraction(7, 8), isFalse);
      expect(const Fraction(-1, 2) == const Fraction(1, -2), isTrue);
    });

    test('comparison and arithmetic are exact', () {
      expect(const Fraction(1, 2) < const Fraction(2, 3), isTrue);
      expect(const Fraction(1, 3) + const Fraction(1, 6), const Fraction(1, 2));
      expect(const Fraction(1, 3) * const Fraction(3, 1), const Fraction(1));
      expect(const Fraction(1, 2) / const Fraction(1, 4), const Fraction(2));
    });

    test('decimal strings are exact or visibly truncated', () {
      expect(const Fraction(3, 4).toDecimalString(), '0.75');
      expect(const Fraction(750).toDecimalString(), '750');
      expect(const Fraction(1, 3).toDecimalString(digits: 4), '0.3333');
      expect(const Fraction(-3, 2).toDecimalString(), '-1.5');
    });

    test('roundHalfUp rounds halves away from zero', () {
      expect(const Fraction(1, 2).roundHalfUp(), 1);
      expect(const Fraction(3, 2).roundHalfUp(), 2);
      expect(const Fraction(-1, 2).roundHalfUp(), -1);
      expect(const Fraction(5, 4).roundHalfUp(), 1);
    });

    test('decimal parsing: commas, trailing zeros, refusals', () {
      expect(fractionFromDecimal('0.75'), const Fraction(3, 4));
      expect(fractionFromDecimal('0.750'), const Fraction(3, 4));
      expect(fractionFromDecimal('12,5'), const Fraction(25, 2));
      expect(fractionFromDecimal('750'), const Fraction(750));
      expect(fractionFromDecimal(' 1.5 '), const Fraction(3, 2));
      expect(fractionFromDecimal(''), isNull);
      expect(fractionFromDecimal('-1'), isNull);
      expect(fractionFromDecimal('abc'), isNull);
      expect(fractionFromDecimal('1.2.3'), isNull);
      expect(fractionFromDecimal('1e5'), isNull);
      expect(fractionFromDecimal('1234567890123456'), isNull); // 16 digits
      expect(
        fractionFromDecimal('123456789012345')!.numerator,
        123456789012345,
      );
    });
  });

  group('units', () {
    test('mass and volume convert exactly, by family', () {
      expect(
        convertQuantity(
          const Fraction(750),
          priceUnitOf('g')!,
          priceUnitOf('kg')!,
        ),
        const Fraction(3, 4),
      );
      expect(
        convertQuantity(
          const Fraction(3, 4),
          priceUnitOf('kg')!,
          priceUnitOf('g')!,
        ),
        const Fraction(750),
      );
      expect(
        convertQuantity(
          const Fraction(1),
          priceUnitOf('l')!,
          priceUnitOf('ml')!,
        ),
        const Fraction(1000),
      );
      expect(
        convertQuantity(
          const Fraction(16),
          priceUnitOf('oz')!,
          priceUnitOf('lb')!,
        ),
        const Fraction(1),
      );
      expect(
        convertQuantity(
          const Fraction(1),
          priceUnitOf('lb')!,
          priceUnitOf('oz')!,
        ),
        const Fraction(16),
      );
      // 1 US fl oz = 29.5735295625 ml exactly.
      expect(
        convertQuantity(
          const Fraction(1),
          priceUnitOf('floz')!,
          priceUnitOf('ml')!,
        )?.toDecimalString(digits: 10),
        '29.5735295625',
      );
    });

    test('different families never convert', () {
      expect(
        convertQuantity(
          const Fraction(1),
          priceUnitOf('g')!,
          priceUnitOf('ml')!,
        ),
        isNull,
      );
      expect(
        convertQuantity(
          const Fraction(1),
          priceUnitOf('l')!,
          priceUnitOf('kg')!,
        ),
        isNull,
      );
      expect(
        convertQuantity(
          const Fraction(1),
          priceUnitOf('piece')!,
          priceUnitOf('g')!,
        ),
        isNull,
      );
    });

    test('the family lists and canonical units', () {
      expect(unitsOfFamily(UnitFamily.mass).map((u) => u.key), [
        'g',
        'kg',
        'oz',
        'lb',
      ]);
      expect(unitsOfFamily(UnitFamily.volume).map((u) => u.key), [
        'ml',
        'l',
        'floz',
      ]);
      expect(unitsOfFamily(UnitFamily.piece).map((u) => u.key), ['piece']);
      expect(canonicalUnitOf(UnitFamily.mass).key, 'kg');
      expect(canonicalUnitOf(UnitFamily.volume).key, 'l');
      expect(priceUnitOf('kg')!.decimals, 3);
      expect(priceUnitOf('g')!.decimals, 3);
    });
  });

  group('money', () {
    final usd = priceCurrencyOf('USD')!;
    final kwd = priceCurrencyOf('KWD')!;
    final jpy = priceCurrencyOf('JPY')!;
    final irr = priceCurrencyOf('IRR')!;

    test('parses to integer minor units at each exponent', () {
      expect(parsePriceAmount('12.5', usd).minor, 1250);
      expect(parsePriceAmount('12.50', usd).minor, 1250);
      expect(parsePriceAmount('0.05', usd).minor, 5);
      expect(parsePriceAmount('12.345', kwd).minor, 12345);
      expect(parsePriceAmount('1500', jpy).minor, 1500);
      expect(parsePriceAmount('0.05', irr).minor, 5);
      expect(parsePriceAmount('1,5', usd).minor, 150); // comma as decimal
    });

    test('tomans enter at exponent 3 against the rial minor unit', () {
      expect(parseTomanPrice('25').minor, 25000);
      expect(parseTomanPrice('1.5').minor, 1500);
      expect(parseTomanPrice('0.0005').error, PriceAmountError.tooPrecise);
    });

    test('refusals are named', () {
      expect(parsePriceAmount('', usd).error, PriceAmountError.empty);
      expect(parsePriceAmount('0', usd).minor, 0);
      expect(parsePriceAmount('-5', usd).error, PriceAmountError.notANumber);
      expect(parsePriceAmount('abc', usd).error, PriceAmountError.notANumber);
      expect(parsePriceAmount('1.2.3', usd).error, PriceAmountError.notANumber);
      expect(
        parsePriceAmount('12.345', usd).error,
        PriceAmountError.tooPrecise,
      );
      expect(
        parsePriceAmount('10000000000000000', jpy).error,
        PriceAmountError.tooLarge,
      );
      // The ceiling itself is allowed; one minor unit more is not.
      expect(parsePriceAmount('1000000000000000', jpy).minor, priceMax);
      expect(
        parsePriceAmount('1000000000000000', usd).error,
        PriceAmountError.tooLarge,
      );
    });

    test('display formats: grouping, Persian digits, major prefill', () {
      expect(formatPriceNumber(1250, 2, persian: false), '12.5');
      expect(formatPriceNumber(125000, 2, persian: true), '۱٬۲۵۰');
      expect(formatPriceNumber(5, 0, persian: false), '5');
      expect(formatPriceNumber(500000000, 0, persian: false), '500,000,000');
      expect(formatPriceNumber(-1250, 2, persian: false), '−12.5');
      expect(priceMajorText(1250, 2), '12.5');
      expect(priceMajorText(5, 0), '5');
      expect(priceMajorText(105, 2), '1.05');
      expect(priceExponentOf('JPY'), 0);
      expect(priceExponentOf('KWD'), 3);
      expect(priceExponentOf('XXX'), 2); // defended default
    });
  });
}
