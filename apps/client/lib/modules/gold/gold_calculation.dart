part of 'gold_math.dart';

/// Exact intermediates; persisted values fit integers exactly on all targets.
const int goldMaxExact = 9007199254740991;
final _maxExact = BigInt.from(goldMaxExact);
BigInt _divRound(BigInt value, BigInt divisor) => value.isNegative
    ? -_divRound(-value, divisor)
    : (value + divisor ~/ BigInt.two) ~/ divisor;
int _money(BigInt value) {
  if (value < BigInt.zero || value > _maxExact) {
    throw RangeError('gold amount exceeds exact storage range');
  }
  return value.toInt();
}

abstract final class GoldMath {
  static GoldResult calculate(GoldInput input) {
    if (input.problems().isNotEmpty) throw StateError('invalid gold input');
    return _calculate(input);
  }

  static GoldResult _calculate(GoldInput input) {
    final rate = input.convertedRateCentiPerG;
    final weight = BigInt.from(input.weightMg);
    final scale = BigInt.from(10000);
    final metal = _divRound(weight * BigInt.from(rate), scale);
    final percentage = _divRound(
      BigInt.from(input.makingPercentBp) * metal,
      scale,
    );
    final perGram = _divRound(
      weight * BigInt.from(input.makingPerGramCenti),
      scale,
    );
    final making = switch (input.makingMode) {
      GoldMakingMode.percent => percentage,
      GoldMakingMode.perGram => perGram,
      GoldMakingMode.fixed => BigInt.from(input.makingFixedRial),
      GoldMakingMode.mixed => percentage + perGram,
    };
    final commission = BigInt.from(input.commissionRial);
    final profitBase = switch (input.profitBase) {
      GoldProfitBase.metalAndMaking => metal + making,
      GoldProfitBase.metalOnly => metal,
      GoldProfitBase.services => making + commission,
    };
    final profit = _divRound(BigInt.from(input.profitBp) * profitBase, scale);
    final vatBase =
        making + profit + (input.commissionTaxable ? commission : BigInt.zero);
    final vat = _divRound(BigInt.from(input.vatBp) * vatBase, scale);
    final extras = input.extras.fold(
      BigInt.zero,
      (sum, extra) => sum + BigInt.from(extra.$2),
    );
    final total = metal + making + profit + commission + vat + extras;
    int? difference;
    int? percent;
    if (input.shopQuoteRial > 0) {
      final diff = BigInt.from(input.shopQuoteRial) - total;
      difference = diff.toInt();
      if (total > BigInt.zero) {
        final pct = _divRound(diff * scale, total);
        if (pct.abs() <= _maxExact) percent = pct.toInt();
      }
    }
    return GoldResult(
      metalValueRial: _money(metal),
      makingChargeRial: _money(making),
      sellerProfitRial: _money(profit),
      commissionRial: _money(commission),
      vatBaseRial: _money(vatBase),
      vatRial: _money(vat),
      extrasRial: _money(extras),
      estimatedTotalRial: _money(total),
      convertedRateCentiPerG: rate,
      rateWasConverted: input.rateWasConverted,
      nonGoldMg: input.grossWeightMg > 0
          ? input.grossWeightMg - input.weightMg
          : 0,
      quoteDiffRial: difference,
      quoteDiffHundredthsPct: percent,
    );
  }

  /// The heaviest net weight (milligrams) whose estimate stays within
  /// [budgetRial], with every other part of [input] as it is — the way back
  /// from «how much can I spend» to «how much gold is that».
  ///
  /// The estimate never falls as the weight grows (each line is a rounded
  /// product of the weight, or a constant), so the answer is found by
  /// halving, not by dividing the budget — a fixed making charge or a fixed
  /// extra makes the division wrong. 0 means even one milligram is over.
  static int maxWeightMgWithin(GoldInput input, int budgetRial) {
    if (budgetRial < 1) return 0;
    bool fits(int weightMg) {
      try {
        return _calculate(input.withWeightMg(weightMg)).estimatedTotalRial <=
            budgetRial;
      } on RangeError {
        return false;
      }
    }

    if (!fits(1)) return 0;
    if (fits(GoldInput.maxWeightMg)) return GoldInput.maxWeightMg;
    var low = 1, high = GoldInput.maxWeightMg;
    while (high - low > 1) {
      final middle = low + (high - low) ~/ 2;
      if (fits(middle)) {
        low = middle;
      } else {
        high = middle;
      }
    }
    return low;
  }

  /// The making charge as a share of the metal value, in basis points —
  /// what a fixed or per-gram charge comes to in the «percent» the trade
  /// quotes. Null when the metal has no value to take a share of.
  static int? makingShareBp(GoldResult result) {
    if (result.metalValueRial <= 0) return null;
    return _divRound(
      BigInt.from(result.makingChargeRial) * BigInt.from(10000),
      BigInt.from(result.metalValueRial),
    ).toInt();
  }
}
