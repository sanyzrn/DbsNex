import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'irr_unit.dart';
import 'loan_detail_screen.dart';
import 'loan_math.dart';
import 'loan_model.dart';
import 'loan_wording.dart';
import 'module.dart';
import 'money_format.dart';

/// One loan, legible at a glance: the person, what is still out (or what
/// came back), and how the due date reads today — in words, with respectful
/// wording for the ones that have passed.
class LoanRow extends StatelessWidget {
  const LoanRow({
    super.key,
    required this.index,
    required this.count,
    required this.loan,
    required this.standing,
    required this.store,
    required this.unit,
    this.showPerson = true,
  });

  final int index;
  final int count;
  final Loan loan;
  final LoanStanding standing;
  final NexModuleStore store;
  final IrrUnit unit;

  /// False on a person's own page, where every row is that person: the
  /// title then says what the record is instead of repeating the name.
  final bool showPerson;

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
    final settled = standing.settled;
    final quantity = settled ? loan.amount : standing.outstanding;

    // What the row says about the record itself. A settled record says what
    // came back, never «0 tomans still out».
    final line = loan.kind == LoanKind.money
        ? strings(context, settled ? 'returnedOn' : 'outstanding', {
            'amount': formatAmount(
              settled ? loan.amount : standing.outstanding,
              loan.currency,
              loan.digits,
              persian,
              unit,
            ),
          })
        : strings(context, settled ? 'rowItemBack' : 'rowItemOut', {
            'what': loan.what.isEmpty ? strings(context, 'item') : loan.what,
            'n': quantity,
          });

    return NexGroupedRow(
      index: index,
      count: count,
      child: ListTile(
        onTap: () => unawaited(
          Navigator.push(
            context,
            NexPageRoute<void>(
              builder: (_) =>
                  LoanDetailScreen(store: store, loanId: loan.id, unit: unit),
            ),
          ),
        ),
        title: Text(
          showPerson ? person : what,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall,
        ),
        subtitle: settled
            ? Text(
                line,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    line,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    dueWording(context, standing.due),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: _dueColor(standing.due.status, scheme),
                    ),
                  ),
                ],
              ),
        trailing: settled
            ? Icon(
                Icons.check_circle_outline,
                size: 20,
                color: scheme.onSurfaceVariant,
              )
            : null,
        isThreeLine: !settled,
      ),
    );
  }

  /// Overdue is the only thing here that needs the colour of a problem;
  /// "no due date" must not look as urgent as "due today".
  Color? _dueColor(DueStatus status, ColorScheme scheme) => switch (status) {
    DueStatus.overdue => scheme.error,
    DueStatus.today || DueStatus.dueSoon => scheme.primary,
    _ => scheme.onSurfaceVariant,
  };
}
