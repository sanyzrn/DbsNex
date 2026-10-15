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
}
