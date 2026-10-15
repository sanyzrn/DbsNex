import 'package:flutter_test/flutter_test.dart';

import 'package:nex_client/modules/gold/gold_math.dart';

/// Gold Check's arithmetic around its edges: profit, commission and VAT;
/// the purity ratio; gross weight and extras; the difference to verify;
/// and the refusal to guess about invalid input. (The reference example
/// and the making-charge modes are in `gold_math_test.dart`.)
void main() {
  group('profit, commission and VAT', () {
    test('profit sits on metal + making, whatever those are', () {
      // metal 100,000,000; making 20,000,000; 7% of 120,000,000 = 8,400,000.
      final result = GoldMath.calculate(
        GoldInput(
          weightMg: 2000,
          finenessPpt: 750,
          rateCentiPerG: 500000000,
          rateRefPpt: 750,
          makingMode: GoldMakingMode.fixed,
          makingFixedRial: 20000000,
          profitBp: 700,
          vatBp: 0,
        ),
      );
      expect(result.sellerProfitRial, 8400000);
    });

    test('the entered commission joins the VAT base and the total', () {
      final without = GoldMath.calculate(
        GoldInput(
          weightMg: 2000,
          finenessPpt: 750,
          rateCentiPerG: 500000000,
          rateRefPpt: 750,
          makingMode: GoldMakingMode.fixed,
          makingFixedRial: 20000000,
          profitBp: 700,
          vatBp: 1000,
        ),
      );
      final withCommission = GoldMath.calculate(
        GoldInput(
          weightMg: 2000,
          finenessPpt: 750,
          rateCentiPerG: 500000000,
          rateRefPpt: 750,
          makingMode: GoldMakingMode.fixed,
          makingFixedRial: 20000000,
          profitBp: 700,
          vatBp: 1000,
          commissionRial: 1000000,
        ),
      );
      expect(withCommission.vatBaseRial, without.vatBaseRial + 1000000);
      expect(withCommission.vatRial, without.vatRial + 100000);
      expect(
        withCommission.estimatedTotalRial,
        without.estimatedTotalRial + 1100000,
      );
    });

    test('0% VAT is a choice, and the line simply shows zero', () {
      final result = GoldMath.calculate(
        GoldInput(
          weightMg: 2000,
          finenessPpt: 750,
          rateCentiPerG: 500000000,
          rateRefPpt: 750,
          makingMode: GoldMakingMode.percent,
          makingPercentBp: 700,
          profitBp: 700,
          vatBp: 0,
        ),
      );
      expect(result.vatRial, 0);
      expect(
        result.estimatedTotalRial,
        result.metalValueRial +
            result.makingChargeRial +
            result.sellerProfitRial,
      );
    });

    test('an editable VAT of 9% changes only the VAT line and the total', () {
      // Base = making 10,000,000 + profit 7,700,000 = 17,700,000 rial.
      // 10% → 1,770,000; 9% → 1,593,000, exactly.
      final ten = GoldMath.calculate(
        GoldInput(
          weightMg: 2000,
          finenessPpt: 750,
          rateCentiPerG: 500000000,
          rateRefPpt: 750,
          makingPercentBp: 1000,
          profitBp: 700,
          vatBp: 1000,
        ),
      );
      final nine = GoldMath.calculate(
        GoldInput(
          weightMg: 2000,
          finenessPpt: 750,
          rateCentiPerG: 500000000,
          rateRefPpt: 750,
          makingPercentBp: 1000,
          profitBp: 700,
          vatBp: 900,
        ),
      );
      expect(ten.vatBaseRial, 17700000);
      expect(ten.vatRial, 1770000);
      expect(nine.makingChargeRial, ten.makingChargeRial);
      expect(nine.sellerProfitRial, ten.sellerProfitRial);
      expect(nine.vatRial, 1593000);
    });
  });

  group('fineness and the purity ratio', () {
    test('a rate at the piece\'s own fineness is used as entered', () {
      final result = GoldMath.calculate(
        GoldInput(
          weightMg: 1000,
          finenessPpt: 875,
          rateCentiPerG: 700000000,
          rateRefPpt: 875,
          makingMode: GoldMakingMode.fixed,
          makingFixedRial: 0,
          profitBp: 0,
          vatBp: 0,
        ),
      );
      expect(result.rateWasConverted, isFalse);
      expect(result.convertedRateCentiPerG, 700000000);
      expect(result.metalValueRial, 70000000); // 7,000,000 toman
    });

    test('an 18k rate for a 21k piece is converted by the ratio, visibly', () {
      // 7,000,000 toman/g at 750 for an 875 piece:
      // 7,000,000 × 875/750 = 8,166,666.666… → 816,666,667 centi (nearest).
      final input = GoldInput(
        weightMg: 1000,
        finenessPpt: 875,
        rateCentiPerG: 700000000,
        rateRefPpt: 750,
        makingMode: GoldMakingMode.fixed,
        makingFixedRial: 0,
        profitBp: 0,
        vatBp: 0,
      );
      expect(input.rateWasConverted, isTrue);
      expect(input.convertedRateCentiPerG, 816666667);
      final result = GoldMath.calculate(input);
      expect(result.rateWasConverted, isTrue);
      expect(result.metalValueRial, 81666667); // 8,166,666.7 toman
    });

    test('a 21k rate for an 18k piece converts down the same way', () {
      final input = GoldInput(
        weightMg: 1000,
        finenessPpt: 750,
        rateCentiPerG: 875000000,
        rateRefPpt: 875,
        makingMode: GoldMakingMode.fixed,
        makingFixedRial: 0,
        profitBp: 0,
        vatBp: 0,
      );
      // 8,750,000 × 750/875 = 7,500,000 exactly.
      expect(input.convertedRateCentiPerG, 750000000);
      expect(GoldMath.calculate(input).metalValueRial, 75000000);
    });
  });

  group('gross weight and extras', () {
    test('non-gold mass is shown as excluded, never priced', () {
      final result = GoldMath.calculate(
        GoldInput(
          weightMg: 4000,
          grossWeightMg: 4750,
          finenessPpt: 750,
          rateCentiPerG: 500000000,
          rateRefPpt: 750,
          makingMode: GoldMakingMode.fixed,
          makingFixedRial: 0,
          profitBp: 0,
          vatBp: 0,
        ),
      );
      expect(result.nonGoldMg, 750);
      // The 0.75 g of stones bought nothing.
      expect(result.metalValueRial, 200000000); // 4 g × 5,000,000 toman
    });

    test('extras land in the total and outside the VAT base', () {
      final result = GoldMath.calculate(
        GoldInput(
          weightMg: 1000,
          finenessPpt: 750,
          rateCentiPerG: 500000000,
          rateRefPpt: 750,
          makingMode: GoldMakingMode.fixed,
          makingFixedRial: 1000000,
          profitBp: 700,
          vatBp: 1000,
          extras: [('stones', 2000000), ('box', 500000)],
        ),
      );
      expect(result.extrasRial, 2500000);
      expect(
        result.vatBaseRial,
        result.makingChargeRial + result.sellerProfitRial,
      );
      expect(
        result.estimatedTotalRial,
        result.metalValueRial +
            result.makingChargeRial +
            result.sellerProfitRial +
            result.vatRial +
            2500000,
      );
    });
  });

  group('the difference to verify', () {
    GoldInput at(int quoteRial) => GoldInput(
      weightMg: 3000,
      finenessPpt: 750,
      rateCentiPerG: 1000000000,
      rateRefPpt: 750,
      makingPercentBp: 1000,
      profitBp: 700,
      vatBp: 1000,
      shopQuoteRial: quoteRial,
    );

    test('a higher quote is a positive difference and a percent', () {
      final result = GoldMath.calculate(at(360000000));
      expect(result.quoteDiffRial, 1590000);
      // 1,590,000 / 358,410,000 = 0.44361…% → 44 hundredths.
      expect(result.quoteDiffHundredthsPct, 44);
    });

    test('a lower quote keeps its negative sign, even near zero', () {
      final result = GoldMath.calculate(at(358000000));
      expect(result.quoteDiffRial, -410000);
      expect(result.quoteDiffHundredthsPct, lessThan(0));
      final tiny = GoldMath.calculate(at(358409995));
      expect(tiny.quoteDiffRial, -5);
      // −5 rials in 358,410,000 is 0.00% after rounding to hundredths —
      // the signed rial amount on the receipt is what keeps the sign.
      expect(tiny.quoteDiffHundredthsPct, 0);
    });
  });

  group('invalid input is refused, not guessed about', () {
    test('every out-of-range field reports itself', () {
      final problems = GoldInput(
        weightMg: 0,
        grossWeightMg: -1,
        finenessPpt: 50,
        rateCentiPerG: 0,
        rateRefPpt: 1000,
        makingPercentBp: 100000,
        profitBp: -1,
        vatBp: 100000,
        commissionRial: -5,
        extras: [('', 0), ('stones', -1)],
        shopQuoteRial: -10,
      ).problems();
      final fields = problems.map((problem) => problem.field).toSet();
      expect(
        fields,
        containsAll([
          GoldProblemField.weight,
          GoldProblemField.grossWeight,
          GoldProblemField.fineness,
          GoldProblemField.rate,
          GoldProblemField.rateRef,
          GoldProblemField.making,
          GoldProblemField.profit,
          GoldProblemField.vat,
          GoldProblemField.commission,
          GoldProblemField.extras,
          GoldProblemField.shopQuote,
        ]),
      );
    });

    test('a gross weight below the net weight is rejected visibly', () {
      final problems = GoldInput(
        weightMg: 5000,
        grossWeightMg: 4000,
        finenessPpt: 750,
        rateCentiPerG: 500000000,
        rateRefPpt: 750,
      ).problems();
      expect(
        problems.map((p) => p.field),
        contains(GoldProblemField.grossWeight),
      );
    });

    test('calculate refuses an input with problems', () {
      expect(
        () => GoldMath.calculate(
          GoldInput(
            weightMg: 0,
            finenessPpt: 750,
            rateCentiPerG: 100,
            rateRefPpt: 750,
          ),
        ),
        throwsStateError,
      );
    });

    test('an unlabeled or negative extra is a problem', () {
      final problems = GoldInput(
        weightMg: 1000,
        finenessPpt: 750,
        rateCentiPerG: 100,
        rateRefPpt: 750,
        extras: [('  ', 100), ('stones', -100)],
      ).problems();
      expect(
        problems.where((p) => p.field == GoldProblemField.extras),
        isNotEmpty,
      );
    });
  });
}
