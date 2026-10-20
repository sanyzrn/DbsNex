import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'loan_people.dart';
import 'money_format.dart';
import 'module.dart';

/// What is still out in one direction, in each currency by itself — a sum
/// across currencies would need a rate nobody has entered — with the
/// overdue count said plainly beside it.
class LoanSummaryCard extends StatelessWidget {
  const LoanSummaryCard({
    super.key,
    required this.summary,
    required this.owedToMe,
  });

  final LoanSummary summary;

  /// True for the Lent tab ("owed to me"), false for Borrowed ("I owe").
  final bool owedToMe;

  @override
  Widget build(BuildContext context) {
    final strings = lentStrings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final persian = NexModuleStrings.persian(context);
    final lines = <String>[
      for (final total in summary.money)
        formatMoney(total.minor, total.currency, total.digits, persian),
      if (summary.itemsOut > 0)
        strings(context, 'itemsOut', {'n': summary.itemsOut}),
    ];
    return NexPanel(
      key: const ValueKey('loans-summary'),
      icon: owedToMe ? Icons.south_west : Icons.north_east,
      title: strings(context, owedToMe ? 'owedToMe' : 'iOwe'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (lines.isEmpty)
            Text(
              strings(context, 'nothingOut'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            )
          else
            for (final line in lines)
              Padding(
                padding: const EdgeInsetsDirectional.only(
                  bottom: NexSpacing.xs,
                ),
                child: Text(line, style: theme.textTheme.titleMedium),
              ),
          if (summary.overdue > 0)
            Text(
              strings(context, 'overdueCount', {'n': summary.overdue}),
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
            ),
        ],
      ),
    );
  }
}
