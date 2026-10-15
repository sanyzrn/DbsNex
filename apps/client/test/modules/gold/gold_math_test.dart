import 'package:flutter_test/flutter_test.dart';

import 'package:nex_client/modules/gold/gold_math.dart';

/// Gold Check's arithmetic, on the reference example and around its
/// edges — integer-scaled, rounded per line, refusing to guess about
/// invalid input.
void main() {
  group('the reference example (3 g, 18k, 10,000,000 toman/g)', () {
    // 3.000 g × 10,000,000 toman/g = 30,000,000 toman metal;
    // 10% making = 3,000,000; 7% profit on 33,000,000 = 2,310,000;
    // 10% VAT on (3,000,000 + 2,310,000) = 531,000;
    // total = 35,841,000 toman = 358,410,000 rials. No other fees.
    final input = GoldInput(
      weightMg: 3000,
      finenessPpt: 750,
      rateCentiPerG: 1000000000, // 10,000,000 toman × 100 centi
      rateRefPpt: 750,
      makingMode: GoldMakingMode.percent,
      makingPercentBp: 1000,
      profitBp: 700,
      vatBp: 1000,
    );

    test('every line, in rials', () {
      final result = GoldMath.calculate(input);
      expect(result.metalValueRial, 300000000);
      expect(result.makingChargeRial, 30000000);
      expect(result.sellerProfitRial, 23100000);
      expect(result.commissionRial, 0);
      expect(result.vatBaseRial, 53100000);
      expect(result.vatRial, 5310000);
      expect(result.extrasRial, 0);
      expect(result.estimatedTotalRial, 358410000);
    });

    test('the metal value is not in the VAT base', () {
      final result = GoldMath.calculate(input);
      expect(
        result.vatBaseRial,
        result.makingChargeRial + result.sellerProfitRial,
      );
    });

    test('with the shop quoting exactly the estimate, the difference is 0', () {
      final result = GoldMath.calculate(
        GoldInput(
          weightMg: 3000,
          finenessPpt: 750,
          rateCentiPerG: 1000000000,
          rateRefPpt: 750,
          makingPercentBp: 1000,
          profitBp: 700,
          vatBp: 1000,
          shopQuoteRial: 358410000,
        ),
      );
      expect(result.quoteDiffRial, 0);
      expect(result.quoteDiffHundredthsPct, 0);
    });
  });

  group('weights and rates', () {
    test('one soot — 0.001 g — is a valid weight and prices exactly', () {
      // 1 mg × 1,000,000,000 centi/g = 1,000,000 centi = 100,000 rial.
      final result = GoldMath.calculate(
        GoldInput(
          weightMg: 1,
          finenessPpt: 750,
          rateCentiPerG: 1000000000,
          rateRefPpt: 750,
          makingMode: GoldMakingMode.fixed,
          makingFixedRial: 0,
          profitBp: 0,
          vatBp: 0,
        ),
      );
      expect(result.metalValueRial, 100000);
      expect(result.estimatedTotalRial, 100000);
    });

    test('a fractional rate keeps its fraction until the line rounds', () {
      // 1 g at 10,000,000.50 toman = 1,000,000,050 centi → 100,000,005 rial.
      final result = GoldMath.calculate(
        GoldInput(
          weightMg: 1000,
          finenessPpt: 750,
          rateCentiPerG: 1000000050,
          rateRefPpt: 750,
          makingMode: GoldMakingMode.fixed,
          makingFixedRial: 0,
          profitBp: 0,
          vatBp: 0,
        ),
      );
      expect(result.metalValueRial, 100000005);
    });

    test('rounding is to the nearest rial, halves away from zero', () {
      // 1 g at 10,000,000.05 toman = 100,000,000.5 rial → 100,000,001.
      final justAboveHalf = GoldMath.calculate(
        GoldInput(
          weightMg: 1000,
          finenessPpt: 999,
          rateCentiPerG: 1000000005,
          rateRefPpt: 999,
          makingMode: GoldMakingMode.fixed,
          makingFixedRial: 0,
          profitBp: 0,
          vatBp: 0,
        ),
      );
      expect(justAboveHalf.metalValueRial, 100000001);
      // 1 mg at 500,500 centi/g = 50.05 rial → 50; at 505,500 → 50.55 → 51.
      final halfRial = GoldMath.calculate(
        GoldInput(
          weightMg: 1,
          finenessPpt: 999,
          rateCentiPerG: 500500,
          rateRefPpt: 999,
          makingMode: GoldMakingMode.fixed,
          makingFixedRial: 0,
          profitBp: 0,
          vatBp: 0,
        ),
      );
      expect(halfRial.metalValueRial, 50);
      final aboveHalf = GoldMath.calculate(
        GoldInput(
          weightMg: 1,
          finenessPpt: 999,
          rateCentiPerG: 505500,
          rateRefPpt: 999,
          makingMode: GoldMakingMode.fixed,
          makingFixedRial: 0,
          profitBp: 0,
          vatBp: 0,
        ),
      );
      expect(aboveHalf.metalValueRial, 51);
    });

    test('very large valid prices do not overflow', () {
      // 10 kg at 100,000,000 toman/g, with large fees inside the combined exact-storage bound.
      // metal = 10⁷ mg × 10¹⁰ centi / 10⁴ = 10¹³ rials, and every product
      // on the way stays under 9.2×10¹⁸.
      final result = GoldMath.calculate(
        GoldInput(
          weightMg: 10000000,
          finenessPpt: 999,
          rateCentiPerG: 10000000000,
          rateRefPpt: 999,
          makingMode: GoldMakingMode.percent,
          makingPercentBp: 99999,
          profitBp: 99999,
          vatBp: 1000,
          commissionRial: 100000000000000,
          extras: [('stones', 100000000000000)],
          shopQuoteRial: 1000000000000000,
        ),
      );
      expect(result.metalValueRial, 10000000000000);
      expect(result.estimatedTotalRial, 1539975800110000);
      // Nothing wrapped around to a negative number.
      expect(result.estimatedTotalRial, lessThanOrEqualTo(goldMaxExact));
      expect(result.metalValueRial, greaterThan(0));
    });
  });

  group('making-charge modes', () {
    final base = GoldInput(
      weightMg: 5000,
      finenessPpt: 750,
      rateCentiPerG: 500000000, // 5,000,000 toman/g
      rateRefPpt: 750,
      profitBp: 0,
      vatBp: 0,
    );

    test('0% making is allowed and means zero', () {
      final result = GoldMath.calculate(base);
      expect(result.makingChargeRial, 0);
    });

    test('percent of metal value', () {
      // metal = 5 g × 5,000,000 toman = 25,000,000 toman = 250,000,000 rial.
      final result = GoldMath.calculate(
        GoldInput(
          weightMg: 5000,
          finenessPpt: 750,
          rateCentiPerG: 500000000,
          rateRefPpt: 750,
          makingPercentBp: 800, // 8%
          profitBp: 0,
          vatBp: 0,
        ),
      );
      expect(result.metalValueRial, 250000000);
      expect(result.makingChargeRial, 20000000);
    });

    test('amount per gram', () {
      // 5 g × 120,000 toman/g making = 600,000 toman = 6,000,000 rial.
      final result = GoldMath.calculate(
        GoldInput(
          weightMg: 5000,
          finenessPpt: 750,
          rateCentiPerG: 500000000,
          rateRefPpt: 750,
          makingMode: GoldMakingMode.perGram,
          makingPerGramCenti: 12000000,
          profitBp: 0,
          vatBp: 0,
        ),
      );
      expect(result.makingChargeRial, 6000000);
    });

    test('fixed amount for the piece', () {
      final result = GoldMath.calculate(
        GoldInput(
          weightMg: 5000,
          finenessPpt: 750,
          rateCentiPerG: 500000000,
          rateRefPpt: 750,
          makingMode: GoldMakingMode.fixed,
          makingFixedRial: 2500000,
          profitBp: 0,
          vatBp: 0,
        ),
      );
      expect(result.makingChargeRial, 2500000);
    });

    test('percent + per gram together, each part rounded then added', () {
      // 8% of 250,000,000 = 20,000,000; 5 g × 10,000.55 toman/g
      // = 50,002.75 toman = 500,027.5 rial → 500,028 (rounded on its own,
      // then added — see README's rounding policy).
      final result = GoldMath.calculate(
        GoldInput(
          weightMg: 5000,
          finenessPpt: 750,
          rateCentiPerG: 500000000,
          rateRefPpt: 750,
          makingMode: GoldMakingMode.mixed,
          makingPercentBp: 800,
          makingPerGramCenti: 1000055,
          profitBp: 0,
          vatBp: 0,
        ),
      );
      expect(result.makingChargeRial, 20000000 + 500028);
    });
  });
}
