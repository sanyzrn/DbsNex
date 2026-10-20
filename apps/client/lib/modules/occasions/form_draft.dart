import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:nex_client/modules/module_api.dart';

/// A draft uses a separate record kind and is never counted as saved data.
/// Serial writes coalesce rapid typing; closing an editor drains the newest
/// snapshot. A baseline fingerprint prevents stale edit drafts overriding a
/// record that has since been saved or changed elsewhere.
class FormDraft {
  FormDraft(this.store, this.id, this.base, this.controllers, this.extra);
  final NexModuleStore store;
  final String id;
  final Map<String, Object?> base;
  final Map<String, TextEditingController> controllers;
  final Map<String, Object?> Function() extra;
  Future<void> _tail = Future.value();
  Map<String, Object?>? _pending;
  bool _draining = false;
  Timer? _debounce;
  bool _closed = false;
  bool _started = false;
  String? _lastSnapshot;

  Future<Map<String, Object?>?> load() async {
    try {
      final body = await store.get('draft', id);
      if (body == null ||
          body['discarded'] == true ||
          body['base'] != jsonEncode(base)) {
        return null;
      }
      final raw = body['fields'];
      if (raw is! Map) return null;
      final recordId = raw['recordId'];
      if (id.endsWith(':new') &&
          recordId is String &&
          await store.get(id.split(':').first, recordId) != null) {
        return null;
      }
      return {
        for (final key in raw.keys)
          if (key is String) key: raw[key],
      };
    } catch (_) {
      return null;
    }
  }

  void start() {
    if (_closed) return;
    _started = true;
    for (final controller in controllers.values) {
      controller.addListener(changed);
    }
  }

  void changed() {
    if (_closed || !_started) return;
    final snapshot = <String, Object?>{
      'v': 1,
      'base': jsonEncode(base),
      'fields': {
        for (final entry in controllers.entries) entry.key: entry.value.text,
        ...extra(),
      },
    };
    final encoded = jsonEncode(snapshot);
    if (encoded == _lastSnapshot) {
      return;
    }
    _lastSnapshot = encoded;
    _pending = snapshot;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _drain);
  }

  void _drain() {
    _debounce?.cancel();
    _debounce = null;
    if (_draining || _pending == null) return;
    _draining = true;
    _tail = _tail
        .then((_) async {
          try {
            var retries = 0;
            while (_pending != null) {
              final body = _pending!;
              _pending = null;
              try {
                await store.put('draft', id, body);
              } catch (_) {
                // Prefer a newer queued edit, even if the form has closed.
                _pending ??= body;
                if (retries++ >= 1) rethrow;
              }
            }
          } finally {
            _draining = false;
          }
        })
        .catchError((Object _) {
          _draining = false;
          _lastSnapshot = null;
        });
  }

  void _detach() {
    for (final controller in controllers.values) {
      controller.removeListener(changed);
    }
  }

  /// Save/discard removes the checkpoint after all older writes finish.
  Future<void> clear() async {
    _closed = true;
    _detach();
    _debounce?.cancel();
    _debounce = null;
    _pending = null;
    await _tail;
    try {
      await store.delete('draft', id);
    } catch (_) {
      // A successful final record remains authoritative if cleanup fails.
      try {
        await store.put('draft', id, {'v': 1, 'discarded': true});
      } catch (_) {
        /* A failed store cannot acknowledge cleanup. */
      }
    }
  }

  /// Back/swipe keeps the draft. Snapshot before controllers are disposed.
  void close() {
    changed();
    _closed = true;
    _detach();
    _drain();
  }

  Future<bool> finish() async {
    close();
    await _tail;
    return _pending == null;
  }

  void resume() {
    _closed = false;
    _lastSnapshot = null;
    start();
  }

  void apply(Map<String, Object?> body) {
    for (final entry in controllers.entries) {
      final value = body[entry.key];
      if (value is String) entry.value.text = value;
    }
  }
}
