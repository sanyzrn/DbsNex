part of 'screen.dart';

extension _PriceAndGoalTabs on _AssetsScreenState {
  List<Widget> pricesView() {
    final known = <AssetMarket>[
      for (final series in valuation.history.values) series.first.market,
      for (final position in valuation.positions) position.holding.market,
      selected,
    ];
    final markets = priceCatalogue(known);
    final byKey = {for (final market in markets) market.key: market};
    final series = valuation.history[selected.key] ?? const <Quote>[];
    final latest = series.firstOrNull;
    final today = civilDay(DateTime.now());
    final future = latest != null && latest.date.isAfter(today);
    final delta = future ? null : quoteDelta(series);
    final market = marketLabel(context, selected, forQuote: true);
    final scheme = Theme.of(context).colorScheme;
    final moved = delta != null && delta.amount != BigInt.zero;
    final up = delta != null && delta.amount > BigInt.zero;
    final changeColor = future
        ? scheme.error
        : !moved
        ? scheme.onSurfaceVariant
        : up
        ? scheme.tertiary
        : scheme.error;
    final changeIcon = future
        ? Icons.event_busy_outlined
        : !moved
        ? Icons.horizontal_rule
        : up
        ? Icons.trending_up
        : Icons.trending_down;
    return [
      NexModuleHero(
        moduleId: 'assets',
        icon: Icons.history,
        eyebrow: market,
        headline: latest == null
            ? s('noPriceYet')
            : cash(BigInt.from(latest.unitRial)),
        caption: latest == null
            ? s('noQuotes')
            : '${s('updated', {'date': date(latest.date)})} · '
                  '${shortAge(context, latest.date, DateTime.now())}',
        chips: [
          if (latest != null &&
              civilDaysBetween(latest.date, today) >= priceFreshDays)
            s('staleBadge'),
          if (future) s('futureBadge'),
        ],
        semanticsLabel: latest == null
            ? '$market: ${s('noPriceYet')}'
            : '$market: ${cash(BigInt.from(latest.unitRial))}',
      ),
      const SizedBox(height: NexSpacing.md),
      DropdownButtonFormField<String>(
        key: ValueKey(selected.key),
        initialValue: byKey.containsKey(selected.key) ? selected.key : null,
        isExpanded: true,
        borderRadius: nexDropdownRadius,
        dropdownColor: nexDropdownColor(context),
        decoration: InputDecoration(labelText: s('assetType')),
        items: [
          for (final market in markets)
            DropdownMenuItem(
              value: market.key,
              child: Text(
                marketLabel(context, market, forQuote: true),
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: (key) {
          final market = key == null ? null : byKey[key];
          if (market != null) selectMarket(market);
        },
      ),
      const SizedBox(height: NexSpacing.md),
      if (latest != null)
        NexPanel(
          title: s('priceMovement'),
          icon: changeIcon,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                future
                    ? s('futureQuote')
                    : delta == null
                    ? s('noEarlierPrice')
                    : priceChange(delta),
                style: TextStyle(color: changeColor),
              ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => unawaited(
                    editor(
                      'quote',
                      market: latest.market,
                      original: latest.record,
                    ),
                  ),
                  label: Text(s('updatePrice')),
                ),
              ),
            ],
          ),
        ),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: FilledButton.icon(
          key: const ValueKey('assets-record-price'),
          onPressed: () => unawaited(editor('quote', market: selected)),
          icon: const Icon(Icons.add),
          label: Text(s('newQuote')),
        ),
      ),
      if (series.isNotEmpty) ...[
        const SizedBox(height: NexSpacing.md),
        NexShelfHeading(icon: Icons.history, title: s('priceHistory')),
        for (final quote in series)
          ListTile(
            key: ValueKey('assets-quote-${quote.record.id}'),
            contentPadding: EdgeInsets.zero,
            title: Text(cash(BigInt.from(quote.unitRial))),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${date(quote.date)} · '
                  '${shortAge(context, quote.date, DateTime.now())}',
                ),
                if (quote.date.isAfter(today))
                  Text(
                    s('futureQuote'),
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: Theme.of(context).colorScheme.error),
                  ),
              ],
            ),
            isThreeLine: quote.date.isAfter(today),
            trailing: entryMenu(
              quote.record,
              () => unawaited(
                editor('quote', market: quote.market, original: quote.record),
              ),
            ),
          ),
      ] else
        Text(s('choosePrice')),
    ];
  }

  String priceChange(QuoteDelta delta) {
    if (delta.amount == BigInt.zero) return s('priceChangeSame');
    final pct = delta.tenths == null
        ? ''
        : percentTenthsText(delta.tenths!, fa);
    return s(delta.amount.isNegative ? 'priceChangeDown' : 'priceChangeUp', {
      'pct': pct,
    });
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
        chips: [mithqalValue(context, owned)],
        semanticsLabel:
            '${s('goals')}: ${s('equivalentGold', {'n': number(owned, 3)})}',
      ),
      const SizedBox(height: NexSpacing.md),
      if (ledger.goals.isEmpty)
        NexEmptyState(
          icon: Icons.flag_outlined,
          message: s('goalEmpty'),
          action: FilledButton.icon(
            key: const ValueKey('assets-add-goal'),
            onPressed: () => unawaited(editor('goal')),
            icon: const Icon(Icons.add),
            label: Text(s('newGoal')),
          ),
        )
      else ...[
        for (final goal in ledger.goals)
          Padding(
            padding: const EdgeInsets.only(bottom: NexSpacing.sm),
            child: goalCard(goal, owned),
          ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilledButton.icon(
            key: const ValueKey('assets-add-goal'),
            onPressed: () => unawaited(editor('goal')),
            icon: const Icon(Icons.add),
            label: Text(s('newGoal')),
          ),
        ),
      ],
    ];
  }

  Widget goalCard(AssetGoal goal, BigInt owned) {
    final target = BigInt.from(goal.targetMg);
    final reached = owned >= target;
    var tenths = BigInt.zero;
    if (target > BigInt.zero) {
      tenths = owned * BigInt.from(1000) ~/ target;
      if (tenths > BigInt.from(1000)) tenths = BigInt.from(1000);
    }
    final percent = percentTenthsText(tenths, fa);
    return NexPanel(
      key: ValueKey('assets-goal-${goal.record.id}'),
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
          Text(
            s('targetMithqal', {'n': number(mesghalMilli(target), 3)}),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: NexSpacing.sm),
          Semantics(
            label: goal.title,
            value: percent,
            child: ExcludeSemantics(
              child: LinearProgressIndicator(
                value: tenths.toDouble() / 1000,
                borderRadius: BorderRadius.circular(NexRadius.sm),
              ),
            ),
          ),
          const SizedBox(height: NexSpacing.sm),
          Wrap(
            spacing: NexSpacing.sm,
            runSpacing: NexSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(percent, style: Theme.of(context).textTheme.titleSmall),
              Text(
                reached
                    ? s('goalMet')
                    : s('goalLeft', {'n': number(target - owned, 3)}),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
