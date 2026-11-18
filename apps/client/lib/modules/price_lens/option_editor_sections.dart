import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'money.dart';
import 'options.dart';
import 'price_lens_common.dart';
import 'strings.dart';
import 'units.dart';
import 'choices.dart';
import 'legacy_amount_entry.dart';
import 'privacy.dart';

/// The offer editor's two long sections: the unit picker (a wrapping
/// pill row that names its family) and the discount section (one
/// kind, one value, applied once).

/// The quantity unit: every unit the module knows, with the family
/// named once one is chosen.
class LensUnitPicker extends StatelessWidget {
  const LensUnitPicker({
    super.key,
    required this.selectedKey,
    required this.onSelected,
  });

  final String selectedKey;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = priceLensStrings;
    final unit = priceUnitOf(selectedKey)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(s(context, 'unitLabel'), style: theme.textTheme.labelLarge),
        const SizedBox(height: NexSpacing.xs),
        LensChoices<String>(
          key: const ValueKey('lens-units'),
          values: priceUnits.map((u) => u.key).toList(),
          value: selectedKey,
          label: (key) =>
              s(context, 'unit${key[0].toUpperCase()}${key.substring(1)}'),
          keyFor: (key) => ValueKey('lens-unit-$key'),
          onChanged: onSelected,
        ),
        if (unit.family != UnitFamily.piece)
          Text(
            s(context, switch (unit.family) {
              UnitFamily.mass => 'unitFamilyMass',
              UnitFamily.volume => 'unitFamilyVolume',
              UnitFamily.piece => 'unitFamilyPiece',
              UnitFamily.roll => 'unitFamilyRoll',
              UnitFamily.sheet => 'unitFamilySheet',
            }),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

/// The discount: one kind — none, a percentage, or a fixed amount —
/// and its value. Never both; applied once, to the entered price.
class LensDiscountSection extends StatelessWidget {
  const LensDiscountSection({
    super.key,
    required this.kind,
    required this.controller,
    required this.currency,
    required this.onKindChanged,
    this.irrUnit = IrrUnit.rial,
    required this.onChanged,
    this.legacyMinor,
    this.error,
  });

  final IrrUnit irrUnit;
  final DiscountKind kind;
  final TextEditingController controller;
  final PriceCurrency currency;
  final ValueChanged<DiscountKind> onKindChanged;
  final VoidCallback onChanged;
  final int? legacyMinor;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = priceLensStrings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(s(context, 'discountLabel'), style: theme.textTheme.labelLarge),
        const SizedBox(height: NexSpacing.xs),
        LensChoices<DiscountKind>(
          values: DiscountKind.values,
          value: kind,
          label: (v) => s(context, switch (v) {
            DiscountKind.none => 'discountNone',
            DiscountKind.percent => 'discountPercentKind',
            DiscountKind.fixed => 'discountFixedKind',
          }),
          keyFor: (v) => ValueKey('lens-discount-${v.name}'),
          onChanged: onKindChanged,
        ),
        NexSegmentSwap(
          selection: kind,
          child: kind == DiscountKind.none
              ? const SizedBox.shrink()
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: NexSpacing.xs),
                    if (lensAmountsHidden(context))
                      const Text('••••')
                    else if (kind == DiscountKind.fixed)
                      LensAmountEntry(
                        legacyMinor: legacyMinor,
                        controller: controller,
                        currency: currency.code,
                        digits: currency.code == 'IRR' ? 0 : currency.exponent,
                        unit: irrUnit,
                        label: s(context, 'discountFixedKind'),
                        errorText: error,
                        fieldKey: const ValueKey('lens-discount-value'),
                      )
                    else
                      TextField(
                        key: const ValueKey('lens-discount-value'),
                        controller: controller,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        textDirection: TextDirection.ltr,
                        decoration: InputDecoration(
                          labelText: kind == DiscountKind.percent
                              ? s(context, 'discountPercentField')
                              : s(context, 'discountFixedKind'),
                          suffixText: kind == DiscountKind.percent
                              ? '%'
                              : currency.code == 'IRR' &&
                                    irrUnit == IrrUnit.toman
                              ? s(context, 'tomanUnit')
                              : currency.code,
                          errorText: error,
                        ),
                        onChanged: (_) => onChanged(),
                      ),
                    const SizedBox(height: NexSpacing.xs),
                    Text(
                      s(context, 'discountOnceNote'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}
