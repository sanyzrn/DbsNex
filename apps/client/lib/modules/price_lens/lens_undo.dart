import 'package:flutter/material.dart';

/// The time a deletion stays reversible — a plain data value, not a
/// motion token; Nex's own capsule notices are unavailable to a module
/// (see README Platform requests), so this is a standard SnackBar.
const maintenanceUndoWindow = Duration(seconds: 6);

/// Offers Undo for a deletion, in the screen's own
/// [ScaffoldMessengerState] — captured **before** the editor sheet
/// pops, because the sheet's context does not outlive its route.
///
/// The words and the restore closure are captured with it, so nothing
/// touches a context across an async gap. The restore rewrites exactly
/// the record that was there: an Undo is as good as the deletion never
/// having happened.
class LensUndo {
  LensUndo._();
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
              duration: maintenanceUndoWindow,
              action: SnackBarAction(label: undoLabel, onPressed: attempt),
            ),
          );
        }
      }
    }

    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: maintenanceUndoWindow,
        action: SnackBarAction(label: undoLabel, onPressed: attempt),
      ),
    );
  }
}
