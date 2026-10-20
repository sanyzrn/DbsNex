import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'loan_detail_screen.dart';
import 'loan_edit_sheet.dart';
import 'loan_math.dart';
import 'loan_model.dart';
import 'loan_wording.dart';
import 'money_format.dart';
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

  @override
  Widget build(BuildContext context) {
    final strings = lentStrings;
    return Scaffold(
      appBar: NexAppBar(
        title: Text(strings(context, 'title')),
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
        TabBarView(
          controller: _tabs,
          children: [
            _LoanList(
              direction: LoanDirection.lent,
              loans: _loans,
              returns: _returns,
              store: widget.store,
              onNewRecord: () => unawaited(_openEditor(LoanDirection.lent)),
            ),
            _LoanList(
              direction: LoanDirection.borrowed,
              loans: _loans,
              returns: _returns,
              store: widget.store,
              onNewRecord: () => unawaited(_openEditor(LoanDirection.borrowed)),
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
    required this.onNewRecord,
  });

  final LoanDirection direction;
  final List<Loan> loans;
  final List<LoanReturn> returns;
  final NexModuleStore store;
  final VoidCallback onNewRecord;

  @override
  Widget build(BuildContext context) {
    final strings = lentStrings;
    final mine = loans.where((l) => l.direction == direction).toList();
    if (mine.isEmpty) {
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
        if (outstanding.isNotEmpty) ...[
          NexShelfHeading(
            icon: Icons.outbox_outlined,
            title: strings(context, 'outstandingHeading'),
          ),
          const SizedBox(height: NexSpacing.sm),
          for (final (index, loan) in outstanding.indexed)
            _LoanRow(
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
            _LoanRow(
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

/// One loan, legible at a glance: the person, what is still out, and how
/// the due date reads today — in words, with respectful wording for the
/// ones that have passed.
class _LoanRow extends StatelessWidget {
  const _LoanRow({
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
