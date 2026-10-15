import 'package:flutter/material.dart';
import 'parking_strings.dart';
import 'package:nex_client/modules/module_api.dart';

/// The questions the parking screen asks, in one place, all through
/// `nexShowDialog` as the design language requires: cancelling first, the
/// destructive action in the error colour, one question per dialog.
class ParkingDialogs {
  const ParkingDialogs._();

  /// «{vehicle} is still parked. Close the earlier parking now, or keep it
  /// open?» — true closes it, false keeps it, null means the person backed
  /// out and nothing should be written.
  static Future<bool?> askAboutEarlier(
    BuildContext context,
    String vehicle,
    NexModuleStrings strings,
  ) => nexShowDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(strings(dialogContext, 'stillParkedTitle')),
      content: NexDialogBody(
        child: Text(
          strings(dialogContext, 'stillParkedBody', {
            'vehicle': vehicle.isEmpty
                ? strings(dialogContext, 'defaultVehicle')
                : vehicle,
          }),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('parking-conflict-close'),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(strings(dialogContext, 'closeEarlier')),
        ),
        TextButton(
          key: const ValueKey('parking-conflict-keep'),
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(strings(dialogContext, 'keepEarlier')),
        ),
      ],
    ),
  );

  /// «Delete this parking?» — true to go ahead.
  static Future<bool?> confirmDelete(
    BuildContext context,
    NexModuleStrings strings,
  ) => nexShowDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(strings(dialogContext, 'deleteParking')),
      content: NexDialogBody(child: Text(strings(dialogContext, 'deleteBody'))),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(AppLocalizations.of(dialogContext).cancel),
        ),
        TextButton(
          key: const ValueKey('parking-delete-confirm'),
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(dialogContext).colorScheme.error,
          ),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(AppLocalizations.of(dialogContext).delete),
        ),
      ],
    ),
  );

  /// «Clear all past parking?» — true to go ahead.
  static Future<bool?> confirmClearHistory(
    BuildContext context,
    NexModuleStrings strings,
  ) => nexShowDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(strings(dialogContext, 'clearHistoryTitle')),
      content: NexDialogBody(
        child: Text(strings(dialogContext, 'clearHistoryBody')),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(AppLocalizations.of(dialogContext).cancel),
        ),
        TextButton(
          key: const ValueKey('parking-clear-confirm'),
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(dialogContext).colorScheme.error,
          ),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(AppLocalizations.of(dialogContext).delete),
        ),
      ],
    ),
  );

  /// «Leave without saving?» — true to discard, false to keep writing.
  /// Null never happens: backing out dismisses to false.
  static Future<bool?> confirmDiscard(
    BuildContext context,
    NexModuleStrings strings,
  ) => nexShowDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(strings(dialogContext, 'discardTitle')),
      content: NexDialogBody(
        child: Text(strings(dialogContext, 'discardBody')),
      ),
      actions: [
        TextButton(
          key: const ValueKey('parking-stay'),
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(strings(dialogContext, 'keepEditing')),
        ),
        TextButton(
          key: const ValueKey('parking-discard'),
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
          key: const ValueKey('parking-undo'),
          label: undoLabel,
          onPressed: () async {
            try {
              await restore();
            } catch (_) {
              if (messenger.mounted) {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      parkingStrings(messenger.context, 'undoFailed'),
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
