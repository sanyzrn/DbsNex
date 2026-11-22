part of 'detail.dart';

extension _FundMember on _FundDetailState {
  /// One member, in full: their shares, their months, what they have paid,
  /// what they still owe, the round's turn and the payouts they received.
  /// A manager should not have to scroll the whole ledger to answer «has
  /// Mina paid?» at the group meeting.
  Future<void> memberSheet(Fields member) async {
    final current = fundMonth(now);
    final share = fund.shareFor(current);
    final currentPayment = fund.payment(current, member['id']);
    final due = dueDay(current, fund.paymentDay);
    final overdue =
        currentPayment == null && due.isBefore(DateUtils.dateOnly(now));
    final arrears = fund.arrearsFor(member, now);
    final payments = fund.paymentsFor(member['id']);
    final wins = fund.winsFor(member['id']);
    final round = fund.roundFor(current);
    final wonThisRound = wins.any((w) => w['round'] == round.number);
    final active = fund.active(current).any((m) => m['id'] == member['id']);
    final from = fundMonth(DateTime.parse(member['from'] as String));
    final untilRaw = member['until'];
    final until = untilRaw == null
        ? null
        : fundMonth(DateTime.parse(untilRaw as String));
    final totalPaid = payments.fold<int>(
      0,
      (sum, payment) => sum + (payment['amountRial'] as int),
    );
    final s = fundStrings;
    Widget payoutLine(BuildContext c, Fields win) {
      final loan = fund.loanFor(win['id']);
      final outstanding = loan == null
          ? 0
          : rows(loan['instalments'])
                .where((part) => part['paidAt'] == null)
                .fold<int>(0, (sum, part) => sum + (part['amountRial'] as int));
      return Text(
        [
          fundMonth(DateTime.parse(win['month'] as String)).title(c),
          if (loan != null)
            cash(loan['amountRial'] as int)
          else
            s(c, 'payoutPending'),
          if (outstanding > 0)
            s(c, 'outstanding', {'amount': cash(outstanding)}),
        ].join(fundSep(c)),
      );
    }

    await nexShowSheet<void>(
      context: context,
      builder: (c) => SafeArea(
        top: false,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(NexSpacing.md),
          children: [
            Text(nameOf(member), style: Theme.of(c).textTheme.titleLarge),
            const SizedBox(height: NexSpacing.xs),
            Text(
              [
                s(c, 'shareCount', {'n': member['shares']}),
                cash(share * (member['shares'] as int)),
                s(c, 'joined', {'date': from.title(c)}),
                if (until != null) s(c, 'left', {'date': until.title(c)}),
              ].join(fundSep(c)),
              style: Theme.of(c).textTheme.bodySmall
                  ?.copyWith(color: Theme.of(c).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: NexSpacing.md),
            NexPanel(
              title: s(c, 'thisRound'),
              icon: Icons.groups_2_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s(c, wonThisRound ? 'memberReceived' : 'memberNotReceived'),
                  ),
                  if (round.total > 0)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(
                        top: NexSpacing.xs,
                      ),
                      child: Text(
                        s(c, 'roundProgress', {
                          'won': round.received,
                          'total': round.total,
                        }),
                      ),
                    ),
                  if (active)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(
                        top: NexSpacing.xs,
                      ),
                      child: Text(
                        currentPayment == null
                            ? s(c, overdue ? 'memberCurrentUnpaid' : 'waiting')
                            : s(c, 'paidOn', {
                                'date': date(
                                  DateTime.parse(
                                    currentPayment['at'] as String,
                                  ),
                                ),
                              }),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: NexSpacing.sm),
            NexPanel(
              title: s(c, 'memberContributions'),
              icon: Icons.receipt_long_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s(c, 'memberTotalPaid', {'amount': cash(totalPaid)})),
                  const SizedBox(height: NexSpacing.xs),
                  Text(
                    arrears.isEmpty
                        ? s(c, 'memberNoArrears')
                        : s(c, 'memberArrears', {'n': arrears.length}),
                  ),
                  for (final payment in payments.reversed.take(4))
                    Padding(
                      padding: const EdgeInsetsDirectional.only(
                        top: NexSpacing.xs,
                      ),
                      child: Text(
                        [
                          fundMonth(DateTime.parse(payment['month'] as String))
                              .title(c),
                          cash(payment['amountRial'] as int),
                          s(c, 'paidOn', {
                            'date': date(
                              DateTime.parse(payment['at'] as String),
                            ),
                          }),
                        ].join(fundSep(c)),
                      ),
                    ),
                  for (final month in arrears.reversed.take(4))
                    Padding(
                      padding: const EdgeInsetsDirectional.only(
                        top: NexSpacing.xs,
                      ),
                      child: Text(
                        [
                          month.month.title(c),
                          cash(month.amountRial),
                          s(c, 'late'),
                        ].join(fundSep(c)),
                        style: TextStyle(color: Theme.of(c).colorScheme.error),
                      ),
                    ),
                ],
              ),
            ),
            if (wins.isNotEmpty) ...[
              const SizedBox(height: NexSpacing.sm),
              NexPanel(
                title: s(c, 'memberWins'),
                icon: Icons.emoji_events_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final win in wins.reversed)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(
                          top: NexSpacing.xs,
                        ),
                        child: payoutLine(c, win),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: NexSpacing.md),
            if (active && currentPayment == null)
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(c);
                  unawaited(payment(member, forMonth: current));
                },
                icon: const Icon(Icons.check_circle_outline),
                label: Text(s(c, 'recordThisMonth')),
              ),
            if (until == null)
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(c);
                  unawaited(leave(member));
                },
                icon: const Icon(Icons.person_remove_outlined),
                label: Text(s(c, 'leave')),
              ),
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: Text(s(c, 'close')),
            ),
          ],
        ),
      ),
    );
  }
}
