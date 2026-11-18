import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'comparison.dart';
import 'money.dart';
import 'money_format.dart';
import 'money_words.dart';
import 'irr_unit.dart';
import 'privacy.dart';
import 'rational.dart';

/// The exact calculator keeps its legacy internal scale. Only this boundary
/// expresses Iranian amounts in whole rials/tomans, through the reference.
String lensMoney(
  BuildContext context,
  Fraction minor,
  String currency, {
  IrrUnit unit = IrrUnit.rial,
}) {
  if (lensAmountsHidden(context)) return '••••';
  final fa = NexModuleStrings.persian(context);
  if (currency == 'IRR') {
    final rial = minor / const Fraction(100);
    if (rial.exactNumerator % rial.exactDenominator == BigInt.zero &&
        rial.exactNumerator.abs() ~/ rial.exactDenominator <=
            BigInt.from(maxMoney)) {
      return formatAmount(
        (rial.exactNumerator ~/ rial.exactDenominator).toInt(),
        'IRR',
        0,
        fa,
        unit,
      );
    }
    final word = currencyUnitWord('IRR', unit, persian: fa);
    return '${formatMinorFraction(minor, unit == IrrUnit.toman ? 3 : 2, persian: fa)} $word';
  }
  return '${formatMinorFraction(minor, priceExponentOf(currency), persian: fa)} \u2066$currency\u2069';
}
