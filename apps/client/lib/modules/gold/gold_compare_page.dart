/// Two saved estimates, side by side, line by line — with the warning when
/// the two are not on the same weight-and-fineness basis, instead of a
/// comparison that looks like it means something.
library;

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'gold_format.dart';
import 'gold_models.dart';
import 'gold_strings.dart';

class GoldComparePage extends StatelessWidget {
  const GoldComparePage({
    super.key,
    required this.first,
    required this.second,
    required this.showRials,
  });

  final GoldQuote first;
  final GoldQuote second;
  final bool showRials;

  @override
  Widget build(BuildContext context) {
    final strings = goldStrings;
    final theme = Theme.of(context);
    final persian = NexModuleStrings.persian(context);
    final sameBasis = first.sameBasisAs(second);
    String money(int rial) =>
        formatRial(rial, persian: persian, rials: showRials);

    final rows = <(String, int, int)>[
      (
        strings(context, 'lineMetal'),
        first.metalValueRial,
        second.metalValueRial,
      ),
      (
        strings(context, 'lineMaking'),
        first.makingChargeRial,
        second.makingChargeRial,
      ),
      (
        strings(context, 'lineProfit'),
        first.sellerProfitRial,
        second.sellerProfitRial,
      ),
      if (first.commissionRial > 0 || second.commissionRial > 0)
        (
          strings(context, 'lineCommission'),
          first.commissionRial,
          second.commissionRial,
        ),
      (strings(context, 'vat'), first.vatRial, second.vatRial),
      if (first.extrasRial > 0 || second.extrasRial > 0)
        (strings(context, 'lineExtras'), first.extrasRial, second.extrasRial),
      (
        strings(context, 'lineTotal'),
        first.estimatedTotalRial,
        second.estimatedTotalRial,
      ),
    ];

    return Scaffold(
      appBar: NexAppBar(title: Text(strings(context, 'compare'))),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: NexSpacing.md),
        children: [
          const SizedBox(height: NexSpacing.md),
          Row(
            children: [
              Icon(
                sameBasis ? Icons.check_circle_outline : Icons.warning_amber,
                size: 18,
                color: sameBasis
                    ? theme.colorScheme.primary
                    : theme.colorScheme.error,
              ),
              const SizedBox(width: NexSpacing.sm),
              Expanded(
                child: Text(
                  strings(context, sameBasis ? 'compareSame' : 'compareWarn'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: sameBasis
                        ? theme.colorScheme.onSurfaceVariant
                        : theme.colorScheme.error,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: NexSpacing.md),
          Text(
            showRials
                ? strings(context, 'receiptUnitRial')
                : strings(context, 'receiptUnitToman'),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: NexSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final quote in [first, second])
                Expanded(
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(
                      end: NexSpacing.sm,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          quote.title.isEmpty
                              ? strings(context, 'receipt')
                              : quote.title,
                          textDirection: nexDirectionOf(quote.title),
                          style: theme.textTheme.titleSmall,
                        ),
                        if (quote.shop.isNotEmpty)
                          Text(
                            quote.shop,
                            textDirection: nexDirectionOf(quote.shop),
                          ),
                        Text(
                          '${goldDigits(quote.quoteDateIso, persian)} · ${strings(context, 'gregorianTag')}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: NexSpacing.md),
          NexPanel(
            title: strings(context, 'compare'),
            icon: Icons.compare_arrows,
            child: Column(
              children: [
                for (final (label, left, right) in rows)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: NexSpacing.xs,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: Text(label)),
                        Expanded(
                          child: Text(
                            money(left),
                            textDirection: TextDirection.ltr,
                            textAlign: TextAlign.end,
                          ),
                        ),
                        const SizedBox(width: NexSpacing.sm),
                        Expanded(
                          child: Text(
                            money(right),
                            textDirection: TextDirection.ltr,
                            textAlign: TextAlign.end,
                          ),
                        ),
                      ],
                    ),
                  ),
                Divider(color: theme.colorScheme.outlineVariant),
                if (sameBasis)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: NexSpacing.xs,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            strings(context, 'compareDifference'),
                            style: theme.textTheme.titleSmall,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            money(
                              first.estimatedTotalRial -
                                  second.estimatedTotalRial,
                            ),
                            textAlign: TextAlign.end,
                            textDirection: TextDirection.ltr,
                            style: theme.textTheme.titleSmall,
                          ),
                        ),
                        const SizedBox(width: NexSpacing.sm),
                        const Expanded(child: SizedBox()),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: NexSpacing.xl),
        ],
      ),
    );
  }
}
