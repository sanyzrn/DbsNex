part of 'split_detail_screen.dart';

class _TotalPanel extends StatelessWidget {
  const _TotalPanel({required this.split, required this.unit});

  final LoanSplit split;
  final IrrUnit unit;

  @override
  Widget build(BuildContext context) {
    final strings = upgradeStrings;
    final theme = Theme.of(context);
    final persian = NexModuleStrings.persian(context);
    return NexPanel(
      key: const ValueKey('split-total'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            loanDateLabel(context, split.date),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: NexSpacing.xs),
          Text(
            strings(context, 'splitTotal', {
              'amount': formatAmount(split.total, 'IRR', 0, persian, unit),
            }),
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: NexSpacing.xs),
          Text(
            // The count in the reader's digits, the names with their comma.
            '${formatNumber(split.people.length, persian)} · '
            '${split.people.join(persian ? '، ' : ', ')}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _BalancesPanel extends StatelessWidget {
  const _BalancesPanel({required this.split, required this.unit});

  final LoanSplit split;
  final IrrUnit unit;

  @override
  Widget build(BuildContext context) {
    final strings = upgradeStrings;
    final theme = Theme.of(context);
    final persian = NexModuleStrings.persian(context);
    final balances = splitBalances(split);
    return NexPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (balances.every((balance) => balance.isEven))
            Text(
              strings(context, 'splitAllEven'),
              style: theme.textTheme.bodyMedium,
            )
          else
            for (final balance in balances)
              Padding(
                padding: const EdgeInsetsDirectional.only(
                  bottom: NexSpacing.xs,
                ),
                child: Text(
                  balance.isEven
                      ? strings(context, 'splitEven', {
                          'person': balance.person,
                        })
                      : strings(
                          context,
                          balance.receives ? 'splitGets' : 'splitOwes',
                          {
                            'person': balance.person,
                            'amount': formatAmount(
                              balance.net.abs(),
                              'IRR',
                              0,
                              persian,
                              unit,
                            ),
                          },
                        ),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
        ],
      ),
    );
  }
}

class _TransfersPanel extends StatelessWidget {
  const _TransfersPanel({
    required this.split,
    required this.unit,
    required this.recorded,
    required this.onRecord,
    required this.onMessage,
  });

  final LoanSplit split;
  final IrrUnit unit;

  /// Whether this payment already has its loan record — asked of the saved
  /// loans, so the answer survives closing the page and the next day.
  final bool Function(SplitTransfer transfer) recorded;
  final ValueChanged<SplitTransfer> onRecord;
  final ValueChanged<SplitTransfer> onMessage;

  @override
  Widget build(BuildContext context) {
    final strings = upgradeStrings;
    final theme = Theme.of(context);
    final persian = NexModuleStrings.persian(context);
    final transfers = settleTransfers(split);
    if (transfers.isEmpty) {
      return NexPanel(
        child: Text(
          strings(context, 'splitAllEven'),
          style: theme.textTheme.bodyMedium,
        ),
      );
    }
    return NexPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, transfer) in transfers.indexed) ...[
            if (index > 0) const Divider(height: NexSpacing.lg),
            Text(
              strings(context, 'splitTransfer', {
                'from': transfer.from,
                'to': transfer.to,
                'amount': formatAmount(
                  transfer.amount,
                  'IRR',
                  0,
                  persian,
                  unit,
                ),
              }),
              key: ValueKey('split-transfer-$index'),
              style: theme.textTheme.bodyMedium,
            ),
            if (split.me.isNotEmpty && transfer.involves(split.me)) ...[
              const SizedBox(height: NexSpacing.xs),
              Wrap(
                spacing: NexSpacing.sm,
                runSpacing: NexSpacing.xs,
                children: [
                  FilledButton.tonalIcon(
                    key: ValueKey('split-record-$index'),
                    // A recorded payment says so instead of inviting a second
                    // identical loan; the guard in the screen holds even if
                    // the record was made on another day.
                    onPressed: recorded(transfer)
                        ? null
                        : () => onRecord(transfer),
                    icon: Icon(
                      recorded(transfer) ? Icons.check : Icons.add_link,
                    ),
                    label: Text(
                      strings(
                        context,
                        recorded(transfer)
                            ? 'splitRecordedChip'
                            : 'splitRecordLoan',
                      ),
                    ),
                  ),
                  TextButton.icon(
                    key: ValueKey('split-message-$index'),
                    onPressed: () => onMessage(transfer),
                    icon: const Icon(Icons.chat_bubble_outline),
                    label: Text(strings(context, 'splitMessage')),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}
