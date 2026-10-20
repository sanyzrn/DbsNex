import 'package:flutter/material.dart';
import 'package:nex_client/modules/module_api.dart';

import 'controller.dart';
import 'logic.dart';
import 'maintenance_undo.dart';
import 'service_history.dart';
import 'models.dart';
import 'strings.dart';
import 'editor_draft.dart';

/// The asset page's long menu: archive, unarchive and delete.
///
/// Deleting asks once, then offers Undo that restores the asset with
/// every event and rule it had — captured before anything is removed.
Future<void> assetPageMenu(
  BuildContext context, {
  required String action,
  required MaintenanceController controller,
  required MaintenanceAsset asset,
  required List<ServiceEvent> events,
  required List<RuleStanding> standings,
}) async {
  final s = maintenanceStrings;
  try {
    switch (action) {
      case 'archive':
        final answer = await _confirm(
          context,
          s(context, 'archiveTitle'),
          s(context, 'archiveBody'),
          s(context, 'archive'),
        );
        if (answer != true || !context.mounted) return;
        // The words and the messenger are captured before the write, so
        // nothing reaches across an async gap.
        final messenger = ScaffoldMessenger.of(context);
        final message = s(context, 'archivedAsset');
        final undoLabel = s(context, 'undo');
        final failure = s(context, 'undoFailed');
        await controller.setArchived(asset, true);
        if (!context.mounted) return;
        // The page stays open; the notice says what happened, and Undo
        // un-archives in one guarded tap (unarchive remains in the
        // menu for later).
        MaintenanceUndo.offer(
          messenger,
          message: message,
          undoLabel: undoLabel,
          failureMessage: failure,
          restore: () => controller.setArchived(asset, false),
        );
      case 'unarchive':
        await controller.setArchived(asset, false);
      case 'copyHistory':
        final text = serviceHistoryText(context, asset, events);
        final copied = s(context, 'historyCopied');
        await nexModuleCopyText(text);
        if (context.mounted) nexShowBanner(context, message: copied);
      case 'shareHistory':
        await nexModuleShareText(serviceHistoryText(context, asset, events));
      case 'delete':
        final answer = await _confirm(
          context,
          s(context, 'deleteAssetTitle'),
          s(context, 'deleteAssetBody', {
            'n': events.length,
            'm': standings.length,
          }),
          s(context, 'delete'),
        );
        if (answer != true || !context.mounted) return;
        final snapshot = controller.snapshotOf(asset.id);
        final messenger = ScaffoldMessenger.of(context);
        final message = s(context, 'deletedAsset');
        final undoLabel = s(context, 'undo');
        final failure = s(context, 'undoFailed');
        await controller.deleteAsset(asset.id);
        if (context.mounted) {
          Navigator.pop(context);
          MaintenanceUndo.offer(
            messenger,
            message: message,
            undoLabel: undoLabel,
            failureMessage: failure,
            restore: () => controller.restoreAsset(
              snapshot.asset,
              snapshot.events,
              snapshot.rules,
            ),
          );
        }
    }
  } catch (_) {
    if (context.mounted) maintenanceWriteFailure(context);
  }
}

Future<bool> _confirm(
  BuildContext context,
  String title,
  String body,
  String confirmWord,
) async {
  final answer = await nexShowDialog<String>(
    context: context,
    builder: (dialogContext) => NexAlertDialog(
      title: Text(title),
      content: NexDialogBody(child: Text(body)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(maintenanceStrings(dialogContext, 'cancel')),
        ),
        TextButton(
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(dialogContext).colorScheme.error,
          ),
          onPressed: () => Navigator.pop(dialogContext, 'yes'),
          child: Text(confirmWord),
        ),
      ],
    ),
  );
  return answer == 'yes';
}
