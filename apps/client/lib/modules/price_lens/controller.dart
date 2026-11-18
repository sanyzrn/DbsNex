import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:nex_client/modules/module_api.dart';

import 'options.dart';
import 'units.dart';
import 'local_writes.dart';
import 'storage_money.dart';

/// Only explicit memories/comparisons persist; the live calculator is scratch.
class PriceLensController extends ChangeNotifier {
  PriceLensController(this.store) {
    _changes = store.changes.listen((_) {
      if (_mutating == 0) unawaited(load());
    });
  }
  final NexModuleStore store;
  late final StreamSubscription<void> _changes;
  Future<void> _tail = Future.value();
  int _mutating = 0, _loadToken = 0;
  bool _disposed = false, loading = true, readFailed = false;
  List<PriceMemory> memories = const [];
  List<SavedComparison> saved = const [];
  List<ModuleRecord> invalidMemories = const [], invalidSaved = const [];
  List<ModuleRecord> shopping = const [];
  final _undos = <String, Future<void> Function()>{};
  @override
  void dispose() {
    _disposed = true;
    unawaited(_changes.cancel());
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    final token = ++_loadToken;
    try {
      await LocalWrites.recover(store);
      final result = await Future.wait([
        store.list('memory'),
        store.list('comparison'),
        store.list('shopping'),
      ]);
      if (_disposed || token != _loadToken) return;
      memories = [
        for (final row in result[0])
          ?PriceMemory.fromBody(row.id, row.body, recordedAt: row.updatedAt),
      ];
      saved = [
        for (final row in result[1])
          ?SavedComparison.fromBody(row.id, row.body),
      ];
      invalidMemories = [
        for (final row in result[0])
          if (PriceMemory.fromBody(row.id, row.body) == null) row,
      ];
      invalidSaved = [
        for (final row in result[1])
          if (SavedComparison.fromBody(row.id, row.body) == null) row,
      ];
      shopping = result[2];
      loading = false;
      readFailed = false;
      _notify();
    } catch (_) {
      if (_disposed || token != _loadToken) return;
      loading = false;
      readFailed = true;
      _notify();
    }
  }

  Future<void> _mutate(Future<void> Function() action) {
    final done = _tail.then((_) async {
      _mutating++;
      try {
        await action();
        await load();
      } finally {
        _mutating--;
      }
    });
    _tail = done.then<void>((_) {}, onError: (Object _) {});
    return done;
  }

  String newMemoryId() => 'mem-${store.newId()}';
  String newComparisonId() => 'cmp-${store.newId()}';
  Future<void> saveMemory(PriceMemory memory) => _mutate(
    () => LocalWrites.serial(store, () async {
      final body = memory.toBody();
      if (PriceMemory.fromBody(memory.id, body) == null) {
        throw StateError('Incomplete memory');
      }
      final raw = await store.get('memory', memory.id);
      if (raw != null && !priceSchemaKnown(raw)) {
        throw StateError('Unsupported memory version');
      }
      final merged = {...keepUnknown(raw, memoryFields), ...body};
      if (raw?['person'] is Map && body['person'] is Map) {
        merged['person'] = {...raw!['person'] as Map, ...body['person'] as Map};
      }
      if (raw?.containsKey('price') == true && !body.containsKey('price')) {
        merged['price'] = memory.priceMinor;
      }
      for (final key in ['paid_num', 'paid_den']) {
        if (!body.containsKey(key)) merged.remove(key);
      }
      await LocalWrites.apply(store, [
        (kind: 'memory', id: memory.id, body: merged),
      ]);
    }),
  );
  Future<void> saveComparison(
    List<PriceOption> options, {
    String? id,
    String? commonUnitKey,
  }) {
    final target = id ?? newComparisonId();
    final snapshot = List<PriceOption>.of(options);
    return _mutate(() async {
      if (snapshot.length < 2 ||
          snapshot.length > 4 ||
          snapshot.any((o) => !optionSafe(o))) {
        throw StateError('Incomplete comparison');
      }
      if (commonUnitKey != null && priceUnitOf(commonUnitKey) == null) {
        throw StateError('Unknown common unit');
      }
      final body = SavedComparison(
        id: target,
        date: DateTime.now(),
        options: snapshot,
        commonUnitKey: commonUnitKey,
      ).toBody();
      await LocalWrites.serial(store, () async {
        final raw = await store.get('comparison', target);
        if (raw != null && !priceSchemaKnown(raw)) {
          throw StateError('Unsupported comparison version');
        }
        final merged = {...?raw, ...body};
        if (commonUnitKey == null) merged.remove('commonUnit');
        await LocalWrites.apply(store, [
          (kind: 'comparison', id: target, body: merged),
        ]);
      });
    });
  }

  bool bought(String productKey) {
    final row = shopping
        .where((r) => r.body['productKey'] == productKey)
        .firstOrNull;
    return row?.body['v'] == 1 && row?.body['bought'] == true;
  }

  Future<void> setBought(String productKey, bool bought) => _mutate(
    () => LocalWrites.serial(store, () async {
      final matching = (await store.list('shopping'))
          .where((r) => r.body['productKey'] == productKey);
      final old = matching.isEmpty ? null : matching.first;
      if (old != null && old.body['v'] != 1) {
        throw StateError('Unsupported list version');
      }
      final id = old?.id ?? store.newId();
      await LocalWrites.apply(store, [
        (
          kind: 'shopping',
          id: id,
          body: {
            ...?old?.body,
            'v': 1,
            'productKey': productKey,
            'bought': bought,
          },
        ),
      ]);
    }),
  );

  Future<void> _delete(String kind, String id) => _mutate(() async {
    _undos['$kind:$id'] = await LocalWrites.delete(store, kind, id);
  });
  Future<void> restore(String kind, String id) => _mutate(() async {
    final undo = _undos['$kind:$id'];
    if (undo == null) throw StateError('Undo unavailable');
    await undo();
    _undos.remove('$kind:$id');
  });
  Future<void> deleteMemory(String id) => _delete('memory', id);
  Future<void> deleteComparison(String id) => _delete('comparison', id);
  Future<void> restoreMemory(PriceMemory m) => restore('memory', m.id);
  Future<void> restoreComparison(SavedComparison c) =>
      restore('comparison', c.id);
  PriceMemory? memoryById(String id) {
    for (final m in memories) {
      if (m.id == id) return m;
    }
    return null;
  }

  SavedComparison? comparisonById(String id) {
    for (final c in saved) {
      if (c.id == id) return c;
    }
    return null;
  }
}
