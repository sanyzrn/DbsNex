import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'comparison.dart';
import 'money_render.dart';
import 'money.dart' show persianLocal;
import 'privacy.dart';
import 'options.dart';
import 'price_lens_common.dart' show lensSep;
import 'rational.dart';
import 'strings.dart';
import 'units.dart';
part 'lens_result_panel.dart';

/// The calculator's presentational pieces: one offer's card, and the
/// result panel that says which is actually cheaper, with the exact
/// arithmetic on show and every unknown said out loud.

/// The unit word for a key.
String unitWordOf(BuildContext context, String key) =>
    priceLensStrings(context, 'unit${key[0].toUpperCase()}${key.substring(1)}');

/// One offer, as a card: what it is, what it costs, what it holds,
/// and its exact unit price once the comparison runs. Tapping edits;
/// the trailing icons remember its price and remove it.
class LensOptionCard extends StatelessWidget {
  const LensOptionCard({
    super.key,
    required this.option,
    required this.result,
    required this.persian,
    required this.onEdit,
    required this.onRemember,
    required this.onRemove,
    this.commonUnitKey,
  });

  final PriceOption option;
  final OptionResult? result;
  final bool persian;
  final VoidCallback onEdit;
  final VoidCallback onRemember;
  final VoidCallback onRemove;
  final String? commonUnitKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = priceLensStrings;
    final hue = NexHue.violet.of(theme.brightness);
    final price = lensMoney(
      context,
      Fraction(option.priceMinor),
      option.currency,
    );
    final count = option.packageCount;
    final paid = option.paidCount;
    final quantity =
        '${persian ? persianLocal(option.quantity.toDecimalString(digits: 6)) : option.quantity.toDecimalString(digits: 6)} '
        '${unitWordOf(context, option.unitKey)}';
    final unitPrice = result?.unitPriceMinor;
    final notComparable = result?.notComparable ?? false;
    return Semantics(
      label: s(context, 'optionSemantics', {
        'label': option.label,
        'price': price,
        'quantity': quantity,
        'unit': unitWordOf(context, option.unitKey),
      }),
      button: true,
      excludeSemantics: false,
      child: Padding(
        padding: const EdgeInsetsDirectional.only(bottom: NexSpacing.sm),
        child: Material(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(NexRadius.lg),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onEdit,
            child: Padding(
              padding: const EdgeInsets.all(NexSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: Text(
                          option.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      if (result?.isBest ?? false)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(
                            end: NexSpacing.sm,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.check_circle_outline,
                                size: 18,
                                color: hue,
                              ),
                              const SizedBox(width: NexSpacing.xs),
                              Text(
                                s(context, 'bestLabel'),
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: hue,
                                ),
                              ),
                            ],
                          ),
                        ),
                      IconButton(
                        tooltip: s(context, 'saveToMemory'),
                        onPressed: onRemember,
                        icon: const Icon(Icons.bookmark_add_outlined),
                      ),
                      IconButton(
                        tooltip: s(context, 'remove'),
                        onPressed: onRemove,
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: NexSpacing.xs),
                  Text(
                    [
                      price,
                      if (count > 1)
                        s(context, 'perPackage', {
                          'quantity': persian
                              ? persianLocal(
                                  option.quantity.toDecimalString(digits: 6),
                                )
                              : option.quantity.toDecimalString(digits: 6),
                          'unit': unitWordOf(context, option.unitKey),
                          'count': count,
                        }),
                      if (count == 1) quantity,
                      if (paid != null && paid != count)
                        s(context, 'paidReceived', {
                          'paid': paid,
                          'received': count,
                        }),
                      ..._discountLine(context, persian),
                      if (option.shippingMinor != null)
                        lensMoney(
                          context,
                          Fraction(option.shippingMinor!),
                          option.currency,
                        ),
                    ].join(lensSep(context)),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if (!optionSafe(option)) Text(s(context, 'incomplete')),
                  if (optionSafe(option))
                    Text(
                      s(context, 'payable', {
                        'price': lensMoney(
                          context,
                          effectivePriceMinor(option),
                          option.currency,
                        ),
                      }),
                      style: theme.textTheme.titleSmall,
                    ),
                  if (unitPrice != null) ...[
                    const SizedBox(height: NexSpacing.sm),
                    Text(
                      '${lensMoney(context, unitPrice, option.currency)}${commonUnitKey == null ? '' : ' / ${unitWordOf(context, commonUnitKey!)}'}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: (result?.isBest ?? false)
                            ? hue
                            : scheme.onSurface,
                      ),
                    ),
                  ],
                  if (notComparable)
                    Text(
                      s(context, 'notComparable'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<String> _discountLine(BuildContext context, bool persian) {
    if (lensAmountsHidden(context)) {
      return option.discount == DiscountKind.none ? [] : ['••••'];
    }
    return switch (option.discount) {
      DiscountKind.none => const [],
      DiscountKind.percent => [
        '${persian ? persianLocal('${option.discountPercent ?? 0}') : option.discountPercent ?? 0}%',
      ],
      DiscountKind.fixed => [
        '−${lensMoney(context, Fraction(option.discountMinor ?? 0), option.currency)}',
      ],
    };
  }
}
