import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'gold_format.dart';
import 'gold_market_math.dart';
import 'gold_strings.dart';

class GoldMarketResult extends StatelessWidget {
  const GoldMarketResult.sale({
    super.key,
    required this.sale,
    required this.weightMg,
    required this.rateCenti,
    required this.settlement,
    required this.deductionBp,
    required this.costRial,
    required this.showRials,
  }) : fineness = 750,
       mithqalCenti = 0;
  const GoldMarketResult.melt({
    super.key,
    required this.weightMg,
    required this.rateCenti,
    required this.fineness,
    required this.mithqalCenti,
    required this.showRials,
  }) : sale = null,
       settlement = 750,
       deductionBp = 0,
       costRial = 0;
  final GoldSaleResult? sale;
  final int weightMg,
      rateCenti,
      fineness,
      mithqalCenti,
      settlement,
      deductionBp,
      costRial;
  final bool showRials;

  @override
  Widget build(BuildContext context) {
    final persian = NexModuleStrings.persian(context);
    final theme = Theme.of(context);
    final unit = goldStrings(context, showRials ? 'rialWord' : 'tomanWord');
    String money(int value) =>
        '${formatRial(value, persian: persian, rials: showRials)} $unit';
    String number(int value) => groupDigits(value, persian: persian);
    String rate(int value) => goldStrings(context, 'rateAmount', {
      'amount': formatCentiRate(value, persian: persian),
    });
    final rows = <(String, String)>[];
    final s = sale;
    final total = s?.netRial ?? GoldMarketMath.metalRial(weightMg, rateCenti);
    if (s != null) {
      rows.addAll([
        (goldStrings(context, 'lineMetal'), money(s.metalRial)),
        (goldStrings(context, 'settlement'), number(settlement)),
        (goldStrings(context, 'marketRate750'), rate(rateCenti)),
        (
          goldStrings(context, 'saleDeduction'),
          '${formatPercent(deductionBp, persian: persian)} · ${money(s.deductionRial)}',
        ),
        (goldStrings(context, 'saleFeeValue'), money(s.feeRial)),
      ]);
      if (costRial > 0) {
        final breakEven = GoldMarketMath.breakEvenRate(
          costRial: costRial,
          weightMg: weightMg,
          settlementPpt: settlement,
          deductionBp: deductionBp,
          feeRial: s.feeRial,
        );
        rows.addAll([
          (goldStrings(context, 'saleCostValue'), money(costRial)),
          (goldStrings(context, 'saleGain'), money(s.netRial - costRial)),
          (
            goldStrings(context, 'saleBreakEven'),
            breakEven == null
                ? goldStrings(context, 'breakEvenUnavailable')
                : rate(breakEven),
          ),
        ]);
      }
    } else {
      final mithqalWeight = GoldMarketMath.weightMithqal(weightMg);
      rows.addAll([
        (goldStrings(context, 'assayFineness'), number(fineness)),
        (goldStrings(context, 'meltGramResult'), rate(rateCenti)),
        (
          goldStrings(context, 'marketMithqal'),
          '${formatCentiRate(mithqalCenti, persian: persian)} ${goldStrings(context, 'tomanWord')}',
        ),
        (goldStrings(context, 'sootResult'), number(weightMg)),
        (
          goldStrings(context, 'mithqalWeightResult'),
          groupDecimal(
            mithqalWeight ~/ 10000,
            mithqalWeight % 10000,
            4,
            persian: persian,
          ),
        ),
        (
          goldStrings(context, 'equivalent750'),
          formatWeightMg(
            GoldMarketMath.equivalent750Mg(weightMg, fineness),
            persian: persian,
          ),
        ),
      ]);
    }
    final caption = goldStrings(context, s == null ? 'meltTotal' : 'saleNet');
    return NexModuleHero(
      key: const ValueKey('gold-market-result'),
      moduleId: 'gold',
      icon: s == null ? Icons.balance_outlined : Icons.sell_outlined,
      eyebrow: caption,
      headline: formatRial(total, persian: persian, rials: showRials),
      caption: unit,
      semanticsLabel: '$caption: ${money(total)}',
      chips: [
        goldStrings(context, 'marketWeightChip', {
          'weight': formatWeightMg(weightMg, persian: persian),
        }),
        goldStrings(context, 'manualRates'),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: NexSpacing.sm),
              child: LayoutBuilder(
                builder: (context, box) {
                  if (box.maxWidth < 340 ||
                      MediaQuery.textScalerOf(context).scale(14) > 20) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label, style: theme.textTheme.bodySmall),
                        Text(value, style: theme.textTheme.titleSmall),
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(label, style: theme.textTheme.bodySmall),
                      ),
                      const SizedBox(width: NexSpacing.sm),
                      Flexible(
                        child: Text(value, style: theme.textTheme.titleSmall),
                      ),
                    ],
                  );
                },
              ),
            ),
          if (costRial > 0)
            Text(
              goldStrings(context, 'breakEvenHint'),
              style: theme.textTheme.bodySmall,
            ),
          const SizedBox(height: NexSpacing.sm),
          TextButton.icon(
            key: const ValueKey('gold-market-copy'),
            icon: const Icon(Icons.copy_outlined),
            label: Text(goldStrings(context, 'copyBreakdown')),
            onPressed: () async {
              final lines = [
                caption,
                goldStrings(context, 'marketWeightChip', {
                  'weight': formatWeightMg(weightMg, persian: persian),
                }),
                ...rows.map((row) => '${row.$1}: ${row.$2}'),
                '$caption: ${money(total)}',
                goldStrings(context, s == null ? 'meltCaution' : 'saleCaution'),
              ];
              try {
                await nexModuleCopyText(lines.join('\n'));
                if (context.mounted) {
                  nexShowBanner(
                    context,
                    message: goldStrings(context, 'breakdownCopied'),
                  );
                }
              } catch (_) {
                if (context.mounted) {
                  nexShowBanner(
                    context,
                    message: goldStrings(context, 'copyFailed'),
                    kind: NexBannerKind.failed,
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }
}
