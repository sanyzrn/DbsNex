import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'irr_unit.dart';
import 'money_format.dart';
import 'split_model.dart';
import 'upgrade_strings.dart';

/// The cost rows of the split editor: each one opens for correction, and the
/// button beside the heading adds the next. Kept out of the editor itself so
/// the form stays readable.
class SplitCostList extends StatelessWidget {
  const SplitCostList({
    super.key,
    required this.costs,
    required this.unit,
    required this.onAdd,
    required this.onEdit,
    required this.onRemove,
  });

  final List<SplitCost> costs;
  final IrrUnit unit;
  final VoidCallback onAdd;
  final ValueChanged<int> onEdit;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    final strings = upgradeStrings;
    final theme = Theme.of(context);
    final persian = NexModuleStrings.persian(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                strings(context, 'splitCosts'),
                style: theme.textTheme.titleSmall,
              ),
            ),
            TextButton.icon(
              key: const ValueKey('split-add-cost'),
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: Text(strings(context, 'splitAddCost')),
            ),
          ],
        ),
        if (costs.isEmpty)
          Text(
            strings(context, 'splitNoCosts'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          for (final (index, cost) in costs.indexed)
            ListTile(
              key: ValueKey('split-cost-$index'),
              contentPadding: EdgeInsets.zero,
              onTap: () => onEdit(index),
              title: Text(
                cost.title.isEmpty
                    ? strings(context, 'splitCostUntitled')
                    : cost.title,
              ),
              subtitle: Text(
                '${cost.payer} · '
                '${formatAmount(cost.amount, 'IRR', 0, persian, unit)}',
              ),
              trailing: IconButton(
                key: ValueKey('split-cost-remove-$index'),
                tooltip: strings(context, 'splitCostRemove'),
                icon: const Icon(Icons.close),
                onPressed: () => onRemove(index),
              ),
            ),
      ],
    );
  }
}
