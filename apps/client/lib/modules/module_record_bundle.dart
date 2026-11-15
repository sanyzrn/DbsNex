import 'nex_module_store.dart';

/// A captured group of records and the means to put it back or take it out
/// whole — what a module's Undo runs. Raw bodies preserve unknown fields and
/// malformed historical values.
class NexModuleRecordBundle {
  NexModuleRecordBundle(this.store, this.records);
  static final Expando<bool> _busy = Expando<bool>();
  final NexModuleStore store;
  final List<({String kind, String id, Map<String, Object?> body})> records;

  /// Captures [id] of [kind], every record of [children] that points at it
  /// through [parentField], its edit draft, and — through [also], which is
  /// what a habit's reminder setting needed before the platform bundle
  /// learned this and was forked wholesale — any further single records.
  static Future<NexModuleRecordBundle> capture(
    NexModuleStore store,
    String kind,
    String id,
    String children,
    String parentField, {
    List<({String kind, String id})> also = const [],
  }) async {
    final parent = await store.get(kind, id);
    final dependent = await store.list(children);
    final draft = await store.get('draft', '$kind:$id');
    final beside = [
      for (final one in also)
        if (one.id.isNotEmpty)
          (kind: one.kind, id: one.id, body: await store.get(one.kind, one.id)),
    ];
    return NexModuleRecordBundle(store, [
      for (final record in dependent)
        if (record.body[parentField] == id)
          (kind: children, id: record.id, body: Map.of(record.body)),
      if (draft != null) (kind: 'draft', id: '$kind:$id', body: Map.of(draft)),
      for (final beside in beside)
        if (beside.body != null)
          (kind: beside.kind, id: beside.id, body: Map.of(beside.body!)),
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

  /// Replays the journals older versions left behind: their deletes ran one
  /// record at a time, and a crash between them is what a journal was for.
  /// A delete written by this version leaves none.
  static Future<void> recover(NexModuleStore store) async {
    if (_busy[store] == true) return;
    _busy[store] = true;
    try {
      for (final operation in await store.list('operation')) {
        final raw = operation.body['records'];
        if (operation.body['v'] != 1 || raw is! List) {
          await store.quarantine(operation);
          continue;
        }
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
        if (records.length != raw.length ||
            records.isEmpty ||
            records.any(
              (r) =>
                  r.kind.isEmpty ||
                  r.id.isEmpty ||
                  r.kind == 'operation' ||
                  r.kind == '__recovery',
            )) {
          await store.quarantine(operation);
          continue;
        }
        await NexModuleRecordBundle(store, records).restore();
        await store.delete('operation', operation.id);
      }
    } finally {
      _busy[store] = false;
    }
  }

  /// Deletes every captured record in one storage transaction. A failure or
  /// a crash leaves all of them exactly where they were — which is what the
  /// journal-and-compensate dance this replaces could only approximate from
  /// the client side, one delete at a time.
  Future<void> delete() async {
    if (records.isEmpty) return;
    _busy[store] = true;
    try {
      await store.deleteRecords([
        for (final record in records) (kind: record.kind, id: record.id),
      ]);
    } finally {
      _busy[store] = false;
    }
  }
}
