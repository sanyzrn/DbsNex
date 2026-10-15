/// One offer under the lens: a labelled package, its price, what it
/// contains, and any discount — everything the person typed, nothing
/// scraped, nothing implied. The effective price (what is actually
/// paid) and the total quantity are derived exactly, in
/// `comparison.dart`.
library;

import 'money.dart';
import 'rational.dart';
import 'units.dart';
import 'local_values.dart';
part 'price_memory.dart';
part 'saved_comparison.dart';

/// How a discount is given: a percentage, a fixed amount off, or none.
/// Never both — an invisible second discount is exactly the trick
/// this module exists to see through.
enum DiscountKind { none, percent, fixed }

class PriceOption {
  PriceOption({
    required this.id,
    required this.label,
    required this.priceMinor,
    required this.currency,
    required this.quantity,
    required this.unitKey,
    this.packageCount = 1,
    this.paidCount,
    this.discount = DiscountKind.none,
    this.discountPercent,
    this.discountMinor,
    this.shippingMinor,
    this.date,
    this.valid = true,
    this.source,
  });

  final String id;

  /// Product or shop label, free text.
  final String label;

  /// The total package price, integer minor units of [currency].
  final int priceMinor;
  final String currency;

  /// How much one package contains, as an exact fraction of [unitKey]
  /// (0.75 kg is 3/4; 750 g is 750).
  final Fraction quantity;
  final String unitKey;

  /// Packages received in this offer. A 6-pack is 6; a "2+1 free" is 3.
  final int packageCount;

  /// Packages paid for, when the offer marks it — a "2+1 free" pays
  /// for 2 and receives 3. Null means all of them are paid for.
  final int? paidCount;

  final DiscountKind discount;

  /// 0–100, for percentage discounts only.
  final int? discountPercent;

  /// Minor units off, for fixed discounts only.
  final int? discountMinor;

  /// Shipping or basket share allocated to this offer — only what the
  /// person explicitly entered, added to what is paid.
  final int? shippingMinor;

  /// When it was shopped, if dated.
  final DateTime? date;

  /// False when a stored body was malformed: shown, fixable, never
  /// counted.
  final bool valid;
  final Map<String, Object?>? source;

  PriceUnit? get unit => priceUnitOf(unitKey);

  Map<String, Object?> toBody() => {
    'label': label,
    'price': priceMinor,
    'currency': currency,
    ...priceMetadata(currency),
    'quantity': quantity.numerator,
    if (quantity.denominator != 1) 'quantityDen': quantity.denominator,
    'unit': unitKey,
    'packageCount': packageCount,
    if (paidCount != null) 'paidCount': paidCount,
    'discount': discount.name,
    if (discountPercent != null) 'discountPercent': discountPercent,
    if (discountMinor != null) 'discountMinor': discountMinor,
    if (shippingMinor != null) 'shippingMinor': shippingMinor,
    if (date != null) 'date': date!.toIso8601String(),
    'schema': 2,
  };

  static PriceOption fromBody(String id, Map<String, Object?> body) {
    final label = _stringOf(body, 'label')?.trim() ?? '';
    final price = body['price'],
        currency = body['currency_code'] ?? body['currency'];
    final unit = _stringOf(body, 'unit'),
        q = body['quantity'],
        den = body['quantityDen'] ?? 1;
    final count = body['packageCount'] ?? 1, paid = body['paidCount'];
    final discountName = body['discount'] ?? 'none';
    final discount = switch (discountName) {
      'percent' => DiscountKind.percent,
      'fixed' => DiscountKind.fixed,
      _ => DiscountKind.none,
    };
    final percent = body['discountPercent'],
        fixed = body['discountMinor'],
        shipping = body['shippingMinor'];
    final dateRaw = body['date'],
        date = dateRaw == null ? null : priceCalendar(dateRaw);
    final valid =
        label.isNotEmpty &&
        boundedMoney(price) &&
        priceMetadataValid(body) &&
        unit != null &&
        priceUnitOf(unit) != null &&
        q is int &&
        q > 0 &&
        q <= 999999999999999 &&
        den is int &&
        den > 0 &&
        den <= 1000000 &&
        Fraction(q, den).terminatesWithin(priceUnitOf(unit)!.decimals) &&
        count is int &&
        count > 0 &&
        count <= 100000 &&
        (paid == null || (paid is int && paid > 0 && paid <= count)) &&
        (dateRaw == null || date != null) &&
        ['none', 'percent', 'fixed'].contains(discountName) &&
        (shipping == null || boundedMoney(shipping)) &&
        switch (discount) {
          DiscountKind.none => percent == null && fixed == null,
          DiscountKind.percent =>
            percent is int && percent >= 0 && percent <= 100 && fixed == null,
          DiscountKind.fixed =>
            boundedMoney(fixed) &&
                price is int &&
                (fixed as int) <= price &&
                percent == null,
        };
    final quantityNumerator = q, packageCount = count;
    return PriceOption(
      id: id,
      label: label.isEmpty ? id : label,
      priceMinor: price is int ? price : 0,
      currency: currency is String ? currency : '',
      quantity: quantityNumerator is int
          ? Fraction(
              quantityNumerator,
              den is int && den > 0 && den <= 1000000 ? den : 1,
            )
          : const Fraction(0),
      unitKey: unit ?? 'piece',
      packageCount: packageCount is int ? packageCount : 1,
      paidCount: _intOrNull(body['paidCount']),
      discount: discount,
      discountPercent: _intOrNull(percent),
      discountMinor: _intOrNull(body['discountMinor']),
      shippingMinor: _intOrNull(body['shippingMinor']),
      date: date,
      valid: valid,
      source: Map.of(body),
    );
  }

  /// A short description of the offer's shape, for memory matching.
  Map<String, Object?> get spec => {
    'label': label,
    'quantity': quantity.numerator,
    if (quantity.denominator != 1) 'quantityDen': quantity.denominator,
    'unit': unitKey,
    'packageCount': packageCount,
    'currency': currency,
    ...priceMetadata(currency),
  };
}

int _intOr(Object? value, int fallback) => value is int ? value : fallback;

int? _intOrNull(Object? value) => value is int ? value : null;

String? _stringOf(Map<String, Object?> body, String key) {
  final value = body[key];
  return value is String ? value : null;
}

/// The exponent to display a currency's amounts with, defended.
int displayExponentOf(String? code) => priceExponentOf(code);

bool boundedMoney(Object? value) =>
    value is int && value >= 0 && value <= priceMax;
DateTime? priceCalendar(Object? value) {
  if (LocalValues.stamp(value) == null) return null;
  final text = value as String;
  final date = DateTime.tryParse(text.substring(0, 10));
  return date;
}

bool optionSafe(PriceOption o) {
  try {
    return o.valid && PriceOption.fromBody(o.id, o.toBody()).valid;
  } catch (_) {
    return false;
  }
}
