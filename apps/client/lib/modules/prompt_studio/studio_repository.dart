import 'dart:async';
import 'dart:convert';

import 'package:nex_client/modules/module_api.dart';

import 'prompt_model.dart';

class StudioConflict implements Exception {}

/// One queue shared by every route in this module session. Fresh-body checks
/// prevent an editor or Undo overwriting a later change.
class StudioRepository {
  StudioRepository(this.store);
  final NexModuleStore store;
  Future<void> _tail = Future.value();
  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> save(
    String id,
    Map<String, Object?>? expected,
    Map<String, Object?> fields,
  ) => _serial(() async {
    final prior = await store.get('entry', id);
    if (jsonEncode(prior) != jsonEncode(expected)) throw StudioConflict();
    final changed =
        prior != null &&
        [
          'title',
          'body',
          'category',
          'notes',
        ].any((key) => prior[key] != fields[key]);
    await store.put('entry', id, {
      ...?prior,
      ...fields,
      'v': 1,
      'updatedAt': DateTime.now().toIso8601String(),
      if (changed)
        'history': [
          {...promptRevision(prior), 'at': prior['updatedAt']},
          ...(prior['history'] is List
                  ? prior['history'] as List
                  : const <Object?>[])
              .take(9),
        ],
    });
  });
  Future<Map<String, Object?>> delete(PromptEntry entry) => _serial(() async {
    final raw = await store.get('entry', entry.id);
    if (jsonEncode(raw) != jsonEncode(entry.raw)) throw StudioConflict();
    await store.delete('entry', entry.id);
    return raw!;
  });
  Future<void> undo(String id, Map<String, Object?> raw) => _serial(() async {
    if (await store.get('entry', id) != null) throw StudioConflict();
    await store.put('entry', id, raw);
  });
}
