import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'strings.dart';

/// The time a deletion stays reversible — a plain data value, not a
/// motion token; Nex's own capsule notices are unavailable to a module
/// (see README Platform requests), so this is a standard SnackBar.
const expensesUndoWindow = Duration(seconds: 6);

/// Offers Undo for a deletion, in the screen's own
/// [ScaffoldMessengerState] — captured **before** the editor sheet
/// pops, because the sheet's context does not outlive its route.
///
/// The words and the restore closure are captured with it, so nothing
/// touches a context across an async gap. The restore rewrites exactly
/// the record that was there: an Undo is as good as the deletion never
/// having happened.
class ExpensesUndo {
  ExpensesUndo._();
  static void offer(
    ScaffoldMessengerState messenger, {
    required String message,
    required String undoLabel,
    required Future<void> Function() restore,
    String? failureMessage,
  }) {
    Future<void> attempt() async {
      try {
        await restore();
      } catch (_) {
        if (messenger.mounted) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(failureMessage ?? message),
              duration: expensesUndoWindow,
              action: SnackBarAction(label: undoLabel, onPressed: attempt),
            ),
          );
        }
      }
    }

    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: expensesUndoWindow,
        action: SnackBarAction(label: undoLabel, onPressed: attempt),
      ),
    );
  }
}

/// Asks before a sheet with unsaved work is closed — shared by the
/// transaction and template editors so a stray back gesture never
/// loses what was typed.
Future<void> confirmExpensesDiscard(
  BuildContext context, {
  Future<bool> Function()? discard,
  Future<bool> Function()? keepDraft,
}) async {
  final answer = await nexShowDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(expenseStrings(dialogContext, 'discardTitle')),
      content: NexDialogBody(
        child: Text(expenseStrings(dialogContext, 'discardBody')),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, 'keep'),
          child: Text(expenseStrings(dialogContext, 'keepEditing')),
        ),
        if (keepDraft != null)
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'draft'),
            child: Text(expenseStrings(dialogContext, 'keepDraft')),
          ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, 'discard'),
          child: Text(expenseStrings(dialogContext, 'discard')),
        ),
      ],
    ),
  );
  if (answer == 'discard' || answer == 'draft') {
    final done = answer == 'draft'
        ? await keepDraft!()
        : await (discard?.call() ?? Future.value(true));
    if (context.mounted && done) Navigator.pop(context);
  }
}
