/// Market conversions use rational integers, independently of widgets or storage.
library;

import 'gold_math.dart';

abstract final class GoldMarketMath {
  /// The Iranian market's quoted mithqal: 4.6083 g at 705 fineness.
  /// It is a market convention, not a universal definition of mithqal.
  static const mithqalTenThousandthsGram = 46083;

  static int _rounded(BigInt n, BigInt d) {
    final value = (n + d ~/ BigInt.two) ~/ d;
    if (value < BigInt.zero || value > BigInt.from(goldMaxExact)) {
      throw RangeError('gold market value outside exact range');
    }
    return value.toInt();
  }

  static void _check(int value, int min, int max) {
    if (value < min || value > max) throw ArgumentError('invalid gold input');
  }

  /// Centi-toman/mithqal (705) → centi-toman/g at the chosen fineness.
  static int gramFromMithqal(int quoteCenti, int fineness) {
    _check(quoteCenti, 1, GoldInput.maxRateCenti * 5);
    _check(fineness, 100, 1000);
    return _rounded(
      BigInt.from(quoteCenti) * BigInt.from(10000 * fineness),
      BigInt.from(mithqalTenThousandthsGram * 705),
    );
  }

  static int mithqalFromGram(int gramCenti, int fineness) {
    _check(gramCenti, 1, GoldInput.maxRateCenti);
    _check(fineness, 100, 1000);
    return _rounded(
      BigInt.from(gramCenti) * BigInt.from(mithqalTenThousandthsGram * 705),
      BigInt.from(10000 * fineness),
    );
  }

  static int rateAt(int rateCenti, int reference, int fineness) {
    _check(rateCenti, 1, GoldInput.maxRateCenti);
    _check(reference, 100, 1000);
    _check(fineness, 100, 1000);
    return _rounded(
      BigInt.from(rateCenti) * BigInt.from(fineness),
      BigInt.from(reference),
    );
  }

  static int metalRial(int weightMg, int rateCenti) {
    _check(weightMg, 1, GoldInput.maxWeightMg);
    _check(rateCenti, 1, GoldInput.maxRateCenti * 10);
    return _rounded(
      BigInt.from(weightMg) * BigInt.from(rateCenti),
      BigInt.from(10000),
    );
  }

  static int equivalent750Mg(int weightMg, int fineness) {
    _check(weightMg, 1, GoldInput.maxWeightMg);
    _check(fineness, 100, 1000);
    return _rounded(
      BigInt.from(weightMg) * BigInt.from(fineness),
      BigInt.from(750),
    );
  }

  /// Mithqal units, scaled by 10,000. Weight stays stored in milligrams.
  static int weightMithqal(int weightMg) {
    _check(weightMg, 1, GoldInput.maxWeightMg);
    return _rounded(
      BigInt.from(weightMg) * BigInt.from(100000),
      BigInt.from(mithqalTenThousandthsGram),
    );
  }

  /// No making/profit/VAT is inferred for buyback. Deductions are explicitly
  /// entered; settlement fineness is distinct from the rate's reference.
  static GoldSaleResult sell({
    required int weightMg,
    required int rate750Centi,
    required int settlementPpt,
    int deductionBp = 0,
    int feeRial = 0,
  }) {
    _check(deductionBp, 0, 10000);
    _check(feeRial, 0, GoldInput.maxAmountRial);
    final rate = rateAt(rate750Centi, 750, settlementPpt);
    final metal = metalRial(weightMg, rate);
    final deduction = _rounded(
      BigInt.from(metal) * BigInt.from(deductionBp),
      BigInt.from(10000),
    );
    if (deduction + feeRial > metal) {
      throw ArgumentError('deductions exceed gold value');
    }
    return GoldSaleResult(
      metal,
      deduction,
      feeRial,
      metal - deduction - feeRial,
    );
  }

  /// The smallest quoted 750 rate that covers cost at the same settlement
  /// conditions. Binary search uses the exact, rounded sale calculation.
  /// Null means no rate within this calculator's cap can cover it.
  static int? breakEvenRate({
    required int costRial,
    required int weightMg,
    required int settlementPpt,
    required int deductionBp,
    required int feeRial,
  }) {
    _check(costRial, 1, GoldInput.maxAmountRial);
    _check(weightMg, 1, GoldInput.maxWeightMg);
    _check(settlementPpt, 100, 1000);
    _check(deductionBp, 0, 10000);
    _check(feeRial, 0, GoldInput.maxAmountRial);
    bool covers(int rate) {
      try {
        return sell(
              weightMg: weightMg,
              rate750Centi: rate,
              settlementPpt: settlementPpt,
              deductionBp: deductionBp,
              feeRial: feeRial,
            ).netRial >=
            costRial;
      } on ArgumentError {
        return false;
      }
    }

    if (!covers(GoldInput.maxRateCenti)) return null;
    var low = 1, high = GoldInput.maxRateCenti;
    while (low < high) {
      final mid = low + (high - low) ~/ 2;
      if (covers(mid)) {
        high = mid;
      } else {
        low = mid + 1;
      }
    }
    return low;
  }
}

class GoldSaleResult {
  const GoldSaleResult(
    this.metalRial,
    this.deductionRial,
    this.feeRial,
    this.netRial,
  );
  final int metalRial;
  final int deductionRial;
  final int feeRial;
  final int netRial;
}
