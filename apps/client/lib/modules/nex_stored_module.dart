import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../platform/crash_reporter.dart';
import '../platform/nex_preferences.dart';
import '../platform/nex_services.dart';
import '../widgets/nex_banner.dart';
import '../widgets/nex_dialog.dart';
import 'nex_module.dart';
import 'module_dates.dart';
import 'nex_module_store.dart';
import 'nex_module_strings.dart';

/// The module every module after «Cycle» is: words, a look and a screen —
/// and nothing else to get wrong.
///
/// Adding, removing, asking whether to keep the data, and deleting it are
/// all done here, the same way for every module, from the generic
/// `module.<id>.on` preference and the module's own [NexModuleStore]. A
/// module built on this never sees the app's services or preferences: its
/// screen is handed its store, and that is all it can reach. See
/// `docs/18-module-kit.md`.
abstract class NexStoredModule extends NexModule {
  const NexStoredModule();

  /// Its words, in both languages — see [NexModuleStrings].
  NexModuleStrings get strings;

  /// Its screen, opened from its tile in Tools, with its store.
  Widget screen(NexModuleStore store);

  /// Called when Nex starts and each time it comes back to the front, while
  /// this module is on and available: the moment to keep its own reminders
  /// ahead without waiting for its screen to be opened (2.4.0). Nothing may
  /// be shown from here. Does nothing unless a module needs it.
  Future<void> keepUp(NexModuleStore store, AppLocalizations l10n) async {}

  /// Optional on-device fact for the daily brief; never supplied to AI.
  Future<String?> briefLine(
    NexModuleStore store,
    AppLocalizations l10n,
  ) async => null;

  @override
  String title(AppLocalizations l10n) => strings.text(l10n, 'title');

  @override
  String tagline(AppLocalizations l10n) => strings.text(l10n, 'tagline');

  @override
  String about(AppLocalizations l10n) => strings.text(l10n, 'about');

  @override
  List<String> points(AppLocalizations l10n) => [
    for (final key in const ['point1', 'point2', 'point3', 'point4'])
      if (strings.en.containsKey(key)) strings.text(l10n, key),
  ];

  @override
  bool isOn(NexPreferences preferences) => preferences.isModuleOn(id);

  @override
  Future<void> turnOn(
    BuildContext context, {
    required NexServices services,
    required NexPreferences preferences,
  }) async {
    await preferences.setModuleOn(id, true);
    // Its kept reminders ring again without waiting for the next launch:
    // data that was kept when the module was removed still carries its
    // `__reminder` records, and a re-add used to leave them silent until
    // the app next started or returned to the front. Quiet — the next
    // start or return tries again if this fails.
    try {
      await services.restoreModuleReminders();
    } catch (_) {
      // Nothing to show from here; re-adding found everything where it was.
    }
  }

  @override
  Future<bool> turnOff(
    BuildContext context, {
    required NexServices services,
    required NexPreferences preferences,
  }) async {
    final l10n = AppLocalizations.of(context);
    final choice = await nexShowDialog<String>(
      context: context,
      builder: (dialogContext) => NexAlertDialog(
        title: Text(l10n.moduleRemoveTitle(title(l10n))),
        content: NexDialogBody(child: Text(l10n.moduleRemoveBody)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.cancel),
          ),
          TextButton(
            key: ValueKey('module-$id-off-delete'),
            onPressed: () => Navigator.pop(dialogContext, 'delete'),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: Text(l10n.moduleRemoveDelete),
          ),
          TextButton(
            key: ValueKey('module-$id-off-keep'),
            onPressed: () => Navigator.pop(dialogContext, 'keep'),
            child: Text(l10n.moduleRemoveKeep),
          ),
        ],
      ),
    );
    if (choice == null) return false;
    // A delete that fails leaves the module where it was (2.7.2). The wipe
    // is one transaction, so a failure — a full disk, a worker that has
    // gone — deleted nothing; turning the module off anyway would leave the
    // person believing their records were gone while every one of them
    // stayed. So it stays on, with its reminders, and says so: the choice
    // can be made again at once. The failure also goes to diagnostics.
    if (choice == 'delete') {
      try {
        await services.moduleDeleteAll(id);
      } catch (error) {
        unawaited(NexCrashLog.handled('module.$id.turnOff', error));
        if (context.mounted) {
          nexShowBanner(context, message: l10n.moduleRemoveFailed(title(l10n)));
        }
        return false;
      }
    }
    try {
      await services.cancelModuleReminders(id);
    } catch (error) {
      unawaited(NexCrashLog.handled('module.$id.turnOff.reminders', error));
    }
    await preferences.setModuleOn(id, false);
    return true;
  }

  @override
  Widget open({
    required NexServices services,
    required NexPreferences preferences,
  }) => NexModuleCalendar(
    solar: preferences.solarCalendar,
    child: screen(NexModuleStore(services, id)),
  );
}
