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
import 'split_math.dart';
import 'split_model.dart';
import 'store_state.dart';
import 'upgrade_strings.dart';

part 'split_detail_panels.dart';

/// One split: what it cost, how everyone stands, and the fewest payments
/// that make it even. A payment to or from the person holding the phone can
/// become an ordinary loan record, so it shows in the lists that already
/// exist — and can be sent as a message with the card or IBAN attached.
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
  late IrrUnit _unit = widget.unit ?? IrrUnit.toman;
  bool _writing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() => readRecords(() async {
    final settings = await readLoanSettings(widget.store);
    final raw = await widget.store.get('split', widget.splitId);
    if (!mounted) return;
    setState(() {
      _unit = settings.irrUnit;
      _split = raw == null ? null : LoanSplit.fromBody(widget.splitId, raw);
    });
  });

  Future<void> _record(SplitTransfer transfer) async {
    final split = _split;
    if (split == null || _writing) return;
    final me = personKey(split.me);
    if (me.isEmpty || !transfer.involves(split.me)) return;
    final other = personKey(transfer.from) == me ? transfer.to : transfer.from;
    final lent = personKey(transfer.to) == me;
    final note = splitNote(split, upgradeWord(context, 'splitLoanNote'));
    final today = civilDateKey(DateTime.now());
    final messenger = NexBannerHost.of(context);
    final recorded = upgradeWord(context, 'splitRecorded');
    final failure = lentStrings(context, 'saveError');
    setState(() => _writing = true);
    try {
      final loans = await widget.store.list('loan');
      final already = loans
          .map(Loan.fromRecord)
          .any(
            (loan) =>
                personKey(loan.person) == personKey(other) &&
                loan.amount == transfer.amount &&
                loan.note == note &&
                loan.issued == today,
          );
      if (!already) {
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
        );
        try {
          await widget.store.put('loan', loan.id, loan.toJson());
        } catch (_) {
          messenger?.show(kind: NexBannerKind.failed, message: failure);
          return;
        }
      }
      if (!mounted) return;
      messenger?.show(message: recorded);
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
          if (split != null)
            IconButton(
              key: const ValueKey('split-delete'),
              tooltip: strings(context, 'splitDelete'),
              icon: const Icon(Icons.delete_outline),
              onPressed: () => unawaited(_delete(split)),
            ),
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
                    onRecord: (transfer) => unawaited(_record(transfer)),
                    onMessage: (transfer) =>
                        unawaited(_message(transfer, split)),
                  ),
                  const SizedBox(height: NexSpacing.md),
                  NexShelfHeading(
                    icon: Icons.receipt_long_outlined,
                    title: strings(context, 'splitCosts'),
                  ),
                  const SizedBox(height: NexSpacing.sm),
                  for (final (index, cost) in split.costs.indexed)
                    NexGroupedRow(
                      index: index,
                      count: split.costs.length,
                      child: ListTile(
                        contentPadding: const EdgeInsetsDirectional.only(
                          start: NexSpacing.md,
                          end: NexSpacing.md,
                        ),
                        title: Text(
                          cost.title.isEmpty
                              ? strings(context, 'splitAddCost')
                              : cost.title,
                          style: theme.textTheme.titleSmall,
                        ),
                        subtitle: Text(
                          '${cost.payer} · ${formatAmount(cost.amount, 'IRR', 0, NexModuleStrings.persian(context), _unit)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
        () => unawaited(_load()),
      ),
    );
  }
}
