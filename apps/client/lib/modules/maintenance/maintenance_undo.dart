import 'package:nex_client/modules/module_api.dart';

/// The time a deletion stays reversible — a plain data value, not a
/// motion token; shared with the app’s top capsule.
const maintenanceUndoWindow = Duration(seconds: 6);

/// Offers Undo for a deletion, in the screen's own
/// [NexBannerHost] — captured **before** the editor sheet
/// pops, because the sheet's context does not outlive its route.
///
/// The words and the restore closure are captured with it, so nothing
/// touches a context across an async gap. The restore rewrites exactly
/// the record that was there: an Undo is as good as the deletion never
/// having happened.
class MaintenanceUndo {
  MaintenanceUndo._();
  static void offer(
    NexBannerHost? messenger, {
    required String message,
    required String undoLabel,
    required Future<void> Function() restore,
    String? failureMessage,
  }) {
    Future<void> attempt() async {
      try {
        await restore();
      } catch (_) {
        if ((messenger?.mounted ?? false)) {
          messenger?.show(
            kind: NexBannerKind.failed,
            message: failureMessage ?? message,
            duration: maintenanceUndoWindow,
            actionLabel: undoLabel,
            onAction: attempt,
          );
        }
      }
    }

    messenger?.show(
      message: message,
      duration: maintenanceUndoWindow,
      actionLabel: undoLabel,
      onAction: attempt,
    );
  }
}
