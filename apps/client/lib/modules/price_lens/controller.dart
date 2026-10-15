import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:nex_client/modules/module_api.dart';
import 'options.dart';
import 'units.dart';
import 'local_writes.dart';

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
      ]);
      if (_disposed || token != _loadToken) return;
      memories = [
        for (final row in result[0])
          if (PriceMemory.fromBody(row.id, row.body) case final memory?) memory,
      ];
      saved = [
        for (final row in result[1])
          if (SavedComparison.fromBody(row.id, row.body) case final item?) item,
      ];
      invalidMemories = [
        for (final row in result[0])
          if (PriceMemory.fromBody(row.id, row.body) == null) row,
      ];
      invalidSaved = [
        for (final row in result[1])
          if (SavedComparison.fromBody(row.id, row.body) == null) row,
      ];
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
      final merged = {...?raw, ...body};
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
      await LocalWrites.apply(store, [
        (kind: 'comparison', id: target, body: body),
      ]);
    });
  }

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
