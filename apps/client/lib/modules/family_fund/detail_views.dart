part of 'detail.dart';

extension _FundViews on _FundDetailState {
  void changeMonth(NexModuleMonth next) => paint(() {
    month = next;
    now = DateTime.now();
  });

  List<Widget> monthView() {
    final active = fund.active(month);
    final dues = FundDues(fund).forMonth(month);
    final contributions = dues
        .where((d) => d.kind == 'fund-contribution')
        .toList();
    final paid = contributions.where((d) => d.done).length;
    final draw = winner;
    final nextDraw = fund.drawPool(month);
    return [
      Row(
        children: [
          IconButton(
            tooltip: s('previous'),
            icon: const BackButtonIcon(),
            onPressed: month.first.isAfter(fund.start.first)
                ? () => changeMonth(month.shift(-1))
                : null,
          ),
          Expanded(
            child: TextButton(
              onPressed: () => changeMonth(initialMonth),
              child: Text(month.title(context), textAlign: TextAlign.center),
            ),
          ),
          IconButton(
            tooltip: s('next'),
            icon: const Icon(Icons.arrow_forward),
            onPressed: month.first.isBefore(initialMonth.first)
                ? () => changeMonth(month.shift(1))
                : null,
          ),
        ],
      ),
      NexModuleHero(
        moduleId: 'family_fund',
        icon: Icons.account_balance_wallet_outlined,
        eyebrow: s('balance'),
        headline: cash(fund.balanceAt(now)),
        caption: s('progress', {'paid': paid, 'total': contributions.length}),
        chips: [
          s('datePayment', {'date': date(dueDay(month, fund.paymentDay))}),
        ],
        child: contributions.isEmpty
            ? null
            : LinearProgressIndicator(value: paid / contributions.length),
      ),
      const SizedBox(height: NexSpacing.md),
      NexPanel(
        title: draw == null
            ? s('noDraw')
            : s('winner', {'name': winnerName(draw)}),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (draw != null) Text(s('round', {'n': draw['round']})),
            if (draw != null && fund.issued(draw['id']))
              Text(s('payoutRecorded')),
            Wrap(
              spacing: NexSpacing.sm,
              children: [
                if (!future && nextDraw.eligible.isNotEmpty)
                  FilledButton.tonalIcon(
                    onPressed: runDraw,
                    icon: const Icon(Icons.casino_outlined),
                    label: Text(s(draw == null ? 'draw' : 'redraw')),
                  ),
                if (draw != null &&
                    !fund.issued(draw['id']) &&
                    fund.balanceAt(now) > 0)
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
            if (future) Text(s('upcoming', {'date': month.title(context)})),
          ],
        ),
      ),
      const SizedBox(height: NexSpacing.md),
      NexShelfHeading(
        icon: Icons.receipt_long_outlined,
        title: s('contributions'),
      ),
      if (active.isEmpty)
        Padding(
          padding: const EdgeInsets.all(NexSpacing.sm),
          child: Text(s('noActive')),
        ),
      for (final (i, member) in active.indexed)
        CheckboxListTile(
          key: ValueKey('pay:${member['id']}'),
          contentPadding: EdgeInsets.zero,
          value: contributions[i].done,
          title: Text(nameOf(member)),
          subtitle: Text(
            '${cash(contributions[i].amountRial!)}${fundSep(context)}${s(contributions[i].done
                ? 'paid'
                : dayKey(contributions[i].at).compareTo(dayKey(now)) < 0
                ? 'late'
                : 'waiting')}',
          ),
          onChanged: future ? null : (_) => unawaited(payment(member)),
        ),
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

  Widget reminderPanel() {
    final selected = fundMonth(now);
    final next = selected.first.isBefore(fund.start.first)
        ? fund.start
        : selected;
    DateTime remindAt(String kind, int day) {
      final today = dayKey(now);
      for (final m in [next, next.shift(1)]) {
        final match = FundDues(fund)
            .forMonth(m)
            .where((d) => d.kind == kind && !d.done)
            .firstOrNull;
        if (match != null && dayKey(match.at).compareTo(today) >= 0) {
          return match.at;
        }
      }
      final at = dueDay(next, day);
      return dayKey(at).compareTo(today) >= 0 ? at : dueDay(next.shift(1), day);
    }

    return NexPanel(
      title: s('reminders'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s('reminderHint')),
          for (final (kind, label, day) in [
            ('fund-contribution', 'payReminder', fund.paymentDay),
            ('fund-draw', 'drawReminder', fund.drawDay),
          ])
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s(label, {'fund': fund.name})),
                FundReminder(
                  key: ValueKey(kind),
                  store: widget.store,
                  reminderKind: kind,
                  fundId: fund.id,
                  initial: remindAt(kind, day),
                  body: s(label, {'fund': fund.name}),
                ),
              ],
            ),
        ],
      ),
    );
  }

  List<Widget> membersView() => [
    NexPanel(
      title: s('members'),
      child: Text(fundLabeled(context, s('shareAmount'), cash(fund.shareRial))),
    ),
    const SizedBox(height: NexSpacing.sm),
    if (fund.members.isEmpty) Text(s('noMembers')),
    for (final m in fund.members)
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(nameOf(m)),
        subtitle: Text(
          [
            s('shareCount', {'n': m['shares']}),
            s('joined', {
              'date': fundMonth(DateTime.parse(m['from'] as String))
                  .title(context),
            }),
            if (m['until'] case final String end)
              s('left', {
                'date': fundMonth(DateTime.parse(end)).title(context),
              }),
          ].join(fundSep(context)),
        ),
        trailing: m['until'] != null
            ? null
            : IconButton(
                tooltip: s('leave'),
                onPressed: () => unawaited(leave(m)),
                icon: const Icon(Icons.person_remove_outlined),
              ),
      ),
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

  List<Widget> loansView() => [
    if (fund.loans.isEmpty)
      NexEmptyState(
        icon: Icons.receipt_long_outlined,
        message: s('noLoans'),
        action: TextButton(
          onPressed: () => paint(() => tab = 0),
          child: Text(s('month')),
        ),
      ),
    for (final loan in fund.loans.reversed)
      Padding(
        padding: const EdgeInsets.only(bottom: NexSpacing.md),
        child: NexPanel(
          title: nameOf(loan),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${cash(loan['amountRial'] as int)}${fundSep(context)}${date(DateTime.parse(loan['at'] as String))}',
              ),
              Text(
                s('outstanding', {
                  'amount': cash(
                    rows(loan['instalments'])
                        .where((i) => i['paidAt'] == null)
                        .fold(0, (sum, i) => sum + (i['amountRial'] as int)),
                  ),
                }),
              ),
              for (final (i, part) in rows(loan['instalments']).indexed)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: part['paidAt'] != null,
                  title: Text(s('instalment', {'n': i + 1})),
                  subtitle: Text(
                    '${date(DateTime.parse(part['due'] as String))}${fundSep(context)}${cash(part['amountRial'] as int)}',
                  ),
                  onChanged: (_) => unawaited(repay(loan, part)),
                ),
            ],
          ),
        ),
      ),
  ];
}
