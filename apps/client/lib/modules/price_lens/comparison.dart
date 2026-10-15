/// The Price Lens's arithmetic: the effective price of an offer (what
/// is actually paid, discounts applied exactly once), the total
/// quantity received, and the unit prices compared as exact
/// fractions. Everything the result panel shows is computed here.
///
/// Three invariants:
///
/// * **One currency.** Offers in different currencies are not
///   comparable; there is no exchange rate and none is implied.
/// * **One family.** Grams against litres is not a question this
///   module answers by guessing a density — it says so and stops.
/// * **No floating point.** Unit prices are [Fraction]s; only the
///   final display is rounded, and it says `≈` when it is.
library;

import 'money.dart';
import 'options.dart';
import 'rational.dart';
import 'units.dart';
import 'local_values.dart';

/// What is actually paid for [option], as an exact fraction of minor
/// units: price, minus the discount (once — percentage or fixed,
/// never both), plus the shipping share. A percentage discount is
/// `price × (100 − pct) / 100`, exact.
Fraction effectivePriceMinor(PriceOption option) {
  var paid = Fraction(option.priceMinor);
  switch (option.discount) {
    case DiscountKind.percent:
      final percent = option.discountPercent ?? 0;
      paid = paid * Fraction(100 - percent, 100);
    case DiscountKind.fixed:
      paid = paid - Fraction(option.discountMinor ?? 0);
    case DiscountKind.none:
      break;
  }
  final shipping = option.shippingMinor;
  if (shipping != null) {
    paid = paid + Fraction(shipping);
  }
  // A fixed discount larger than the price is refused at entry; this
  // is the defensive floor for hand-written records.
  if (paid < const Fraction(0)) paid = const Fraction(0);
  return paid;
}

/// Everything received: the per-package quantity times the package
/// count, converted to [common] exactly. Null when the units are of
/// different families — not comparable, never guessed.
Fraction? totalQuantityIn(PriceOption option, PriceUnit common) {
  final unit = option.unit;
  if (unit == null) return null;
  return convertQuantity(
    option.quantity * Fraction(option.packageCount),
    unit,
    common,
  );
}

/// One offer's standing against the comparison.
class OptionResult {
  const OptionResult({
    required this.option,
    required this.unitPriceMinor,
    required this.quantityInCommon,
    this.isBest = false,
    this.notComparable = false,
  });

  final PriceOption option;

  /// Minor units per one common unit, exact — the number the whole
  /// module turns on. Null when not comparable.
  final Fraction? unitPriceMinor;

  /// Total quantity in the common unit.
  final Fraction? quantityInCommon;

  final bool isBest;

  /// Why this option cannot join the comparison.
  final bool notComparable;
}

/// Why a comparison cannot happen at all.
enum ComparisonState {
  tooFewOptions,
  mixedCurrencies,
  mixedFamilies,
  incompleteOption,
  ready,
}

/// Runs the comparison of [options] in [commonUnit] at a moment.
/// Options are compared only when every one is valid, in one
/// currency and one family; anything else is said, not smoothed.
class Comparison {
  const Comparison({
    required this.state,
    required this.results,
    this.currency,
    this.family,
  });

  final ComparisonState state;
  final List<OptionResult> results;

  /// The one currency every offer shares, when they do.
  final String? currency;

  final UnitFamily? family;

  /// The best (lowest) exact unit price, or null.
  Fraction? get bestUnitPrice {
    Fraction? best;
    for (final result in results) {
      final price = result.unitPriceMinor;
      if (price == null) continue;
      if (best == null || price < best) best = price;
    }
    return best;
  }

  int? get bestIndex {
    var index = 0;
    for (final result in results) {
      final price = result.unitPriceMinor;
      if (price != null && result.isBest) return index;
      index++;
    }
    return null;
  }
}

/// Compares [options] (2 to 4) in [commonUnit]. The [commonUnit]'s
/// family and the offers' currencies decide comparability; the best
/// offer is the lowest exact unit price, ties included.
Comparison compareOptions(List<PriceOption> options, PriceUnit commonUnit) {
  if (options.length < 2 || options.length > 4) {
    return const Comparison(state: ComparisonState.tooFewOptions, results: []);
  }
  if (options.any((o) => !optionSafe(o))) {
    return const Comparison(
      state: ComparisonState.incompleteOption,
      results: [],
    );
  }
  final currency = options.first.currency;
  if (options.any((o) => o.currency != currency)) {
    return const Comparison(
      state: ComparisonState.mixedCurrencies,
      results: [],
    );
  }
  // The common unit decides the family: an offer in another family is
  // not comparable — v1 disallows mass-vs-volume outright.
  final family = commonUnit.family;
  if (options.any((option) => option.unit!.family != family)) {
    return Comparison(
      state: ComparisonState.mixedFamilies,
      results: [
        for (final option in options)
          OptionResult(
            option: option,
            unitPriceMinor: null,
            quantityInCommon: null,
            notComparable: true,
          ),
      ],
    );
  }
  final results = <OptionResult>[];
  Fraction? best;
  for (final option in options) {
    final quantity = totalQuantityIn(option, commonUnit);
    if (quantity == null || quantity <= const Fraction(0)) {
      results.add(
        OptionResult(
          option: option,
          unitPriceMinor: null,
          quantityInCommon: null,
          notComparable: true,
        ),
      );
      continue;
    }
    final price = effectivePriceMinor(option);
    final unitPrice = price / quantity;
    results.add(
      OptionResult(
        option: option,
        unitPriceMinor: unitPrice,
        quantityInCommon: quantity,
      ),
    );
    if (best == null || unitPrice < best) best = unitPrice;
  }
  // Mark the best: every offer at the lowest price is marked, ties
  // are equals and never broken by a rounding step.
  final marked = [
    for (final result in results)
      if (result.unitPriceMinor != null && result.unitPriceMinor == best)
        OptionResult(
          option: result.option,
          unitPriceMinor: result.unitPriceMinor,
          quantityInCommon: result.quantityInCommon,
          isBest: true,
        )
      else
        result,
  ];
  if (marked.any((r) => r.notComparable)) {
    return Comparison(state: ComparisonState.mixedFamilies, results: marked);
  }
  return Comparison(
    state: ComparisonState.ready,
    results: marked,
    currency: currency,
    family: family,
  );
}

/// The extra paid by choosing [result] over the best: per common unit
/// and for the amount this offer contains. Exact fractions in minor
/// units.
({Fraction perUnit, Fraction forThisAmount})? savingsOf(
  OptionResult result,
  Fraction best,
) {
  final price = result.unitPriceMinor;
  final quantity = result.quantityInCommon;
  if (price == null || quantity == null || price <= best) return null;
  final perUnit = price - best;
  return (perUnit: perUnit, forThisAmount: perUnit * quantity);
}

/// Formats an exact minor-unit [fraction] for display, in major units:
/// grouped integer part when it is whole, `≈` decimal when it is not
/// (the rounding is display-only; the comparison above never rounded).
String formatMinorFraction(
  Fraction fraction,
  int exponent, {
  required bool persian,
}) {
  final scaled = fraction / Fraction(_pow10(exponent));
  // Fractions are never normalised, so "whole" is a modulo question,
  // not a denominator == 1 question: 12000/100 is 120, exactly.
  if (scaled.exactNumerator % scaled.exactDenominator == BigInt.zero) {
    return groupLocal(
      (scaled.exactNumerator ~/ scaled.exactDenominator).toString(),
      persian,
    );
  }
  final approximate = scaled.toDecimalString(digits: exponent + 2);
  final trimmed = approximate.replaceFirst(RegExp(r'0+$'), '');
  final cut = trimmed.endsWith('.')
      ? trimmed.substring(0, trimmed.length - 1)
      : trimmed;
  final shown = persian ? persianLocal(cut) : cut;
  return '${scaled.terminatesWithin(exponent + 2) ? '' : '≈'}$shown';
}

int _pow10(int n) {
  var result = 1;
  for (var i = 0; i < n; i++) {
    result *= 10;
  }
  return result;
}

/// The memory match for an offer: an earlier price the person entered
/// for the same product and the same package specification. Only an
/// exact spec match counts — a claim that a price rose needs
/// comparable goods, verified dates, and a purely mathematical
/// difference.
PriceMemory? memoryMatchFor(PriceOption option, List<PriceMemory> memories) {
  if (!optionSafe(option)) return null;
  final before = option.date ?? DateTime.now();
  PriceMemory? match;
  final label = option.label.trim().toLowerCase().replaceAll(
    RegExp(r'\s+'),
    ' ',
  );
  for (final m in memories) {
    if (m.label.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ') != label ||
        m.currency != option.currency ||
        m.packageCount != option.packageCount) {
      continue;
    }
    if (LocalValues.stamp(m.date.toIso8601String()) == null ||
        !DateTime(
          m.date.year,
          m.date.month,
          m.date.day,
        ).isBefore(DateTime(before.year, before.month, before.day))) {
      continue;
    }
    final from = priceUnitOf(m.unitKey), to = option.unit;
    if (from == null ||
        to == null ||
        convertQuantity(m.quantity, from, to) != option.quantity) {
      continue;
    }
    if (match == null ||
        m.date.isAfter(match.date) ||
        m.date == match.date && m.id.compareTo(match.id) > 0) {
      match = m;
    }
  }
  return match;
}

Fraction memoryDifference(PriceOption o, PriceMemory m) =>
    effectivePriceMinor(o) - m.exactPaid;
int memoryDifferenceMinor(PriceOption o, PriceMemory m) =>
    memoryDifference(o, m).roundHalfUp();
