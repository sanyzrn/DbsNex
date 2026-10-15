import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/price_lens/rational.dart';
import 'package:nex_client/modules/price_lens/options.dart';
import 'package:nex_client/modules/price_lens/comparison.dart';
import 'package:nex_client/modules/price_lens/units.dart';
import 'package:nex_client/modules/price_lens/money.dart';

void main() {
  PriceOption offer({
    int price = 1000,
    Fraction quantity = const Fraction(1),
    String unit = 'kg',
    String currency = 'USD',
    int received = 1,
    int? paid,
    DiscountKind discount = DiscountKind.none,
    int? percent,
    int? fixed,
    int? shipping,
    DateTime? date,
  }) => PriceOption(
    id: 'o',
    label: 'Rice',
    priceMinor: price,
    currency: currency,
    quantity: quantity,
    unitKey: unit,
    packageCount: received,
    paidCount: paid,
    discount: discount,
    discountPercent: percent,
    discountMinor: fixed,
    shippingMinor: shipping,
    date: date,
  );
  test('BigInt cross products cannot overflow or reverse ordering', () {
    final huge = Fraction.exact(
      BigInt.parse('999999999999999999999999999999'),
      BigInt.from(3),
    );
    expect(
      huge * const Fraction(3),
      Fraction.exact(
        BigInt.parse('999999999999999999999999999999'),
        BigInt.one,
      ),
    );
    expect(huge > const Fraction(priceMax), isTrue);
    final a = offer(
      price: priceMax,
      quantity: const Fraction(1, 1000),
      unit: 'oz',
    );
    final b = offer(
      price: priceMax - 1,
      quantity: const Fraction(1, 1000),
      unit: 'oz',
    );
    final result = compareOptions([a, b], priceUnitOf('kg')!);
    expect(result.state, ComparisonState.ready);
    expect(result.bestIndex, 1);
    expect(
      result.results.first.unitPriceMinor!.exactNumerator,
      greaterThan(BigInt.from(priceMax)),
    );
  });
  test('negative denominator normalization, hash and zero denominator', () {
    expect(const Fraction(1, -2) < const Fraction(0), isTrue);
    expect(const Fraction(1, -2).hashCode, const Fraction(-1, 2).hashCode);
    expect(const Fraction(1, -2).toDecimalString(), '-0.5');
    expect(() => const Fraction(1) / const Fraction(0), throwsArgumentError);
  });
  test(
    'Unicode plain decimals and tiny grams are valid; punctuation is not',
    () {
      expect(fractionFromDecimal('۰٫۱۲۵'), const Fraction(1, 8));
      expect(fractionFromDecimal('١٫٥'), const Fraction(3, 2));
      expect(fractionFromDecimal('.'), isNull);
      expect(fractionFromDecimal('1e3'), isNull);
      expect(
        optionSafe(offer(quantity: const Fraction(1, 1000), unit: 'g')),
        isTrue,
      );
      expect(
        optionSafe(offer(quantity: const Fraction(1, 2), unit: 'piece')),
        isFalse,
      );
    },
  );
  test(
    'bundle total is discounted once, shipping added once, received used',
    () {
      final o = offer(
        price: 2000,
        received: 3,
        paid: 2,
        discount: DiscountKind.percent,
        percent: 10,
        shipping: 100,
      );
      expect(effectivePriceMinor(o), const Fraction(1900));
      expect(totalQuantityIn(o, priceUnitOf('kg')!), const Fraction(3));
      expect(
        PriceOption.fromBody('o', {...o.toBody(), 'paidCount': 4}).valid,
        isFalse,
      );
    },
  );
  test('fixed discount over price and stacked records are invalid', () {
    expect(
      optionSafe(offer(discount: DiscountKind.fixed, fixed: 1001)),
      isFalse,
    );
    expect(
      PriceOption.fromBody('o', {
        ...offer().toBody(),
        'discount': 'percent',
        'discountPercent': 10,
        'discountMinor': 1,
      }).valid,
      isFalse,
    );
    expect(
      PriceOption.fromBody('o', {
        ...offer().toBody(),
        'discount': 'mystery',
      }).valid,
      isFalse,
    );
    expect(
      PriceOption.fromBody('o', {
        ...offer().toBody(),
        'shippingMinor': -1,
      }).valid,
      isFalse,
    );
  });
  test('malformed precision and dates never normalize silently', () {
    for (final field in [
      {'quantityDen': 0},
      {'quantityDen': '1'},
      {'quantity': -1},
      {'currency_exponent': 3},
      {'currency': 'ZZZ', 'currency_code': 'ZZZ'},
      {'date': '2026-02-30T00:00:00'},
    ]) {
      expect(
        PriceOption.fromBody('o', {...offer().toBody(), ...field}).valid,
        isFalse,
      );
    }
    expect(priceCalendar('2024-02-29T23:00:00-12:00'), DateTime(2024, 2, 29));
  });
  test('mixed families and five offers cannot claim a cheapest choice', () {
    expect(
      compareOptions([offer(), offer(unit: 'l')], priceUnitOf('kg')!).state,
      ComparisonState.mixedFamilies,
    );
    expect(
      compareOptions(
        List.generate(5, (_) => offer()),
        priceUnitOf('kg')!,
      ).state,
      ComparisonState.tooFewOptions,
    );
  });
  test('currency precision and zero minor amounts are explicit', () {
    expect(parsePriceAmount('۱۲٫۳۴۵', priceCurrencyOf('KWD')!).minor, 12345);
    expect(
      parsePriceAmount('1.1', priceCurrencyOf('JPY')!).error,
      PriceAmountError.tooPrecise,
    );
    expect(parseTomanPrice('۰').minor, 0);
    expect(optionSafe(offer(price: 0)), isTrue);
    expect(offer().toBody()['currency_exponent'], 2);
  });
  test('display marks only truncated values and never trims integer zeros', () {
    expect(
      formatMinorFraction(const Fraction(1250), 2, persian: false),
      '12.5',
    );
    expect(
      formatMinorFraction(const Fraction(1, 3), 2, persian: false),
      '≈0.0033',
    );
    expect(
      formatMinorFraction(const Fraction(1000000000000000), 0, persian: false),
      '1,000,000,000,000,000',
    );
  });
  test(
    'normalized same spec and strictly earlier dates define memory match',
    () {
      final o = offer(
        quantity: const Fraction(3, 4),
        date: DateTime(2026, 10, 14),
      );
      PriceMemory m(String id, DateTime date, {String label = '  RICE  '}) =>
          PriceMemory(
            id: id,
            label: label,
            priceMinor: 1000,
            currency: 'USD',
            quantity: const Fraction(750),
            unitKey: 'g',
            date: date,
          );
      final old = m('old', DateTime(2026, 10, 1));
      expect(
        memoryMatchFor(o, [
          old,
          m('today', DateTime(2026, 10, 14)),
          m('future', DateTime(2027)),
        ])!.id,
        'old',
      );
      expect(
        memoryMatchFor(o, [
          m('other', DateTime(2026, 10, 1), label: 'Different'),
        ]),
        isNull,
      );
    },
  );
  test(
    'fractional paid memory survives serialization without rounding loss',
    () {
      final o = offer(price: 1, discount: DiscountKind.percent, percent: 50);
      final paid = effectivePriceMinor(o);
      final m = PriceMemory(
        id: 'm',
        label: 'Rice',
        priceMinor: paid.roundHalfUp(),
        paidFraction: paid,
        currency: 'USD',
        quantity: const Fraction(1),
        unitKey: 'kg',
        date: DateTime(2026, 10, 1),
      );
      final read = PriceMemory.fromBody('m', m.toBody())!;
      expect(read.exactPaid, const Fraction(1, 2));
      expect(memoryDifference(o, read), const Fraction(0));
    },
  );
  test(
    'unknown/empty/oversized histories and malformed saved rows are refused',
    () {
      final m = PriceMemory(
        id: 'm',
        label: 'Rice',
        priceMinor: 100,
        currency: 'USD',
        quantity: const Fraction(1),
        unitKey: 'kg',
        date: DateTime(2026, 10, 1),
      );
      expect(PriceMemory.fromBody('m', {...m.toBody(), 'label': ' '}), isNull);
      expect(
        PriceMemory.fromBody('m', {
          ...m.toBody(),
          'paid_num': '1',
          'paid_den': '0',
        }),
        isNull,
      );
      expect(
        SavedComparison.fromBody('c', {
          'date': '2026-10-14',
          'options': List.filled(5, offer().toBody()),
        }),
        isNull,
      );
    },
  );
}
