part of 'loan_detail_screen.dart';

/// What the loan is and where it stands, in one panel.
class _SummaryPanel extends StatelessWidget {
  const _SummaryPanel({
    required this.loan,
    required this.standing,
    required this.unit,
  });

  final Loan loan;
  final LoanStanding standing;
  final IrrUnit unit;

  @override
  Widget build(BuildContext context) {
    final strings = lentStrings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final persian = NexModuleStrings.persian(context);
    final person = loan.person.isEmpty
        ? strings(context, 'untitledPerson')
        : loan.person;
    final directionLine = strings(
      context,
      loan.direction == LoanDirection.lent ? 'lentTo' : 'borrowedFrom',
      {'person': person},
    );
    final what = loan.kind == LoanKind.money
        ? formatAmount(loan.amount, loan.currency, loan.digits, persian, unit)
        : strings(context, 'itemTitle', {
            'n': loan.amount,
            'what': loan.what.isEmpty ? strings(context, 'item') : loan.what,
          });
    final words = loan.kind == LoanKind.money
        ? formatAmountWords(
            loan.amount,
            loan.currency,
            loan.digits,
            persian,
            unit,
          )
        : null;

    return NexPanel(
      icon: loan.direction == LoanDirection.lent
          ? Icons.north_east_outlined
          : Icons.south_west_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(directionLine, style: theme.textTheme.titleSmall),
          const SizedBox(height: NexSpacing.xs),
          Text(
            what,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (words != null)
            Text(
              words,
              key: const ValueKey('loan-total-words'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: NexSpacing.sm),
          Text(
            standing.settled
                ? strings(context, 'settledWord')
                : strings(context, 'outstanding', {
                    'amount': loan.kind == LoanKind.money
                        ? formatAmount(
                            standing.outstanding,
                            loan.currency,
                            loan.digits,
                            persian,
                            unit,
                          )
                        : formatNumber(standing.outstanding, persian),
                  }),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: standing.settled
                  ? scheme.onSurfaceVariant
                  : scheme.primary,
            ),
          ),
          const SizedBox(height: NexSpacing.sm),
          if (!standing.settled) ...[
            Text(
              loan.due == null
                  ? dueWording(context, standing.due)
                  : '${dueWording(context, standing.due)} · ${loanDateLabel(context, loan.due!)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: standing.due.status == DueStatus.overdue
                    ? scheme.error
                    : scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: NexSpacing.xs),
          ],
          Text(
            strings(context, 'issuedOn', {
              'date': loanDateLabel(context, loan.issued),
            }),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (loan.note.isNotEmpty) ...[
            const SizedBox(height: NexSpacing.sm),
            NexTextDirection(
              text: loan.note,
              child: Text(loan.note, style: theme.textTheme.bodyMedium),
            ),
          ],
        ],
      ),
    );
  }
}
