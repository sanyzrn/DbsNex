part of 'lens_test.dart';

void _lensCases2() {
  group('the comparison', () {
    test('2 × 500ml against 1L, in litres', () {
      final twoBy500 = offer(
        'a',
        10000,
        quantity: const Fraction(500),
        unit: 'ml',
        packageCount: 2,
      );
      final oneLitre = offer(
        'b',
        12000,
        quantity: const Fraction(1),
        unit: 'l',
      );
      final result = compareOptions([twoBy500, oneLitre], priceUnitOf('l')!);
      expect(result.state, ComparisonState.ready);
      expect(result.currency, 'IRR');
      expect(result.results.first.unitPriceMinor, const Fraction(10000));
      expect(result.results.last.unitPriceMinor, const Fraction(12000));
      expect(result.results.first.isBest, isTrue);
      expect(result.results.last.isBest, isFalse);
    });

    test('750g against 1kg: the cheaper-looking bag is dearer per kg', () {
      final bag750 = offer('a', 9000, quantity: const Fraction(750), unit: 'g');
      final bag1kg = offer('b', 11500, quantity: const Fraction(1), unit: 'kg');
      final result = compareOptions([bag750, bag1kg], priceUnitOf('kg')!);
      expect(result.results.first.unitPriceMinor, const Fraction(12000));
      expect(result.results.last.unitPriceMinor, const Fraction(11500));
      expect(result.bestUnitPrice, const Fraction(11500));
      expect(result.results.last.isBest, isTrue);
    });

    test('a 2+1 free beats the same two-pack at the same price', () {
      final threeForTwo = offer(
        'a',
        30000,
        unit: 'piece',
        packageCount: 3,
        paidCount: 2,
      );
      final single = offer('b', 11000, unit: 'piece');
      final result = compareOptions([
        threeForTwo,
        single,
      ], priceUnitOf('piece')!);
      expect(result.results.first.unitPriceMinor, const Fraction(10000));
      expect(result.results.first.isBest, isTrue);
      // Savings for the loser, per piece and for its amount.
      final savings = savingsOf(result.results.last, result.bestUnitPrice!);
      expect(savings!.perUnit, const Fraction(1000));
      expect(savings.forThisAmount, const Fraction(1000));
      expect(savingsOf(result.results.first, result.bestUnitPrice!), isNull);
    });

    test('one discount, applied exactly once; 0% and 100%', () {
      final ten = offer(
        'a',
        100000,
        discount: DiscountKind.percent,
        percent: 10,
      );
      expect(effectivePriceMinor(ten), const Fraction(90000));
      final zero = offer(
        'b',
        100000,
        discount: DiscountKind.percent,
        percent: 0,
      );
      expect(effectivePriceMinor(zero), const Fraction(100000));
      final all = offer(
        'c',
        100000,
        discount: DiscountKind.percent,
        percent: 100,
      );
      expect(effectivePriceMinor(all), const Fraction(0));
      final fixed = offer(
        'd',
        100000,
        discount: DiscountKind.fixed,
        fixedMinor: 20000,
      );
      expect(effectivePriceMinor(fixed), const Fraction(80000));
    });

    test('a fixed discount and an entered shipping share combine once', () {
      final option = offer(
        'a',
        100000,
        discount: DiscountKind.fixed,
        fixedMinor: 20000,
        shippingMinor: 5000,
      );
      expect(effectivePriceMinor(option), const Fraction(85000));
    });

    test('a fixed discount past the price is floored at zero, defensively', () {
      final handWritten = offer(
        'a',
        1000,
        discount: DiscountKind.fixed,
        fixedMinor: 9000,
      );
      expect(effectivePriceMinor(handWritten), const Fraction(0));
    });

    test('mixed currencies are refused, not converted', () {
      final result = compareOptions([
        offer('a', 100000, currency: 'IRR'),
        offer('b', 299, currency: 'USD'),
      ], priceUnitOf('kg')!);
      expect(result.state, ComparisonState.mixedCurrencies);
      expect(result.results, isEmpty);
    });

    test('mass against volume is not a question this module answers', () {
      final result = compareOptions([
        offer('a', 100, quantity: const Fraction(500), unit: 'ml'),
        offer('b', 100, quantity: const Fraction(500), unit: 'ml'),
      ], priceUnitOf('kg')!);
      expect(result.state, ComparisonState.mixedFamilies);
      expect(result.results.every((r) => r.notComparable), isTrue);
    });

    test('one stray offer in another family is marked, not hidden', () {
      final result = compareOptions([
        offer('a', 9000, quantity: const Fraction(750), unit: 'g'),
        offer('b', 8000, quantity: const Fraction(800), unit: 'g'),
        offer('c', 5000, quantity: const Fraction(1), unit: 'l'),
      ], priceUnitOf('kg')!);
      expect(result.state, ComparisonState.mixedFamilies);
      expect(result.results[2].notComparable, isTrue);
      expect(result.results[2].unitPriceMinor, isNull);
      expect(result.results[1].isBest, isFalse);
    });

    test('too few options, and an invalid offer, say so', () {
      expect(
        compareOptions([offer('a', 1)], priceUnitOf('kg')!).state,
        ComparisonState.tooFewOptions,
      );
      final broken = PriceOption.fromBody('x', {'label': '', 'price': -5});
      expect(broken.valid, isFalse);
      expect(
        compareOptions([offer('a', 1), broken], priceUnitOf('kg')!).state,
        ComparisonState.incompleteOption,
      );
    });

    test('ties are equals, both marked, never broken', () {
      final result = compareOptions([
        offer('a', 10000, quantity: const Fraction(500), unit: 'g'),
        offer('b', 20000, quantity: const Fraction(1000), unit: 'g'),
      ], priceUnitOf('g')!);
      expect(result.results.every((r) => r.isBest), isTrue);
      expect(result.bestUnitPrice, const Fraction(20));
    });

    test('huge prices and tiny quantities stay exact', () {
      final huge = offer(
        'a',
        priceMax,
        quantity: const Fraction(1),
        unit: 'piece',
      );
      final tiny = offer('b', 1, quantity: const Fraction(1, 1000), unit: 'g');
      final result = compareOptions([huge, tiny], priceUnitOf('piece')!);
      // g does not compare with pieces.
      expect(result.results[1].notComparable, isTrue);
      final mass = compareOptions([
        tiny,
        offer('c', 2000000, quantity: const Fraction(1), unit: 'kg'),
      ], priceUnitOf('g')!);
      expect(mass.results.first.unitPriceMinor, const Fraction(1000));
      expect(mass.results.last.unitPriceMinor, const Fraction(2000));
    });

    test('round-trip through a body keeps the arithmetic', () {
      final original = offer(
        'a',
        125000,
        currency: 'IRR',
        quantity: const Fraction(3, 4),
        unit: 'kg',
        packageCount: 3,
        paidCount: 2,
        discount: DiscountKind.percent,
        percent: 10,
        shippingMinor: 5000,
        date: DateTime(2026, 10, 13),
      );
      final read = PriceOption.fromBody('a', original.toBody());
      expect(read.valid, isTrue);
      expect(read.quantity, const Fraction(3, 4));
      expect(read.packageCount, 3);
      expect(read.paidCount, 2);
      expect(read.discount, DiscountKind.percent);
      expect(read.discountPercent, 10);
      expect(read.shippingMinor, 5000);
      expect(read.date, DateTime(2026, 10, 13));
      // 125000 × 0.9 = 112500, + 5000 shipping = 117500, over 3 × 0.75 kg.
      expect(effectivePriceMinor(read), const Fraction(117500));
      expect(
        effectivePriceMinor(read) / (read.quantity * const Fraction(3)),
        const Fraction(470000, 9),
      );
    });
  });

  group('display of exact fractions', () {
    test('whole amounts group; others say approximately', () {
      expect(
        formatMinorFraction(const Fraction(12000), 2, persian: false),
        '120',
      );
      expect(
        formatMinorFraction(const Fraction(12500), 2, persian: false),
        '125',
      );
      expect(
        formatMinorFraction(const Fraction(10000, 3), 2, persian: false),
        startsWith('≈33.33'),
      );
      expect(
        formatMinorFraction(const Fraction(120000), 0, persian: false),
        '120,000',
      );
      expect(
        formatMinorFraction(const Fraction(12000), 2, persian: true),
        '۱۲۰',
      );
    });
  });
}
