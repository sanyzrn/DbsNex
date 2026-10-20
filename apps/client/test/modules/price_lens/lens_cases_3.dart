part of 'lens_test.dart';

void _lensCases3() {
  group('price memory', () {
    final date = DateTime(2026, 9, 1);
    PriceMemory memory(String label, {int price = 100000, DateTime? when}) =>
        PriceMemory(
          id: 'mem-${label.hashCode.abs()}',
          label: label,
          priceMinor: price,
          currency: 'IRR',
          quantity: const Fraction(750),
          unitKey: 'g',
          date: when ?? date,
        );

    test('only an exact spec matches; the newest wins', () {
      final option = offer(
        ' Rice 750g ',
        110000,
        quantity: const Fraction(750),
        unit: 'g',
      );
      final match = memoryMatchFor(option, [
        memory('other thing'),
        memory('RICE 750G', when: DateTime(2026, 8, 1)),
        memory('rice 750g', when: DateTime(2026, 9, 5)),
      ]);
      expect(match, isNotNull);
      expect(match!.date, DateTime(2026, 9, 5));
    });

    test(
      'a different quantity, unit, currency or count is not the same product',
      () {
        final option = offer(
          'rice',
          110000,
          quantity: const Fraction(750),
          unit: 'g',
        );
        expect(
          memoryMatchFor(option, [
            PriceMemory(
              id: 'm1',
              label: 'rice',
              priceMinor: 1,
              currency: 'IRR',
              quantity: const Fraction(800),
              unitKey: 'g',
              date: date,
            ),
          ]),
          isNull,
        );
        expect(
          memoryMatchFor(option, [
            PriceMemory(
              id: 'm2',
              label: 'rice',
              priceMinor: 1,
              currency: 'USD',
              quantity: const Fraction(750),
              unitKey: 'g',
              date: date,
            ),
          ]),
          isNull,
        );
        expect(
          memoryMatchFor(option, [
            PriceMemory(
              id: 'm3',
              label: 'rice',
              priceMinor: 1,
              currency: 'IRR',
              quantity: const Fraction(750),
              unitKey: 'kg',
              date: date,
            ),
          ]),
          isNull,
        );
      },
    );

    test('750 g and 0.75 kg are physically the same package', () {
      final option = offer(
        'rice',
        110000,
        quantity: const Fraction(750),
        unit: 'g',
      );
      final match = memoryMatchFor(option, [
        PriceMemory(
          id: 'kg-memory',
          label: 'rice',
          priceMinor: 100000,
          currency: 'IRR',
          quantity: const Fraction(3, 4),
          unitKey: 'kg',
          date: date,
        ),
      ]);
      expect(match, isNotNull);
      expect(match!.id, 'kg-memory');
      // A different physical size still is not the same product.
      expect(
        memoryMatchFor(option, [
          PriceMemory(
            id: 'kg-off',
            label: 'rice',
            priceMinor: 100000,
            currency: 'IRR',
            quantity: const Fraction(4, 5),
            unitKey: 'kg',
            date: date,
          ),
        ]),
        isNull,
      );
    });

    test('the difference is a subtraction of two typed numbers', () {
      final option = offer(
        'rice',
        110000,
        quantity: const Fraction(750),
        unit: 'g',
      );
      final earlier = memory('rice', price: 100000);
      expect(memoryDifferenceMinor(option, earlier), 10000);
      expect(
        memoryDifferenceMinor(
          offer('rice', 95000, quantity: const Fraction(750), unit: 'g'),
          earlier,
        ),
        -5000,
      );
    });
  });
}
