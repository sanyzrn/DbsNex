import 'package:flutter/material.dart';
import 'medicine_strings.dart';
import 'package:nex_client/modules/module_api.dart';

/// The questions the medicine screens ask, in one place, all through
/// `nexShowDialog`: the cancelling action first, the destructive one in
/// the error colour, one question per dialog.
class MedicineDialogs {
  const MedicineDialogs._();

  /// «Delete {name}?» — true to go ahead.
  static Future<bool?> confirmDelete(
    BuildContext context,
    NexModuleStrings strings,
    String name,
  ) => nexShowDialog<bool>(
    context: context,
    builder: (dialogContext) => NexAlertDialog(
      title: Text(strings(dialogContext, 'deleteMedicine', {'name': name})),
      content: NexDialogBody(
        child: Text(strings(dialogContext, 'deleteMedicineBody')),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(AppLocalizations.of(dialogContext).cancel),
        ),
        TextButton(
          key: const ValueKey('medicine-delete-confirm'),
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(dialogContext).colorScheme.error,
          ),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(AppLocalizations.of(dialogContext).delete),
        ),
      ],
    ),
  );

  /// «Archive {name}?» — true to archive.
  static Future<bool?> confirmArchive(
    BuildContext context,
    NexModuleStrings strings,
    String name,
  ) => nexShowDialog<bool>(
    context: context,
    builder: (dialogContext) => NexAlertDialog(
      title: Text(strings(dialogContext, 'archiveMedicine', {'name': name})),
      content: NexDialogBody(
        child: Text(strings(dialogContext, 'archiveBody')),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(AppLocalizations.of(dialogContext).cancel),
        ),
        TextButton(
          key: const ValueKey('medicine-archive-confirm'),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(strings(dialogContext, 'archived')),
        ),
      ],
    ),
  );

  /// A medicine name that is already on the list: keep both, or stop and
  /// edit what is written? True keeps both; null backs out.
  static Future<bool?> askDuplicate(
    BuildContext context,
    NexModuleStrings strings,
    String name,
  ) => nexShowDialog<bool>(
    context: context,
    builder: (dialogContext) => NexAlertDialog(
      title: Text(strings(dialogContext, 'duplicateName')),
      content: NexDialogBody(
        child: Text(strings(dialogContext, 'deleteMedicine', {'name': name})),
      ),
      actions: [
        TextButton(
          key: const ValueKey('medicine-duplicate-cancel'),
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(AppLocalizations.of(dialogContext).cancel),
        ),
        TextButton(
          key: const ValueKey('medicine-duplicate-keep'),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(strings(dialogContext, 'keepBoth')),
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
          key: const ValueKey('medicine-stay'),
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(strings(dialogContext, 'keepWriting')),
        ),
        TextButton(
          key: const ValueKey('medicine-discard'),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(strings(dialogContext, 'discard')),
        ),
      ],
    ),
  );

  /// A time-limited Undo for whatever was just removed. The [undoLabel]
  /// is taken before the write, not from a context that may have gone.
  static void offerUndo(
    ScaffoldMessengerState messenger,
    String message,
    String undoLabel,
    Future<void> Function() restore,
  ) {
    // One at a time: a new question replaces the one still on screen.
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(
          key: const ValueKey('medicine-undo'),
          label: undoLabel,
          onPressed: () async {
            try {
              await restore();
            } catch (_) {
              if (messenger.mounted) {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      medicineStrings(messenger.context, 'undoFailed'),
                    ),
                  ),
                );
              }
            }
          },
        ),
      ),
    );
  }
}
