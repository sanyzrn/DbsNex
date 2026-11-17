import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'currency_scales.dart';
import 'module.dart';

class CurrencyField extends StatelessWidget {
  const CurrencyField({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final String value;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    borderRadius: nexDropdownRadius,
    dropdownColor: nexDropdownColor(context),
    key: ValueKey(value),
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(
      labelText: smokeFreeStrings(context, 'currency'),
    ),
    items: [
      for (final code in {
        'IRR',
        'USD',
        'EUR',
        'GBP',
        'AED',
        'JPY',
        'KWD',
        ...currencyScales.keys,
        value,
      })
        DropdownMenuItem(
          value: code,
          // In Persian the rial is named, its code beside it.
          child: Text(
            code == 'IRR' && Directionality.of(context) == TextDirection.rtl
                ? 'ریال (IRR)'
                : code,
          ),
        ),
    ],
    onChanged: onChanged == null
        ? null
        : (code) {
            if (code != null) onChanged!(code);
          },
  );
}
