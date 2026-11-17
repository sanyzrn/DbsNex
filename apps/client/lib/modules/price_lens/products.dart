import 'options.dart';
import 'rational.dart';
import 'units.dart';

/// Exact identity from the person's own name, currency and measurement kind.
/// A retailer or a similar-looking brand is never inferred from the name.
String productNameKey(String name) => name
    .trim()
    .toLowerCase()
    .replaceAll('ي', 'ی')
    .replaceAll('ك', 'ک')
    .replaceAll('\u200c', ' ')
    .replaceAll(RegExp(r'\s+'), ' ');
String productKeyOf(PriceMemory m) =>
    '${m.currency}|${priceUnitOf(m.unitKey)!.family.name}|${productNameKey(m.productLabel)}';
DateTime priceDay(DateTime day) => DateTime(day.year, day.month, day.day);

class LensProduct {
  LensProduct(this.key, List<PriceMemory> prices)
    : prices = List<PriceMemory>.unmodifiable(
        List<PriceMemory>.of(prices)..sort((a, b) {
          final date = priceDay(a.date).compareTo(priceDay(b.date));
          if (date != 0) return date;
          final stamp = (a.recordedAt ?? a.date).compareTo(
            b.recordedAt ?? b.date,
          );
          return stamp == 0 ? a.id.compareTo(b.id) : stamp;
        }),
      );
  final String key;
  final List<PriceMemory> prices;
  String get label => prices.last.productLabel;
  String get currency => prices.last.currency;
  PriceUnit get common =>
      canonicalUnitOf(priceUnitOf(prices.last.unitKey)!.family);
  PriceMemory? latestKnown(DateTime today) {
    final known = prices.where(
      (p) => !priceDay(p.date).isAfter(priceDay(today)),
    );
    return known.isEmpty ? null : known.last;
  }

  PriceMemory? previousDay(PriceMemory latest) {
    final previous = prices.where(
      (p) => priceDay(p.date).isBefore(priceDay(latest.date)),
    );
    return previous.isEmpty ? null : previous.last;
  }
}

List<LensProduct> productHistory(Iterable<PriceMemory> memories) {
  final groups = <String, List<PriceMemory>>{};
  for (final m in memories) {
    if (priceUnitOf(m.unitKey) == null) continue;
    (groups[productKeyOf(m)] ??= []).add(m);
  }
  return [
    for (final e in groups.entries) LensProduct(e.key, e.value),
  ]..sort((a, b) => productNameKey(a.label).compareTo(productNameKey(b.label)));
}

Fraction memoryUnitPrice(PriceMemory m, PriceUnit common) =>
    m.exactPaid /
    convertQuantity(
      m.quantity * Fraction(m.packageCount),
      priceUnitOf(m.unitKey)!,
      common,
    )!;

/// Signed percentage of an earlier comparable unit price. A free baseline
/// has no percentage increase; the UI still shows both exact observations.
Fraction? productChange(LensProduct product, DateTime today) {
  final latest = product.latestKnown(today);
  if (latest == null) return null;
  final old = product.previousDay(latest);
  if (old == null) return null;
  final before = memoryUnitPrice(old, product.common);
  if (before == const Fraction(0)) return null;
  return (memoryUnitPrice(latest, product.common) - before) /
      before *
      const Fraction(100);
}

/// One decimal, rounded only for presentation; no native-int overflow even
/// when a tiny old price is followed by a very large one.
String percentageChangeText(Fraction value) {
  final n = value.exactNumerator, d = value.exactDenominator;
  final tenths = (n.abs() * BigInt.from(20) + d) ~/ (d * BigInt.two);
  final whole = tenths ~/ BigInt.from(10), rest = tenths % BigInt.from(10);
  return '${n.isNegative
      ? '−'
      : n == BigInt.zero
      ? ''
      : '+'}$whole${rest == BigInt.zero ? '' : '.$rest'}';
}

int elapsedPriceDays(DateTime from, DateTime to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;
