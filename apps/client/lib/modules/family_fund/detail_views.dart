part of 'detail.dart';

extension _FundViews on _FundDetailState {
  Widget monthSwitcher() => Row(
    children: [
      IconButton(
        tooltip: s('previous'),
        icon: const Icon(Icons.chevron_left),
        onPressed: month.first.isAfter(fund.start.first)
            ? () => changeMonth(month.shift(-1))
            : null,
      ),
      Expanded(
        child: Tooltip(
          message: s('today'),
          child: TextButton(
            onPressed: month == initialMonth
                ? null
                : () => changeMonth(initialMonth),
            child: Text(month.title(context), textAlign: TextAlign.center),
          ),
        ),
      ),
      IconButton(
        tooltip: s('next'),
        icon: const Icon(Icons.chevron_right),
        onPressed: month.first.isBefore(initialMonth.first)
            ? () => changeMonth(month.shift(1))
            : null,
      ),
    ],
  );

  List<Widget> monthView() {
    final active = started ? fund.active(month) : const <Fields>[];
    final paid = active
        .where((m) => fund.payment(month, m['id']) != null)
        .length;
    final collected = fund.collectedFor(month);
    final pot = fund.potFor(month);
    final draw = winner;
    final pool = fund.drawPool(month);
    final round = fund.roundFor(month);
    final today = DateUtils.dateOnly(now);
    final due = dueDay(month, fund.paymentDay);
    final overdue = active.where((member) {
      if (fund.payment(month, member['id']) != null) return false;
      return due.isBefore(today);
    }).length;
    return [
      monthSwitcher(),
      NexModuleHero(
        moduleId: 'family_fund',
        icon: Icons.account_balance_wallet_outlined,
        eyebrow: s('balance'),
        headline: cash(fund.balanceAt(now)),
        caption: !started
            ? s('upcoming', {'date': month.title(context)})
            : active.isEmpty
            ? s('noActive')
            : s('progress', {'paid': paid, 'total': active.length}),
        chips: [
          if (started) s('datePayment', {'date': date(due)}),
          if (round.total > 0) s('round', {'n': round.number}),
          if (overdue > 0) s('overdueCount', {'n': overdue}),
        ],
        semanticsLabel: '${s('balance')}: ${cash(fund.balanceAt(now))}',
        child: active.isEmpty
            ? null
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LinearProgressIndicator(value: paid / active.length),
                  const SizedBox(height: NexSpacing.xs),
                  Text(
                    hidden
                        ? s('masked')
                        : s('collectedOf', {
                            'amount': cash(collected),
                            'total': cash(pot),
                          }),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
      ),
      const SizedBox(height: NexSpacing.md),
      roundPanel(
        draw: draw,
        pool: pool,
        round: round,
        balance: fund.balanceAt(now),
      ),
      const SizedBox(height: NexSpacing.md),
      NexShelfHeading(
        icon: Icons.receipt_long_outlined,
        title: s('contributions'),
        note: hidden
            ? s('masked')
            : s('collectedOf', {'amount': cash(collected), 'total': cash(pot)}),
      ),
      if (active.isEmpty)
        Padding(
          padding: const EdgeInsets.all(NexSpacing.sm),
          child: Text(
            started
                ? s('noActive')
                : s('upcoming', {'date': month.title(context)}),
          ),
        ),
      for (final member in active) paymentRow(member, due, today),
      if (fund.members.isEmpty)
        FilledButton.icon(
          onPressed: addMember,
          icon: const Icon(Icons.person_add_alt_1_outlined),
          label: Text(s('member')),
        ),
      const SizedBox(height: NexSpacing.md),
      reminderPanel(),
    ];
  }

  Widget roundPanel({
    required Fields? draw,
    required ({int round, List<Fields> eligible}) pool,
    required FundRound round,
    required int balance,
  }) {
    final issued = draw != null && fund.issued(draw['id']);
    return NexPanel(
      title: draw == null
          ? s('noDraw')
          : s('winner', {'name': winnerName(draw)}),
      icon: Icons.casino_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (round.total > 0) ...[
            Text(
              s('roundProgress', {'won': round.received, 'total': round.total}),
            ),
            const SizedBox(height: NexSpacing.xs),
            LinearProgressIndicator(value: round.received / round.total),
          ] else
            Text(s('roundEmpty')),
          if (round.remaining.isNotEmpty)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: NexSpacing.xs),
              child: Text(
                s('roundRemaining', {
                  'names': round.remaining.map(nameOf).join(fundSep(context)),
                }),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (draw != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: NexSpacing.xs),
              child: Text(
                [
                  s('round', {'n': draw['round']}),
                  date(DateTime.parse(draw['at'] as String)),
                  if (issued) s('payoutRecorded'),
                ].join(fundSep(context)),
              ),
            ),
          if (issued)
            Text(
              s('locked'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          if (future)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: NexSpacing.xs),
              child: Text(s('upcoming', {'date': month.title(context)})),
            )
          else if (draw != null && !issued && pool.eligible.isEmpty)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: NexSpacing.xs),
              child: Text(s('noPool')),
            ),
          const SizedBox(height: NexSpacing.sm),
          Wrap(
            spacing: NexSpacing.sm,
            runSpacing: NexSpacing.xs,
            children: [
              if (started && !future && pool.eligible.isNotEmpty)
                FilledButton.tonalIcon(
                  key: const ValueKey('fund-draw'),
                  onPressed: runDraw,
                  icon: const Icon(Icons.casino_outlined),
                  label: Text(s(draw == null ? 'draw' : 'redraw')),
                ),
              if (draw != null && !issued && balance > 0)
                FilledButton.tonal(
                  onPressed: () => unawaited(issue(draw)),
                  child: Text(s('issue')),
                ),
              if (fund.draws.isNotEmpty)
                TextButton(
                  onPressed: drawHistory,
                  child: Text(s('drawHistory')),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget paymentRow(Fields member, DateTime due, DateTime today) {
    final paid = fund.payment(month, member['id']);
    final amount = paid == null
        ? monthShare * (member['shares'] as int)
        : paid['amountRial'] as int;
    final overdue = paid == null && due.isBefore(today) && !future;
    final lateDays = today.difference(DateUtils.dateOnly(due)).inDays;
    return CheckboxListTile(
      key: ValueKey('pay:${member['id']}'),
      contentPadding: EdgeInsets.zero,
      value: paid != null,
      title: Text(nameOf(member)),
      subtitle: Text(
        [
          cash(amount),
          if ((member['shares'] as int) > 1)
            s('shareCount', {'n': member['shares']}),
          if (paid != null)
            s('paidOn', {'date': date(DateTime.parse(paid['at'] as String))})
          else if (future)
            s('dueOn', {'date': date(due)})
          else if (overdue)
            s('lateBy', {'n': lateDays})
          else
            s('dueOn', {'date': date(due)}),
        ].join(fundSep(context)),
      ),
      onChanged: future ? null : (_) => unawaited(payment(member)),
    );
  }

  List<Widget> membersView() {
    final current = fundMonth(now);
    final at = current.first.isBefore(fund.start.first) ? fund.start : current;
    final share = fund.shareFor(at);
    final activeNow = fund.active(current).map((m) => m['id']).toSet();
    final today = DateUtils.dateOnly(now);
    final currentMembers = fund.members
        .where((m) => m['until'] == null)
        .toList();
    final former = fund.members.where((m) => m['until'] != null).toList();
    return [
      NexPanel(
        title: s('sharePot'),
        icon: Icons.price_change_outlined,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(fundLabeled(context, s('shareNow'), cash(share))),
            const SizedBox(height: NexSpacing.xs),
            Text(fundLabeled(context, s('pot'), cash(fund.potFor(at)))),
            if (fund.shareChanges.isNotEmpty) ...[
              const SizedBox(height: NexSpacing.sm),
              Text(
                s('shareHistory'),
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: NexSpacing.xs),
              for (final change in fund.shareChanges.reversed.take(4))
                Text(
                  [
                    fundMonth(DateTime.parse(change['from'] as String))
                        .title(context),
                    cash(change['shareRial'] as int),
                  ].join(fundSep(context)),
                ),
            ],
            const SizedBox(height: NexSpacing.sm),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: changeShare,
                icon: const Icon(Icons.price_change_outlined),
                label: Text(s('editShare')),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: NexSpacing.md),
      NexShelfHeading(
        icon: Icons.person_outline,
        title: s('members'),
        note: s('membersCount', {'n': currentMembers.length}),
      ),
      if (currentMembers.isEmpty) Text(s('noMembers')),
      for (final member in currentMembers)
        memberRow(
          member,
          share: share,
          current: current,
          today: today,
          active: activeNow.contains(member['id']),
        ),
      if (former.isNotEmpty) ...[
        const SizedBox(height: NexSpacing.md),
        NexShelfHeading(
          icon: Icons.person_off_outlined,
          title: s('formerMembers'),
        ),
        for (final member in former)
          memberRow(
            member,
            share: share,
            current: current,
            today: today,
            active: false,
          ),
      ],
      const SizedBox(height: NexSpacing.sm),
      FilledButton.icon(
        onPressed: addMember,
        icon: const Icon(Icons.person_add_alt_1_outlined),
        label: Text(s('member')),
      ),
      if (fund.rules.isNotEmpty) ...[
        const SizedBox(height: NexSpacing.md),
        NexPanel(title: s('rules'), child: SelectableText(fund.rules)),
      ],
    ];
  }

  Widget memberRow(
    Fields member, {
    required int share,
    required NexModuleMonth current,
    required DateTime today,
    required bool active,
  }) {
    final paid = active ? fund.payment(current, member['id']) : null;
    final due = dueDay(current, fund.paymentDay);
    final overdue = active && paid == null && due.isBefore(today);
    final from = fundMonth(DateTime.parse(member['from'] as String));
    final untilRaw = member['until'];
    final until = untilRaw == null
        ? null
        : fundMonth(DateTime.parse(untilRaw as String));
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: () => unawaited(memberSheet(member)),
      title: Text(nameOf(member)),
      subtitle: Text(
        [
          s('shareCount', {'n': member['shares']}),
          cash(share * (member['shares'] as int)),
          if (active) s(paid == null ? (overdue ? 'late' : 'waiting') : 'paid'),
          if (from.first.isAfter(current.first))
            s('joined', {'date': from.title(context)}),
          if (until != null) s('left', {'date': until.title(context)}),
        ].join(fundSep(context)),
      ),
      trailing: until != null
          ? null
          : IconButton(
              tooltip: s('leave'),
              onPressed: () => unawaited(leave(member)),
              icon: const Icon(Icons.person_remove_outlined),
            ),
    );
  }

  List<Widget> loansView() {
    final today = DateUtils.dateOnly(now);
    final outstanding = fund.loans.fold<int>(
      0,
      (sum, loan) =>
          sum +
          rows(loan['instalments'])
              .where((part) => part['paidAt'] == null)
              .fold<int>(0, (all, part) => all + (part['amountRial'] as int)),
    );
    return [
      if (fund.loans.isEmpty)
        NexEmptyState(
          icon: Icons.receipt_long_outlined,
          message: s('noLoans'),
          action: TextButton(
            onPressed: () => paint(() => tab = 0),
            child: Text(s('month')),
          ),
        )
      else ...[
        NexPanel(
          title: s('loans'),
          icon: Icons.receipt_long_outlined,
          child: Text(s('outstandingTotal', {'amount': cash(outstanding)})),
        ),
        const SizedBox(height: NexSpacing.md),
        for (final loan in fund.loans.reversed)
          Padding(
            padding: const EdgeInsets.only(bottom: NexSpacing.md),
            child: loanCard(loan, today),
          ),
      ],
    ];
  }

  Widget loanCard(Fields loan, DateTime today) {
    final parts = rows(loan['instalments']);
    final paid = parts.where((part) => part['paidAt'] != null).length;
    final outstanding = parts
        .where((part) => part['paidAt'] == null)
        .fold<int>(0, (sum, part) => sum + (part['amountRial'] as int));
    final next = parts.indexWhere((part) => part['paidAt'] == null);
    final id = loan['draw'] as String;
    final expanded = expandedLoans.contains(id);
    return NexPanel(
      title: nameOf(loan),
      icon: Icons.person_outline,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            [
              cash(loan['amountRial'] as int),
              date(DateTime.parse(loan['at'] as String)),
            ].join(fundSep(context)),
          ),
          const SizedBox(height: NexSpacing.xs),
          Text(s('instalmentsPaid', {'paid': paid, 'total': parts.length})),
          const SizedBox(height: NexSpacing.xs),
          LinearProgressIndicator(value: paid / parts.length),
          const SizedBox(height: NexSpacing.xs),
          Text(
            outstanding == 0
                ? s('settled')
                : s('outstanding', {'amount': cash(outstanding)}),
            style: outstanding == 0
                ? Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.primary)
                : null,
          ),
          if (expanded)
            for (final (i, part) in parts.indexed)
              instalmentRow(loan, i, part, today)
          else if (next >= 0) ...[
            const SizedBox(height: NexSpacing.sm),
            Text(
              s('nextInstalment'),
              style: Theme.of(context).textTheme.labelLarge,
            ),
            instalmentRow(loan, next, parts[next], today),
          ],
          if (parts.isNotEmpty)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: () => paint(() {
                  if (!expandedLoans.remove(id)) expandedLoans.add(id);
                }),
                child: Text(s(expanded ? 'hideInstalments' : 'allInstalments')),
              ),
            ),
        ],
      ),
    );
  }

  Widget instalmentRow(Fields loan, int index, Fields part, DateTime today) {
    final paidAt = part['paidAt'];
    final due = DateUtils.dateOnly(DateTime.parse(part['due'] as String));
    final late = paidAt == null && due.isBefore(today);
    return CheckboxListTile(
      key: ValueKey('loan:${loan['draw']}:inst:$index'),
      contentPadding: EdgeInsets.zero,
      value: paidAt != null,
      title: Text(s('instalment', {'n': index + 1})),
      subtitle: Text(
        [
          cash(part['amountRial'] as int),
          if (paidAt != null)
            s('paidOn', {'date': date(DateTime.parse(paidAt as String))})
          else if (late)
            s('lateBy', {'n': today.difference(due).inDays})
          else
            s('dueOn', {'date': date(due)}),
        ].join(fundSep(context)),
      ),
      onChanged: (_) => unawaited(repay(loan, index)),
    );
  }

  Widget reminderPanel() {
    DateTime remindAt(String kind, int day) {
      final today = DateUtils.dateOnly(now);
      var at = fundMonth(now);
      if (at.first.isBefore(fund.start.first)) at = fund.start;
      for (var i = 0; i < 4; i++, at = at.shift(1)) {
        if (kind == 'fund-draw' && fund.winner(at) != null) continue;
        if (kind == 'fund-contribution') {
          final active = fund.active(at);
          if (active.isNotEmpty &&
              active.every((m) => fund.payment(at, m['id']) != null)) {
            continue;
          }
        }
        final due = dueDay(at, day);
        if (!due.isBefore(today)) {
          return DateTime(due.year, due.month, due.day, 9);
        }
      }
      final due = dueDay(at, day);
      return DateTime(due.year, due.month, due.day, 9);
    }

    return NexPanel(
      title: s('reminders'),
      icon: Icons.notifications_none_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s('reminderHint'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          for (final (kind, dayLabel, titleKey, day) in [
            (
              'fund-contribution',
              'contributionDay',
              'payReminder',
              fund.paymentDay,
            ),
            ('fund-draw', 'drawDayLabel', 'drawReminder', fund.drawDay),
          ])
            Padding(
              padding: const EdgeInsetsDirectional.only(top: NexSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s(dayLabel, {'day': day}),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  FundReminder(
                    key: ValueKey(kind),
                    store: widget.store,
                    reminderKind: kind,
                    fundId: fund.id,
                    initial: remindAt(kind, day),
                    body: s(titleKey, {'fund': fund.name}),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
