import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'loan_edit_sheet.dart';
import 'loan_math.dart';
import 'loan_model.dart';
import 'loan_date_entry.dart';
import 'loan_wording.dart';
import 'return_history.dart';
import 'money_format.dart';
import 'module.dart';
import 'store_state.dart';
import 'record_bundle.dart';
import 'return_sheet.dart';

/// One loan's whole story: what is still out, how the due date reads, and
/// every return in order — the history an edit can never wipe. Recording
/// a return and marking fully settled are the two things a person comes
/// here to do.
class LoanDetailScreen extends StatefulWidget {
  const LoanDetailScreen({
    super.key,
    required this.store,
    required this.loanId,
  });

  final NexModuleStore store;
  final String loanId;

  @override
  State<LoanDetailScreen> createState() => _LoanDetailScreenState();
}

class _LoanDetailScreenState extends State<LoanDetailScreen>
    with WidgetsBindingObserver, StoreState<LoanDetailScreen> {
  Loan? _loan;
  List<LoanReturn> _returns = const [];
  StreamSubscription<void>? _changes;
  int _loadToken = 0;
  bool _writing = false;
  bool _sheetOpen = false;

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
    super.dispose();
  }

  Future<void> _load() => readRecords(_read);

  /// One sheet at a time: a double-tap on Edit or Record a return must not
  /// stack two editors that each write their own record.
  Future<void> _openSheet(Future<void> Function() open) async {
    if (_sheetOpen || _writing) return;
    _sheetOpen = true;
    try {
      await open();
    } finally {
      _sheetOpen = false;
    }
  }

  Future<void> _read() async {
    await RecordBundle.recover(widget.store);
    final token = ++_loadToken;
    final body = await widget.store.get('loan', widget.loanId);
    final returns = await widget.store.list('return');
    if (!mounted || token != _loadToken) return;
    if (body == null) {
      if (_writing) return;
      Navigator.of(context).maybePop();
      return;
    }
    // The store's own order, newest first, kept stable within a date so a
    // reload never shuffles the history a person was reading.
    final history =
        [
          for (final (index, record)
              in returns
                  .map(LoanReturn.fromRecord)
                  .where((r) => r.loanId == widget.loanId)
                  .toList()
                  .indexed)
            (index, record),
        ]..sort((a, b) {
          final byDate = b.$2.date.compareTo(a.$2.date);
          return byDate != 0 ? byDate : a.$1.compareTo(b.$1);
        });
    setState(() {
      _loan = Loan.fromBody(widget.loanId, body);
      _returns = [for (final (_, record) in history) record];
    });
  }

  Future<void> _guard(Future<void> Function() action) async {
    if (_writing) return;
    setState(() => _writing = true);
    try {
      await action();
      if (mounted) await _load();
    } catch (_) {
      writeError();
    } finally {
      if (mounted) setState(() => _writing = false);
    }
  }

  /// Deleting a loan takes its whole return history with it — and Undo
  /// brings the complete set back, not only the headline.
  Future<void> _delete() => _guard(() async {
    final loan = _loan;
    if (loan == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    final errorMessage = lentStrings(context, 'saveError');
    final bundle = await RecordBundle.capture(
      widget.store,
      'loan',
      loan.id,
      'return',
      'loan',
    );
    await bundle.delete();
    if (!mounted) return;
    Navigator.of(context).maybePop();
    messenger.showSnackBar(
      SnackBar(
        content: Text(lentStrings(context, 'loanDeleted')),
        action: SnackBarAction(
          label: l10n.undo,
          onPressed: () => unawaited(
            bundle.restore().catchError((Object _) {
              messenger.showSnackBar(SnackBar(content: Text(errorMessage)));
            }),
          ),
        ),
      ),
    );
  });

  @override
  Widget build(BuildContext context) {
    final loan = _loan;
    if (loan == null) {
      return Scaffold(
        appBar: NexAppBar(),
        body: recordsBody(const SizedBox(), () => unawaited(_load())),
      );
    }
    final strings = lentStrings;
    final standing = LoanMath.standing(loan, _returns);
    final person = loan.person.isEmpty
        ? strings(context, 'untitledPerson')
        : loan.person;

    return Scaffold(
      appBar: NexAppBar(
        title: Text(person, maxLines: 2, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            key: const ValueKey('loan-edit'),
            tooltip: strings(context, 'editRecord'),
            icon: const Icon(Icons.edit_outlined),
            onPressed: _writing || _sheetOpen
                ? null
                : () => unawaited(
                    _openSheet(
                      () => showLoanEditSheet(
                        context,
                        widget.store,
                        editing: loan,
                        returns: _returns,
                      ),
                    ),
                  ),
          ),
          NexPopupMenuButton<String>(
            key: const ValueKey('loan-menu'),
            tooltip: strings(context, 'more'),
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'delete') unawaited(_delete());
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'delete',
                child: Text(
                  strings(context, 'deleteLoan'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
          ),
        ],
      ),
      body: recordsBody(
        ListView(
          padding: EdgeInsetsDirectional.fromSTEB(
            NexSpacing.md,
            NexSpacing.sm,
            NexSpacing.md,
            NexSpacing.lg + nexBottomInset(context),
          ),
          children: [
            _SummaryPanel(loan: loan, standing: standing),
            const SizedBox(height: NexSpacing.md),
            if (!standing.settled) ...[
              FilledButton.icon(
                key: const ValueKey('loan-record-return'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                onPressed: _writing || _sheetOpen
                    ? null
                    : () => unawaited(
                        _openSheet(
                          () => showReturnSheet(
                            context,
                            widget.store,
                            loan: loan,
                            returns: _returns,
                          ),
                        ),
                      ),
                icon: const Icon(Icons.replay_outlined),
                label: Text(strings(context, 'recordReturn')),
              ),
              const SizedBox(height: NexSpacing.sm),
              TextButton(
                key: const ValueKey('loan-mark-settled'),
                onPressed: _writing
                    ? null
                    : () => unawaited(_recordReturn(standing.outstanding)),
                child: Text(strings(context, 'markSettled')),
              ),
              const SizedBox(height: NexSpacing.md),
            ],
            LoanReturnHistory(
              loan: loan,
              returns: _returns,
              onDelete: (record) => unawaited(_deleteReturn(record)),
            ),
            const SizedBox(height: NexSpacing.xl),
          ],
        ),
        () => unawaited(_load()),
      ),
    );
  }

  /// Writes one return record; shared by the sheet flow and "mark fully
  /// settled", so a settlement is exactly a return of what remained — and
  /// correcting it is exactly deleting that return.
  Future<void> _recordReturn(int amount) => _guard(() async {
    final loan = _loan;
    if (loan == null || amount <= 0) return;
    final body = await widget.store.get('loan', loan.id);
    if (body == null) return;
    final fresh = Loan.fromBody(loan.id, body);
    final records = (await widget.store.list(
      'return',
    )).map(LoanReturn.fromRecord).toList();
    final remaining = LoanMath.standing(fresh, records).outstanding;
    if (remaining <= 0) return;
    await widget.store.put('return', widget.store.newId(), {
      'loan': loan.id,
      'date': civilDateKey(DateTime.now()),
      'amount': remaining,
    });
  });

  /// Taking a mistaken return back: the SnackBar's Undo re-`put`s the
  /// complete record, so balances return to exactly what they were.
  Future<void> _deleteReturn(LoanReturn record) => _guard(() async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    final errorMessage = lentStrings(context, 'saveError');
    final raw = await widget.store.get('return', record.id);
    if (raw == null) return;
    await widget.store.delete('return', record.id);
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(lentStrings(context, 'returnDeleted')),
        action: SnackBarAction(
          label: l10n.undo,
          onPressed: () => unawaited(
            widget.store.put('return', record.id, raw).catchError((Object _) {
              messenger.showSnackBar(SnackBar(content: Text(errorMessage)));
            }),
          ),
        ),
      ),
    );
  });
}

/// What the loan is and where it stands, in one panel.
class _SummaryPanel extends StatelessWidget {
  const _SummaryPanel({required this.loan, required this.standing});

  final Loan loan;
  final LoanStanding standing;

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
        ? formatMoney(loan.amount, loan.currency, loan.digits, persian)
        : '${formatNumber(loan.amount, persian)} × ${loan.what.isEmpty ? strings(context, 'item') : loan.what}';

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
          const SizedBox(height: NexSpacing.sm),
          Text(
            standing.settled
                ? strings(context, 'settledWord')
                : strings(context, 'outstanding', {
                    'amount': loan.kind == LoanKind.money
                        ? formatMoney(
                            standing.outstanding,
                            loan.currency,
                            loan.digits,
                            persian,
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
