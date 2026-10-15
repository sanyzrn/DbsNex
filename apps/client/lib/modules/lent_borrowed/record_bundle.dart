import 'package:nex_client/modules/module_api.dart';

/// Raw bodies preserve unknown fields and malformed historical values in Undo.
class RecordBundle {
  RecordBundle(this.store, this.records);
  static final Expando<bool> _busy = Expando<bool>();
  final NexModuleStore store;
  final List<({String kind, String id, Map<String, Object?> body})> records;

  static Future<RecordBundle> capture(
    NexModuleStore store,
    String kind,
    String id,
    String children,
    String parentField,
  ) async {
    final parent = await store.get(kind, id);
    final dependent = await store.list(children);
    final draft = await store.get('draft', '$kind:$id');
    return RecordBundle(store, [
      for (final record in dependent)
        if (record.body[parentField] == id)
          (kind: children, id: record.id, body: Map.of(record.body)),
      if (draft != null) (kind: 'draft', id: '$kind:$id', body: Map.of(draft)),
      if (parent != null) (kind: kind, id: id, body: Map.of(parent)),
    ]);
  }

  Future<void> restore() async {
    for (final record in records) {
      await store.put(record.kind, record.id, record.body);
    }
    if (records.isNotEmpty) await store.delete('operation', _journalId);
  }

  String get _journalId => '${records.last.kind}:${records.last.id}';

  /// Incomplete deletion is rolled back after a crash or a storage failure.
  static Future<void> recover(NexModuleStore store) async {
    if (_busy[store] == true) return;
    _busy[store] = true;
    try {
      for (final operation in await store.list('operation')) {
        final raw = operation.body['records'];
        if (raw is! List) continue;
        final records =
            <({String kind, String id, Map<String, Object?> body})>[];
        for (final entry in raw) {
          if (entry is! Map ||
              entry['kind'] is! String ||
              entry['id'] is! String ||
              entry['body'] is! Map) {
            continue;
          }
          final body = entry['body'] as Map;
          if (body.keys.any((key) => key is! String)) continue;
          records.add((
            kind: entry['kind'] as String,
            id: entry['id'] as String,
            body: {for (final key in body.keys) key as String: body[key]},
          ));
        }
        if (records.length != raw.length || records.isEmpty) continue;
        await RecordBundle(store, records).restore();
        await store.delete('operation', operation.id);
      }
    } finally {
      _busy[store] = false;
    }
  }

  Future<void> delete() async {
    if (records.isEmpty) return;
    _busy[store] = true;
    try {
      await store.put('operation', _journalId, {
        'v': 1,
        'records': [
          for (final r in records) {'kind': r.kind, 'id': r.id, 'body': r.body},
        ],
      });
      for (final record in records) {
        await store.delete(record.kind, record.id);
      }
      await store.delete('operation', _journalId);
    } catch (_) {
      // The API has no transaction. Compensate before reporting a failed delete.
      await restore();
      rethrow;
    } finally {
      _busy[store] = false;
    }
  }
}
