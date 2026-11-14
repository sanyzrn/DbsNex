import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/converter/converter_history.dart';

import 'package:nex_client/platform/nex_services.dart';

import '../../support/nex_harness.dart';

void main() {
  late NexTestHarness harness;
  late NexModuleStore store;

  setUp(() async {
    harness = await NexTestHarness.create(name: 'converter_records_');
    store = NexModuleStore(harness.services, 'converter');
  });
  tearDown(() => harness.dispose());

  ConverterEntry entry(
    String label, {
    int minute = 0,
    ConverterTab tab = ConverterTab.units,
    Map<String, Object?>? payload,
  }) => ConverterEntry(
    id: '',
    tab: tab,
    label: label,
    payload: payload ?? {'value': label},
    at: DateTime(2026, 1, 1, 0, minute),
  );

  test('a conversion is kept once, at the top', () async {
    await converterRemember(store, entry('a', minute: 1));
    await converterRemember(store, entry('b', minute: 2));
    await converterRemember(store, entry('a', minute: 3));
    final history = converterReadHistory(
      await store.list('recent'),
      await store.list('favorite'),
    );
    expect(history.recents.map((e) => e.label), ['a', 'b']);
  });

  test('the same conversion repeated does not churn the list', () async {
    await converterRemember(store, entry('a', minute: 1));
    final first = (await store.list('recent')).single.id;
    await converterRemember(store, entry('a', minute: 1));
    final again = await store.list('recent');
    expect(again, hasLength(1));
    expect(again.single.id, first);
  });

  test('twenty are kept and the oldest falls away', () async {
    for (var index = 0; index < 25; index++) {
      await converterRemember(store, entry('v$index', minute: index));
    }
    final records = await store.list('recent');
    expect(records, hasLength(20));
    final history = converterReadHistory(records, const []);
    expect(history.recents.first.label, 'v24');
    expect(history.recents.last.label, 'v5');
    expect(history.recents.map((e) => e.label), isNot(contains('v0')));
  });

  test('starring adds a favourite, and taking it off removes it', () async {
    final first = entry('a', minute: 1);
    expect(converterIsFavorite(first, const []), isFalse);
    final starred = await converterStar(store, first, star: true);
    expect(starred, isNotNull);
    expect(starred!.starred, isTrue);
    var favorites = converterReadHistory(
      const [],
      await store.list('favorite'),
    ).favorites;
    expect(favorites.map((e) => e.label), ['a']);
    expect(converterIsFavorite(first, favorites), isTrue);

    await converterStar(store, first, star: true);
    favorites = converterReadHistory(
      const [],
      await store.list('favorite'),
    ).favorites;
    expect(favorites, hasLength(1), reason: 'starring twice is not two stars');

    await converterStar(store, first, star: false);
    favorites = converterReadHistory(
      const [],
      await store.list('favorite'),
    ).favorites;
    expect(favorites, isEmpty);
  });

  test('a record that lost its fields is skipped, never thrown over', () async {
    await store.put('recent', 'empty', {'v': 1});
    await store.put('recent', 'no-label', {
      'v': 1,
      'tab': 'units',
      'payload': {'value': '3'},
    });
    await store.put('recent', 'blank-label', {'v': 1, 'label': '   '});
    await store.put('recent', 'kept', {
      'v': 1,
      'tab': 'nowhere',
      'label': 'kept',
      'payload': 'not a map',
      'at': 42,
    });
    final history = converterReadHistory(await store.list('recent'), const []);
    expect(history.recents.map((e) => e.label), ['kept']);
    final kept = history.recents.single;
    expect(kept.payload, isEmpty);
    expect(kept.tab, ConverterTab.units, reason: 'an unknown tab is units');
    expect(kept.at, isA<DateTime>());
  });

  test('forgetting and putting back returns the record', () async {
    await converterRemember(store, entry('a', minute: 1));
    final record = (await store.list('recent')).single;
    final history = converterReadHistory([record], const []);
    final kept = history.recents.single;
    await converterForget(store, kept);
    expect(await store.list('recent'), isEmpty);
    await converterPutBack(store, kept);
    final back = converterReadHistory(await store.list('recent'), const []);
    expect(back.recents.single.label, 'a');
  });

  test("a favourite is put back as a favourite", () async {
    final starred = await converterStar(
      store,
      entry('a', minute: 1),
      star: true,
    );
    await converterForget(store, starred!);
    expect(await store.list('favorite'), isEmpty);
    await converterPutBack(store, starred);
    expect(await store.list('favorite'), hasLength(1));
    expect(await store.list('recent'), isEmpty);
  });

  test('another module cannot see these records', () async {
    await converterRemember(store, entry('a'));
    expect(
      await harness.services.moduleRecords('occasions', 'recent'),
      isEmpty,
    );
    expect(
      await harness.services.moduleRecords('converter', 'recent'),
      hasLength(1),
    );
  });
}
