/// The calculator's four input panels, drawn apart from the form's state
/// so each side stays readable: this file only lays out fields, the state
/// and parsing live in `gold_form.dart`.
library;

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'gold_fields.dart';
import 'gold_math.dart';
import 'gold_strings.dart';

/// One separately priced extra's two controllers.
class GoldExtraControllers {
  GoldExtraControllers(this.label, this.amount);

  final TextEditingController label;
  final TextEditingController amount;
}

/// The piece itself: net weight, gross weight, fineness.
Widget goldPiecePanel(
  BuildContext context, {
  required TextEditingController weight,
  required TextEditingController gross,
  required int fineness,
  required ValueChanged<int> onFineness,
}) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    GoldNumberField(
      fieldKey: const ValueKey('gold-weight'),
      label: goldStrings(context, 'weight'),
      hint: goldStrings(context, 'weightHint'),
      controller: weight,
      scale: 3,
      maxScaled: GoldInput.maxWeightMg,
      allowEmpty: false,
    ),
    const SizedBox(height: NexSpacing.sm),
    GoldNumberField(
      fieldKey: const ValueKey('gold-gross'),
      label: goldStrings(context, 'grossWeight'),
      hint: goldStrings(context, 'grossWeightHint'),
      controller: gross,
      scale: 3,
      maxScaled: GoldInput.maxGrossMg,
    ),
    const SizedBox(height: NexSpacing.md),
    GoldFinenessField(
      fieldKey: const ValueKey('gold-fineness'),
      label: goldStrings(context, 'fineness'),
      hint: goldStrings(context, 'finenessHint'),
      value: fineness,
      onChanged: onFineness,
    ),
  ],
);

/// The rate and the fineness it is quoted for.
Widget goldRatePanel(
  BuildContext context, {
  required TextEditingController rate,
  required int rateRef,
  required ValueChanged<int> onRateRef,
}) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    GoldNumberField(
      fieldKey: const ValueKey('gold-rate'),
      label: goldStrings(context, 'rate'),
      hint: goldStrings(context, 'rateHint'),
      controller: rate,
      scale: 2,
      maxScaled: GoldInput.maxRateCenti,
      allowEmpty: false,
    ),
    const SizedBox(height: NexSpacing.md),
    GoldFinenessField(
      fieldKey: const ValueKey('gold-rate-ref'),
      label: goldStrings(context, 'rateRef'),
      hint: goldStrings(context, 'rateRefHint'),
      value: rateRef,
      onChanged: onRateRef,
    ),
  ],
);

/// The making charge in its four modes, the profit, the VAT and the
/// commission.
Widget goldChargesPanel(
  BuildContext context, {
  required GoldMakingMode mode,
  required ValueChanged<GoldMakingMode> onMode,
  required TextEditingController makingPercent,
  required TextEditingController makingPerGram,
  required TextEditingController makingFixed,
  required TextEditingController profit,
  required TextEditingController vat,
  required TextEditingController commission,
  required GoldProfitBase profitBase,
  required ValueChanged<GoldProfitBase> onProfitBase,
  required bool commissionTaxable,
  required ValueChanged<bool> onCommissionTaxable,
}) {
  final theme = Theme.of(context);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      GoldDropdownField<GoldMakingMode>(
        fieldKey: const ValueKey('gold-making-mode'),
        label: goldStrings(context, 'making'),
        value: mode,
        items: [
          (GoldMakingMode.percent, goldStrings(context, 'makingModePercent')),
          (GoldMakingMode.perGram, goldStrings(context, 'makingModePerGram')),
          (GoldMakingMode.fixed, goldStrings(context, 'makingModeFixed')),
          (GoldMakingMode.mixed, goldStrings(context, 'makingModeMixed')),
        ],
        onSelected: onMode,
      ),
      const SizedBox(height: NexSpacing.sm),
      if (mode == GoldMakingMode.percent || mode == GoldMakingMode.mixed) ...[
        GoldNumberField(
          fieldKey: const ValueKey('gold-making-percent'),
          label: goldStrings(context, 'makingPercentLabel'),
          controller: makingPercent,
          scale: 2,
          maxScaled: GoldInput.maxPercentBp,
        ),
        const SizedBox(height: NexSpacing.sm),
      ],
      if (mode == GoldMakingMode.perGram || mode == GoldMakingMode.mixed) ...[
        GoldNumberField(
          fieldKey: const ValueKey('gold-making-pergram'),
          label: goldStrings(context, 'makingPerGramLabel'),
          controller: makingPerGram,
          scale: 2,
          maxScaled: GoldInput.maxPerGramCenti,
        ),
        const SizedBox(height: NexSpacing.sm),
      ],
      if (mode == GoldMakingMode.fixed)
        GoldNumberField(
          fieldKey: const ValueKey('gold-making-fixed'),
          label: goldStrings(context, 'makingFixedLabel'),
          controller: makingFixed,
          scale: 2,
          maxScaled: GoldInput.maxAmountRial * 10,
        ),
      const SizedBox(height: NexSpacing.sm),
      GoldNumberField(
        fieldKey: const ValueKey('gold-profit'),
        label: goldStrings(context, 'profit'),
        hint: goldStrings(context, 'profitHint'),
        controller: profit,
        scale: 2,
        maxScaled: GoldInput.maxPercentBp,
      ),
      const SizedBox(height: NexSpacing.sm),
      GoldDropdownField<GoldProfitBase>(
        fieldKey: const ValueKey('gold-profit-base'),
        label: goldStrings(context, 'profitBase'),
        value: profitBase,
        items: [
          for (final base in GoldProfitBase.values)
            (base, goldStrings(context, 'profitBase_${base.name}')),
        ],
        onSelected: onProfitBase,
      ),
      const SizedBox(height: NexSpacing.sm),
      GoldNumberField(
        fieldKey: const ValueKey('gold-vat'),
        label: goldStrings(context, 'vat'),
        hint: goldStrings(context, 'vatHint'),
        controller: vat,
        scale: 2,
        maxScaled: GoldInput.maxPercentBp,
      ),
      const SizedBox(height: NexSpacing.xs),
      Row(
        children: [
          Icon(
            Icons.event_outlined,
            size: 14,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: NexSpacing.xs),
          Expanded(
            child: Text(
              '${goldStrings(context, 'vatDated')} · '
              '${goldStrings(context, 'vatBaseNote')}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: NexSpacing.md),
      GoldNumberField(
        fieldKey: const ValueKey('gold-commission'),
        label: goldStrings(context, 'commission'),
        hint: goldStrings(context, 'commissionHint'),
        controller: commission,
        scale: 2,
        maxScaled: GoldInput.maxAmountRial * 10,
      ),
      SwitchListTile.adaptive(
        key: const ValueKey('gold-commission-taxable'),
        contentPadding: EdgeInsets.zero,
        title: Text(goldStrings(context, 'commissionTaxable')),
        subtitle: Text(goldStrings(context, 'commissionTaxableHint')),
        value: commissionTaxable,
        onChanged: onCommissionTaxable,
      ),
    ],
  );
}

/// The separately priced extras and the seller's quoted total.
Widget goldExtrasPanel(
  BuildContext context, {
  required List<GoldExtraControllers> extras,
  required VoidCallback onAddExtra,
  required void Function(int index) onRemoveExtra,
  required TextEditingController shopQuote,
}) {
  final theme = Theme.of(context);
  final strings = goldStrings;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        strings(context, 'extrasHint'),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: NexSpacing.sm),
      for (var i = 0; i < extras.length; i++)
        Padding(
          padding: const EdgeInsetsDirectional.only(bottom: NexSpacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: GoldAutoTextField(
                  fieldKey: ValueKey('gold-extra-label-$i'),
                  label: strings(context, 'extraLabel'),
                  controller: extras[i].label,
                ),
              ),
              const SizedBox(width: NexSpacing.sm),
              Expanded(
                child: GoldNumberField(
                  fieldKey: ValueKey('gold-extra-amount-$i'),
                  label: strings(context, 'extraAmount'),
                  controller: extras[i].amount,
                  scale: 2,
                  maxScaled: GoldInput.maxAmountRial * 10,
                ),
              ),
              IconButton(
                tooltip: strings(context, 'removeExtraTip'),
                onPressed: () => onRemoveExtra(i),
                icon: const Icon(Icons.remove_circle_outline),
              ),
            ],
          ),
        ),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          key: const ValueKey('gold-add-extra'),
          onPressed: onAddExtra,
          icon: const Icon(Icons.add),
          label: Text(strings(context, 'addExtra')),
        ),
      ),
      const Divider(height: NexSpacing.lg),
      GoldNumberField(
        fieldKey: const ValueKey('gold-shop-quote'),
        label: strings(context, 'shopQuote'),
        hint: strings(context, 'shopQuoteHint'),
        controller: shopQuote,
        scale: 2,
        maxScaled: GoldInput.maxAmountRial * 10,
      ),
    ],
  );
}
