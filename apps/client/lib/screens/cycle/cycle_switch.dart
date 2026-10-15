import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../platform/cycle_reminders.dart';
import '../../platform/nex_preferences.dart';
import '../../platform/nex_services.dart';
import '../../platform/reminders.dart';
import '../../widgets/nex_dialog.dart';

/// Turns «Cycle» on or off. Off asks once what to do with its data; on is
/// the switch alone. Resolves to the new state — unchanged when the person
/// backed out of the question.
Future<bool> nexSetCycleEnabled(
  BuildContext context, {
  required NexServices services,
  required NexPreferences preferences,
  required bool value,
}) async {
  if (value) {
    await preferences.setCycleEnabled(true);
    if (context.mounted) {
      await CycleReminders.apply(
        context: context,
        services: services,
        preferences: preferences,
      );
    }
    return true;
  }
  final l10n = AppLocalizations.of(context);
  final choice = await nexShowDialog<String>(
    context: context,
    builder: (dialogContext) => NexAlertDialog(
      title: Text(l10n.cycleTurnOffTitle),
      content: NexDialogBody(child: Text(l10n.cycleTurnOffBody)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(l10n.cancel),
        ),
        TextButton(
          key: const ValueKey('cycle-off-delete'),
          onPressed: () => Navigator.pop(dialogContext, 'delete'),
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(dialogContext).colorScheme.error,
          ),
          child: Text(l10n.cycleTurnOffDelete),
        ),
        TextButton(
          key: const ValueKey('cycle-off-keep'),
          onPressed: () => Navigator.pop(dialogContext, 'keep'),
          child: Text(l10n.cycleTurnOffKeep),
        ),
      ],
    ),
  );
  if (choice == null) return true;
  if (choice == 'delete') await services.cycleDeleteAll();
  await services.reminders.cancelCycle();
  await preferences.setCycleEnabled(false);
  return false;
}
