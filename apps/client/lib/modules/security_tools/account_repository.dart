import 'dart:async';
import 'dart:convert';

import 'package:nex_client/modules/module_api.dart';

import 'account_model.dart';

class SecurityConflict implements Exception {}

class AccountRepository {
  AccountRepository(this.store);
  final NexModuleStore store;
  Future<void> _tail = Future.value();
  Future<T> _queue<T>(Future<T> Function() action) {
    final next = _tail.then((_) => action());
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<void> save(
    String id,
    Map<String, Object?>? expected,
    String label,
    Map<String, String> updates,
  ) => _queue(() async {
    final raw = await store.get('account', id);
    if (jsonEncode(raw) != jsonEncode(expected)) throw SecurityConflict();
    if (label.trim().isEmpty ||
        label.length > 60 ||
        updates.entries.any(
          (e) =>
              !securityChecks.contains(e.key) || !checkStates.contains(e.value),
        )) {
      throw ArgumentError('invalid checklist');
    }
    final priorChecks = raw?['checks'];
    await store.put('account', id, {
      ...?raw,
      'v': 1,
      'label': label.trim(),
      'checks': {
        if (priorChecks is Map)
          for (final e in priorChecks.entries)
            if (e.key is String) e.key as String: e.value,
        ...updates,
      },
    });
  });
  Future<Map<String, Object?>> delete(SecurityAccount account) => _queue(
    () async {
      final raw = await store.get('account', account.id);
      if (jsonEncode(raw) != jsonEncode(account.raw)) throw SecurityConflict();
      await store.delete('account', account.id);
      return raw!;
    },
  );
  Future<void> undo(String id, Map<String, Object?> raw) => _queue(() async {
    if (await store.get('account', id) != null) throw SecurityConflict();
    await store.put('account', id, raw);
  });
}
