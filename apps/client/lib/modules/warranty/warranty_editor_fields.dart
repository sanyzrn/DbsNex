import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'warranty_field_pair.dart';
import 'warranty_fields.dart';
import 'warranty_logic.dart';
import 'warranty_models.dart';
import 'warranty_parse.dart';
import 'warranty_strings.dart';

/// The editor's own field groups — identity, coverage, and the card a
/// service desk reads — kept apart so the editor file stays about what it
/// saves and the widgets file about the list. Every field shows exactly
/// what the person wrote; nothing is guessed.

/// The identity fields of the warranty editor: product, category, brand,
/// model, serial and shop. The product's error helper appears only after a
/// failed save.
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
    this.showProduct = true,
    this.showMore = true,
  });

  /// Which half to draw: the product alone, or everything else about it
  /// (category, brand, model, shop, serial) — the editor keeps the second
  /// behind "more details".
  final bool showProduct;
  final bool showMore;
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
        if (showProduct)
          WarrantyFields.line(
            fieldKey: const ValueKey('warranty-field-product'),
            controller: product,
            label: strings(context, 'product'),
            hint: strings(context, 'productHint'),
            helper: productRequired != null && product.text.trim().isEmpty
                ? productRequired
                : null,
          ),
        if (showMore) ...[
          const SizedBox(height: NexSpacing.sm),
          WarrantyFieldPair(
            first: WarrantyFields.line(
              fieldKey: const ValueKey('warranty-field-category'),
              controller: category,
              label: strings(context, 'category'),
            ),
            second: WarrantyFields.line(
              fieldKey: const ValueKey('warranty-field-brand'),
              controller: brand,
              label: strings(context, 'brand'),
            ),
          ),
          const SizedBox(height: NexSpacing.sm),
          WarrantyFieldPair(
            first: WarrantyFields.line(
              fieldKey: const ValueKey('warranty-field-model'),
              controller: model,
              label: strings(context, 'model'),
            ),
            second: WarrantyFields.line(
              fieldKey: const ValueKey('warranty-field-merchant'),
              controller: merchant,
              label: strings(context, 'merchant'),
            ),
          ),
          const SizedBox(height: NexSpacing.sm),
          WarrantyFields.ltrLine(
            fieldKey: const ValueKey('warranty-field-serial'),
            controller: serial,
            label: strings(context, 'serial'),
            hint: strings(context, 'serialHint'),
          ),
        ],
      ],
    );
  }
}

/// The coverage section of the warranty editor: which kind of cover this is
/// — the difference between a company warranty, the shop's guarantee and
/// after-sales service — the duration in months or the end date itself,
/// never both, with the computed end shown in front of the person.
class WarrantyCoverageFields extends StatelessWidget {
  const WarrantyCoverageFields({
    super.key,
    required this.purchase,
    required this.duration,
    required this.endDate,
    required this.coverageType,
    required this.coverKind,
    required this.onCoverKind,
    this.showErrors = false,
  });

  final bool showErrors;
  final TextEditingController purchase;
  final TextEditingController duration;
  final TextEditingController endDate;
  final TextEditingController coverageType;
  final String coverKind;
  final ValueChanged<String> onCoverKind;

  @override
  Widget build(BuildContext context) {
    final strings = warrantyStrings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final purchaseDate = WarrantyParse.date(purchase.text);
    final months = WarrantyParse.count(duration.text);
    final writtenEnd = WarrantyParse.date(endDate.text);
    final computable =
        months != null &&
        months > 0 &&
        months <= 2400 &&
        purchaseDate != null &&
        purchaseDate != WarrantyParse.invalid &&
        purchaseDate.year + (purchaseDate.month + months - 1) ~/ 12 <= 2100;
    final computedEnd = computable
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
    final hint = WarrantyFields.coverKindHint(context, coverKind);

    Widget error(String text) => Padding(
      padding: const EdgeInsets.only(top: NexSpacing.xs),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(strings(context, 'coverage'), style: theme.textTheme.titleSmall),
        Text(
          strings(context, 'coverageNote'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: NexSpacing.md),
        Text(
          strings(context, 'coverKindLabel'),
          style: theme.textTheme.labelLarge?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: NexSpacing.xs),
        Wrap(
          spacing: NexSpacing.sm,
          runSpacing: NexSpacing.xs,
          children: [
            for (final kind in WarrantyModels.coverKinds)
              ChoiceChip(
                key: ValueKey('warranty-cover-$kind'),
                label: Text(WarrantyFields.coverKind(context, kind)),
                selected: coverKind == kind,
                // Tapping the chosen kind again clears it: the person may not
                // know, and an empty answer is better than a guessed one.
                onSelected: (selected) => onCoverKind(selected ? kind : ''),
              ),
          ],
        ),
        if (hint.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: NexSpacing.xs),
            child: Text(
              hint,
              key: const ValueKey('warranty-cover-hint'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        const SizedBox(height: NexSpacing.md),
        WarrantyFieldPair(
          first: WarrantyFields.number(
            fieldKey: const ValueKey('warranty-field-duration'),
            controller: duration,
            label: strings(context, 'durationMonths'),
            hint: strings(context, 'durationHint'),
          ),
          second: NexModuleDateEntry(
            controller: endDate,
            child: WarrantyFields.line(
              fieldKey: const ValueKey('warranty-field-end'),
              controller: endDate,
              label: strings(context, 'orEndDate'),
              hint: strings(context, 'dateHint'),
            ),
          ),
        ),
        const SizedBox(height: NexSpacing.xs),
        Text(
          strings(context, 'commonTerms'),
          style: theme.textTheme.labelMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: NexSpacing.xs),
        Wrap(
          spacing: NexSpacing.sm,
          runSpacing: NexSpacing.xs,
          children: [
            for (final term in const [6, 12, 18, 24, 36])
              ActionChip(
                key: ValueKey('warranty-term-$term'),
                label: Text(strings(context, 'term', {'count': term})),
                onPressed: () {
                  // The two ways of saying the same thing: choosing a term
                  // takes the written end date away instead of leaving both.
                  endDate.clear();
                  duration.text = '$term';
                },
              ),
          ],
        ),
        if (showErrors && end == null)
          error(
            strings(context, 'coverageRequired', {
              'months': 2400,
              'year': 2100,
            }),
          ),
        if (bothWays)
          error(strings(context, 'chooseOne'))
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
        if (beforePurchase) error(strings(context, 'endBeforePurchase')),
        const SizedBox(height: NexSpacing.md),
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

/// What a service centre asks about the card itself: which company stands
/// behind it, the line to call and the card number — and, for a phone, who
/// it is registered to.
class WarrantySupportFields extends StatelessWidget {
  const WarrantySupportFields({
    super.key,
    required this.company,
    required this.supportPhone,
    required this.cardNumber,
    required this.registryOwner,
    required this.onRegistry,
  });

  final TextEditingController company;
  final TextEditingController supportPhone;
  final TextEditingController cardNumber;
  final String registryOwner;
  final ValueChanged<String> onRegistry;

  @override
  Widget build(BuildContext context) {
    final strings = warrantyStrings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings(context, 'supportTitle'),
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: NexSpacing.sm),
        WarrantyFields.line(
          fieldKey: const ValueKey('warranty-field-company'),
          controller: company,
          label: strings(context, 'company'),
          hint: strings(context, 'companyHint'),
        ),
        const SizedBox(height: NexSpacing.sm),
        WarrantyFieldPair(
          first: WarrantyFields.ltrLine(
            fieldKey: const ValueKey('warranty-field-phone'),
            controller: supportPhone,
            label: strings(context, 'supportPhone'),
            hint: strings(context, 'supportPhoneHint'),
          ),
          second: WarrantyFields.ltrLine(
            fieldKey: const ValueKey('warranty-field-card'),
            controller: cardNumber,
            label: strings(context, 'cardNumber'),
            hint: strings(context, 'cardNumberHint'),
          ),
        ),
        const SizedBox(height: NexSpacing.md),
        Text(
          strings(context, 'registryLabel'),
          style: theme.textTheme.labelLarge?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: NexSpacing.xs),
        Wrap(
          spacing: NexSpacing.sm,
          runSpacing: NexSpacing.xs,
          children: [
            for (final (owner, key) in const [
              (WarrantyModels.registryMine, 'registryMine'),
              (WarrantyModels.registryOther, 'registryOther'),
            ])
              ChoiceChip(
                key: ValueKey('warranty-registry-$owner'),
                label: Text(strings(context, key)),
                selected: registryOwner == owner,
                onSelected: (selected) => onRegistry(selected ? owner : ''),
              ),
          ],
        ),
        const SizedBox(height: NexSpacing.xs),
        Text(
          strings(context, 'registryHint'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
