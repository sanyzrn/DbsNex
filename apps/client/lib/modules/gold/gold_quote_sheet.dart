/// The detail sheet a saved estimate opens into: the receipt as it was
/// saved, with the shop's words, and the two actions — edit it back into
/// the calculator, or delete it (with its Undo).
library;

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'gold_format.dart';
import 'gold_models.dart';
import 'gold_strings.dart';

/// Shows the saved estimate and resolves to `'edit'`, `'delete'` or null.
Future<String?> showGoldQuoteSheet(
  BuildContext context, {
  required GoldQuote quote,
  required bool showRials,
}) => nexShowSheet<String>(
  context: context,
  builder: (sheetContext) =>
      _GoldQuoteSheet(quote: quote, showRials: showRials),
);

class _GoldQuoteSheet extends StatelessWidget {
  const _GoldQuoteSheet({required this.quote, required this.showRials});

  final GoldQuote quote;
  final bool showRials;

  @override
  Widget build(BuildContext context) {
    final strings = goldStrings;
    final theme = Theme.of(context);
    final persian = NexModuleStrings.persian(context);
    String money(int rial) =>
        formatRial(rial, persian: persian, rials: showRials);
    final input = quote.input;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(NexSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            quote.title.isEmpty ? strings(context, 'receipt') : quote.title,
            style: theme.textTheme.titleLarge,
          ),
          if (quote.shop.isNotEmpty)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: NexSpacing.xs),
              child: Text(
                quote.shop,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          const SizedBox(height: NexSpacing.xs),
          Text(
            '${strings(context, 'quoteDated', {'date': goldDigits(quote.quoteDateIso, persian)})} · '
            '${strings(context, 'gregorianTag')}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: NexSpacing.md),
          for (final (label, amount) in [
            (strings(context, 'lineMetal'), quote.metalValueRial),
            (strings(context, 'lineMaking'), quote.makingChargeRial),
            (strings(context, 'lineProfit'), quote.sellerProfitRial),
            if (quote.commissionRial > 0)
              (strings(context, 'lineCommission'), quote.commissionRial),
            (strings(context, 'lineVatBase'), quote.vatBaseRial),
            (
              strings(context, 'lineVat', {
                'pct': formatPercent(input.vatBp, persian: persian),
              }),
              quote.vatRial,
            ),
            if (quote.extrasRial > 0)
              (strings(context, 'lineExtras'), quote.extrasRial),
            (strings(context, 'lineTotal'), quote.estimatedTotalRial),
            if (input.shopQuoteRial > 0)
              (strings(context, 'shopQuote'), input.shopQuoteRial),
          ])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: NexSpacing.xs),
              child: Row(
                children: [
                  Expanded(child: Text(label)),
                  Flexible(
                    child: Text(
                      money(amount),
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.end,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: label == strings(context, 'lineTotal')
                            ? FontWeight.w700
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (quote.notes.isNotEmpty) ...[
            const SizedBox(height: NexSpacing.md),
            Text(
              quote.notes,
              textDirection: nexDirectionOf(quote.notes),
              style: theme.textTheme.bodyMedium,
            ),
          ],
          const SizedBox(height: NexSpacing.md),
          FilledButton.icon(
            key: const ValueKey('gold-quote-edit'),
            onPressed: () => Navigator.pop(context, 'edit'),
            icon: const Icon(Icons.edit_outlined),
            label: Text(strings(context, 'openInCalculator')),
          ),
          const SizedBox(height: NexSpacing.sm),
          TextButton.icon(
            key: const ValueKey('gold-quote-delete'),
            onPressed: () => Navigator.pop(context, 'delete'),
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
            icon: const Icon(Icons.delete_outline),
            label: Text(AppLocalizations.of(context).delete),
          ),
        ],
      ),
    );
  }
}
