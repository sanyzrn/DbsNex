import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/price_lens/controller.dart';
import 'package:nex_client/modules/price_lens/options.dart';
import 'package:nex_client/modules/price_lens/rational.dart';
import 'lens_test_store.dart';
import '../../support/nex_harness.dart';

void main() {
  late NexTestHarness h;
  late LensFaultStore store;
  late PriceLensController c;
  PriceMemory memory(String id) => PriceMemory(
    id: id,
    label: 'Rice',
    priceMinor: 100,
    currency: 'USD',
    quantity: const Fraction(1),
    unitKey: 'kg',
    date: DateTime(2026, 10, 1),
  );
  PriceOption offer(String id) => PriceOption(
    id: id,
    label: id,
    priceMinor: 100,
    currency: 'USD',
    quantity: const Fraction(1),
    unitKey: 'kg',
  );
  setUp(() async {
    h = await NexTestHarness.create(name: 'lens_reliability_');
    store = LensFaultStore(h.services);
    c = PriceLensController(store);
    await c.load();
  });
  tearDown(() async {
    c.dispose();
    await h.dispose();
  });
  test(
    'post-commit memory failure rolls back; retry retains identity',
    () async {
      store.failAfterKind = 'memory';
      await expectLater(c.saveMemory(memory('m')), throwsStateError);
      expect(await store.get('memory', 'm'), isNull);
      await c.saveMemory(memory('m'));
      expect(await store.list('memory'), hasLength(1));
      expect(await store.list('operation'), isEmpty);
    },
  );
  test(
    'failed comparison and stable retry restore common unit and offers',
    () async {
      final options = [offer('a'), offer('b')];
      store.failAfterKind = 'comparison';
      await expectLater(
        c.saveComparison(options, id: 'c', commonUnitKey: 'g'),
        throwsStateError,
      );
      expect(await store.list('comparison'), isEmpty);
      await c.saveComparison(options, id: 'c', commonUnitKey: 'g');
      expect(c.saved.single.commonUnitKey, 'g');
      expect(c.saved.single.options, hasLength(2));
    },
  );
  test('concurrent writes await each mutation and its reload', () async {
    await Future.wait([
      for (var i = 0; i < 12; i++) c.saveMemory(memory('m$i')),
    ]);
    expect(c.memories, hasLength(12));
    expect(await store.list('operation'), isEmpty);
  });
  test('raw unknown fields survive deletion and guarded Undo', () async {
    final raw = {
      ...memory('m').toBody(),
      'future': {
        'x': [1, 2],
      },
    };
    await store.put('memory', 'm', raw);
    await c.load();
    await c.deleteMemory('m');
    await c.restore('memory', 'm');
    expect(await store.get('memory', 'm'), raw);
    await c.deleteMemory('m');
    await store.put('memory', 'm', {...raw, 'price': 99});
    await expectLater(c.restore('memory', 'm'), throwsStateError);
    expect((await store.get('memory', 'm'))!['price'], 99);
  });
  test('malformed history remains manageable with exact raw Undo', () async {
    final raw = {'label': 'Broken', 'quantityDen': 0, 'future': 'keep'};
    await store.put('memory', 'broken', raw);
    await pumpEventQueue();
    await c.load();
    expect(c.memories, isEmpty);
    expect(c.invalidMemories.single.id, 'broken');
    await c.deleteMemory('broken');
    expect(c.invalidMemories, isEmpty);
    await c.restore('memory', 'broken');
    expect(await store.get('memory', 'broken'), raw);
  });
  test(
    'read failure exposes Retry and retains previously loaded history',
    () async {
      await c.saveMemory(memory('m'));
      store.failRead = true;
      await c.load();
      expect(c.readFailed, isTrue);
      expect(c.memories, hasLength(1));
      store.failRead = false;
      await c.load();
      expect(c.readFailed, isFalse);
    },
  );
  test('invalid options never become a saved comparison', () async {
    final bad = PriceOption.fromBody('bad', {'label': 'Bad', 'quantityDen': 0});
    await expectLater(c.saveComparison([offer('a'), bad]), throwsStateError);
    expect(await store.list('comparison'), isEmpty);
  });
}
