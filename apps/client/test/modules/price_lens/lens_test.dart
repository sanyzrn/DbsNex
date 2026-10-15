import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/price_lens/comparison.dart';
import 'package:nex_client/modules/price_lens/money.dart';
import 'package:nex_client/modules/price_lens/options.dart';
import 'package:nex_client/modules/price_lens/rational.dart';
import 'package:nex_client/modules/price_lens/units.dart';

/// The lens's arithmetic, exactly: fractions, unit conversion, money
/// parsing for every exponent, and the comparison rules the brief
/// names — 2×500ml vs 1L, 750g vs 1kg, 2+1 free, one discount applied
/// once, 0% and 100%, shipping, mixed currencies and families refused,
/// ties never broken, memory matching spec-exact.
part 'lens_cases_1.dart';
part 'lens_cases_2.dart';
part 'lens_cases_3.dart';

PriceOption offer(
  String id,
  int price, {
  String currency = 'IRR',
  Fraction quantity = const Fraction(1),
  String unit = 'kg',
  int packageCount = 1,
  int? paidCount,
  DiscountKind discount = DiscountKind.none,
  int? percent,
  int? fixedMinor,
  int? shippingMinor,
  DateTime? date,
}) => PriceOption(
  id: id,
  label: id,
  priceMinor: price,
  currency: currency,
  quantity: quantity,
  unitKey: unit,
  packageCount: packageCount,
  paidCount: paidCount,
  discount: discount,
  discountPercent: percent,
  discountMinor: fixedMinor,
  shippingMinor: shippingMinor,
  date: date,
);

void main() {
  _lensCases1();
  _lensCases2();
  _lensCases3();
}
