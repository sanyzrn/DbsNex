import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'gold_format.dart';
import 'gold_math.dart';
import 'gold_strings.dart';

/// A quiet visual answer to “how much of this price is actually gold?”.
/// Amounts remain readable without the colour bar, including with TalkBack.
class GoldCostLens extends StatelessWidget {
  const GoldCostLens({
    super.key,
    required this.input,
    required this.result,
    required this.showRials,
  });
  final GoldInput input;
  final GoldResult result;
  final bool showRials;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final persian = NexModuleStrings.persian(context);
    final total = result.estimatedTotalRial;
    if (total == 0) return const SizedBox.shrink();
    final metal = result.metalValueRial;
    final services = total - metal - result.extrasRial;
    final parts = [
      (metal, nexModuleAccent(context, 'gold'), 'lineMetal'),
      (services, theme.colorScheme.secondary, 'costServices'),
      (result.extrasRial, theme.colorScheme.tertiary, 'lineExtras'),
    ];
    String money(int value) =>
        formatRial(value, persian: persian, rials: showRials);
    final share =
        ((BigInt.from(metal) * BigInt.from(10000) + BigInt.from(total ~/ 2)) ~/
                BigInt.from(total))
            .toInt();
    final perGram =
        ((BigInt.from(total) * BigInt.from(1000) +
                    BigInt.from(input.weightMg ~/ 2)) ~/
                BigInt.from(input.weightMg))
            .toInt();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          goldStrings(context, 'costLens'),
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: NexSpacing.sm),
        Semantics(
          label: goldStrings(context, 'metalShare', {
            'pct': formatPercent(share, persian: persian),
          }),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(NexRadius.sm),
            child: SizedBox(
              height: NexSpacing.sm,
              child: Row(
                children: [
                  for (final (amount, color, _) in parts)
                    if (amount > 0)
                      Expanded(
                        flex: amount,
                        child: ColoredBox(
                          color: color,
                          child: const SizedBox.expand(),
                        ),
                      ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: NexSpacing.sm),
        Wrap(
          spacing: NexSpacing.md,
          runSpacing: NexSpacing.sm,
          children: [
            for (final (amount, _, label) in parts)
              if (amount > 0)
                Text(
                  '${goldStrings(context, label)} · ${formatPercent(((BigInt.from(amount) * BigInt.from(10000) + BigInt.from(total ~/ 2)) ~/ BigInt.from(total)).toInt(), persian: persian)}',
                  style: theme.textTheme.bodySmall,
                ),
          ],
        ),
        const SizedBox(height: NexSpacing.sm),
        Text(
          goldStrings(context, 'allInGram', {
            'amount': money(perGram),
            'unit': goldStrings(context, showRials ? 'rialWord' : 'tomanWord'),
          }),
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}
