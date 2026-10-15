import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'loan_model.dart';
import 'money_format.dart';
import 'module.dart';

/// Every return, newest first, each removable — the honest history of what
/// has come back so far.
class LoanReturnHistory extends StatelessWidget {
  const LoanReturnHistory({
    super.key,
    required this.loan,
    required this.returns,
    required this.onDelete,
  });

  final Loan loan;
  final List<LoanReturn> returns;
  final void Function(LoanReturn record) onDelete;

  @override
  Widget build(BuildContext context) {
    final strings = lentStrings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final persian = NexModuleStrings.persian(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NexShelfHeading(
          icon: Icons.history_outlined,
          title: strings(context, 'returnHistory'),
        ),
        const SizedBox(height: NexSpacing.sm),
        if (returns.isEmpty)
          Padding(
            padding: const EdgeInsetsDirectional.all(NexSpacing.md),
            child: Text(
              strings(context, 'noReturns'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          )
        else
          for (final (index, record) in returns.indexed)
            NexGroupedRow(
              index: index,
              count: returns.length,
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.check_circle_outline, size: 20),
                title: Text(
                  strings(context, 'returnedOn', {
                    'amount': loan.kind == LoanKind.money
                        ? formatMoney(
                            record.amount,
                            loan.currency,
                            loan.digits,
                            persian,
                          )
                        : formatNumber(record.amount, persian),
                  }),
                ),
                subtitle: Text(
                  _relative(record.date, strings, context),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                trailing: IconButton(
                  key: ValueKey('return-delete-${record.id}'),
                  tooltip: strings(context, 'deleteReturn'),
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => onDelete(record),
                ),
              ),
            ),
      ],
    );
  }

  String _relative(
    String dateKey,
    NexModuleStrings strings,
    BuildContext context,
  ) {
    final parsed = DateTime.tryParse(dateKey);
    final now = DateTime.now();
    if (parsed == null) return strings(context, 'dateUnknown');

    final days = DateTime.utc(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime.utc(parsed.year, parsed.month, parsed.day)).inDays;
    if (days < 0) return strings(context, 'futureDate', {'n': -days});
    if (days == 0) return strings(context, 'returnToday');
    if (days == 1) return strings(context, 'yesterdayWord');
    return strings(context, 'returnDaysAgo', {'n': days});
  }
}
