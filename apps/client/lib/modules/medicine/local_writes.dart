import 'dart:async';
import 'dart:convert';
import 'package:nex_client/modules/module_api.dart';

typedef LocalChange = ({String kind, String id, Map<String, Object?>? body});

/// Serial module writes and a durable rollback journal. The public API has
/// no database transaction; a reopen repairs an interrupted operation.
class LocalWrites {
  static final Expando<Future<void>> _tails = Expando<Future<void>>();
  static Future<T> serial<T>(NexModuleStore store, Future<T> Function() run) {
    final previous = _tails[store] ?? Future<void>.value();
    final result = previous.then((_) async {
      await _recover(store);
      return run();
    });
    _tails[store] = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  static Future<void> recover(NexModuleStore store) =>
      serial(store, () async {});
  static bool same(Object? a, Object? b) => jsonEncode(a) == jsonEncode(b);
  static Future<void> _write(NexModuleStore store, LocalChange change) =>
      change.body == null
      ? store.delete(change.kind, change.id)
      : store.put(change.kind, change.id, change.body!);
  static Map<String, Object?> _encoded(LocalChange c) => {
    'kind': c.kind,
    'id': c.id,
    'body': c.body,
  };
  static LocalChange _decoded(Object? raw) {
    if (raw is! Map ||
        raw['kind'] is! String ||
        raw['id'] is! String ||
        !raw.containsKey('body') ||
        (raw['body'] != null && raw['body'] is! Map)) {
      throw StateError('Invalid journal');
    }
    return (
      kind: raw['kind'] as String,
      id: raw['id'] as String,
      body: raw['body'] == null
          ? null
          : Map<String, Object?>.from(raw['body'] as Map),
    );
  }

  static Future<void> _recover(NexModuleStore store) async {
    for (final op in await store.list('operation')) {
      List<LocalChange> before;
      try {
        if (op.body['v'] != 1 ||
            op.body['before'] is! List ||
            (op.body.containsKey('committed') &&
                op.body['committed'] is! bool)) {
          throw const FormatException('Unknown operation');
        }
        before = (op.body['before'] as List).map(_decoded).toList();
        if (before.any(
          (c) =>
              c.kind == 'operation' ||
              c.kind == '__recovery' ||
              c.kind.isEmpty ||
              c.id.isEmpty,
        )) {
          throw const FormatException('Invalid recovery target');
        }
      } catch (_) {
        await store.quarantine(op);
        continue;
      }
      if (op.body['committed'] != true) {
        for (final change in before.reversed) {
          await _write(store, change);
        }
      }
      await store.delete('operation', op.id);
    }
  }

  /// Called INSIDE serial. Returns a guarded Undo that refuses to overwrite
  /// any subsequent change to the affected records.
  static Future<Future<void> Function()> apply(
    NexModuleStore store,
    List<LocalChange> after,
  ) async {
    final before = <LocalChange>[
      for (final c in after)
        (kind: c.kind, id: c.id, body: await store.get(c.kind, c.id)),
    ];
    final id = store.newId();
    final journal = {'v': 1, 'before': before.map(_encoded).toList()};
    try {
      await store.put('operation', id, journal);
      for (final c in after) {
        await _write(store, c);
      }
      await store.put('operation', id, {...journal, 'committed': true});
    } catch (_) {
      // A write can throw after committing. Respect a durable commit marker.
      final stored = await store.get('operation', id);
      if (stored?['committed'] != true) {
        if (stored != null) {
          for (final c in before.reversed) {
            await _write(store, c);
          }
          await store.delete('operation', id);
        }
        rethrow;
      }
    }
    try {
      await store.delete('operation', id);
    } catch (_) {
      // Committed marker is authoritative; recover only cleans it.
    }
    return () => serial(store, () async {
      for (final c in after) {
        if (!same(await store.get(c.kind, c.id), c.body)) {
          throw StateError('Undo conflicts with a later change');
        }
      }
      await apply(store, before.reversed.toList());
    });
  }

  static Future<Future<void> Function()> delete(
    NexModuleStore store,
    String kind,
    String id, {
    String? children,
    String? parentField,
  }) => serial(store, () async {
    final parent = await store.get(kind, id);
    if (parent == null) {
      throw StateError('Record no longer exists');
    }
    final after = <LocalChange>[
      if (children != null)
        for (final r in await store.list(children))
          if (r.body[parentField] == id) (kind: children, id: r.id, body: null),
      (kind: 'draft', id: '$kind:$id', body: null),
      (kind: kind, id: id, body: null),
    ];
    return apply(store, after);
  });
  static Future<void> patch(
    NexModuleStore store,
    String kind,
    String id,
    Map<String, Object?> fields,
  ) => serial(store, () async {
    final raw = await store.get(kind, id);
    if (raw == null) {
      throw StateError('Record no longer exists');
    }
    await apply(store, [
      (kind: kind, id: id, body: {...raw, ...fields}),
    ]);
  });
}
