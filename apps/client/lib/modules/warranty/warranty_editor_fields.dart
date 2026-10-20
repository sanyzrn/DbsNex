import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'warranty_fields.dart';
import 'warranty_logic.dart';
import 'warranty_parse.dart';
import 'warranty_strings.dart';

/// The editor's own field groups, kept apart so the editor file stays
/// about what it saves and the widgets file about the list. Every field
/// shows exactly what the person wrote; nothing is guessed.

/// The identity fields of the warranty editor: product, category, brand,
/// model, serial and merchant. The product's error helper appears only
/// after a failed save.
class WarrantyIdentityFields extends StatelessWidget {
  const WarrantyIdentityFields({
    super.key,
    required this.product,
    required this.category,
    required this.brand,
    required this.model,
    required this.serial,
    required this.merchant,
    this.productRequired,
  });

  final TextEditingController product;
  final TextEditingController category;
  final TextEditingController brand;
  final TextEditingController model;
  final TextEditingController serial;
  final TextEditingController merchant;
  final String? productRequired;

  @override
  Widget build(BuildContext context) {
    final strings = warrantyStrings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WarrantyFields.line(
          fieldKey: const ValueKey('warranty-field-product'),
          controller: product,
          label: strings(context, 'product'),
          hint: strings(context, 'productHint'),
          helper: productRequired != null && product.text.trim().isEmpty
              ? productRequired
              : null,
        ),
        const SizedBox(height: NexSpacing.sm),
        Row(
          children: [
            Expanded(
              child: WarrantyFields.line(
                fieldKey: const ValueKey('warranty-field-category'),
                controller: category,
                label: strings(context, 'category'),
              ),
            ),
            const SizedBox(width: NexSpacing.sm),
            Expanded(
              child: WarrantyFields.line(
                fieldKey: const ValueKey('warranty-field-brand'),
                controller: brand,
                label: strings(context, 'brand'),
              ),
            ),
          ],
        ),
        const SizedBox(height: NexSpacing.sm),
        Row(
          children: [
            Expanded(
              child: WarrantyFields.line(
                fieldKey: const ValueKey('warranty-field-model'),
                controller: model,
                label: strings(context, 'model'),
              ),
            ),
            const SizedBox(width: NexSpacing.sm),
            Expanded(
              child: WarrantyFields.line(
                fieldKey: const ValueKey('warranty-field-merchant'),
                controller: merchant,
                label: strings(context, 'merchant'),
              ),
            ),
          ],
        ),
        const SizedBox(height: NexSpacing.sm),
        WarrantyFields.line(
          fieldKey: const ValueKey('warranty-field-serial'),
          controller: serial,
          label: strings(context, 'serial'),
          hint: strings(context, 'serialHint'),
        ),
      ],
    );
  }
}

/// The coverage section of the warranty editor: the note about whose
/// terms these are, a duration in months or an end date — never both —
/// with the computed end shown in front of the person, and the coverage
/// type label.
class WarrantyCoverageFields extends StatelessWidget {
  const WarrantyCoverageFields({
    super.key,
    required this.purchase,
    required this.duration,
    required this.endDate,
    required this.coverageType,
    this.showErrors = false,
  });

  final bool showErrors;
  final TextEditingController purchase;
  final TextEditingController duration;
  final TextEditingController endDate;
  final TextEditingController coverageType;

  @override
  Widget build(BuildContext context) {
    final strings = warrantyStrings;
    final theme = Theme.of(context);
    final purchaseDate = WarrantyParse.date(purchase.text);
    final months = WarrantyParse.count(duration.text);
    final writtenEnd = WarrantyParse.date(endDate.text);
    final computedEnd =
        months != null &&
            months > 0 &&
            months <= 2400 &&
            purchaseDate != null &&
            purchaseDate.year + (purchaseDate.month + months - 1) ~/ 12 <=
                2100 &&
            purchaseDate != WarrantyParse.invalid
        ? WarrantyLogic.addMonths(
            DateTime(purchaseDate.year, purchaseDate.month, purchaseDate.day),
            months,
          )
        : null;
    final end = (writtenEnd != null && writtenEnd != WarrantyParse.invalid)
        ? writtenEnd
        : computedEnd;
    final bothWays =
        duration.text.trim().isNotEmpty && endDate.text.trim().isNotEmpty;
    final beforePurchase =
        purchaseDate != null &&
        purchaseDate != WarrantyParse.invalid &&
        end != null &&
        !WarrantyLogic.endAfterPurchase(purchaseDate, end);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(strings(context, 'coverage'), style: theme.textTheme.titleSmall),
        Text(
          strings(context, 'coverageNote'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: NexSpacing.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: WarrantyFields.number(
                fieldKey: const ValueKey('warranty-field-duration'),
                controller: duration,
                label: strings(context, 'durationMonths'),
                hint: strings(context, 'durationHint'),
              ),
            ),
            const SizedBox(width: NexSpacing.sm),
            Expanded(
              child: NexModuleDateEntry(
                controller: endDate,
                child: WarrantyFields.line(
                  fieldKey: const ValueKey('warranty-field-end'),
                  controller: endDate,
                  label: strings(context, 'orEndDate'),
                  hint: strings(context, 'dateHint'),
                ),
              ),
            ),
          ],
        ),
        if (showErrors && end == null)
          Text(
            strings(context, 'coverageRequired', {
              'months': 2400,
              'year': 2100,
            }),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        if (bothWays)
          Text(
            strings(context, 'chooseOne'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          )
        else if (end != null)
          Padding(
            padding: const EdgeInsets.only(top: NexSpacing.xs),
            child: Text(
              strings(context, 'endsOn', {
                'date': WarrantyFields.dayLabel(context, end),
              }),
              key: const ValueKey('warranty-ends-on'),
              style: theme.textTheme.bodyMedium,
            ),
          ),
        if (beforePurchase)
          Text(
            strings(context, 'endBeforePurchase'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        const SizedBox(height: NexSpacing.sm),
        WarrantyFields.line(
          fieldKey: const ValueKey('warranty-field-type'),
          controller: coverageType,
          label: strings(context, 'coverageType'),
          hint: strings(context, 'coverageTypeHint'),
        ),
      ],
    );
  }
}
