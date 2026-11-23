part of 'screen.dart';

extension _HoldingsTab on _AssetsScreenState {
  String change(BigInt value, BigInt? tenths) => value == BigInt.zero
      ? s('unchanged')
      : '${s(value.isNegative ? 'loss' : 'gain')} · ${cash(value.abs())}'
            '${tenths == null ? '' : ' · ${percentTenthsText(tenths, fa)}'}';

  List<Widget> holdingsView() {
    final v = valuation;
    if (v.positions.isEmpty) return emptyBook();
    final prompt = pricePrompt(v);
    final allocationPanel = allocation(v);
    final filter = typeFilterBar(v);
    final visible = typeFilter == null
        ? v.positions
        : v.positions
              .where((p) => p.holding.market.type == typeFilter)
              .toList();
    return [
      holdingsHero(v),
      if (prompt != null) ...[const SizedBox(height: NexSpacing.md), prompt],
      const SizedBox(height: NexSpacing.md),
      equivalents(v),
      if (allocationPanel != null) ...[
        const SizedBox(height: NexSpacing.md),
        allocationPanel,
      ],
      const SizedBox(height: NexSpacing.md),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: FilledButton.icon(
          key: const ValueKey('assets-add'),
          onPressed: () => unawaited(editor('holding')),
          icon: const Icon(Icons.add),
          label: Text(s('newHolding')),
        ),
      ),
      if (filter != null) ...[const SizedBox(height: NexSpacing.md), filter],
      const SizedBox(height: NexSpacing.md),
      if (visible.isEmpty)
        Text(s('filterEmpty'))
      else
        for (final position in visible)
          Padding(
            padding: const EdgeInsets.only(bottom: NexSpacing.sm),
            child: holdingCard(position),
          ),
    ];
  }

  List<Widget> emptyBook() => [
    const SizedBox(height: NexSpacing.lg),
    NexEmptyState(
      icon: Icons.account_balance_wallet_outlined,
      message:
          '${s('emptyTitle')}\n\n${s('emptyStep1')}\n'
          '${s('emptyStep2')}\n${s('emptyStep3')}',
      action: FilledButton.icon(
        key: const ValueKey('assets-add'),
        onPressed: () => unawaited(editor('holding')),
        icon: const Icon(Icons.add),
        label: Text(s('newHolding')),
      ),
    ),
  ];

  Widget holdingsHero(Valuation v) {
    final priced = v.priced > 0;
    return NexModuleHero(
      moduleId: 'assets',
      icon: Icons.account_balance_wallet_outlined,
      headline: priced ? cash(v.total) : s('noPriceYet'),
      eyebrow: s(v.unpriced == 0 ? 'netValue' : 'partial'),
      caption: s(priced ? 'priceBasis' : 'noValuation'),
      semanticsLabel: priced
          ? '${s('netValue')}: ${cash(v.total)}'
          : s('noPriceYet'),
      chips: [
        if (v.unpriced > 0)
          s('checkPrices', {'n': v.priced, 'total': v.positions.length}),
      ],
      child: priced ? Text(change(v.profit, v.profitTenths)) : null,
    );
  }

  /// One quiet nudge, never two: an unpriced lot first (its cost is kept but
  /// its value is missing), then a price that has gone stale.
  Widget? pricePrompt(Valuation v) {
    final unpriced = v.firstUnpriced;
    if (unpriced != null) {
      return NexPanel(
        key: const ValueKey('assets-price-prompt'),
        child: promptBody(
          icon: Icons.price_change_outlined,
          title: s('unpricedTitle', {'n': v.unpriced}),
          body: s('unpricedBody'),
          action: s('addPrice'),
          onAction: () => unawaited(openQuote(unpriced.holding.market)),
        ),
      );
    }
    final oldest = v.oldestPricedQuote;
    if (oldest == null || oldest.days < priceFreshDays) return null;
    return NexPanel(
      key: const ValueKey('assets-price-prompt'),
      child: promptBody(
        icon: Icons.update,
        title: s('staleTitle'),
        body: s('staleBody', {'n': oldest.days}),
        action: s('updatePrice'),
        onAction: () => unawaited(openQuote(oldest.market)),
      ),
    );
  }

  Widget promptBody({
    required IconData icon,
    required String title,
    required String body,
    required String action,
    required VoidCallback onAction,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: nexModuleAccent(context, 'assets')),
          const SizedBox(width: NexSpacing.sm),
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleSmall),
          ),
        ],
      ),
      const SizedBox(height: NexSpacing.xs),
      Text(body, style: Theme.of(context).textTheme.bodySmall),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton(onPressed: onAction, child: Text(action)),
      ),
    ],
  );

  Widget equivalents(Valuation v) => NexPanel(
    title: s('equivalents'),
    icon: Icons.balance_outlined,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        benchmark(v, AssetMarket.gold, 1000),
        benchmark(v, AssetMarket.usd, 100),
      ],
    ),
  );

  Widget benchmark(Valuation v, AssetMarket market, int factor) {
    final rate = v.latest(market);
    final result = v.equivalent(market, factor);
    final gold = market.type == AssetType.gold;
    final title = result == null
        ? marketLabel(context, market, forQuote: true)
        : gold
        ? goldEquivalentBoth(context, result)
        : s('equivalentUsd', {'n': number(result, 2)});
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(marketIcon(market.type)),
      title: Text(title),
      subtitle: rate == null
          ? Text(s('rateNeeded'))
          : Text(
              '${s('updated', {'date': date(rate.date)})} · '
              '${shortAge(context, rate.date, DateTime.now())}',
            ),
      trailing: IconButton(
        tooltip: s('updatePrice'),
        icon: const Icon(Icons.edit_outlined),
        onPressed: () => unawaited(openQuote(market)),
      ),
      onTap: () => selectMarket(market, openPrices: true),
    );
  }

  /// Where the priced value sits: a share bar and one line per kind. A person
  /// asking "how much of this is gold?" should not have to add the lots up.
  Widget? allocation(Valuation v) {
    if (v.total <= BigInt.zero || v.byType.length < 2) return null;
    final types = AssetType.values
        .where((type) => v.byType[type] != null)
        .toList();
    if (types.length < 2) return null;
    final accent = nexModuleAccent(context, 'assets');
    final alphas = [1.0, 0.68, 0.46, 0.3];
    final tenths = {
      for (final type in types)
        type: rounded(v.byType[type]! * BigInt.from(1000), v.total),
    };
    return NexPanel(
      title: s('allocation'),
      icon: Icons.donut_small_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExcludeSemantics(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(NexRadius.sm),
              child: Row(
                children: [
                  for (final (i, type) in types.indexed)
                    Expanded(
                      flex: (v.byType[type]! * BigInt.from(1000) ~/ v.total)
                          .toInt()
                          .clamp(1, 1000)
                          .toInt(),
                      child: Container(
                        height: 10,
                        color: accent.withValues(
                          alpha: alphas[i % alphas.length],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: NexSpacing.sm),
          for (final (i, type) in types.indexed)
            Padding(
              padding: const EdgeInsets.only(top: NexSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.only(top: NexSpacing.xs),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent.withValues(
                        alpha: alphas[i % alphas.length],
                      ),
                    ),
                  ),
                  const SizedBox(width: NexSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s(type.name)),
                        Text(
                          cash(v.byType[type]!),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: NexSpacing.sm),
                  Text(percentTenthsText(tenths[type]!, fa)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget? typeFilterBar(Valuation v) {
    final types = AssetType.values
        .where((type) => v.typeCounts[type] != null)
        .toList();
    if (v.positions.length < 4 || types.length < 2) return null;
    return Wrap(
      spacing: NexSpacing.sm,
      runSpacing: NexSpacing.xs,
      children: [
        ChoiceChip(
          key: const ValueKey('assets-filter-all'),
          label: Text(s('filterAll')),
          selected: typeFilter == null,
          onSelected: (_) => setTypeFilter(null),
        ),
        for (final type in types)
          ChoiceChip(
            key: ValueKey('assets-filter-${type.name}'),
            label: Text(
              '${s(type.name)} · ${number(BigInt.from(v.typeCounts[type]!), 0)}',
            ),
            selected: typeFilter == type,
            onSelected: (_) => setTypeFilter(type),
          ),
      ],
    );
  }

  Widget holdingCard(Position p) {
    final h = p.holding;
    final market = h.market;
    final now = DateTime.now();
    final qty = number(BigInt.from(h.quantity), market.digits);
    final shownQty = switch (market.type) {
      AssetType.gold => s('goldQuantity', {'n': qty, 'fineness': h.fineness}),
      AssetType.coin => s('coinQuantity', {'n': qty}),
      // «۴۵۰ USD»: the amount with its code, which reads in both languages.
      AssetType.currency => '$qty ${market.code}',
      _ => qty,
    };
    final quote = p.quote;
    final age = quote == null ? null : civilDaysBetween(quote.date, now);
    final stale = age != null && age >= priceFreshDays;
    return NexPanel(
      key: ValueKey('assets-holding-${h.record.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(marketIcon(market.type), size: 20),
              const SizedBox(width: NexSpacing.sm),
              Expanded(
                child: Text(
                  marketLabel(context, market),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              entryMenu(
                h.record,
                () => unawaited(
                  editor('holding', market: market, original: h.record),
                ),
              ),
            ],
          ),
          Text(shownQty),
          if (market.type == AssetType.gold) ...[
            Text(
              '${karatText(context, h.fineness)}'
              "${h.fineness == 750 ? '' : ' · ${s('normalizedGold', {'n': number(normalizedGoldMg(h.quantity, h.fineness), 3)})}'}",
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: NexSpacing.xs),
          Text(
            p.value == null ? s('unpriced') : cash(p.value!),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (p.profit case final profit?) Text(change(profit, p.profitTenths)),
          if (quote != null)
            Row(
              children: [
                if (stale)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(
                      end: NexSpacing.xs,
                    ),
                    child: Icon(
                      Icons.schedule,
                      size: 14,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                Flexible(
                  child: Text(
                    '${s('updated', {'date': date(quote.date)})} · '
                    '${shortAge(context, quote.date, now)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            )
          else if (valuation.latest(market) != null)
            Text(
              s('olderThanPurchase'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          Wrap(
            spacing: NexSpacing.sm,
            children: [
              TextButton.icon(
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => unawaited(openQuote(market)),
                label: Text(s(quote == null ? 'setRate' : 'updatePrice')),
              ),
              TextButton.icon(
                icon: const Icon(Icons.history),
                onPressed: () => selectMarket(market, openPrices: true),
                label: Text(s('priceHistory')),
              ),
            ],
          ),
          ExpansionTile(
            // Its own storage key: without one, an expanded tile inside a
            // keyed ListView can read the list's saved scroll offset (a
            // double) as its open/closed state and throw on the next build.
            key: PageStorageKey('assets-details-${h.record.id}'),
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: NexSpacing.sm),
            title: Text(s('holdingDetails')),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${s('costBasis')} · ${cash(p.cost)}'),
              Text(
                s(market.type == AssetType.gold ? 'paidGramLine' : 'paidLine', {
                  'price': cash(BigInt.from(h.costPerUnitRial)),
                }),
              ),
              Text(s('boughtOn', {'date': date(h.bought)})),
              Text(
                [
                  s(h.custody.name),
                  if (h.location.isNotEmpty) h.location,
                ].join(' · '),
              ),
              if (market.custom)
                Text(
                  s('customNameHint'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
