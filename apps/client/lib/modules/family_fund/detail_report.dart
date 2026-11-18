part of 'detail.dart';

extension _FundReport on _FundDetailState {
  Future<void> report() async {
    final active = fund.active(month);
    String list(bool paid) {
      final names = active
          .where((m) => (fund.payment(month, m['id']) != null) == paid)
          .map(nameOf)
          .join('، ');
      return names.isEmpty ? s('none') : names;
    }

    final current = winner;
    final text = [
      fund.name,
      month.title(context),
      '${s('paid')} · ${list(true)}',
      '${s('waiting')} · ${list(false)}',
      '${s('balance')} (${date(now)}) · ${cash(fund.balanceAt(now))}',
      current == null
          ? s('noDraw')
          : s('winner', {'name': winnerName(current)}),
    ].join('\n');
    await nexShowSheet<void>(
      context: context,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(NexSpacing.md),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(s('report'), style: Theme.of(c).textTheme.titleLarge),
                const SizedBox(height: NexSpacing.md),
                SelectableText(text),
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
                          message: s('saveError'),
                          kind: NexBannerKind.failed,
                        );
                      }
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> drawHistory() async {
    await nexShowSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(NexSpacing.md),
          children: [
            Text(
              s('drawHistory'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            for (final d in fund.draws.reversed)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(s('winner', {'name': winnerName(d)})),
                subtitle: Text(
                  [
                    fundMonth(DateTime.parse(d['month'] as String))
                        .title(context),
                    date(DateTime.parse(d['at'] as String)),
                    s('pool', {'n': d['round']}),
                    rows(d['eligible']).map(nameOf).join(' · '),
                    if ((d['reason'] as String).isNotEmpty)
                      '${s('reason')} · ${d['reason']}',
                  ].join('\n'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
