part of 'detail.dart';

extension _FundActions on _FundDetailState {
  Future<bool> confirm(String title, {String? body}) async =>
      await nexShowDialog<bool>(
        context: context,
        builder: (c) => NexAlertDialog(
          title: Text(title),
          scrollable: true,
          content: body == null ? null : NexDialogBody(child: Text(body)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: Text(s('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(s('confirm')),
            ),
          ],
        ),
      ) ==
      true;

  Future<void> addMember() async {
    final current = fundMonth(now);
    final initial = current.first.isBefore(fund.start.first)
        ? fund.start
        : current;
    await openFundEditor(
      context,
      widget.store,
      keyName: 'member:${fund.id}',
      title: s('member'),
      fields: ['memberName', 'shares'],
      initial: initial,
      validate: (d) {
        final month = d['month'];
        if ((d['memberName'] as String).isEmpty) return 'invalidName';
        if (!between(d['shares'], 1, 100)) return 'invalidShares';
        if (month is! NexModuleMonth ||
            month.first.isBefore(fund.start.first) ||
            month.first.isBefore(current.first)) {
          return 'invalidMonth';
        }
        return null;
      },
      save: (d) async {
        if (fund.members.any((m) => m['id'] == d['id'])) return;
        await write({
          ...fund.body,
          'members': [
            ...fund.members,
            <String, Object?>{
              'id': d['id'],
              'person': {'name': d['memberName']},
              'shares': d['shares'],
              'from': dayKey((d['month'] as NexModuleMonth).first),
            },
          ],
        });
      },
    );
  }

  Future<void> editFund() async {
    final persian = NexModuleStrings.persian(context);
    var saved = false;
    await openFundEditor(
      context,
      widget.store,
      keyName: 'edit:${fund.id}',
      title: s('editFund'),
      description: s('editFundHint'),
      fields: ['name', 'payDay', 'drawDay', 'rules'],
      initialValues: {
        'name': fund.name,
        'payDay': nexDigits('${fund.paymentDay}', persian: persian),
        'drawDay': nexDigits('${fund.drawDay}', persian: persian),
        'rules': fund.rules,
      },
      validate: (d) {
        if ((d['name'] as String).isEmpty) return 'invalidName';
        if (!between(d['payDay'], 1, 31) || !between(d['drawDay'], 1, 31)) {
          return 'invalidDay';
        }
        if ((d['rules'] as String).length > 3000) return 'invalid';
        return null;
      },
      save: (d) async {
        await write({
          ...fund.body,
          'name': d['name'],
          'paymentDay': d['payDay'],
          'drawDay': d['drawDay'],
          'rules': d['rules'],
        });
        saved = true;
      },
    );
    if (saved && mounted) {
      nexShowBanner(context, message: s('fundUpdated'));
    }
  }

  Future<void> changeShare() async {
    final current = fundMonth(now);
    final initial = current.first.isBefore(fund.start.first)
        ? fund.start
        : current;
    var saved = false;
    NexModuleMonth? changed;
    await openFundEditor(
      context,
      widget.store,
      keyName: 'share:${fund.id}',
      title: s('editShare'),
      description: s('shareChangeHint'),
      fields: ['shareAmount'],
      initial: initial,
      monthLabel: 'appliesFrom',
      unit: unit,
      initialValues: {
        'shareAmount': amountInput(fund.shareFor(initial), 'IRR', 0, unit),
      },
      validate: (d) {
        final month = d['month'];
        if (month is! NexModuleMonth ||
            month.first.isBefore(fund.start.first)) {
          return 'invalidMonth';
        }
        if (!between(d['shareAmount'], 1, 100000000000)) {
          return 'invalidShare';
        }
        return null;
      },
      save: (d) async {
        final month = d['month'] as NexModuleMonth;
        await write(fund.withShare(month, d['shareAmount'] as int));
        saved = true;
        changed = month;
      },
    );
    if (saved && mounted) {
      nexShowBanner(
        context,
        message: s('shareChanged', {'date': changed!.title(context)}),
      );
    }
  }

  Future<void> leave(Fields member) async {
    final current = fundMonth(DateTime.now());
    final from = member['from'] as String;
    final upcoming = from.compareTo(dayKey(current.first)) > 0;
    if (upcoming) {
      if (!await confirm(
            s('removeUpcomingMember'),
            body: s('removeUpcomingBody'),
          ) ||
          !mounted) {
        return;
      }
      await update(
        {
          ...fund.body,
          'members': [
            for (final m in fund.members)
              if (m['id'] != member['id']) m,
          ],
        },
        undo: true,
        message: s('leaveRecorded', {'name': nameOf(member)}),
      );
      return;
    }
    if (!await confirm(s('leave'), body: s('leaveBody')) || !mounted) return;
    final next = dayKey(current.shift(1).first);
    final until = next.compareTo(from) > 0 ? next : from;
    await update(
      {
        ...fund.body,
        'members': [
          for (final m in fund.members)
            if (m['id'] == member['id']) {...m, 'until': until} else m,
        ],
      },
      undo: true,
      message: s('leaveRecorded', {'name': nameOf(member)}),
    );
  }

  Future<void> payment(Fields member, {NexModuleMonth? forMonth}) async {
    final at = forMonth ?? month;
    final fresh = DateTime.now();
    if (at.first.isBefore(fund.start.first) ||
        at.first.isAfter(fresh) ||
        !fund.active(at).any((m) => m['id'] == member['id'])) {
      return;
    }
    final current = fund.payment(at, member['id']);
    if (current != null &&
        (!await confirm(
              s('removePaymentBody', {
                'name': nameOf(member),
                'month': at.title(context),
              }),
            ) ||
            !mounted)) {
      return;
    }
    final next = {
      ...fund.body,
      'payments': [
        for (final p in fund.payments)
          if (p['member'] != member['id'] || p['month'] != dayKey(at.first)) p,
        if (current == null)
          <String, Object?>{
            'member': member['id'],
            'month': dayKey(at.first),
            'at': dayKey(fresh),
            'amountRial': fund.shareFor(at) * (member['shares'] as int),
          },
      ],
    };
    if (!fund.keepsLedgerSound(next)) {
      nexShowBanner(context, message: s('cannotUndoMoney'));
      return;
    }
    await update(
      next,
      undo: true,
      message: s(current == null ? 'paymentRecorded' : 'paymentRemoved', {
        'name': nameOf(member),
      }),
    );
  }

  Future<void> runDraw() async {
    final pool = fund.drawPool(month);
    if (!started || future || pool.eligible.isEmpty) return;
    await nexShowSheet<void>(
      context: context,
      builder: (_) => _DrawSheet(
        eligible: pool.eligible,
        round: pool.round,
        redraw: winner != null,
        month: month,
        potText: cash(fund.potFor(month)),
        onDraw: performDraw,
      ),
    );
  }

  Future<Fields?> performDraw(String reason) async {
    try {
      final next = fund.draw(
        month,
        DateTime.now(),
        widget.store.newId(),
        reason,
        Random.secure(),
      );
      final result = rows(next['draws']).last;
      await write(next);
      return result;
    } on Object {
      return null;
    }
  }

  Future<void> issue(Fields draw) async {
    if (fund.issued(draw['id']) || winner?['id'] != draw['id'] || busy) return;
    final balance = fund.balanceAt(DateTime.now());
    if (balance <= 0) return;
    final drawMonth = fundMonth(DateTime.parse(draw['month'] as String));
    final pot = fund.potFor(drawMonth);
    final suggested = min(balance, pot > 0 ? pot : balance);
    var saved = false;
    await openFundEditor(
      context,
      widget.store,
      keyName: 'payout:${fund.id}:${draw['id']}',
      title: s('issue'),
      description: [
        s('winner', {'name': winnerName(draw)}),
        s('available', {'amount': cash(balance)}),
        s('pot', {'amount': cash(pot)}),
      ].join('\n'),
      fields: ['principal', 'count'],
      initial: fundMonth(DateTime.now()).shift(1),
      monthLabel: 'repayStart',
      unit: unit,
      initialValues: {
        if (suggested > 0) 'principal': amountInput(suggested, 'IRR', 0, unit),
        'count': '6',
      },
      validate: (d) {
        final month = d['month'];
        final count = d['count'], principal = d['principal'];
        if (month is! NexModuleMonth ||
            month.first.isBefore(fundMonth(DateTime.now()).first)) {
          return 'invalidMonth';
        }
        if (count is! int || !between(count, 1, 60)) return 'invalidCount';
        if (principal is! int ||
            principal < count ||
            principal > min(balance, 100000000000000)) {
          return 'invalidPrincipal';
        }
        return null;
      },
      save: (d) async {
        if (fund.issued(draw['id']) || winner?['id'] != draw['id']) {
          throw StateError('Payout changed');
        }
        final principal = d['principal'] as int;
        if (principal > fund.balanceAt(DateTime.now())) {
          throw StateError('Payout changed');
        }
        final next = {
          ...fund.body,
          'loans': [
            ...fund.loans,
            <String, Object?>{
              'draw': draw['id'],
              'at': dayKey(DateTime.now()),
              'amountRial': principal,
              'person': rows(draw['eligible'])
                  .firstWhere((e) => e['id'] == draw['winner'])['person'],
              'instalments': instalments(
                principal,
                d['count'] as int,
                d['month'] as NexModuleMonth,
                fund.paymentDay,
              ),
            },
          ],
        };
        if (!fund.keepsLedgerSound(next)) {
          throw StateError('Payout changed');
        }
        await write(next);
        saved = true;
      },
    );
    if (saved && mounted) {
      nexShowBanner(context, message: s('payoutRecorded'));
    }
  }

  Future<void> repay(Fields loan, int index) async {
    final loanId = loan['draw'];
    final current = fund.loans.where((l) => l['draw'] == loanId).firstOrNull;
    if (current == null) return;
    final parts = rows(current['instalments']);
    if (index < 0 || index >= parts.length) return;
    final part = parts[index];
    final removing = part['paidAt'] != null;
    if (removing && (!await confirm(s('removePayment')) || !mounted)) return;
    final next = {
      ...fund.body,
      'loans': [
        for (final l in fund.loans)
          if (l['draw'] == loanId)
            {
              ...l,
              'instalments': [
                for (final (i, entry) in rows(l['instalments']).indexed)
                  if (i == index)
                    {
                      ...entry,
                      'paidAt': removing ? null : dayKey(DateTime.now()),
                    }
                  else
                    entry,
              ],
            }
          else
            l,
      ],
    };
    if (!fund.keepsLedgerSound(next)) {
      nexShowBanner(context, message: s('cannotUndoMoney'));
      return;
    }
    await update(next, undo: true, message: s(removing ? 'updated' : 'repaid'));
  }
}
