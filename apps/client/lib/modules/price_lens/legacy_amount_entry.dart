import 'package:flutter/material.dart';

import 'amount_field.dart';
import 'irr_unit.dart';
import 'money_words.dart';

/// Compatibility boundary only: old sub-rial quotes must never be silently
/// truncated by the shared whole-rial field. New observations use AmountField.
class LensAmountEntry extends StatelessWidget {
  const LensAmountEntry({
    super.key,
    required this.controller,
    required this.currency,
    required this.digits,
    required this.unit,
    required this.label,
    this.legacyMinor,
    this.errorText,
    this.hint,
    this.fieldKey,
  });
  final TextEditingController controller;
  final String currency, label;
  final int digits;
  final IrrUnit unit;
  final int? legacyMinor;
  final String? errorText, hint;
  final Key? fieldKey;
  @override
  Widget build(BuildContext context) {
    if (currency == 'IRR' && legacyMinor != null && legacyMinor! % 100 != 0) {
      return TextField(
        key: fieldKey,
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textDirection: TextDirection.ltr,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          errorText: errorText,
          suffixText: currencyUnitWord(
            currency,
            unit,
            persian: Directionality.of(context) == TextDirection.rtl,
          ),
        ),
      );
    }
    return AmountField(
      controller: controller,
      currency: currency,
      digits: digits,
      unit: unit,
      label: label,
      hint: hint,
      errorText: errorText,
      fieldKey: fieldKey,
    );
  }
}
