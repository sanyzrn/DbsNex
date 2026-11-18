import 'model.dart';
import 'money_format.dart';

/// Whole-rial display rounds each position half-up. Intermediate products
/// and all aggregates use BigInt, including sums beyond the JSON int range.
BigInt rounded(BigInt numerator, BigInt denominator) =>
    (numerator + (denominator ~/ BigInt.two)) ~/ denominator;

BigInt costOf(Holding h) => rounded(
  BigInt.from(h.quantity) * BigInt.from(h.costPerUnitRial),
  BigInt.from(moneyFactor(h.market.digits)),
);

BigInt valueAt(Holding h, Quote quote) {
  final gold = h.market.type == AssetType.gold;
  return rounded(
    BigInt.from(h.quantity) *
        BigInt.from(quote.unitRial) *
        BigInt.from(gold ? h.fineness : 1),
    BigInt.from(moneyFactor(h.market.digits) * (gold ? 750 : 1)),
  );
}

class Position {
  const Position(this.holding, this.quote, this.cost, this.value);
  final Holding holding;
  final Quote? quote;
  final BigInt cost;
  final BigInt? value;
  BigInt? get profit => value == null ? null : value! - cost;
}

class Valuation {
  Valuation(List<Holding> holdings, List<Quote> quotes, DateTime asOf) {
    final day = civilDay(asOf);
    final ordered = quotes.where((q) => !q.date.isAfter(day)).toList()
      ..sort((a, b) {
        final byDay = b.date.compareTo(a.date);
        if (byDay != 0) return byDay;
        final bySave = b.record.updatedAt.compareTo(a.record.updatedAt);
        return bySave != 0 ? bySave : b.record.id.compareTo(a.record.id);
      });
    for (final q in ordered) {
      history.putIfAbsent(q.market.key, () => []).add(q);
    }
    for (final h in holdings) {
      final candidate = latest(h.market);
      final quote =
          candidate != null &&
              !candidate.date.isBefore(h.bought) &&
              !h.bought.isAfter(day)
          ? candidate
          : null;
      final cost = costOf(h);
      final value = quote == null ? null : valueAt(h, quote);
      positions.add(Position(h, quote, cost, value));
      if (value != null) {
        total += value;
        pricedCost += cost;
        priced++;
      }
      if (h.market.type == AssetType.gold && !h.bought.isAfter(day)) {
        _goldPptMg += BigInt.from(h.quantity) * BigInt.from(h.fineness);
      }
    }
  }

  final history = <String, List<Quote>>{};
  final positions = <Position>[];
  BigInt total = BigInt.zero, pricedCost = BigInt.zero;
  BigInt _goldPptMg = BigInt.zero;
  int priced = 0;

  int get unpriced => positions.length - priced;
  BigInt get profit => total - pricedCost;
  BigInt get goldMg => rounded(_goldPptMg, BigInt.from(750));
  Quote? latest(AssetMarket market) => history[market.key]?.firstOrNull;
  BigInt? equivalent(AssetMarket market, int factor) {
    final rate = latest(market);
    return rate == null || priced == 0
        ? null
        : rounded(total * BigInt.from(factor), BigInt.from(rate.unitRial));
  }
}
