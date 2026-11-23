import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/assets/model.dart';
import 'package:nex_client/modules/assets/projection.dart';
import 'package:nex_client/modules/assets/valuation.dart';

import 'fixtures.dart';

void main() {
  final asOf = DateTime(2026, 11, 15), earlier = DateTime(2026, 11, 1);
  Holding holding(
    AssetMarket market,
    int qty, {
    int fineness = 750,
    int price = 10000,
  }) => Holding.read(
    entry(
      'holding',
      'h',
      holdingBody(market, qty, earlier, fineness: fineness, price: price),
    ),
  )!;
  Quote quote(
    AssetMarket market,
    int price, {
    DateTime? at,
    DateTime? saved,
    String id = 'q',
  }) => Quote.read(
    entry('quote', id, quoteBody(market, price, at ?? asOf), updated: saved),
  )!;
  const emami = AssetMarket(AssetType.coin, code: 'emami');
  const bahar = AssetMarket(AssetType.coin, code: 'bahar');

  test('gold fineness changes metal value and normalized grams, while paid cost uses actual weight', () {
    final h = holding(AssetMarket.gold, 2500, fineness: 900);
    final q = quote(AssetMarket.gold, 12000);
    final v = Valuation([h], [q, quote(AssetMarket.usd, 80000)], asOf);
    expect(v.total, BigInt.from(36000));
    expect(v.pricedCost, BigInt.from(25000));
    expect(v.profit, BigInt.from(11000));
    expect(v.goldMg, BigInt.from(3000));
    expect(v.equivalent(AssetMarket.gold, 1000), BigInt.from(3000));
    expect(v.equivalent(AssetMarket.usd, 100), BigInt.from(45));
  });

  test('unpriced holdings stay unknown and do not enter subtotal profit', () {
    final v = Valuation(
      [holding(emami, 2), holding(bahar, 1), holding(AssetMarket.usd, 125)],
      [quote(bahar, 15000), quote(AssetMarket.usd, 8000)],
      asOf,
    );
    expect(v.priced, 2);
    expect(v.unpriced, 1);
    expect(v.positions.first.quote, isNull);
    expect(v.positions.first.profit, isNull);
    expect(v.total, BigInt.from(25000));
    expect(v.profit, BigInt.from(2500));
    expect(v.goldMg, BigInt.zero);
    expect(v.equivalent(AssetMarket.gold, 1000), isNull);
  });

  test('future prices stay in history but never value the book', () {
    final q = [
      quote(emami, 200, at: DateTime(2026, 12, 1)),
      quote(emami, 150, at: earlier, saved: DateTime(2026, 12, 1)),
      quote(emami, 190, saved: DateTime(2026, 11, 15, 12)),
      quote(emami, 180, saved: DateTime(2026, 11, 15, 8)),
    ];
    final v = Valuation([holding(emami, 2)], q, asOf);
    // The future record used to vanish from the price screen and could not
    // be corrected; it is still history, but only the usable day values.
    expect(v.history[emami.key]!.map((q) => q.unitRial), [200, 190, 180, 150]);
    expect(v.latest(emami)?.unitRial, 190);
    expect(v.total, BigInt.from(380));
  });

  test(
    'a quote before purchase is shown in history but does not value the lot',
    () {
      final v = Valuation(
        [holding(AssetMarket.gold, 1000)],
        [quote(AssetMarket.gold, 100, at: DateTime(2026, 10))],
        asOf,
      );
      expect(v.unpriced, 1);
      expect(v.latest(AssetMarket.gold), isNotNull);
      expect(v.equivalent(AssetMarket.gold, 1000), isNull);
    },
  );

  test(
    'value and gains handle half-rial rounding and products larger than int64',
    () {
      final usd = holding(AssetMarket.usd, 50, price: 3);
      final v = Valuation([usd], [quote(AssetMarket.usd, 1)], asOf);
      expect(v.total, BigInt.one);
      expect(v.profit, -BigInt.one);
      final large = holding(emami, 1000000000, price: 0);
      expect(
        valueAt(large, quote(emami, 9007199254740991)),
        BigInt.parse('9007199254740991000000000'),
      );
    },
  );

  test('custom assets normalize Persian variants but coin and other markets stay separate', () {
    const first = AssetMarket(AssetType.other, name: '  نقره كاري ');
    const second = AssetMarket(AssetType.other, name: 'نقره‌کاری');
    expect(first.key, second.key);
    expect(
      first.key,
      isNot(
        const AssetMarket(
          AssetType.coin,
          code: 'custom',
          name: 'نقره کاری',
        ).key,
      ),
    );
  });

  test(
    'profit percentages round a loss away from zero and skip a zero cost',
    () {
      final gain = Valuation(
        [holding(emami, 1, price: 1000)],
        [quote(emami, 1250)],
        asOf,
      );
      expect(gain.profit, BigInt.from(250));
      expect(gain.profitTenths, BigInt.from(250));
      expect(gain.positions.single.profitTenths, BigInt.from(250));
      final loss = Valuation(
        [holding(emami, 1, price: 1000)],
        [quote(emami, 750)],
        asOf,
      );
      expect(loss.profitTenths, BigInt.from(-250));
      final gift = Valuation(
        [holding(emami, 1, price: 0)],
        [quote(emami, 750)],
        asOf,
      );
      expect(gift.profitTenths, isNull);
      expect(gift.positions.single.profitTenths, isNull);
    },
  );

  test('the book has one stable order and totals by kind', () {
    Holding lot(String id, DateTime bought, {DateTime? updated}) =>
        Holding.read(
          entry(
            'holding',
            id,
            holdingBody(AssetMarket.usd, 100, bought),
            updated: updated,
          ),
        )!;
    final first = lot('first', earlier);
    final second = lot('second', asOf, updated: DateTime(2026, 11, 20));
    final gold = holding(AssetMarket.gold, 1000, price: 1);
    final v = Valuation(
      [second, gold, first],
      [quote(AssetMarket.usd, 100), quote(AssetMarket.gold, 100)],
      asOf,
    );
    expect(v.positions.map((p) => p.holding.record.id), [
      gold.record.id,
      'first',
      'second',
    ]);
    expect(v.typeCounts, {AssetType.gold: 1, AssetType.currency: 2});
    expect(v.byType.keys.toSet(), {AssetType.gold, AssetType.currency});
    expect(v.byType[AssetType.gold], BigInt.from(100));
    expect(v.byType[AssetType.currency], BigInt.from(200));
    expect(v.oldestPricedQuote?.market.type, AssetType.gold);
  });

  test('unpriced lots, price changes and freshness are explicit', () {
    final v = Valuation(
      [holding(emami, 2), holding(bahar, 1)],
      [
        quote(emami, 150, at: DateTime(2026, 11, 1)),
        quote(emami, 140, at: DateTime(2026, 10, 20)),
        quote(bahar, 500, at: earlier),
      ],
      asOf,
    );
    expect(v.firstUnpriced, isNull);
    final unpriced = Valuation(
      [holding(emami, 2), holding(bahar, 1)],
      [quote(bahar, 500, at: earlier)],
      asOf,
    );
    expect(unpriced.firstUnpriced?.holding.market.code, 'emami');
    expect(unpriced.unpriced, 1);
    final delta = quoteDelta(v.history[emami.key]!);
    expect(delta?.amount, BigInt.from(10));
    expect(delta?.tenths, BigInt.from(71));
    final same = quoteDelta([quote(emami, 150), quote(emami, 150)]);
    expect(same?.amount, BigInt.zero);
    expect(same?.tenths, BigInt.zero);
    expect(quoteDelta([quote(emami, 150)]), isNull);
  });

  test('gold is also measured in mithqal and kept at 18k', () {
    expect(mesghalMilli(BigInt.from(46083)), BigInt.from(10000));
    expect(mesghalMilli(BigInt.from(4608)), BigInt.from(1000));
    expect(karatOf(750), 18);
    expect(karatOf(916), 22);
    expect(karatOf(999), 24);
    expect(normalizedGoldMg(2500, 900), BigInt.from(3000));
  });

  test('the price catalogue offers common assets before they are held', () {
    final catalogue = priceCatalogue(const [
      AssetMarket(AssetType.other, name: 'Silver'),
    ]);
    expect(catalogue.first.key, AssetMarket.gold.key);
    expect(catalogue.any((m) => m.key == AssetMarket.usd.key), isTrue);
    expect(
      catalogue.any(
        (m) => m.key == const AssetMarket(AssetType.currency, code: 'EUR').key,
      ),
      isTrue,
    );
    expect(
      catalogue.any(
        (m) => m.key == const AssetMarket(AssetType.coin, code: 'gram').key,
      ),
      isTrue,
    );
    expect(catalogue.last.name, 'Silver');
    expect(compareMarkets(AssetMarket.gold, AssetMarket.usd), lessThan(0));
  });

  test('defensive parsing and private summaries omit sensitive numeric and storage details', () {
    final source = entry(
      'holding',
      'h',
      holdingBody(
        AssetMarket.gold,
        500,
        earlier,
        price: 12345,
        location: 'Private storage',
      ),
    );
    expect(summarize(source)!.private, isTrue);
    expect(summarize(source)!.detail, isNull);
    expect(
      summarize(entry('holding', 'bad', {...source.body, 'v': 3})),
      isNull,
    );
    expect(
      Holding.read(entry('holding', 'bad', {...source.body, 'quantity': 0})),
      isNull,
    );
    expect(
      Quote.read(
        entry('quote', 'bad', {
          ...quoteBody(AssetMarket.gold, 12, earlier),
          'unitRial': 0,
        }),
      ),
      isNull,
    );
    expect(readDay('2026-02-30T00:00:00.000'), isNull);
    expect(duesBetween(earlier, asOf), isEmpty);
  });
}
