part of 'detail.dart';

extension _FundReport on _FundDetailState {
  Future<void> report() async {
    final active = fund.active(month);
    final paidNames = active
        .where((m) => fund.payment(month, m['id']) != null)
        .map(nameOf)
        .toList();
    final waitingNames = active
        .where((m) => fund.payment(month, m['id']) == null)
        .map(nameOf)
        .toList();
    final current = winner;
    final round = fund.roundFor(month);
    final text = [
      fund.name,
      month.title(context),
      fundLabeled(
        context,
        s('paid'),
        paidNames.isEmpty ? s('none') : paidNames.join(fundSep(context)),
      ),
      fundLabeled(
        context,
        s('waiting'),
        waitingNames.isEmpty ? s('none') : waitingNames.join(fundSep(context)),
      ),
      fundLabeled(context, s('collected'), cash(fund.collectedFor(month))),
      fundLabeled(
        context,
        '${s('balance')} (${date(now)})',
        cash(fund.balanceAt(now)),
      ),
      current == null
          ? s('noDraw')
          : s('winner', {'name': winnerName(current)}),
      if (round.total > 0)
        s('roundProgress', {'won': round.received, 'total': round.total}),
    ].join('\n');
    await nexShowSheet<void>(
      context: context,
      builder: (c) => SafeArea(
        top: false,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(NexSpacing.md),
          children: [
            Text(s('report'), style: Theme.of(c).textTheme.titleLarge),
            const SizedBox(height: NexSpacing.xs),
            Text(
              [fund.name, month.title(c)].join(fundSep(c)),
              style: Theme.of(c).textTheme.bodySmall
                  ?.copyWith(color: Theme.of(c).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: NexSpacing.md),
            NexPanel(child: SelectableText(text)),
            const SizedBox(height: NexSpacing.md),
            FilledButton.icon(
              icon: const Icon(Icons.ios_share),
              label: Text(s('share')),
              onPressed: () async {
                try {
                  await nexModuleShareText(text);
                } on Object {
                  if (c.mounted) {
                    nexShowBanner(
                      c,
                      message: s('shareError'),
                      kind: NexBannerKind.failed,
                    );
                  }
                }
              },
            ),
            const SizedBox(height: NexSpacing.xs),
            TextButton.icon(
              icon: const Icon(Icons.copy_all_outlined),
              label: Text(s('copy')),
              onPressed: () async {
                try {
                  await nexModuleCopyText(text);
                  if (c.mounted) nexShowBanner(c, message: s('copied'));
                } on Object {
                  if (c.mounted) {
                    nexShowBanner(
                      c,
                      message: s('copyError'),
                      kind: NexBannerKind.failed,
                    );
                  }
                }
              },
            ),
            if (waitingNames.isNotEmpty) ...[
              const SizedBox(height: NexSpacing.xs),
              TextButton.icon(
                icon: const Icon(Icons.campaign_outlined),
                label: Text(s('shareReminder')),
                onPressed: shareReminder,
              ),
            ],
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: Text(s('close')),
            ),
          ],
        ),
      ),
    );
  }

  /// A short message for the group chat: who still has this month's share
  /// open, and how much a share is. Amounts are left out entirely when the
  /// manager has hidden them.
  Future<void> shareReminder() async {
    final active = fund.active(month);
    final waiting = active
        .where((m) => fund.payment(month, m['id']) == null)
        .map(nameOf)
        .toList();
    final text = waiting.isEmpty
        ? s('reminderMessageAllPaid', {
            'month': month.title(context),
            'fund': fund.name,
          })
        : s('reminderMessage', {
            'month': month.title(context),
            'fund': fund.name,
            'names': waiting.join(fundSep(context)),
          });
    final money = hidden
        ? ''
        : '\n${fundLabeled(context, s('shareNow'), cash(fund.shareFor(month)))}';
    try {
      await nexModuleShareText('$text$money');
    } on Object {
      if (mounted) {
        nexShowBanner(
          context,
          message: s('shareError'),
          kind: NexBannerKind.failed,
        );
      }
    }
  }

  Future<void> drawHistory() async {
    await nexShowSheet<void>(
      context: context,
      builder: (c) => SafeArea(
        top: false,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(NexSpacing.md),
          children: [
            Text(s('drawHistory'), style: Theme.of(c).textTheme.titleLarge),
            for (final draw in fund.draws.reversed)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.casino_outlined),
                title: Text(s('winner', {'name': winnerName(draw)})),
                subtitle: Text(
                  [
                    fundMonth(DateTime.parse(draw['month'] as String)).title(c),
                    date(DateTime.parse(draw['at'] as String)),
                    s('round', {'n': draw['round']}),
                    rows(draw['eligible'])
                        .map((member) {
                          final shares = member['shares'];
                          return shares is int
                              ? '${nameOf(member)} (${s('shareCount', {'n': shares})})'
                              : nameOf(member);
                        })
                        .join(fundSep(c)),
                    if ((draw['reason'] as String).isNotEmpty)
                      fundLabeled(context, s('reason'), '${draw['reason']}'),
                    if (fund.issued(draw['id'])) s('payoutRecorded'),
                  ].join('\n'),
                ),
              ),
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: Text(s('close')),
            ),
          ],
        ),
      ),
    );
  }
}
