import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/gold/gold_market_math.dart';
import 'package:nex_client/modules/gold/gold_math.dart';
import 'package:nex_client/modules/gold/gold_format.dart';

void main() {
  test('oversized pasted numbers are rejected before parsing', () {
    final text = '9' * 100000;
    expect(parseScaled(text, 2), isNull);
    expect(parseScaledDetailed(text, 2).$2, GoldParseProblem.tooBig);
  });

  test('705 mithqal uses 4.6083 g, not a 750 gram or rounded divisor', () {
    // At 10,000,000 toman per gram (750), the 705 mithqal is 43,318,020.
    expect(GoldMarketMath.mithqalFromGram(1000000000, 750), 4331802000);
    expect(GoldMarketMath.gramFromMithqal(4331802000, 750), 1000000000);
    expect(GoldMarketMath.gramFromMithqal(4331802000, 705), 940000000);
    expect(GoldMarketMath.equivalent750Mg(3000, 705), 2820);
    expect(GoldMarketMath.weightMithqal(46083), 100000);
  });

  test('conversion round trips to within one centi-toman', () {
    for (final rate in [1, 10000, 123456789, GoldInput.maxRateCenti]) {
      for (final ppt in [705, 750, 875, 916, 999]) {
        final quote = GoldMarketMath.mithqalFromGram(rate, ppt);
        if (quote <= GoldInput.maxRateCenti * 5) {
          expect(
            (GoldMarketMath.gramFromMithqal(quote, ppt) - rate).abs(),
            lessThanOrEqualTo(1),
          );
        }
      }
    }
  });

  test('buyback never silently removes purity or purchase charges', () {
    final same = GoldMarketMath.sell(
      weightMg: 3000,
      rate750Centi: 1000000000,
      settlementPpt: 750,
    );
    expect(same.netRial, 300000000);
    final settlement = GoldMarketMath.sell(
      weightMg: 3000,
      rate750Centi: 1000000000,
      settlementPpt: 740,
      deductionBp: 100,
      feeRial: 100000,
    );
    expect(settlement.metalRial, 296000000);
    expect(settlement.deductionRial, 2960000);
    expect(settlement.netRial, 292940000);
  });

  test('deductions may consume all proceeds but cannot exceed them', () {
    expect(
      GoldMarketMath.sell(
        weightMg: 1000,
        rate750Centi: 10000,
        settlementPpt: 750,
        deductionBp: 10000,
      ).netRial,
      0,
    );
    expect(
      () => GoldMarketMath.sell(
        weightMg: 1000,
        rate750Centi: 10000,
        settlementPpt: 750,
        deductionBp: 10000,
        feeRial: 1,
      ),
      throwsArgumentError,
    );
  });

  test(
    'break-even is the first centi-toman whose rounded proceeds cover cost',
    () {
      for (final weight in [1, 2125, 10000000]) {
        for (final ppt in [740, 750, 999]) {
          for (final cost in [1, 358410000, 999999999999]) {
            final rate = GoldMarketMath.breakEvenRate(
              costRial: cost,
              weightMg: weight,
              settlementPpt: ppt,
              deductionBp: 125,
              feeRial: 70,
            );
            if (rate == null) continue;
            expect(
              GoldMarketMath.sell(
                weightMg: weight,
                rate750Centi: rate,
                settlementPpt: ppt,
                deductionBp: 125,
                feeRial: 70,
              ).netRial,
              greaterThanOrEqualTo(cost),
            );
            if (rate > 1) {
              try {
                expect(
                  GoldMarketMath.sell(
                    weightMg: weight,
                    rate750Centi: rate - 1,
                    settlementPpt: ppt,
                    deductionBp: 125,
                    feeRial: 70,
                  ).netRial,
                  lessThan(cost),
                );
              } on ArgumentError {
                // Below the smallest valid payout cannot cover a positive cost.
              }
            }
          }
        }
      }
      expect(
        GoldMarketMath.breakEvenRate(
          costRial: 1,
          weightMg: 1000,
          settlementPpt: 750,
          deductionBp: 10000,
          feeRial: 0,
        ),
        isNull,
      );
    },
  );

  test('invalid and out-of-range inputs are rejected, never clamped', () {
    for (final weight in [0, -1, GoldInput.maxWeightMg + 1]) {
      expect(
        () => GoldMarketMath.sell(
          weightMg: weight,
          rate750Centi: 1,
          settlementPpt: 750,
        ),
        throwsArgumentError,
      );
    }
    expect(() => GoldMarketMath.gramFromMithqal(0, 750), throwsArgumentError);
    expect(() => GoldMarketMath.rateAt(10, 0, 750), throwsArgumentError);
    expect(() => GoldMarketMath.weightMithqal(0), throwsArgumentError);
    expect(
      () => GoldMarketMath.sell(
        weightMg: 1,
        rate750Centi: 100,
        settlementPpt: 750,
        deductionBp: 10001,
      ),
      throwsArgumentError,
    );
  });
}
