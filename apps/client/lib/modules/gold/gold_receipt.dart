/// The receipt: what was calculated, line by line, with what was entered
/// kept visibly apart from what was worked out — and a plain-text
/// breakdown a person can select and copy.
library;

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'gold_dates.dart';
import 'gold_format.dart';
import 'gold_math.dart';
import 'gold_strings.dart';

/// The live receipt panel. [input] and [result] are what the calculator
/// holds right now; both stay non-null only when the form is valid.
class GoldReceipt extends StatelessWidget {
  const GoldReceipt({
    super.key,
    required this.input,
    required this.result,
    required this.showRials,
    required this.quoteDate,
  });

  final GoldInput input;
  final GoldResult result;
  final bool showRials;

  /// The quote date typed for this estimate, shown inside the breakdown.
  final String quoteDate;

  @override
  Widget build(BuildContext context) {
    final strings = goldStrings;
    final persian = NexModuleStrings.persian(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    String money(int rial) =>
        formatRial(rial, persian: persian, rials: showRials);

    final rows = <(String, String)>[
      (strings(context, 'lineMetal'), money(result.metalValueRial)),
      (strings(context, 'lineMaking'), money(result.makingChargeRial)),
      (strings(context, 'lineProfit'), money(result.sellerProfitRial)),
      if (result.commissionRial > 0)
        (strings(context, 'lineCommission'), money(result.commissionRial)),
      (strings(context, 'lineVatBase'), money(result.vatBaseRial)),
      (
        strings(context, 'lineVat', {
          'pct': formatPercent(input.vatBp, persian: persian),
        }),
        money(result.vatRial),
      ),
      if (result.extrasRial > 0)
        (strings(context, 'lineExtras'), money(result.extrasRial)),
    ];

    final diff = result.quoteDiffRial;
    final diffPct = result.quoteDiffHundredthsPct;

    return Semantics(
      label: strings(context, 'receiptSemantics', {
        'total': money(result.estimatedTotalRial),
      }),
      child: NexPanel(
        title: strings(context, 'receipt'),
        icon: Icons.receipt_long_outlined,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.only(bottom: NexSpacing.sm),
              child: Text(
                showRials
                    ? strings(context, 'receiptUnitRial')
                    : strings(context, 'receiptUnitToman'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            if (result.rateWasConverted)
              _Note(
                text: strings(context, 'rateConverted', {
                  'ppt': groupDigits(input.finenessPpt, persian: persian),
                  'rate': formatCentiRate(
                    result.convertedRateCentiPerG,
                    persian: persian,
                  ),
                  'ratio':
                      '${groupDigits(input.finenessPpt, persian: persian)}'
                      '/${groupDigits(input.rateRefPpt, persian: persian)}',
                }),
              ),
            if (result.nonGoldMg > 0)
              _Note(
                text: strings(context, 'nonGoldLine', {
                  'amount': formatWeightMg(result.nonGoldMg, persian: persian),
                }),
              ),
            for (final (label, amount) in rows)
              _Row(label: label, amount: amount),
            // A fixed or per-gram charge in the trade's own words: what
            // share of the metal it comes to.
            if (input.makingMode != GoldMakingMode.percent &&
                GoldMath.makingShareBp(result) != null)
              _Note(
                text: strings(context, 'makingShare', {
                  'pct': formatPercent(
                    GoldMath.makingShareBp(result)!,
                    persian: persian,
                  ),
                }),
              ),
            if (result.extrasRial > 0)
              _Note(text: strings(context, 'extrasTaxNote')),
            if (input.vatBp == 0) _Note(text: strings(context, 'vatZeroNote')),
            Divider(color: scheme.outlineVariant, height: NexSpacing.lg),
            _Row(
              label: strings(context, 'lineTotal'),
              amount: money(result.estimatedTotalRial),
              emphasized: true,
            ),
            if (diff != null) ...[
              const SizedBox(height: NexSpacing.sm),
              _Row(
                label: strings(context, 'lineDiff'),
                amount:
                    '${diff >= 0 ? '+' : ''}${money(diff)} · '
                    '${diffPct == null ? strings(context, 'diffPercentUnavailable') : formatPercent(diffPct, persian: persian)}',
                emphasized: true,
              ),
              Padding(
                padding: const EdgeInsetsDirectional.only(top: NexSpacing.xs),
                child: Text(
                  strings(context, 'diffExplainer'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
            const SizedBox(height: NexSpacing.md),
            _Breakdown(
              input: input,
              result: result,
              showRials: showRials,
              quoteDate: quoteDate,
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.amount,
    this.emphasized = false,
  });

  final String label;
  final String amount;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style =
        (emphasized ? theme.textTheme.titleMedium : theme.textTheme.bodyMedium)
            ?.copyWith(
              fontWeight: emphasized ? FontWeight.w700 : null,
              color: emphasized
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.onSurfaceVariant,
            );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: NexSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: style)),
          const SizedBox(width: NexSpacing.sm),
          Flexible(
            child: Text(
              amount,
              style: style,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(
      bottom: NexSpacing.sm,
      end: NexSpacing.xs,
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.info_outline,
          size: 16,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: NexSpacing.sm),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    ),
  );
}

/// The plain-text cost breakdown: one button copies it all, and the words
/// also sit in a [SelectionArea] for taking a part.
class _Breakdown extends StatelessWidget {
  const _Breakdown({
    required this.input,
    required this.result,
    required this.showRials,
    required this.quoteDate,
  });

  final GoldInput input;
  final GoldResult result;
  final bool showRials;
  final String quoteDate;

  List<String> _lines(BuildContext context) {
    final persian = NexModuleStrings.persian(context);
    String money(int rial) =>
        formatRial(rial, persian: persian, rials: showRials);
    String pct(int bp) => formatPercent(bp, persian: persian);
    String weight(int mg) => formatWeightMg(mg, persian: persian);
    String rate(int centi) => formatCentiRate(centi, persian: persian);
    final strings = goldStrings;

    return [
      strings(context, 'breakdownMetal', {
        'weight': weight(input.weightMg),
        'rate': rate(result.convertedRateCentiPerG),
        'amount': money(result.metalValueRial),
      }),
      switch (input.makingMode) {
        GoldMakingMode.percent => strings(context, 'breakdownMakingPercent', {
          'pct': pct(input.makingPercentBp),
          'amount': money(result.makingChargeRial),
        }),
        GoldMakingMode.perGram => strings(context, 'breakdownMakingPerGram', {
          'rate': rate(input.makingPerGramCenti),
          'weight': weight(input.weightMg),
          'amount': money(result.makingChargeRial),
        }),
        GoldMakingMode.fixed => strings(context, 'breakdownMakingFixed', {
          'amount': money(result.makingChargeRial),
        }),
        GoldMakingMode.mixed => strings(context, 'breakdownMakingMixed', {
          'pct': pct(input.makingPercentBp),
          'rate': rate(input.makingPerGramCenti),
          'amount': money(result.makingChargeRial),
        }),
      },
      strings(context, 'breakdownProfit_${input.profitBase.name}', {
        'pct': pct(input.profitBp),
        'amount': money(result.sellerProfitRial),
      }),
      if (result.commissionRial > 0)
        strings(context, 'breakdownCommission', {
          'amount': money(result.commissionRial),
        }),
      strings(
        context,
        input.commissionTaxable
            ? 'breakdownVatBase'
            : 'breakdownVatBaseNoCommission',
        {'amount': money(result.vatBaseRial)},
      ),
      strings(context, 'breakdownVat', {
        'pct': pct(input.vatBp),
        'amount': money(result.vatRial),
      }),
      for (final (label, amount) in input.extras)
        strings(context, 'breakdownExtra', {
          'label': label,
          'amount': money(amount),
        }),
      strings(context, 'breakdownTotal', {
        'amount': money(result.estimatedTotalRial),
      }),
      if (input.shopQuoteRial > 0)
        strings(context, 'breakdownQuote', {
          'amount': money(input.shopQuoteRial),
        }),
      if (result.quoteDiffRial != null && result.quoteDiffHundredthsPct != null)
        strings(context, 'breakdownDiff', {
          'amount': money(result.quoteDiffRial!),
          'pct': pct(result.quoteDiffHundredthsPct!),
        }),
      if (quoteDate.isNotEmpty)
        strings(context, 'breakdownDate', {
          'date': goldStoredDateLabel(context, quoteDate),
          'ppt': groupDigits(input.rateRefPpt, persian: persian),
        }),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = goldStrings;
    final lines = _lines(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          strings(context, 'breakdownTitle'),
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: NexSpacing.xs),
        SelectionArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final line in lines)
                Text(
                  line,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: NexSpacing.xs),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: const ValueKey('gold-copy-estimate'),
            onPressed: () async {
              await nexModuleCopyText(lines.join('\n'));
              if (!context.mounted) return;
              nexShowBanner(
                context,
                message: strings(context, 'breakdownCopied'),
              );
            },
            icon: const Icon(Icons.copy_outlined),
            label: Text(strings(context, 'copyBreakdown')),
          ),
        ),
        Text(
          strings(context, 'breakdownHint'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      ],
    );
  }
}
