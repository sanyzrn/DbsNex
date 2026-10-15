import 'dart:async';
import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';
import 'form_draft.dart';
import 'strings.dart';

/// Raw checkpoints do not enter totals; failed reads never replace a draft.
class ExpenseEditorDraft {
  ExpenseEditorDraft({
    required this.store,
    required this.kind,
    required this.fields,
    required this.extra,
    required this.applyExtra,
    required this.repaint,
    String? existingId,
    Map<String, Object?>? base,
    String? scope,
    String? target,
  }) {
    recordId = target ?? existingId ?? store.newId();
    draftId = scope ?? '$kind:${existingId ?? 'new'}';
    draft = FormDraft(
      store,
      draftId,
      base ?? {},
      fields,
      () => {...extra(), 'recordId': recordId},
    );
  }
  final NexModuleStore store;
  final String kind;
  final Map<String, TextEditingController> fields;
  final Map<String, Object?> Function() extra;
  final void Function(Map<String, Object?>) applyExtra;
  final VoidCallback repaint;
  late final FormDraft draft;
  late final String draftId;
  late String recordId;
  bool writeFailed = false;
  bool loading = true, failed = false, disposed = false, _reading = false;
  Future<void> load() async {
    if (_reading || disposed) return;
    _reading = true;
    loading = true;
    repaint();
    final body = await draft.load();
    _reading = false;
    if (disposed) return;
    failed = draft.loadFailed;
    if (!failed && body != null) {
      if (body['recordId'] is String &&
          (body['recordId'] as String).isNotEmpty) {
        recordId = body['recordId'] as String;
      }
      draft.apply(body);
      applyExtra(body);
    }
    loading = false;
    if (!failed) draft.resume();
    repaint();
  }

  void changed() {
    if (!loading && !failed) draft.changed();
  }

  Future<bool> finish() => draft.finish();
  void resume() {
    if (!failed) draft.resume();
  }

  void dispose() {
    disposed = true;
    draft.close();
  }
}

class ExpensesDraftFrame extends StatelessWidget {
  const ExpensesDraftFrame({
    super.key,
    required this.session,
    required this.child,
    required this.busy,
  });
  final ExpenseEditorDraft session;
  final Widget child;
  final bool busy;
  @override
  Widget build(BuildContext context) => session.loading
      ? const Padding(
          padding: EdgeInsets.all(NexSpacing.md),
          child: Center(child: CircularProgressIndicator()),
        )
      : session.failed
      ? Padding(
          padding: const EdgeInsets.all(NexSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(expenseStrings(context, 'loadFailed')),
              TextButton(
                onPressed: () => unawaited(session.load()),
                child: Text(expenseStrings(context, 'retry')),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(expenseStrings(context, 'cancel')),
              ),
            ],
          ),
        )
      : Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (session.writeFailed)
              Padding(
                padding: const EdgeInsets.all(NexSpacing.sm),
                child: Text(
                  expenseStrings(context, 'saveFailed'),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            Flexible(
              child: AbsorbPointer(absorbing: busy, child: child),
            ),
          ],
        );
}

void expenseWriteFailure(BuildContext context) => ScaffoldMessenger.of(
  context,
).showSnackBar(SnackBar(content: Text(expenseStrings(context, 'saveFailed'))));
