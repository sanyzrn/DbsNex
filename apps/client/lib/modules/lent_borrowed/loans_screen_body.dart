import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'irr_unit.dart';
import 'loan_filter.dart';
import 'loan_math.dart';
import 'loan_model.dart';
import 'loan_people.dart';
import 'loan_row.dart';
import 'loan_summary_card.dart';
import 'module.dart';

/// One tab: the loans of one direction, outstanding first, settled under
/// their own quiet heading. Split from the page so each file keeps to one
/// job — and so the ranking can be read without the page around it.
class LoanListBody extends StatelessWidget {
  const LoanListBody({
    super.key,
    required this.direction,
    required this.loans,
    required this.returns,
    required this.store,
    required this.query,
    required this.filter,
    required this.unit,
    required this.onNewRecord,
  });

  final String query;
  final LoanFilter filter;
  final LoanDirection direction;
  final List<Loan> loans;
  final List<LoanReturn> returns;
  final NexModuleStore store;
  final IrrUnit unit;
  final VoidCallback onNewRecord;

  @override
  Widget build(BuildContext context) {
    final strings = lentStrings;
    final all = loans.where((l) => l.direction == direction).toList();
    final summary = LoanSummary.of(all, returns);
    // One standings pass feeds the filter, the ranking and the rows; the
    // build used to scan the returns list twice per loan.
    final standings = LoanMath.standingsOf(all, returns);
    final mine = [
      for (final loan in all)
        if (loanMatches(loan, query) && filter.allows(standings[loan.id]!))
          loan,
    ];
    if (all.isEmpty) {
      return ListView(
        padding: const EdgeInsetsDirectional.all(NexSpacing.md),
        children: [
          NexEmptyState(
            icon: Icons.swap_horiz_outlined,
            message: strings(
              context,
              direction == LoanDirection.lent
                  ? 'noLoansLent'
                  : 'noLoansBorrowed',
            ),
            // Only while the library has no record at all; after that the
            // button floating on the page does the job.
            action: loans.isEmpty
                ? FilledButton.icon(
                    key: const ValueKey('loans-new'),
                    onPressed: onNewRecord,
                    icon: const Icon(Icons.add),
                    label: Text(strings(context, 'newRecord')),
                  )
                : null,
          ),
        ],
      );
    }
    if (mine.isEmpty) {
      return ListView(
        padding: const EdgeInsetsDirectional.all(NexSpacing.md),
        children: [
          LoanSummaryCard(
            summary: summary,
            owedToMe: direction == LoanDirection.lent,
            unit: unit,
          ),
          NexEmptyState(
            icon: Icons.search_off_outlined,
            message: strings(context, 'noMatches'),
          ),
        ],
      );
    }
    // Newest saved first within a rank: the store's own order, kept stable
    // so a reload never shuffles the loans a person was looking at.
    final ranked =
        [
          for (final (index, loan) in mine.indexed)
            if (!standings[loan.id]!.settled) (index, loan),
        ]..sort((a, b) {
          final rank =
              _dueRank(standings[b.$2.id]!) - _dueRank(standings[a.$2.id]!);
          return rank != 0 ? rank : a.$1.compareTo(b.$1);
        });
    final outstanding = [for (final (_, loan) in ranked) loan];
    final settled = mine.where((l) => standings[l.id]!.settled).toList();

    return ListView(
      padding: EdgeInsetsDirectional.fromSTEB(
        NexSpacing.md,
        NexSpacing.sm,
        NexSpacing.md,
        // Room for the floating New button, so the last settled row is not
        // read through it.
        NexSpacing.xl * 3 + nexBottomInset(context),
      ),
      children: [
        LoanSummaryCard(
          summary: summary,
          owedToMe: direction == LoanDirection.lent,
          unit: unit,
        ),
        const SizedBox(height: NexSpacing.md),
        if (outstanding.isNotEmpty)
          ..._section(
            context,
            icon: Icons.outbox_outlined,
            title: strings(context, 'outstandingHeading'),
            rows: outstanding,
            standings: standings,
          ),
        if (settled.isNotEmpty) ...[
          if (outstanding.isNotEmpty) const SizedBox(height: NexSpacing.lg),
          ..._section(
            context,
            icon: Icons.task_alt_outlined,
            title: strings(context, 'settledHeading'),
            rows: settled,
            standings: standings,
          ),
        ],
        const SizedBox(height: NexSpacing.xl),
      ],
    );
  }

  List<Widget> _section(
    BuildContext context, {
    required IconData icon,
    required String title,
    required List<Loan> rows,
    required Map<String, LoanStanding> standings,
  }) => [
    NexShelfHeading(icon: icon, title: title),
    const SizedBox(height: NexSpacing.sm),
    for (final (index, loan) in rows.indexed)
      LoanRow(
        index: index,
        count: rows.length,
        loan: loan,
        standing: standings[loan.id]!,
        store: store,
        unit: unit,
      ),
  ];

  /// Overdue first, then due soon, then the rest — the loans that need
  /// attention are the loans at the top.
  int _dueRank(LoanStanding standing) => switch (standing.due.status) {
    DueStatus.overdue => 5,
    DueStatus.today => 4,
    DueStatus.dueSoon => 3,
    DueStatus.later => 2,
    DueStatus.none => 1,
    DueStatus.settled => 0,
  };
}
