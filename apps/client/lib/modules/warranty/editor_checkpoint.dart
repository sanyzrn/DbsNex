import 'dart:async';
import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';
import 'form_draft.dart';

/// The checkpoint is separate from saved records and retains raw input.
class EditorCheckpoint {
  EditorCheckpoint(
    this.store,
    this.kind,
    this.existing,
    this.fields,
    this.extra,
    this.applyExtra,
    this.repaint,
  ) : id = existing?.id ?? store.newId(),
      initial = {for (final e in fields.entries) e.key: e.value.text};
  final NexModuleStore store;
  final String kind;
  final ModuleRecord? existing;
  final Map<String, TextEditingController> fields;
  final Map<String, Object?> Function() extra;
  final void Function(Map<String, Object?>) applyExtra;
  final VoidCallback repaint;
  final Map<String, String> initial;
  final String id;
  late final Map<String, Object?> initialExtra = Map.of(extra());
  Map<String, Object?> get _base {
    if (existing == null) return kind == 'claim' ? Map.of(extra()) : {};
    final nonEditable = {'archived'};
    final version = existing!.body['v'];
    if (version == 1 || version == 2) nonEditable.add('v');
    return {
      for (final e in existing!.body.entries)
        if (!nonEditable.contains(e.key)) e.key: e.value,
    };
  }

  String get _draftId => kind == 'claim'
      ? 'claim:${extra()['parentId']}:${extra()['kind']}:new'
      : '$kind:${existing?.id ?? 'new'}';
  late final FormDraft draft = FormDraft(
    store,
    _draftId,
    _base,
    fields,
    () => {
      ...extra(),
      'recordId': recordId,
      'initialFields': initial,
      'initialExtra': initialExtra,
    },
  );

  bool loading = true;
  bool failed = false;
  bool busy = false;
  bool disposed = false;
  bool _reading = false;
  Future<void> load() async {
    if (_reading || disposed) {
      return;
    }
    _reading = true;
    loading = true;
    repaint();
    initialExtra; // Capture choices before applying a saved draft.
    final saved = await draft.load();
    _reading = false;
    if (disposed) {
      return;
    }
    failed = draft.loadFailed;
    if (saved != null && !failed) {
      final target = saved['recordId'];
      // Stable identity of a resumed new entry.
      if (existing == null && target is String && target.isNotEmpty) {
        _resumedId = target;
      }
      final origins = saved['initialFields'];
      for (final e in fields.entries) {
        final value = saved[e.key];
        final origin = origins is Map ? origins[e.key] : null;
        // Restore edits, but retain fresh fields the user had not changed.
        if (value is String &&
            (origin is! String ||
                value != origin ||
                initial[e.key] == origin)) {
          e.value.text = value;
        }
      }
      applyExtra(saved);
    }
    loading = false;
    if (!failed) draft.resume();
    repaint();
  }

  String? _resumedId;
  String get recordId => _resumedId ?? id;
  List<String> editedKeys(
    Map<String, Object?> body,
    Map<String, List<String>> groups,
  ) {
    if (existing == null) {
      return {...body.keys, ...groups.keys}.toList();
    }
    return [
      for (final e in groups.entries)
        if (e.value.any(
          (key) => fields.containsKey(key)
              ? fields[key]!.text != initial[key]
              : !LocalComparison.same(extra()[key], initialExtra[key]),
        ))
          e.key,
    ];
  }

  static Map<String, Object?> merge(
    Map<String, Object?> raw,
    Map<String, Object?> body,
    List<String> keys,
  ) {
    final result = Map<String, Object?>.of(raw);
    for (final key in keys) {
      if (body.containsKey(key)) {
        result[key] = body[key];
      } else {
        result.remove(key);
      }
    }
    return result;
  }

  void changed() {
    if (!loading && !failed) draft.changed();
  }

  Future<bool> discard() => draft.clear();
  void dispose() {
    disposed = true;
    draft.close();
  }
}

class LocalComparison {
  static bool same(Object? a, Object? b) => a.toString() == b.toString();
}

/// Save is completed inside the editor. Failed reads cannot replace a draft.
class CheckpointFrame extends StatefulWidget {
  const CheckpointFrame({
    super.key,
    required this.session,
    required this.strings,
    required this.child,
    this.checkpointBack = false,
  });
  final EditorCheckpoint session;
  final NexModuleStrings strings;
  final Widget child;
  final bool checkpointBack;
  @override
  State<CheckpointFrame> createState() => _CheckpointFrameState();
}

class _CheckpointFrameState extends State<CheckpointFrame> {
  bool _closing = false;
  Future<void> _leave() async {
    if (_closing || widget.session.busy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _closing = true);
    final kept = await widget.session.draft.finish();
    if (!mounted) return;
    if (kept) {
      Navigator.of(context).pop();
    } else {
      if (!widget.session.failed) widget.session.draft.resume();
      setState(() => _closing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.strings(context, 'saveFailed'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: widget.checkpointBack ? false : !widget.session.busy,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && widget.checkpointBack) unawaited(_leave());
    },
    child: widget.session.loading
        ? const Center(child: CircularProgressIndicator())
        : widget.session.failed
        ? Padding(
            padding: const EdgeInsets.all(NexSpacing.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.strings(context, 'loadFailed')),
                TextButton(
                  onPressed: () => unawaited(widget.session.load()),
                  child: Text(widget.strings(context, 'retry')),
                ),
              ],
            ),
          )
        : AbsorbPointer(
            absorbing: _closing || widget.session.busy,
            child: widget.child,
          ),
  );
}
