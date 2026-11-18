import 'dart:convert';

import 'package:nex_client/modules/module_api.dart';

import 'model.dart';
import 'valuation.dart';

class AssetLedger {
  AssetLedger(this.store);
  final NexModuleStore store;
  late Valuation valuation;
  List<AssetGoal> goals = [];
  bool damaged = false;

  Future<void> load() async {
    final sets = await Future.wait([
      store.list('holding'),
      store.list('quote'),
      store.list('goal'),
    ]);
    final holdings = sets[0].map(Holding.read).nonNulls.toList();
    final quotes = sets[1].map(Quote.read).nonNulls.toList();
    goals = sets[2].map(AssetGoal.read).nonNulls.toList();
    valuation = Valuation(holdings, quotes, DateTime.now());
    damaged =
        holdings.length + quotes.length + goals.length !=
        sets.fold(0, (sum, list) => sum + list.length);
  }

  bool _same(Fields? left, Fields? right) =>
      jsonEncode(left) == jsonEncode(right);

  Future<void> save(
    String kind,
    String id,
    Fields fields,
    ModuleRecord? original,
  ) async {
    final old = await store.get(kind, id);
    final next = {...?original?.body, ...fields};
    if (_same(old, next)) return;
    if (!_same(old, original?.body)) throw StateError('Entry changed');
    try {
      await store.put(kind, id, next);
    } on Object {
      if (!_same(await store.get(kind, id), next)) rethrow;
    }
  }

  Future<void> remove(ModuleRecord record) async {
    if (!_same(await store.get(record.kind, record.id), record.body)) {
      throw StateError('Entry changed');
    }
    try {
      await store.delete(record.kind, record.id);
    } on Object {
      if (await store.get(record.kind, record.id) != null) rethrow;
    }
  }

  Future<void> restore(ModuleRecord record) async {
    final current = await store.get(record.kind, record.id);
    if (_same(current, record.body)) return;
    if (current != null) throw StateError('Entry changed after deletion');
    await store.put(record.kind, record.id, record.body);
  }
}
