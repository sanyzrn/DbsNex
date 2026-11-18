part of 'screen.dart';

extension _HoldingsTab on _AssetsScreenState {
  String change(BigInt value) => value == BigInt.zero
      ? s('unchanged')
      : '${s(value.isNegative ? 'loss' : 'gain')} · ${cash(value.abs())}';

  List<Widget> holdingsView() {
    final v = valuation;
    return [
      NexModuleHero(
        moduleId: 'assets',
        icon: Icons.account_balance_wallet_outlined,
        headline: v.priced == 0 ? s('noValuation') : cash(v.total),
        eyebrow: s(v.unpriced == 0 ? 'netValue' : 'partial'),
        caption: s('priceBasis'),
        chips: [
          if (v.positions.isNotEmpty)
            s('checkPrices', {'n': v.priced, 'total': v.positions.length}),
        ],
        child: v.priced == 0 ? null : Text(change(v.profit)),
      ),
      const SizedBox(height: NexSpacing.md),
      if (v.positions.isNotEmpty) ...[
        NexPanel(
          title: s('equivalents'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              benchmark(AssetMarket.gold, 'equivalentGold', 3),
              benchmark(AssetMarket.usd, 'equivalentUsd', 2),
            ],
          ),
        ),
        const SizedBox(height: NexSpacing.md),
      ] else
        Text(s('empty')),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: FilledButton.icon(
          onPressed: () => unawaited(editor('holding')),
          icon: const Icon(Icons.add),
          label: Text(s('newHolding')),
        ),
      ),
      const SizedBox(height: NexSpacing.md),
      for (final position in v.positions)
        Padding(
          padding: const EdgeInsets.only(bottom: NexSpacing.sm),
          child: holdingCard(position),
        ),
    ];
  }

  Widget benchmark(AssetMarket market, String label, int digits) {
    final rate = valuation.latest(market);
    final result = valuation.equivalent(
      market,
      market.type == AssetType.gold ? 1000 : 100,
    );
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(marketIcon(market.type)),
      title: Text(
        result == null
            ? marketLabel(context, market, forQuote: true)
            : s(label, {'n': number(result, digits)}),
      ),
      subtitle: rate == null
          ? Text(s('rateNeeded'))
          : Text(s('updated', {'date': date(rate.date)})),
      onTap: () => selectMarket(market, openPrices: true),
    );
  }

  Widget holdingCard(Position p) {
    final h = p.holding;
    final market = h.market;
    final qty = number(BigInt.from(h.quantity), market.digits);
    final shownQty = switch (market.type) {
      AssetType.gold => s('goldQuantity', {'n': qty, 'fineness': h.fineness}),
      AssetType.coin => s('coinQuantity', {'n': qty}),
      _ => qty,
    };
    return NexPanel(
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
          Text(
            p.value == null ? s('unpriced') : cash(p.value!),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (p.profit case final profit?) Text(change(profit)),
          if (p.quote case final q?)
            Text(s('updated', {'date': date(q.date)}))
          else if (valuation.latest(market) != null)
            Text(s('olderThanPurchase')),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            title: Text(s('holdingDetails')),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${s('costBasis')} · ${cash(p.cost)}'),
              Text(
                s('paidLine', {'price': cash(BigInt.from(h.costPerUnitRial))}),
              ),
              Text(s('boughtOn', {'date': date(h.bought)})),
              Text(
                [
                  s(h.custody.name),
                  if (h.location.isNotEmpty) h.location,
                ].join(' · '),
              ),
            ],
          ),
          TextButton.icon(
            icon: const Icon(Icons.history),
            onPressed: () => selectMarket(market, openPrices: true),
            label: Text(s(p.value == null ? 'setRate' : 'priceHistory')),
          ),
        ],
      ),
    );
  }
}
