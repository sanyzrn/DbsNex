import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/price_lens/controller.dart';
import 'package:nex_client/modules/price_lens/options.dart';
import 'package:nex_client/modules/price_lens/products.dart';
import 'package:nex_client/modules/price_lens/projection.dart';
import 'package:nex_client/modules/price_lens/rational.dart';
import 'package:nex_client/modules/price_lens/units.dart';

import 'lens_test_store.dart';
import '../../support/nex_harness.dart';

PriceMemory observation(
  String id,
  int day,
  int rials,
  int grams, {
  String name = 'Rice',
  String currency = 'IRR',
  String unit = 'g',
  DateTime? recordedAt,
}) => PriceMemory(
  id: id,
  label: name,
  productName: name,
  priceMinor: rials * 100,
  currency: currency,
  quantity: Fraction(grams),
  unitKey: unit,
  date: DateTime(2026, 10, day),
  recordedAt: recordedAt,
);

void main() {
  final today = DateTime(2026, 10, 20);
  test('smaller pack at the same price exposes unit-price inflation', () {
    final p = productHistory([
      observation('a', 1, 90000, 1000),
      observation('b', 15, 90000, 750),
    ]).single;
    expect(memoryUnitPrice(p.prices.last, p.common), const Fraction(12000000));
    expect(productChange(p, today), const Fraction(100, 3));
    expect(percentageChangeText(productChange(p, today)!), '+33.3');
    expect(elapsedPriceDays(p.prices.first.date, p.prices.last.date), 14);
  });
  test('growth, decrease and no change are signed, with no float overflow', () {
    expect(percentageChangeText(const Fraction(-125, 10)), '−12.5');
    expect(percentageChangeText(const Fraction(0)), '0');
    expect(
      percentageChangeText(
        Fraction.exact(BigInt.parse('999999999999999999999'), BigInt.one),
      ),
      '+999999999999999999999',
    );
  });
  test('a free baseline or same-day observations make no percent claim', () {
    expect(
      productChange(
        productHistory([
          observation('a', 1, 0, 1000),
          observation('b', 15, 1, 1000),
        ]).single,
        today,
      ),
      isNull,
    );
    expect(
      productChange(
        productHistory([
          observation('a', 1, 10, 1000),
          observation('b', 1, 20, 1000),
        ]).single,
        today,
      ),
      isNull,
    );
  });
  test('future shopping dates never become latest prices or estimates', () {
    final p = productHistory([
      observation('a', 1, 10, 1000),
      observation('b', 25, 20, 1000),
    ]).single;
    expect(p.latestKnown(today)!.id, 'a');
    expect(productChange(p, today), isNull);
    expect(p.prices, hasLength(2));
  });
  test('shopping day leads, then record time, regardless of UUID order', () {
    final p = productHistory([
      observation('z', 10, 10, 1000, recordedAt: DateTime(2026, 10, 19, 8)),
      observation('a', 10, 20, 1000, recordedAt: DateTime(2026, 10, 19, 9)),
      observation('older', 9, 30, 1000, recordedAt: DateTime(2026, 10, 20)),
    ]).single;
    expect(p.latestKnown(today)!.id, 'a');
  });
  test('explicit Persian product names group across sizes, never currencies or families', () {
    final all = productHistory([
      observation('a', 1, 10, 750, name: ' كيک '),
      observation('b', 10, 20, 1000, name: 'کیک'),
      observation('c', 10, 20, 1000, name: 'کیک', unit: 'ml'),
      observation('d', 10, 20, 1000, name: 'کیک', currency: 'USD'),
    ]);
    expect(all, hasLength(3));
    expect(all.where((p) => p.prices.length == 2), hasLength(1));
  });
  test('rolls and sheets are distinct; 100 sheets converts exactly', () {
    expect(
      convertQuantity(
        const Fraction(2),
        priceUnitOf('sheet100')!,
        priceUnitOf('sheet')!,
      ),
      const Fraction(200),
    );
    expect(
      convertQuantity(
        const Fraction(1),
        priceUnitOf('roll')!,
        priceUnitOf('sheet')!,
      ),
      isNull,
    );
    expect(
      convertQuantity(
        const Fraction(1),
        priceUnitOf('piece')!,
        priceUnitOf('roll')!,
      ),
      isNull,
    );
  });
  test(
    'new Iranian prices have one whole Rial value, old meaning stays exact',
    () {
      final modern = observation('m', 1, 45000, 750).toBody();
      expect(modern['priceRial'], 45000);
      expect(modern.containsKey('price'), isFalse);
      final old = {...modern}..remove('priceRial');
      old.addAll({
        'schema': 2,
        'price': 4500000,
        'future': {'x': 1},
        'person': {
          'name': 'Shop',
          'id': 'person-1',
          'cards': ['keep'],
        },
      });
      final read = PriceMemory.fromBody('m', old)!;
      expect(read.priceMinor, 4500000);
      expect(read.toBody()['person'], old['person']);
      expect(read.toBody()['future'], old['future']);
      expect(read.toBody()['price'], old['price']);
      expect(PriceMemory.fromBody('m', {...modern, 'price': 1}), isNull);
      expect(PriceMemory.fromBody('m', {...modern, 'schema': 99}), isNull);
    },
  );
  test('old sub-rial quotes remain exact rather than being rounded', () {
    final body = observation('m', 1, 1, 750).toBody()..remove('priceRial');
    body.addAll({'schema': 2, 'price': 12345});
    final m = PriceMemory.fromBody('m', body)!;
    expect(m.toBody()['price'], 12345);
    expect(m.toBody().containsKey('priceRial'), isFalse);
  });
  test(
    'record timestamps retain time through serialization for same-day ordering',
    () {
      final stamp = DateTime(2026, 10, 15, 17, 42, 30);
      final m = observation('m', 15, 10, 750, recordedAt: stamp);
      expect(PriceMemory.fromBody(m.id, m.toBody())!.recordedAt, stamp);
    },
  );
  test('foreign prices retain smallest units and explicit currency', () {
    final m = observation('m', 1, 3, 750, currency: 'USD');
    expect(m.toBody()['amount'], 300);
    expect(m.toBody().containsKey('priceRial'), isFalse);
    expect(PriceMemory.fromBody('m', m.toBody())!.priceMinor, 300);
    expect(PriceMemory.fromBody('m', {...m.toBody(), 'price': 1}), isNull);
  });
  test(
    'summaries are private and pure, exclude drafts and foreign modules',
    () {
      ModuleRecord row(String kind, {String module = 'price_lens'}) =>
          ModuleRecord(
            module: module,
            kind: kind,
            id: 'm',
            body: observation('m', 1, 10, 750).toBody(),
            updatedAt: today,
          );
      final record = row('memory');
      final before = Map.of(record.body);
      expect(summarize(record)!.title, 'Rice');
      expect(summarize(record)!.private, isTrue);
      expect(summarize(row('draft')), isNull);
      expect(summarize(row('memory', module: 'expenses')), isNull);
      expect(record.body, before);
      expect(duesBetween(today, today.add(const Duration(days: 30))), isEmpty);
    },
  );

  group('storage integration', () {
    late NexTestHarness h;
    late LensFaultStore store;
    late PriceLensController c;
    setUp(() async {
      h = await NexTestHarness.create(name: 'lens_products_');
      store = LensFaultStore(h.services);
      c = PriceLensController(store);
      await c.load();
    });
    tearDown(() async {
      c.dispose();
      await h.dispose();
    });
    test(
      'fresh unknown metadata survives edits and guarded delete/undo',
      () async {
        final m = observation('m', 1, 10, 750);
        await c.saveMemory(m);
        final old = (await store.get('memory', 'm'))!;
        await store.put('memory', 'm', {
          ...old,
          'future': {'k': 1},
          'person': {
            'name': 'Old',
            'id': 'p',
            'ibans': ['keep'],
          },
        });
        final edit = PriceMemory(
          id: m.id,
          label: m.label,
          priceMinor: 2000,
          currency: m.currency,
          quantity: m.quantity,
          unitKey: m.unitKey,
          date: m.date,
          person: {'name': 'New'},
        );
        await c.saveMemory(edit);
        final raw = (await store.get('memory', 'm'))!;
        expect(raw['future'], {'k': 1});
        expect(raw['person'], {
          'name': 'New',
          'id': 'p',
          'ibans': ['keep'],
        });
        await c.deleteMemory('m');
        await c.restore('memory', 'm');
        expect(await store.get('memory', 'm'), raw);
      },
    );
    test(
      'queued shopping toggles keep one record and survive reopening',
      () async {
        await Future.wait([
          c.setBought('p', true),
          c.setBought('p', false),
          c.setBought('p', true),
        ]);
        expect(await store.list('shopping'), hasLength(1));
        expect(c.bought('p'), isTrue);
        c.dispose();
        c = PriceLensController(store);
        await c.load();
        expect(c.bought('p'), isTrue);
      },
    );
    test('shopping failure rolls back and retry succeeds', () async {
      store.failAfterKind = 'shopping';
      await expectLater(c.setBought('p', true), throwsStateError);
      expect(c.bought('p'), isFalse);
      await c.setBought('p', true);
      expect(await store.list('shopping'), hasLength(1));
    });
    test(
      'clearing a saved common unit does not resurrect its old value',
      () async {
        final o = PriceOption(
          id: 'o',
          label: 'Rice',
          priceMinor: 1000,
          currency: 'IRR',
          quantity: const Fraction(1),
          unitKey: 'kg',
        );
        await c.saveComparison([o, o], id: 'c', commonUnitKey: 'g');
        await store.put('comparison', 'c', {
          ...(await store.get('comparison', 'c'))!,
          'future': true,
        });
        await c.saveComparison([o, o], id: 'c');
        final raw = (await store.get('comparison', 'c'))!;
        expect(raw['future'], isTrue);
        expect(raw.containsKey('commonUnit'), isFalse);
      },
    );
    test('future schemas cannot be overwritten', () async {
      final m = observation('m', 1, 10, 750);
      await store.put('memory', 'm', {...m.toBody(), 'schema': 99});
      await expectLater(c.saveMemory(m), throwsStateError);
      expect((await store.get('memory', 'm'))!['schema'], 99);
    });
    test(
      'a recovery journal cannot write reserved or unknown record kinds',
      () async {
        await store.put('operation', 'invalid', {
          'v': 1,
          'before': [
            {
              'kind': 'memory',
              'id': 'injected',
              'body': observation('m', 1, 10, 750).toBody(),
            },
            {
              'kind': '__reminder',
              'id': 'blocked',
              'body': <String, Object?>{},
            },
          ],
        });
        await c.load();
        expect(await store.get('memory', 'injected'), isNull);
        expect(await store.list('operation'), isEmpty);
        expect(await store.list('__reminder'), isEmpty);
      },
    );
  });
}
