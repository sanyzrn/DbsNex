import 'package:flutter/material.dart';
import 'warranty_strings.dart';
import 'package:nex_client/modules/module_api.dart';

/// The questions the warranty screens ask, in one place, all through
/// `nexShowDialog`: cancelling first, the destructive one in the error
/// colour, one question per dialog.
class WarrantyDialogs {
  const WarrantyDialogs._();

  /// «Delete {name}?» — true to go ahead.
  static Future<bool?> confirmDelete(
    BuildContext context,
    NexModuleStrings strings,
    String name,
  ) => nexShowDialog<bool>(
    context: context,
    builder: (dialogContext) => NexAlertDialog(
      title: Text(strings(dialogContext, 'deleteWarranty', {'name': name})),
      content: NexDialogBody(
        child: Text(strings(dialogContext, 'deleteWarrantyBody')),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(AppLocalizations.of(dialogContext).cancel),
        ),
        TextButton(
          key: const ValueKey('warranty-delete-confirm'),
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(dialogContext).colorScheme.error,
          ),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(AppLocalizations.of(dialogContext).delete),
        ),
      ],
    ),
  );

  /// «Leave without saving?» — true to discard.
  static Future<bool?> confirmDiscard(
    BuildContext context,
    NexModuleStrings strings,
  ) => nexShowDialog<bool>(
    context: context,
    builder: (dialogContext) => NexAlertDialog(
      title: Text(strings(dialogContext, 'discardTitle')),
      content: NexDialogBody(
        child: Text(strings(dialogContext, 'discardBody')),
      ),
      actions: [
        TextButton(
          key: const ValueKey('warranty-stay'),
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(strings(dialogContext, 'keepWriting')),
        ),
        TextButton(
          key: const ValueKey('warranty-discard'),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(strings(dialogContext, 'discard')),
        ),
      ],
    ),
  );

  /// A time-limited Undo for whatever was just removed. The [undoLabel]
  /// is taken before the write, not from a context that may have gone.
  static void offerUndo(
    NexBannerHost? messenger,
    String message,
    String undoLabel,
    Future<void> Function() restore,
  ) {
    // One at a time: a new question replaces the one still on screen.
    final failureMessage = messenger == null
        ? ''
        : warrantyStrings(messenger.context, 'undoFailed');
    nexHideBanner();
    messenger?.show(
      message: message,
      actionKey: const ValueKey('warranty-undo'),
      actionLabel: undoLabel,
      onAction: () async {
        try {
          await restore();
        } catch (_) {
          if (messenger.mounted) {
            messenger.show(kind: NexBannerKind.failed, message: failureMessage);
          }
        }
      },
    );
  }
}
