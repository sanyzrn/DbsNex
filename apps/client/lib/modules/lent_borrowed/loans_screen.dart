import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'loan_edit_sheet.dart';
import 'loan_filter.dart';
import 'loan_people.dart';
import 'loan_row.dart';
import 'loan_summary_card.dart';
import 'people_screen.dart';
import 'loan_math.dart';
import 'loan_model.dart';
import 'module.dart';
import 'store_state.dart';
import 'record_bundle.dart';

/// The overview: Lent and Borrowed never mix, outstanding comes before
/// settled, and a due date that has passed is said plainly, at the top,
/// where the person is looking when they open the module.
class LoansScreen extends StatefulWidget {
  const LoansScreen({super.key, required this.store});

  final NexModuleStore store;

  @override
  State<LoansScreen> createState() => _LoansScreenState();
}

class _LoansScreenState extends State<LoansScreen>
    with
        SingleTickerProviderStateMixin,
        WidgetsBindingObserver,
        StoreState<LoansScreen> {
  List<Loan> _loans = const [];
  List<LoanReturn> _returns = const [];
  StreamSubscription<void>? _changes;
  int _loadToken = 0;
  bool _editorOpen = false;
  late final TabController _tabs = TabController(length: 2, vsync: this);
  final TextEditingController _search = TextEditingController();
  LoanFilter _filter = LoanFilter.all;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _changes = widget.store.changes.listen((_) => unawaited(_load()));
    unawaited(_load());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_changes?.cancel());
    _tabs.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() => readRecords(_read);

  /// One editor at a time: a double-tap on New must not stack two sheets
  /// that each write their own record.
  Future<void> _openEditor(LoanDirection direction) async {
    if (_editorOpen) return;
    _editorOpen = true;
    try {
      await showLoanEditSheet(
        context,
        widget.store,
        initialDirection: direction,
      );
    } finally {
      _editorOpen = false;
    }
  }

  Future<void> _read() async {
    await RecordBundle.recover(widget.store);
    final token = ++_loadToken;
    final loans = await widget.store.list('loan');
    final returns = await widget.store.list('return');
    if (!mounted || token != _loadToken) return;
    setState(() {
      _loans = loans.map(Loan.fromRecord).toList();
      _returns = returns.map(LoanReturn.fromRecord).toList();
    });
  }

  Widget _searchBar(BuildContext context) {
    final strings = lentStrings;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        NexSpacing.md,
        NexSpacing.sm,
        NexSpacing.md,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NexAutoDirection(
            controller: _search,
            builder: (context, direction) => TextField(
              key: const ValueKey('loans-search'),
              controller: _search,
              textDirection: direction,
              textInputAction: TextInputAction.search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: strings(context, 'searchHint'),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: MaterialLocalizations.of(
                          context,
                        ).deleteButtonTooltip,
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(_search.clear),
                      ),
              ),
            ),
          ),
          const SizedBox(height: NexSpacing.sm),
          Wrap(
            spacing: NexSpacing.sm,
            runSpacing: NexSpacing.xs,
            children: [
              for (final filter in LoanFilter.values)
                ChoiceChip(
                  key: ValueKey('loans-filter-${filter.name}'),
                  label: Text(strings(context, 'filter_${filter.name}')),
                  selected: _filter == filter,
                  onSelected: (_) => setState(() => _filter = filter),
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = lentStrings;
    return Scaffold(
      appBar: NexAppBar(
        title: Text(strings(context, 'title')),
        actions: [
          IconButton(
            key: const ValueKey('loans-people'),
            tooltip: strings(context, 'people'),
            icon: const Icon(Icons.people_outline),
            onPressed: () => unawaited(
              Navigator.push(
                context,
                NexPageRoute<void>(
                  builder: (_) => PeopleScreen(store: widget.store),
                ),
              ),
            ),
          ),
        ],
        bottom: TabBar(
          key: const ValueKey('loans-tabs'),
          controller: _tabs,
          tabs: [
            Tab(
              key: const ValueKey('loans-tab-lent'),
              text: strings(context, 'tabLent'),
            ),
            Tab(
              key: const ValueKey('loans-tab-borrowed'),
              text: strings(context, 'tabBorrowed'),
            ),
          ],
        ),
      ),
      // One primary action per page: with no record at all it is the button
      // in the empty state, not a second one floating beside it.
      floatingActionButton: _loans.isEmpty
          ? null
          : FloatingActionButton.extended(
              key: const ValueKey('loans-new'),
              onPressed: () => unawaited(
                _openEditor(
                  _tabs.index == 0
                      ? LoanDirection.lent
                      : LoanDirection.borrowed,
                ),
              ),
              icon: const Icon(Icons.add),
              label: Text(strings(context, 'newRecord')),
            ),
      body: recordsBody(
        Column(
          children: [
            if (_loans.isNotEmpty) _searchBar(context),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _LoanList(
                    direction: LoanDirection.lent,
                    loans: _loans,
                    returns: _returns,
                    store: widget.store,
                    query: _search.text,
                    filter: _filter,
                    onNewRecord: () =>
                        unawaited(_openEditor(LoanDirection.lent)),
                  ),
                  _LoanList(
                    direction: LoanDirection.borrowed,
                    loans: _loans,
                    returns: _returns,
                    store: widget.store,
                    query: _search.text,
                    filter: _filter,
                    onNewRecord: () =>
                        unawaited(_openEditor(LoanDirection.borrowed)),
                  ),
                ],
              ),
            ),
          ],
        ),
        () => unawaited(_load()),
      ),
    );
  }
}

/// One tab: the loans of one direction, outstanding first, settled under
/// their own quiet heading.
class _LoanList extends StatelessWidget {
  const _LoanList({
    required this.direction,
    required this.loans,
    required this.returns,
    required this.store,
    required this.query,
    required this.filter,
    required this.onNewRecord,
  });

  final String query;
  final LoanFilter filter;
  final LoanDirection direction;
  final List<Loan> loans;
  final List<LoanReturn> returns;
  final NexModuleStore store;
  final VoidCallback onNewRecord;

  @override
  Widget build(BuildContext context) {
    final strings = lentStrings;
    final all = loans.where((l) => l.direction == direction).toList();
    final summary = LoanSummary.of(all, returns);
    final mine = [
      for (final loan in all)
        if (loanMatches(loan, query) &&
            filter.allows(LoanMath.standing(loan, returns)))
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
          ),
          NexEmptyState(
            icon: Icons.search_off_outlined,
            message: strings(context, 'noMatches'),
          ),
        ],
      );
    }
    final standings = {
      for (final loan in mine) loan.id: LoanMath.standing(loan, returns),
    };
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
        NexSpacing.lg + nexBottomInset(context),
      ),
      children: [
        LoanSummaryCard(
          summary: summary,
          owedToMe: direction == LoanDirection.lent,
        ),
        const SizedBox(height: NexSpacing.md),
        if (outstanding.isNotEmpty) ...[
          NexShelfHeading(
            icon: Icons.outbox_outlined,
            title: strings(context, 'outstandingHeading'),
          ),
          const SizedBox(height: NexSpacing.sm),
          for (final (index, loan) in outstanding.indexed)
            LoanRow(
              index: index,
              count: outstanding.length,
              loan: loan,
              standing: standings[loan.id]!,
              store: store,
            ),
        ],
        if (settled.isNotEmpty) ...[
          if (outstanding.isNotEmpty) const SizedBox(height: NexSpacing.lg),
          NexShelfHeading(
            icon: Icons.task_alt_outlined,
            title: strings(context, 'settledHeading'),
          ),
          const SizedBox(height: NexSpacing.sm),
          for (final (index, loan) in settled.indexed)
            LoanRow(
              index: index,
              count: settled.length,
              loan: loan,
              standing: standings[loan.id]!,
              store: store,
            ),
        ],
        const SizedBox(height: NexSpacing.xl),
      ],
    );
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
