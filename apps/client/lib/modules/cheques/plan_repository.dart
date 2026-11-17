import 'dart:convert';

import 'package:nex_client/modules/module_api.dart';

import 'plan_model.dart';
import 'repository.dart';
import 'values.dart';
import 'money_format.dart' show maxMoney;

class PlanRepository {
  PlanRepository(this.store);
  final NexModuleStore store;
  Future<void> _tail = Future.value();
  Future<T> serial<T>(Future<T> Function() f) {
    final n = _tail.then((_) => f());
    _tail = n.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return n;
  }

  Future<void> fresh(String id, Map<String, Object?>? expected) async {
    if (jsonEncode(await store.get('plan', id)) != jsonEncode(expected)) {
      throw const ChequeFailure('conflict');
    }
  }

  Future<InstalmentPlan> save(
    String id,
    Map<String, Object?>? expected,
    Map<String, Object?> fields,
  ) => serial(() async {
    await fresh(id, expected);
    final amount = chequeAmount(fields['totalRial'] ?? expected?['totalRial']);
    final before = fields['beforeDays'] ?? expected?['beforeDays'];
    if (amount != null &&
            amount > BigInt.from(maxMoney) &&
            amount != chequeAmount(expected?['totalRial']) ||
        !{1, 3, 7, 14, 30}.contains(before) &&
            before != expected?['beforeDays']) {
      throw const ChequeFailure('validation');
    }
    final p = InstalmentPlan(id, {
      ...?expected,
      ...fields,
      'v': 1,
      'totalRial': storedRials(fields['totalRial'] ?? expected?['totalRial']),
      'paid': expected?['paid'] ?? <String, Object?>{},
    });
    if (!p.valid || p.date(p.count - 1).year > 2100) {
      throw const ChequeFailure('validation');
    }
    if (expected != null &&
        (expected['paid'] as Map).isNotEmpty &&
        ['totalRial', 'count', 'months', 'first', 'calendar'].any(
          (k) => k == 'totalRial'
              ? chequeAmount(p.raw[k]) != chequeAmount(expected[k])
              : p.raw[k] != expected[k],
        )) {
      throw const ChequeFailure('locked');
    }
    await store.put('plan', id, p.raw);
    return p;
  });
  Future<InstalmentPlan> toggle(InstalmentPlan p, int index) =>
      serial(() async {
        await fresh(p.id, p.raw);
        if (!p.valid || index < 0 || index >= p.count) {
          throw const ChequeFailure('validation');
        }
        final paid = Map<String, Object?>.from(p.raw['paid'] as Map);
        if (paid.containsKey('$index')) {
          paid.remove('$index');
        } else {
          paid['$index'] = chequeDayKey(DateTime.now());
        }
        final updated = InstalmentPlan(p.id, {...p.raw, 'paid': paid});
        await store.put('plan', p.id, updated.raw);
        return updated;
      });
  Future<Map<String, Object?>> delete(InstalmentPlan p) => serial(() async {
    await fresh(p.id, p.raw);
    await store.deleteRecords([
      (kind: 'plan', id: p.id),
      (kind: 'draft', id: 'plan:${p.id}'),
    ]);
    return p.raw;
  });
  Future<void> restore(String id, Map<String, Object?> raw) => serial(() async {
    if (await store.get('plan', id) != null) {
      throw const ChequeFailure('conflict');
    }
    await store.put('plan', id, raw);
  });
}
