/// «From a budget»: the way back from an amount of money to an amount of
/// gold. It reads the rate, purity, charges, profit and VAT the calculator
/// already holds, asks only for the budget, and answers with the heaviest
/// piece that stays within it — the same formula run the other way.
library;

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'gold_format.dart';
import 'gold_math.dart';
import 'gold_strings.dart';

/// Opens the sheet over [input] (the calculator with a placeholder weight).
/// Resolves to the weight in milligrams when the person chose to use it.
Future<int?> showGoldBudgetSheet(
  BuildContext context, {
  required GoldInput input,
  required bool showRials,
}) => nexShowSheet<int>(
  context: context,
  swipeToClose: true,
  builder: (_) => _GoldBudgetSheet(input: input, showRials: showRials),
);

class _GoldBudgetSheet extends StatefulWidget {
  const _GoldBudgetSheet({required this.input, required this.showRials});

  final GoldInput input;
  final bool showRials;

  @override
  State<_GoldBudgetSheet> createState() => _GoldBudgetSheetState();
}

class _GoldBudgetSheetState extends State<_GoldBudgetSheet> {
  final _budget = TextEditingController();

  @override
  void dispose() {
    _budget.dispose();
    super.dispose();
  }

  /// The budget in rials, or null while the field is empty or not a number
  /// the calculator accepts. The field is toman, like every amount here.
  int? get _budgetRial {
    final (value, problem) = parseScaledDetailed(_budget.text, 2);
    if (problem != null || value == null || value < 1) return null;
    final rial = value ~/ 10 + (value % 10 >= 5 ? 1 : 0);
    return rial >= 1 && rial <= GoldInput.maxAmountRial ? rial : null;
  }

  @override
  Widget build(BuildContext context) {
    final strings = goldStrings;
    final theme = Theme.of(context);
    final persian = NexModuleStrings.persian(context);
    final rial = _budgetRial;
    final weight = rial == null
        ? null
        : GoldMath.maxWeightMgWithin(widget.input, rial);
    final atCap = weight == GoldInput.maxWeightMg;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        NexSpacing.md,
        NexSpacing.md,
        NexSpacing.md,
        NexSpacing.md + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            strings(context, 'budgetTitle'),
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: NexSpacing.xs),
          Text(
            strings(context, 'budgetAbout'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: NexSpacing.md),
          TextField(
            key: const ValueKey('gold-budget-field'),
            controller: _budget,
            autofocus: true,
            textDirection: TextDirection.ltr,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: strings(context, 'budgetField'),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: NexSpacing.md),
          if (_budget.text.trim().isNotEmpty && rial == null)
            Text(
              strings(context, 'budgetBad'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            )
          else if (weight != null && weight == 0)
            Text(
              key: const ValueKey('gold-budget-none'),
              strings(context, 'budgetNone'),
              style: theme.textTheme.bodyMedium,
            )
          else if (weight != null) ...[
            NexPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    strings(context, atCap ? 'budgetAtCap' : 'budgetResult', {
                      'weight': formatWeightMg(weight, persian: persian),
                      'amount':
                          '${formatRial(rial!, persian: persian, rials: widget.showRials)} '
                          '${strings(context, widget.showRials ? 'rialWord' : 'tomanWord')}',
                    }),
                    key: const ValueKey('gold-budget-result'),
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: NexSpacing.xs),
                  Text(
                    strings(context, 'budgetNote'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: NexSpacing.md),
            FilledButton(
              key: const ValueKey('gold-budget-use'),
              onPressed: () => Navigator.pop(context, weight),
              child: Text(strings(context, 'budgetUse')),
            ),
          ],
        ],
      ),
    );
  }
}
