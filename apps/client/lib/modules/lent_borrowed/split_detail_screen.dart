import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'irr_unit.dart';
import 'loan_date_entry.dart';
import 'loan_model.dart';
import 'loan_people.dart';
import 'loan_settings.dart';
import 'module.dart';
import 'money_format.dart';
import 'person_message.dart';
import 'split_cost_sheet.dart';
import 'split_editor_sheet.dart';
import 'split_math.dart';
import 'split_model.dart';
import 'store_state.dart';
import 'upgrade_strings.dart';

part 'split_detail_panels.dart';

/// One split: what it cost, how everyone stands, and the fewest payments
/// that make it even. A payment to or from the person holding the phone can
/// become an ordinary loan record, so it shows in the lists that already
/// exist — and can be sent as a message with the card or IBAN attached.
///
/// A saved split stays editable: a cost added later, a wrong amount, a name
/// or the date corrected in place, without losing the trip around it.
class SplitDetailScreen extends StatefulWidget {
  const SplitDetailScreen({
    super.key,
    required this.store,
    required this.splitId,
    this.unit,
  });

  final NexModuleStore store;
  final String splitId;
  final IrrUnit? unit;

  @override
  State<SplitDetailScreen> createState() => _SplitDetailScreenState();
}

class _SplitDetailScreenState extends State<SplitDetailScreen>
    with StoreState<SplitDetailScreen> {
  LoanSplit? _split;
  List<Loan> _loans = const [];
  late IrrUnit _unit = widget.unit ?? IrrUnit.toman;
  StreamSubscription<void>? _changes;
  bool _writing = false;

  @override
  void initState() {
    super.initState();
    _changes = widget.store.changes.listen((_) => unawaited(_load()));
    unawaited(_load());
  }

  @override
  void dispose() {
    unawaited(_changes?.cancel());
    super.dispose();
  }

  Future<void> _load() => readRecords(() async {
    final settings = await readLoanSettings(widget.store);
    final raw = await widget.store.get('split', widget.splitId);
    final loans = await widget.store.list('loan');
    if (!mounted) return;
    setState(() {
      _unit = settings.irrUnit;
      _split = raw == null ? null : LoanSplit.fromBody(widget.splitId, raw);
      _loans = loans.map(Loan.fromRecord).toList();
    });
  });

  /// The settle word is both the note's prefix and what tells a recorded
  /// transfer from one still waiting, so both read it the same way.
  String get _settleWord => upgradeWord(context, 'splitLoanNote');

  bool _recorded(LoanSplit split, SplitTransfer transfer) =>
      splitTransferRecorded(_loans, split, transfer, _settleWord);

  Future<void> _record(SplitTransfer transfer) async {
    final split = _split;
    if (split == null || _writing) return;
    final me = personKey(split.me);
    if (me.isEmpty || !transfer.involves(split.me)) return;
    final other = personKey(transfer.from) == me ? transfer.to : transfer.from;
    final lent = personKey(transfer.to) == me;
    final note = splitNote(split, _settleWord);
    final today = civilDateKey(DateTime.now());
    final messenger = NexBannerHost.of(context);
    final recorded = upgradeWord(context, 'splitRecorded');
    final failure = lentStrings(context, 'saveError');
    setState(() => _writing = true);
    try {
      final loans = (await widget.store.list('loan'))
          .map(Loan.fromRecord)
          .toList();
      if (!splitTransferRecorded(loans, split, transfer, _settleWord)) {
        final loan = Loan(
          id: widget.store.newId(),
          direction: lent ? LoanDirection.lent : LoanDirection.borrowed,
          person: other,
          kind: LoanKind.money,
          amount: transfer.amount,
          what: '',
          issued: today,
          due: null,
          note: note,
          // The link back to this split, so a later rename keeps the payment
          // recorded instead of offering it again.
          splitId: split.id,
        );
        await widget.store.put('loan', loan.id, loan.toJson());
      }
      if (!mounted) return;
      messenger?.show(message: recorded);
      await _load();
    } catch (_) {
      messenger?.show(kind: NexBannerKind.failed, message: failure);
    } finally {
      if (mounted) setState(() => _writing = false);
    }
  }

  Future<void> _message(SplitTransfer transfer, LoanSplit split) async {
    final me = personKey(split.me);
    final other = personKey(transfer.from) == me ? transfer.to : transfer.from;
    final iPay = personKey(transfer.from) == me;
    final persian = NexModuleStrings.persian(context);
    final amount = formatAmount(transfer.amount, 'IRR', 0, persian, _unit);
    final intro = [
      upgradeWord(context, 'splitMessageIntro', {
        'person': other,
        'title': split.title,
        'amount': amount,
      }),
      upgradeWord(context, iPay ? 'splitMessageIOwe' : 'splitMessageOwed', {
        'amount': amount,
      }),
      upgradeWord(context, 'splitMessageClose'),
    ].join(' ');
    await showPersonMessageSheet(
      context,
      widget.store,
      person: other,
      unit: _unit,
      balanceLines: [intro],
    );
  }

  /// Costs live inside the split, so one write replaces them and every field
  /// this version does not know stays exactly as it was.
  Future<void> _writeCosts(
    LoanSplit split,
    List<SplitCost> Function(List<SplitCost>) edit,
  ) async {
    final saved = await storeWrite(context, () async {
      final raw = await widget.store.get('split', split.id);
      if (raw == null) throw StateError('Split no longer exists');
      final current = LoanSplit.fromBody(split.id, raw);
      await widget.store.put(
        'split',
        split.id,
        current.copyWith(costs: edit(current.costs)).toJson(previous: raw),
      );
    });
    if (saved && mounted) await _load();
  }

  Future<void> _addCost(LoanSplit split) async {
    if (_writing || split.people.length < 2) return;
    final cost = await showSplitCostSheet(
      context,
      people: split.people,
      unit: _unit,
    );
    if (cost == null || !mounted) return;
    setState(() => _writing = true);
    try {
      await _writeCosts(split, (costs) => [...costs, cost]);
    } finally {
      if (mounted) setState(() => _writing = false);
    }
  }

  Future<void> _editCost(LoanSplit split, int index) async {
    if (_writing) return;
    final cost = await showSplitCostSheet(
      context,
      people: split.people,
      unit: _unit,
      existing: split.costs[index],
    );
    if (cost == null || !mounted) return;
    setState(() => _writing = true);
    try {
      await _writeCosts(split, (costs) {
        final id = split.costs[index].id;
        final currentIndex = id.isEmpty
            ? (index < costs.length && costs[index].id.isEmpty ? index : -1)
            : costs.indexWhere((entry) => entry.id == id);
        if (currentIndex == -1) throw StateError('Cost no longer exists');
        return [...costs]..[currentIndex] = cost;
      });
    } finally {
      if (mounted) setState(() => _writing = false);
    }
  }

  Future<void> _editSplit(LoanSplit split) async {
    final saved = await showSplitEditorSheet(
      context,
      widget.store,
      unit: _unit,
      existing: split,
    );
    if (saved == true && mounted) await _load();
  }

  Future<void> _delete(LoanSplit split) async {
    final messenger = NexBannerHost.of(context);
    final l10n = AppLocalizations.of(context);
    final failure = lentStrings(context, 'saveError');
    final raw = await widget.store.get('split', split.id);
    if (raw == null) return;
    await widget.store.delete('split', split.id);
    if (!mounted) return;
    Navigator.of(context).maybePop();
    messenger?.show(
      message: upgradeWord(context, 'splitDeleted'),
      actionLabel: l10n.undo,
      onAction: () => unawaited(
        widget.store.put('split', split.id, raw).catchError((Object _) {
          messenger.show(kind: NexBannerKind.failed, message: failure);
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = upgradeStrings;
    final theme = Theme.of(context);
    final persian = NexModuleStrings.persian(context);
    final split = _split;
    return Scaffold(
      appBar: NexAppBar(
        title: Text(
          split?.title.isNotEmpty == true
              ? split!.title
              : strings(context, 'splitsTitle'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (split != null) ...[
            IconButton(
              key: const ValueKey('split-edit'),
              tooltip: strings(context, 'splitEdit'),
              icon: const Icon(Icons.edit_outlined),
              onPressed: _writing ? null : () => unawaited(_editSplit(split)),
            ),
            IconButton(
              key: const ValueKey('split-delete'),
              tooltip: strings(context, 'splitDelete'),
              icon: const Icon(Icons.delete_outline),
              onPressed: _writing ? null : () => unawaited(_delete(split)),
            ),
          ],
        ],
      ),
      body: recordsBody(
        split == null
            ? NexEmptyState(
                icon: Icons.groups_outlined,
                message: strings(context, 'splitsEmpty'),
              )
            : ListView(
                key: const ValueKey('split-detail-body'),
                padding: EdgeInsetsDirectional.fromSTEB(
                  NexSpacing.md,
                  NexSpacing.sm,
                  NexSpacing.md,
                  NexSpacing.lg + nexBottomInset(context),
                ),
                children: [
                  _TotalPanel(split: split, unit: _unit),
                  const SizedBox(height: NexSpacing.md),
                  NexShelfHeading(
                    icon: Icons.balance,
                    title: strings(context, 'splitBalances'),
                  ),
                  const SizedBox(height: NexSpacing.sm),
                  _BalancesPanel(split: split, unit: _unit),
                  const SizedBox(height: NexSpacing.md),
                  NexShelfHeading(
                    icon: Icons.swap_horiz,
                    title: strings(context, 'splitTransfers'),
                  ),
                  const SizedBox(height: NexSpacing.sm),
                  _TransfersPanel(
                    split: split,
                    unit: _unit,
                    recorded: (transfer) => _recorded(split, transfer),
                    onRecord: (transfer) => unawaited(_record(transfer)),
                    onMessage: (transfer) =>
                        unawaited(_message(transfer, split)),
                  ),
                  const SizedBox(height: NexSpacing.md),
                  NexShelfHeading(
                    icon: Icons.receipt_long_outlined,
                    title: strings(context, 'splitCosts'),
                    trailing: TextButton.icon(
                      key: const ValueKey('split-cost-add'),
                      onPressed: _writing
                          ? null
                          : () => unawaited(_addCost(split)),
                      icon: const Icon(Icons.add),
                      label: Text(strings(context, 'splitAddCost')),
                    ),
                  ),
                  const SizedBox(height: NexSpacing.sm),
                  for (final (index, cost) in split.costs.indexed)
                    NexGroupedRow(
                      index: index,
                      count: split.costs.length,
                      child: ListTile(
                        key: ValueKey('split-cost-${cost.id}'),
                        onTap: _writing
                            ? null
                            : () => unawaited(_editCost(split, index)),
                        contentPadding: const EdgeInsetsDirectional.only(
                          start: NexSpacing.md,
                          end: NexSpacing.sm,
                        ),
                        title: Text(
                          cost.title.isEmpty
                              ? strings(context, 'splitCostUntitled')
                              : cost.title,
                          style: theme.textTheme.titleSmall,
                        ),
                        subtitle: Text(
                          '${cost.payer} · '
                          '${formatAmount(cost.amount, 'IRR', 0, persian, _unit)}'
                          ' · ${_modeWord(strings, context, cost.mode)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        trailing: Icon(
                          Icons.chevron_right,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
        () => unawaited(_load()),
      ),
    );
  }

  String _modeWord(
    NexModuleStrings strings,
    BuildContext context,
    SplitMode mode,
  ) => switch (mode) {
    SplitMode.equal => strings(context, 'splitEqual'),
    SplitMode.shares => strings(context, 'splitShares'),
    SplitMode.amounts => strings(context, 'splitAmounts'),
  };
}
