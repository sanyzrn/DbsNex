import 'package:flutter/material.dart';

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
    key: ValueKey(value),
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(
      labelText: lentStrings(context, 'currency'),
      border: const OutlineInputBorder(),
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
          child: Text(code, textDirection: TextDirection.ltr),
        ),
    ],
    onChanged: onChanged == null
        ? null
        : (code) {
            if (code != null) onChanged!(code);
          },
  );
}
