import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'comparison.dart';
import 'money.dart';
import 'options.dart';
import 'rational.dart';
import 'strings.dart';
import 'units.dart';

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
    final exponent = priceExponentOf(option.currency);
    final price =
        '${formatPriceNumber(option.priceMinor, exponent, persian: persian)} '
        '${option.currency}';
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
                          'quantity': option.quantity.toDecimalString(
                            digits: 6,
                          ),
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
                        '${formatPriceNumber(option.shippingMinor!, exponent, persian: persian)} ${option.currency}',
                    ].join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if (!optionSafe(option)) Text(s(context, 'incomplete')),
                  if (optionSafe(option))
                    Text(
                      s(context, 'payable', {
                        'price':
                            '${formatMinorFraction(effectivePriceMinor(option), exponent, persian: persian)} ${option.currency}',
                      }),
                      style: theme.textTheme.titleSmall,
                    ),
                  if (unitPrice != null) ...[
                    const SizedBox(height: NexSpacing.sm),
                    Text(
                      '${formatMinorFraction(unitPrice, exponent, persian: persian)} ${option.currency}${commonUnitKey == null ? '' : ' / ${unitWordOf(context, commonUnitKey!)}'}',
                      textDirection: TextDirection.ltr,
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
    final exponent = priceExponentOf(option.currency);
    return switch (option.discount) {
      DiscountKind.none => const [],
      DiscountKind.percent => ['${option.discountPercent ?? 0}%'],
      DiscountKind.fixed => [
        '−${formatPriceNumber(option.discountMinor ?? 0, exponent, persian: persian)}',
      ],
    };
  }
}

/// The result: which offer is actually cheaper, why, and by exactly
/// how much the others are not. Savings are relative to the cheapest
/// entered offer — never to a fabricated market baseline.
class LensResultPanel extends StatelessWidget {
  const LensResultPanel({
    super.key,
    required this.comparison,
    required this.commonUnit,
    required this.persian,
    required this.memoryLine,
  });

  final Comparison comparison;
  final PriceUnit commonUnit;
  final bool persian;
  final Widget? memoryLine;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = priceLensStrings;
    final hue = NexHue.violet.of(theme.brightness);
    final unitWord = unitWordOf(context, commonUnit.key);
    final exponent = priceExponentOf(comparison.currency);

    if (comparison.state != ComparisonState.ready) {
      final message = switch (comparison.state) {
        ComparisonState.tooFewOptions => s(context, 'tooFew'),
        ComparisonState.mixedCurrencies => s(context, 'mixedCurrencies'),
        ComparisonState.mixedFamilies => s(context, 'notComparable'),
        ComparisonState.incompleteOption => s(context, 'incomplete'),
        ComparisonState.ready => '',
      };
      return NexPanel(
        title: s(context, 'title'),
        icon: Icons.calculate_outlined,
        child: Text(message, style: theme.textTheme.bodyMedium),
      );
    }

    final best = comparison.bestUnitPrice;
    final bestCount = comparison.results.where((r) => r.isBest).length;
    final rows = <Widget>[];
    for (final result in comparison.results) {
      rows.add(
        _ResultRow(
          result: result,
          best: best,
          exponent: exponent,
          unitWord: unitWord,
          persian: persian,
        ),
      );
    }
    return NexPanel(
      title: s(context, 'resultTitle', {'unit': unitWord}),
      icon: Icons.emoji_events_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...rows,
          if (bestCount > 1)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: NexSpacing.xs),
              child: Text(
                s(context, 'tieNote'),
                style: theme.textTheme.bodySmall?.copyWith(color: hue),
              ),
            ),
          const Divider(height: NexSpacing.lg),
          Text(
            s(context, 'smallestNote'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: NexSpacing.xs),
          Text(
            s(context, 'priceComparisonNote'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (memoryLine != null) ...[
            const Divider(height: NexSpacing.lg),
            memoryLine!,
          ],
        ],
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.result,
    required this.best,
    required this.exponent,
    required this.unitWord,
    required this.persian,
  });

  final OptionResult result;
  final Fraction? best;
  final int exponent;
  final String unitWord;
  final bool persian;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = priceLensStrings;
    final hue = NexHue.violet.of(theme.brightness);
    final price = result.unitPriceMinor;
    if (price == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: NexSpacing.xs),
        child: Text(
          '${result.option.label} · ${s(context, 'notComparable')}',
          style: theme.textTheme.bodyMedium,
        ),
      );
    }
    final bestPrice = best;
    final savings = bestPrice == null ? null : savingsOf(result, bestPrice);
    final label = result.option.label;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: NexSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (result.isBest)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: NexSpacing.xs),
                  child: Icon(Icons.check_circle_outline, size: 16, color: hue),
                ),
              Expanded(
                child: Text(
                  s(context, 'unitPriceOf', {
                    'label': label,
                    'price':
                        '${formatMinorFraction(price, exponent, persian: persian)} '
                        '${result.option.currency}',
                    'unit': unitWord,
                  }),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          if (savings != null) ...[
            const SizedBox(height: 2),
            Text(
              s(context, 'savingsVsBest', {
                'extra':
                    '${formatMinorFraction(savings.perUnit, exponent, persian: persian)} ${result.option.currency}',
              }),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            Text(
              s(context, 'savingsForQuantity', {
                'price':
                    '${formatMinorFraction(savings.forThisAmount, exponent, persian: persian)} ${result.option.currency}',
              }),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}
