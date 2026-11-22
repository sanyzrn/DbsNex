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
///
/// The list is built lazily: a ledger of a hundred records paints the rows
/// on the screen, not all of them, so opening the tab stays quick and the
/// scroll keeps its frame rate.
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
      // A filter that hides everything is not a failed search: saying
      // «nothing matches that» after tapping Overdue, with no search typed,
      // blamed the person for a list that is simply empty.
      final searching = query.trim().isNotEmpty;
      return ListView(
        padding: const EdgeInsetsDirectional.all(NexSpacing.md),
        children: [
          LoanSummaryCard(
            summary: summary,
            owedToMe: direction == LoanDirection.lent,
            unit: unit,
          ),
          NexEmptyState(
            icon: !searching && filter == LoanFilter.settled
                ? Icons.task_alt_outlined
                : !searching
                ? Icons.event_available_outlined
                : Icons.search_off_outlined,
            message: _emptyMessage(context, searching: searching),
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
    final slots = <_Slot>[
      const _Summary(),
      const _Gap(NexSpacing.md),
      if (outstanding.isNotEmpty) ...[
        _Heading(
          icon: Icons.outbox_outlined,
          title: strings(context, 'outstandingHeading'),
        ),
        const _Gap(NexSpacing.sm),
        for (final (index, loan) in outstanding.indexed)
          _Row(loan: loan, index: index, count: outstanding.length),
      ],
      if (settled.isNotEmpty) ...[
        if (outstanding.isNotEmpty) const _Gap(NexSpacing.lg),
        _Heading(
          icon: Icons.task_alt_outlined,
          title: strings(context, 'settledHeading'),
        ),
        const _Gap(NexSpacing.sm),
        for (final (index, loan) in settled.indexed)
          _Row(loan: loan, index: index, count: settled.length),
      ],
      const _Gap(NexSpacing.xl),
    ];

    return ListView.builder(
      padding: EdgeInsetsDirectional.fromSTEB(
        NexSpacing.md,
        NexSpacing.sm,
        NexSpacing.md,
        // Room for the floating New button, so the last settled row is not
        // read through it.
        NexSpacing.xl * 3 + nexBottomInset(context),
      ),
      itemCount: slots.length,
      itemBuilder: (context, index) {
        final slot = slots[index];
        return switch (slot) {
          _Summary() => LoanSummaryCard(
            summary: summary,
            owedToMe: direction == LoanDirection.lent,
            unit: unit,
          ),
          _Heading(:final icon, :final title) => NexShelfHeading(
            icon: icon,
            title: title,
          ),
          _Gap(:final height) => SizedBox(height: height),
          _Row(loan: final loan, index: final rowIndex, count: final count) =>
            LoanRow(
              index: rowIndex,
              count: count,
              loan: loan,
              standing: standings[loan.id]!,
              store: store,
              unit: unit,
            ),
        };
      },
    );
  }

  /// What an empty list says: the search found nothing, or this filter has
  /// nothing to show yet.
  String _emptyMessage(BuildContext context, {required bool searching}) {
    final strings = lentStrings;
    if (searching) return strings(context, 'noMatches');
    return switch (filter) {
      LoanFilter.all => strings(context, 'noMatches'),
      LoanFilter.dueSoon => strings(context, 'emptyDueSoon'),
      LoanFilter.overdue => strings(context, 'emptyOverdue'),
      LoanFilter.settled => strings(context, 'emptySettled'),
    };
  }

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

/// One line of the lazily built tab: the hero, a heading, a gap or a row.
sealed class _Slot {
  const _Slot();
}

class _Summary extends _Slot {
  const _Summary();
}

class _Heading extends _Slot {
  const _Heading({required this.icon, required this.title});

  final IconData icon;
  final String title;
}

class _Gap extends _Slot {
  const _Gap(this.height);

  final double height;
}

class _Row extends _Slot {
  const _Row({required this.loan, required this.index, required this.count});

  final Loan loan;
  final int index;
  final int count;
}
