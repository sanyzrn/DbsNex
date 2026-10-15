import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/price_lens/controller.dart';
import 'package:nex_client/modules/price_lens/options.dart';
import 'package:nex_client/modules/price_lens/rational.dart';
import 'package:nex_client/platform/nex_services.dart';

import '../../support/nex_harness.dart';

/// The controller over a real store: memories and saved comparisons
/// land, reload in order, restore exactly after Undo, survive a fresh
/// controller — and no other module sees any of it.
void main() {
  late NexTestHarness harness;
  late NexModuleStore store;
  late PriceLensController controller;

  setUp(() async {
    harness = await NexTestHarness.create(name: 'nex_pl_');
    store = NexModuleStore(harness.services, 'price_lens');
    controller = PriceLensController(store);
    await controller.load();
  });

  tearDown(() async {
    controller.dispose();
    await harness.dispose();
  });

  PriceMemory memory(
    String id, {
    String label = 'Rice 1kg',
    int price = 125000,
    DateTime? when,
  }) => PriceMemory(
    id: id,
    label: label,
    priceMinor: price,
    currency: 'IRR',
    quantity: const Fraction(1),
    unitKey: 'kg',
    date: when ?? DateTime(2026, 10, 1),
  );

  test('a remembered price is read back exactly, newest saved first', () async {
    await controller.saveMemory(memory('mem-a'));
    await controller.saveMemory(memory('mem-b', price: 99000));
    expect(controller.memories, hasLength(2));
    expect(controller.memories.first.id, 'mem-b');
    expect(controller.memories.first.priceMinor, 99000);
    expect(controller.memories.first.currency, 'IRR');
    expect(controller.memoryById('mem-a')!.priceMinor, 125000);
  });

  test('deleting and Undo restore the exact body', () async {
    final original = memory('mem-undo', price: 4242);
    await controller.saveMemory(original);
    await controller.deleteMemory('mem-undo');
    expect(controller.memories, isEmpty);
    await controller.restoreMemory(original);
    expect(controller.memories, hasLength(1));
    expect(controller.memories.first.priceMinor, 4242);
    expect(controller.memories.first.id, 'mem-undo');
    expect(controller.memories.first.date, DateTime(2026, 10, 1));
  });

  test('a malformed memory body is refused, never half-read', () async {
    await store.put('memory', 'mem-bad', {'label': 'no price'});
    await store.put('memory', 'mem-ok', {
      'label': 'Milk 1L',
      'price': 30000,
      'currency': 'IRR',
      'quantity': 1,
      'unit': 'l',
      'date': '2026-10-02T00:00:00',
      'schema': 1,
    });
    // Direct writes (bypassing the controller) fire change events; let
    // those listener reloads finish, then load with the final token.
    await pumpEventQueue();
    await controller.load();
    expect(controller.memories, hasLength(1));
    expect(controller.memories.first.label, 'Milk 1L');
    expect(controller.memories.first.unitKey, 'l');
  });

  PriceOption option(String id, {int price = 100000}) => PriceOption(
    id: id,
    label: id,
    priceMinor: price,
    currency: 'IRR',
    quantity: const Fraction(1),
    unitKey: 'kg',
    date: DateTime(2026, 10, 13),
  );

  test('a saved comparison keeps its options whole', () async {
    await controller.saveComparison([
      option('opt-a'),
      option('opt-b', price: 110000),
    ]);
    expect(controller.saved, hasLength(1));
    final saved = controller.saved.first;
    expect(saved.options, hasLength(2));
    expect(saved.options.first.priceMinor, 100000);
    expect(saved.options.first.currency, 'IRR');
    expect(saved.options.first.unitKey, 'kg');
    expect(saved.id, startsWith('cmp-'));
  });

  test('a malformed comparison body is refused too', () async {
    await store.put('comparison', 'cmp-bad', {
      'date': 'not-a-date',
      'options': [],
    });
    await pumpEventQueue();
    await controller.load();
    expect(controller.saved, isEmpty);
  });

  test('deleting a comparison and Undo restore it with its options', () async {
    await controller.saveComparison([option('opt-a'), option('opt-b')]);
    final saved = controller.saved.first;
    await controller.deleteComparison(saved.id);
    expect(controller.saved, isEmpty);
    await controller.restoreComparison(saved);
    expect(controller.saved, hasLength(1));
    expect(controller.saved.first.options, hasLength(2));
    expect(controller.comparisonById(saved.id), isNotNull);
  });

  test(
    'records persist across a fresh controller, as after reopening',
    () async {
      await controller.saveMemory(memory('mem-persist'));
      await controller.saveComparison([
        option('opt-a'),
        option('opt-b'),
        option('opt-c'),
      ]);

      final reopened = PriceLensController(store);
      await reopened.load();
      expect(reopened.memories, hasLength(1));
      expect(reopened.saved.first.options, hasLength(3));
      reopened.dispose();
    },
  );

  test('no other module sees these records', () async {
    await controller.saveMemory(memory('mem-isolated'));
    final other = NexModuleStore(harness.services, 'expenses');
    expect(await other.list('memory'), isEmpty);
    expect(
      await harness.services.moduleRecords('price_lens', 'memory'),
      hasLength(1),
    );
    expect(await harness.services.moduleRecords('other', 'memory'), isEmpty);
  });

  test('ids from the store are unique and prefixed', () {
    expect(controller.newMemoryId(), isNot(controller.newMemoryId()));
    expect(controller.newMemoryId(), startsWith('mem-'));
    expect(controller.newComparisonId(), startsWith('cmp-'));
  });
}
