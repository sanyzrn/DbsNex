part of 'screen.dart';

extension _PriceAndGoalTabs on _AssetsScreenState {
  List<Widget> pricesView() {
    final markets = <String, AssetMarket>{
      AssetMarket.gold.key: AssetMarket.gold,
      AssetMarket.usd.key: AssetMarket.usd,
      for (final series in valuation.history.values)
        series.first.market.key: series.first.market,
      for (final p in valuation.positions)
        p.holding.market.key: p.holding.market,
      selected.key: selected,
    };
    final series = valuation.history[selected.key] ?? const <Quote>[];
    final latest = series.firstOrNull;
    return [
      NexModuleHero(
        moduleId: 'assets',
        icon: Icons.history,
        eyebrow: s('prices'),
        headline: marketLabel(context, selected, forQuote: true),
        caption: latest == null
            ? s('noQuotes')
            : s('updated', {'date': date(latest.date)}),
      ),
      const SizedBox(height: NexSpacing.md),
      DropdownButtonFormField<String>(
        key: ValueKey(selected.key),
        initialValue: selected.key,
        isExpanded: true,
        borderRadius: nexDropdownRadius,
        dropdownColor: nexDropdownColor(context),
        decoration: InputDecoration(labelText: s('assetType')),
        items: [
          for (final m in markets.values)
            DropdownMenuItem(
              value: m.key,
              child: Text(
                marketLabel(context, m, forQuote: true),
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: (key) {
          if (key != null) selectMarket(markets[key]!);
        },
      ),
      const SizedBox(height: NexSpacing.md),
      if (latest != null)
        NexPanel(
          title: cash(BigInt.from(latest.unitRial)),
          child: Text(s('updated', {'date': date(latest.date)})),
        ),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: FilledButton.icon(
          onPressed: () => unawaited(editor('quote', market: selected)),
          icon: const Icon(Icons.add),
          label: Text(s('newQuote')),
        ),
      ),
      if (series.isNotEmpty) ...[
        const SizedBox(height: NexSpacing.md),
        NexShelfHeading(icon: Icons.history, title: s('priceHistory')),
        for (final q in series)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(cash(BigInt.from(q.unitRial))),
            subtitle: Text(date(q.date)),
            trailing: entryMenu(
              q.record,
              () => unawaited(
                editor('quote', market: q.market, original: q.record),
              ),
            ),
          ),
      ] else
        Text(s('choosePrice')),
    ];
  }

  List<Widget> goalsView() {
    final owned = valuation.goldMg;
    return [
      NexModuleHero(
        moduleId: 'assets',
        icon: Icons.flag_outlined,
        eyebrow: s('goals'),
        headline: s('equivalentGold', {'n': number(owned, 3)}),
        caption: s('goalWhy'),
      ),
      const SizedBox(height: NexSpacing.md),
      if (ledger.goals.isEmpty) Text(s('goalEmpty')),
      for (final goal in ledger.goals)
        Padding(
          padding: const EdgeInsets.only(bottom: NexSpacing.sm),
          child: goalCard(goal, owned),
        ),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: FilledButton.icon(
          onPressed: () => unawaited(editor('goal')),
          icon: const Icon(Icons.add),
          label: Text(s('newGoal')),
        ),
      ),
    ];
  }

  Widget goalCard(AssetGoal goal, BigInt owned) {
    final target = BigInt.from(goal.targetMg);
    final reached = owned >= target;
    final progress = reached ? 1.0 : owned.toInt() / goal.targetMg;
    return NexPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  goal.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              entryMenu(
                goal.record,
                () => unawaited(editor('goal', original: goal.record)),
              ),
            ],
          ),
          Text(
            s('goalProgress', {
              'current': number(owned, 3),
              'target': number(target, 3),
            }),
          ),
          const SizedBox(height: NexSpacing.sm),
          LinearProgressIndicator(value: progress),
          const SizedBox(height: NexSpacing.sm),
          Text(
            reached
                ? s('goalMet')
                : s('goalLeft', {'n': number(target - owned, 3)}),
          ),
        ],
      ),
    );
  }
}
