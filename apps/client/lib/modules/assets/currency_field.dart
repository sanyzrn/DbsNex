import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'currency_scales.dart';
import 'module.dart';
import 'presentation.dart' show currencyName;

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
    decoration: InputDecoration(labelText: assetStrings(context, 'currency')),
    items: [
      for (final code in {
        'USD',
        'EUR',
        'GBP',
        'AED',
        'TRY',
        'JPY',
        'KWD',
        ...currencyScales.keys,
        value,
      })
        if (code != 'IRR')
          DropdownMenuItem(
            value: code,
            child: Text(
              currencyName(context, code) == code
                  ? code
                  : '${currencyName(context, code)} ($code)',
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
