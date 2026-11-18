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
    final thisMonth = fundMonth(now);
    await openFundEditor(
      context,
      widget.store,
      keyName: 'member:${fund.id}',
      title: s('member'),
      fields: ['memberName', 'shares'],
      initial: initialMonth,
      validate: (d) =>
          (d['memberName'] as String).isEmpty ||
              !between(d['shares'], 1, 100) ||
              (d['month'] as NexModuleMonth).first.isBefore(fund.start.first) ||
              (d['month'] as NexModuleMonth).first.isBefore(thisMonth.first)
          ? 'invalid'
          : null,
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

  Future<void> leave(Fields member) async {
    if (!await confirm(s('leave'), body: s('leaveBody')) || !mounted) return;
    final next = dayKey(fundMonth(DateTime.now()).shift(1).first);
    await update({
      ...fund.body,
      'members': [
        for (final m in fund.members)
          if (m['id'] == member['id']) {...m, 'until': next} else m,
      ],
    }, undo: true);
  }

  bool affordable(Fields body) {
    final candidate = Fund(fund.id, body);
    return candidate.loans.every(
      (l) => candidate.balanceAt(DateTime.parse(l['at'] as String)) >= 0,
    );
  }

  Future<void> payment(Fields member) async {
    final current = fund.payment(month, member['id']);
    if (current != null && (!await confirm(s('removePayment')) || !mounted)) {
      return;
    }
    final next = {
      ...fund.body,
      'payments': [
        ...fund.payments.where((p) => p != current),
        if (current == null)
          <String, Object?>{
            'member': member['id'],
            'month': key,
            'at': dayKey(DateTime.now()),
            'amountRial': fund.shareRial * (member['shares'] as int),
          },
      ],
    };
    if (!affordable(next)) {
      nexShowBanner(context, message: s('cannotUndoMoney'));
      return;
    }
    await update(next, undo: true);
  }

  Future<void> runDraw() async {
    final pool = fund.drawPool(month);
    if (pool.eligible.isEmpty) return;
    final preview = pool.eligible.map(nameOf).join(' · ');
    if (winner != null) {
      await openFundEditor(
        context,
        widget.store,
        keyName: 'redraw:${fund.id}:$key',
        title: s('redraw'),
        description: '${s('pool', {'n': pool.round})}\n$preview',
        fields: ['reason'],
        validate: (d) => (d['reason'] as String).isEmpty ? 'invalid' : null,
        save: (d) async {
          if (fund.draws.any((e) => e['id'] == d['id'])) return;
          await write(
            fund.draw(
              month,
              DateTime.now(),
              d['id'] as String,
              d['reason'] as String,
              Random.secure(),
            ),
          );
        },
      );
    } else if (await confirm(
          s('pool', {'n': pool.round}),
          body: '$preview\n\n${s('drawPolicy')}',
        ) &&
        mounted) {
      await update(
        fund.draw(
          month,
          DateTime.now(),
          widget.store.newId(),
          '',
          Random.secure(),
        ),
      );
    }
  }

  Future<void> issue(Fields draw) async {
    final balance = fund.balanceAt(DateTime.now());
    await openFundEditor(
      context,
      widget.store,
      keyName: 'payout:${fund.id}:${draw['id']}',
      title:
          '${s('issue')} · ${winnerName(draw)}\n${s('available', {'amount': cash(balance)})}',
      fields: ['principal', 'count'],
      initial: fundMonth(DateTime.now()).shift(1),
      unit: unit,
      validate: (d) {
        final principal = d['principal'], count = d['count'];
        return principal is! int ||
                count is! int ||
                !between(count, 1, 60) ||
                !between(principal, count, min(balance, 100000000000000)) ||
                (d['month'] as NexModuleMonth).first.isBefore(
                  fundMonth(DateTime.now()).first,
                )
            ? 'invalid'
            : null;
      },
      save: (d) async {
        if (fund.issued(draw['id'])) return;
        if (winner?['id'] != draw['id'] ||
            (d['principal'] as int) > fund.balanceAt(DateTime.now())) {
          throw StateError('Payout changed');
        }
        await write({
          ...fund.body,
          'loans': [
            ...fund.loans,
            <String, Object?>{
              'draw': draw['id'],
              'at': dayKey(DateTime.now()),
              'amountRial': d['principal'],
              'person': rows(draw['eligible'])
                  .firstWhere((e) => e['id'] == draw['winner'])['person'],
              'instalments': instalments(
                d['principal'] as int,
                d['count'] as int,
                d['month'] as NexModuleMonth,
                fund.paymentDay,
              ),
            },
          ],
        });
      },
    );
  }

  Future<void> repay(Fields loan, Fields part) async {
    final removing = part['paidAt'] != null;
    if (removing && (!await confirm(s('removePayment')) || !mounted)) return;
    final next = {
      ...fund.body,
      'loans': [
        for (final l in fund.loans)
          if (l == loan)
            {
              ...l,
              'instalments': [
                for (final i in rows(l['instalments']))
                  if (i == part)
                    {...i, 'paidAt': removing ? null : dayKey(DateTime.now())}
                  else
                    i,
              ],
            }
          else
            l,
      ],
    };
    if (!affordable(next)) {
      nexShowBanner(context, message: s('cannotUndoMoney'));
      return;
    }
    await update(next, undo: true);
  }
}
