part of 'options.dart';

/// A price-memory snapshot the person chose to keep: what, how much
/// of it, for what price, on what day — explicitly "you entered
/// this", never a market rate.
class PriceMemory {
  PriceMemory({
    required this.id,
    required this.label,
    required this.priceMinor,
    required this.currency,
    required this.quantity,
    required this.unitKey,
    required this.date,
    this.packageCount = 1,
    this.paidFraction,
    this.source,
  });

  final String id;
  final String label;
  final int priceMinor;
  final String currency;
  final Fraction quantity;
  final String unitKey;
  final DateTime date;
  final int packageCount;
  final Fraction? paidFraction;
  Fraction get exactPaid => paidFraction ?? Fraction(priceMinor);
  final Map<String, Object?>? source;

  Map<String, Object?> toBody() => {
    'label': label,
    'price': priceMinor,
    'currency': currency,
    ...priceMetadata(currency),
    'quantity': quantity.numerator,
    if (quantity.denominator != 1) 'quantityDen': quantity.denominator,
    'unit': unitKey,
    'packageCount': packageCount,
    'date': date.toIso8601String(),
    if (paidFraction != null)
      'paid_num': paidFraction!.exactNumerator.toString(),
    if (paidFraction != null)
      'paid_den': paidFraction!.exactDenominator.toString(),
    'schema': 2,
  };

  static PriceMemory? fromBody(String id, Map<String, Object?> body) {
    final label = _stringOf(body, 'label');
    final price = body['price'];
    final currency = body['currency_code'] ?? body['currency'];
    final unit = _stringOf(body, 'unit');
    final quantity = body['quantity'];
    final dateRaw = _stringOf(body, 'date');
    final date = dateRaw == null ? null : priceCalendar(dateRaw);
    if (label == null ||
        label.trim().isEmpty ||
        !(price is int && price >= 0 && price <= priceMax * 2) ||
        !priceMetadataValid(body) ||
        currency is! String ||
        unit == null ||
        priceUnitOf(unit) == null ||
        quantity is! int ||
        quantity <= 0 ||
        quantity > 999999999999999 ||
        (body['quantityDen'] != null &&
            (body['quantityDen'] is! int ||
                (body['quantityDen'] as int) <= 0 ||
                (body['quantityDen'] as int) > 1000000)) ||
        (body['packageCount'] != null &&
            (body['packageCount'] is! int ||
                (body['packageCount'] as int) <= 0 ||
                (body['packageCount'] as int) > 100000)) ||
        date == null) {
      return null;
    }
    Fraction? exact;
    if (body.containsKey('paid_num') || body.containsKey('paid_den')) {
      final n = body['paid_num'], den = body['paid_den'];
      if (n is! String ||
          den is! String ||
          n.length > 18 ||
          den.length > 3 ||
          !RegExp(r'^[0-9]+$').hasMatch(n) ||
          !RegExp(r'^[0-9]+$').hasMatch(den)) {
        return null;
      }
      final nn = BigInt.parse(n), dd = BigInt.parse(den);
      if (dd <= BigInt.zero || dd > BigInt.from(100)) return null;
      exact = Fraction.exact(nn, dd);
      if (exact < const Fraction(0) ||
          exact > const Fraction(priceMax * 2) ||
          exact.roundHalfUp() != price) {
        return null;
      }
    }
    return PriceMemory(
      id: id,
      label: label,
      priceMinor: price,
      currency: currency,
      quantity: Fraction(quantity, _intOr(body['quantityDen'], 1)),
      unitKey: unit,
      date: date,
      packageCount: _intOr(body['packageCount'], 1),
      paidFraction: exact,
      source: Map.of(body),
    );
  }
}
