part of 'loan_detail_screen.dart';

/// What a record still offers while something is out: record a return,
/// settle it, the reminder message, and the optional due-day reminder.
///
/// Kept beside the summary so the page reads as "what it is, then what I can
/// do", and so a thing lent keeps its message while money owed offers the
/// other one: asking for the card to pay to.
class _LoanActions extends StatelessWidget {
  const _LoanActions({
    required this.store,
    required this.loan,
    required this.standing,
    required this.unit,
    required this.busy,
    required this.sheetOpen,
    required this.onReturn,
    required this.onSettle,
    required this.onDetailChanged,
  });

  final NexModuleStore store;
  final Loan loan;
  final LoanStanding standing;
  final IrrUnit unit;
  final bool busy;
  final bool sheetOpen;
  final VoidCallback onReturn;
  final VoidCallback onSettle;
  final ValueChanged<bool> onDetailChanged;

  /// A thing lent keeps its reminder message; asking to pay needs money and
  /// a name to ask.
  bool get _canMessage =>
      loan.direction == LoanDirection.lent ||
      (loan.kind == LoanKind.money && loan.person.trim().isNotEmpty);

  @override
  Widget build(BuildContext context) {
    final strings = lentStrings;
    final lent = loan.direction == LoanDirection.lent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          key: const ValueKey('loan-record-return'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: busy || sheetOpen ? null : onReturn,
          icon: const Icon(Icons.replay_outlined),
          label: Text(strings(context, 'recordReturn')),
        ),
        const SizedBox(height: NexSpacing.sm),
        TextButton(
          key: const ValueKey('loan-mark-settled'),
          onPressed: busy || sheetOpen ? null : onSettle,
          child: Text(strings(context, 'markSettled')),
        ),
        if (_canMessage)
          TextButton.icon(
            key: ValueKey(lent ? 'loan-message' : 'loan-pay-message'),
            // Owing money asks the other thing of the other person: their
            // card or IBAN, so the debt is paid rather than chased.
            onPressed: () => unawaited(
              lent
                  ? showLoanMessageSheet(context, loan, standing, unit)
                  : showPersonMessageSheet(
                      context,
                      store,
                      person: loan.person,
                      unit: unit,
                      balanceLines: [
                        loanPayMessage(context, loan, standing, unit),
                      ],
                    ),
            ),
            icon: const Icon(Icons.chat_bubble_outline),
            label: Text(
              strings(context, lent ? 'messageTitle' : 'messagePayTitle'),
            ),
          ),
        const SizedBox(height: NexSpacing.md),
        // A due date is only worth having if something says so when it comes:
        // an optional system reminder, opened on the due day.
        LoanReminderSection(
          store: store,
          loan: loan,
          standing: standing,
          unit: unit,
          onDetailChanged: busy ? (_) {} : onDetailChanged,
        ),
        const SizedBox(height: NexSpacing.md),
      ],
    );
  }
}

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
