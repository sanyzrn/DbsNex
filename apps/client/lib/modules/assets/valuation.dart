import 'model.dart';
import 'money_format.dart';

/// A price older than this is worth a quiet nudge: in Iran the 18k gram and
/// the dollar move every week, so a month-old book value is a memory, not a
/// value.
const priceFreshDays = 7;

/// Whole-rial display rounds each position half-up. Intermediate products
/// and all aggregates use BigInt, including sums beyond the JSON int range.
BigInt rounded(BigInt numerator, BigInt denominator) =>
    (numerator + (denominator ~/ BigInt.two)) ~/ denominator;

/// [rounded] for a value that may be negative — a loss and a fall in price
/// have to round away from zero, not towards it.
BigInt signedRounded(BigInt numerator, BigInt denominator) {
  final negative = numerator.isNegative;
  final value = rounded(numerator.abs(), denominator);
  return negative ? -value : value;
}

/// Civil days between two local dates; never 24-hour spans, so a clock change
/// cannot turn "yesterday" into "today".
int civilDaysBetween(DateTime from, DateTime to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

/// 750 → 18, 916 → 22, 999 → 24: the karat name a person says for a
/// thousandth fineness. Rounded to the nearest karat because shops say
/// «۲۲ عیار», not «۲۱٫۹۸».
int karatOf(int fineness) => ((fineness * 24) + 500) ~/ 1000;

/// The 18k-equivalent weight of [quantityMg] at [fineness], kept in
/// milligrams so a quarter-gram piece still shows.
BigInt normalizedGoldMg(int quantityMg, int fineness) =>
    rounded(BigInt.from(quantityMg) * BigInt.from(fineness), BigInt.from(750));

/// Milligrams in one mithqal (4.6083 g), as the ten-thousandths used below.
/// [mesghalMilli] returns thousandths of a mithqal from milligrams.
BigInt mesghalMilli(BigInt mg) =>
    rounded(mg * BigInt.from(10000), BigInt.from(46083));

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

  /// The gain or loss as tenths of a percent (12.5% → 125). Null when the
  /// recorded cost is zero, where a percentage would say nothing.
  BigInt? get profitTenths {
    final gain = profit;
    if (gain == null || cost <= BigInt.zero) return null;
    return signedRounded(gain * BigInt.from(1000), cost);
  }
}

/// The change between the newest two observations of one price.
class QuoteDelta {
  const QuoteDelta(this.amount, this.tenths);
  final BigInt amount;
  final BigInt? tenths;
}

QuoteDelta? quoteDelta(List<Quote> newestFirst) {
  if (newestFirst.length < 2) return null;
  final latest = BigInt.from(newestFirst[0].unitRial);
  final previous = BigInt.from(newestFirst[1].unitRial);
  final amount = latest - previous;
  return QuoteDelta(
    amount,
    previous <= BigInt.zero
        ? null
        : signedRounded(amount * BigInt.from(1000), previous),
  );
}

class Valuation {
  Valuation(List<Holding> holdings, List<Quote> quotes, DateTime asOf)
    : asOf = civilDay(asOf) {
    // Every observation is history, including a future-dated one (older
    // versions could store one): it used to vanish from the price screen and
    // could never be corrected. Valuation below uses only the observations
    // dated up to today.
    final sortedQuotes = [...quotes]..sort(_newestQuoteFirst);
    for (final quote in sortedQuotes) {
      history.putIfAbsent(quote.market.key, () => []).add(quote);
    }
    final usable = <String, List<Quote>>{};
    for (final quote in sortedQuotes) {
      if (quote.date.isAfter(this.asOf)) continue;
      usable.putIfAbsent(quote.market.key, () => []).add(quote);
    }
    for (final entry in usable.entries) {
      _latest[entry.key] = entry.value.first;
    }

    // A stable order inside the book: the same lot stays in the same place
    // after it is edited, and purchases of one asset sit together oldest
    // first. The store lists by save time, which was the opposite.
    final ordered = [...holdings]..sort(_holdingOrder);
    for (final holding in ordered) {
      final candidate = latest(holding.market);
      final quote =
          candidate != null &&
              !candidate.date.isBefore(holding.bought) &&
              !holding.bought.isAfter(this.asOf)
          ? candidate
          : null;
      final cost = costOf(holding);
      final value = quote == null ? null : valueAt(holding, quote);
      positions.add(Position(holding, quote, cost, value));
      typeCounts.update(
        holding.market.type,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
      if (value != null) {
        total += value;
        pricedCost += cost;
        priced++;
        byType.update(
          holding.market.type,
          (sum) => sum + value,
          ifAbsent: () => value,
        );
      }
      if (holding.market.type == AssetType.gold &&
          !holding.bought.isAfter(this.asOf)) {
        _goldPptMg +=
            BigInt.from(holding.quantity) * BigInt.from(holding.fineness);
      }
    }
  }

  final DateTime asOf;
  final history = <String, List<Quote>>{};
  final positions = <Position>[];
  final byType = <AssetType, BigInt>{};
  final typeCounts = <AssetType, int>{};
  final _latest = <String, Quote>{};
  BigInt total = BigInt.zero, pricedCost = BigInt.zero;
  BigInt _goldPptMg = BigInt.zero;
  int priced = 0;

  int get unpriced => positions.length - priced;
  BigInt get profit => total - pricedCost;

  /// The gain or loss as tenths of a percent of the priced cost.
  BigInt? get profitTenths => pricedCost <= BigInt.zero
      ? null
      : signedRounded(profit * BigInt.from(1000), pricedCost);

  BigInt get goldMg => rounded(_goldPptMg, BigInt.from(750));
  Quote? latest(AssetMarket market) => _latest[market.key];

  /// Days since the newest usable price of [market], or null when there is
  /// none.
  int? ageOf(AssetMarket market) {
    final quote = latest(market);
    return quote == null ? null : civilDaysBetween(quote.date, asOf);
  }

  BigInt? equivalent(AssetMarket market, int factor) {
    final rate = latest(market);
    return rate == null || priced == 0
        ? null
        : rounded(total * BigInt.from(factor), BigInt.from(rate.unitRial));
  }

  /// The first lot, in the same order as the screen, whose value is unknown.
  Position? get firstUnpriced =>
      positions.where((position) => position.value == null).firstOrNull;

  /// The priced lot whose rate is the oldest — the one to refresh first.
  /// Gold and the standard coins sort before currencies, so the nudge asks
  /// for the benchmark people update most often.
  ({AssetMarket market, int days})? get oldestPricedQuote {
    ({AssetMarket market, int days})? oldest;
    for (final position in positions) {
      final quote = position.quote;
      if (quote == null) continue;
      final days = civilDaysBetween(quote.date, asOf);
      if (oldest == null || days > oldest.days) {
        oldest = (market: position.holding.market, days: days);
      }
    }
    return oldest;
  }

  static int _newestQuoteFirst(Quote a, Quote b) {
    final byDay = b.date.compareTo(a.date);
    if (byDay != 0) return byDay;
    final bySave = b.record.updatedAt.compareTo(a.record.updatedAt);
    return bySave != 0 ? bySave : b.record.id.compareTo(a.record.id);
  }

  static int _holdingOrder(Holding a, Holding b) {
    final byMarket = compareMarkets(a.market, b.market);
    if (byMarket != 0) return byMarket;
    final byBought = a.bought.compareTo(b.bought);
    if (byBought != 0) return byBought;
    return a.record.id.compareTo(b.record.id);
  }
}
