import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'loan_detail_screen.dart';
import 'loan_math.dart';
import 'loan_model.dart';
import 'loan_wording.dart';
import 'money_format.dart';
import 'module.dart';

/// One loan, legible at a glance: the person, what is still out, and how
/// the due date reads today — in words, with respectful wording for the
/// ones that have passed.
class LoanRow extends StatelessWidget {
  const LoanRow({
    super.key,
    required this.index,
    required this.count,
    required this.loan,
    required this.standing,
    required this.store,
  });

  final int index;
  final int count;
  final Loan loan;
  final LoanStanding standing;
  final NexModuleStore store;

  @override
  Widget build(BuildContext context) {
    final strings = lentStrings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final persian = NexModuleStrings.persian(context);
    final person = loan.person.isEmpty
        ? strings(context, 'untitledPerson')
        : loan.person;
    final what = loan.kind == LoanKind.money
        ? strings(context, 'money')
        : (loan.what.isEmpty ? strings(context, 'item') : loan.what);

    final amountText = loan.kind == LoanKind.money
        ? formatMoney(standing.outstanding, loan.currency, loan.digits, persian)
        : formatNumber(standing.outstanding, persian);

    return NexGroupedRow(
      index: index,
      count: count,
      child: ListTile(
        onTap: () => unawaited(
          Navigator.push(
            context,
            NexPageRoute<void>(
              builder: (_) => LoanDetailScreen(store: store, loanId: loan.id),
            ),
          ),
        ),
        title: Text(
          person,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$what · ${strings(context, 'outstanding', {'amount': amountText})}',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            _dueText(context, scheme),
          ],
        ),
        trailing: standing.settled
            ? Icon(
                Icons.check_circle_outline,
                size: 20,
                color: scheme.onSurfaceVariant,
              )
            : null,
        isThreeLine: true,
      ),
    );
  }

  Widget _dueText(BuildContext context, ColorScheme scheme) {
    final due = standing.due;
    final style = themeOf(context).textTheme.bodySmall?.copyWith(
      color: due.status == DueStatus.overdue ? scheme.error : scheme.primary,
    );
    return Text(
      dueWording(context, due),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }

  ThemeData themeOf(BuildContext context) => Theme.of(context);
}
