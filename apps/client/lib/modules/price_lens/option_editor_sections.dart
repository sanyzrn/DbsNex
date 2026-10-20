import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'money.dart';
import 'options.dart';
import 'price_lens_common.dart';
import 'strings.dart';
import 'units.dart';

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
        Wrap(
          key: const ValueKey('lens-units'),
          spacing: NexSpacing.sm,
          runSpacing: NexSpacing.xs,
          children: [
            for (final candidate in priceUnits)
              LensPill(
                key: ValueKey('lens-unit-${candidate.key}'),
                label: s(
                  context,
                  'unit${candidate.key[0].toUpperCase()}'
                  '${candidate.key.substring(1)}',
                ),
                selected: candidate.key == selectedKey,
                onTap: () => onSelected(candidate.key),
              ),
          ],
        ),
        if (unit.family != UnitFamily.piece)
          Text(
            s(context, switch (unit.family) {
              UnitFamily.mass => 'unitFamilyMass',
              UnitFamily.volume => 'unitFamilyVolume',
              UnitFamily.piece => 'unitFamilyPiece',
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
    this.error,
  });

  final IrrUnit irrUnit;
  final DiscountKind kind;
  final TextEditingController controller;
  final PriceCurrency currency;
  final ValueChanged<DiscountKind> onKindChanged;
  final VoidCallback onChanged;
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
        Wrap(
          spacing: NexSpacing.sm,
          runSpacing: NexSpacing.xs,
          children: [
            for (final candidate in DiscountKind.values)
              LensPill(
                key: ValueKey('lens-discount-${candidate.name}'),
                label: s(context, switch (candidate) {
                  DiscountKind.none => 'discountNone',
                  DiscountKind.percent => 'discountPercentKind',
                  DiscountKind.fixed => 'discountFixedKind',
                }),
                selected: candidate == kind,
                onTap: () => onKindChanged(candidate),
              ),
          ],
        ),
        if (kind != DiscountKind.none) ...[
          const SizedBox(height: NexSpacing.xs),
          TextField(
            key: const ValueKey('lens-discount-value'),
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              labelText: kind == DiscountKind.percent
                  ? s(context, 'discountPercentField')
                  : s(context, 'discountFixedKind'),
              suffixText: kind == DiscountKind.percent
                  ? '%'
                  : currency.code == 'IRR' && irrUnit == IrrUnit.toman
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
      ],
    );
  }
}
