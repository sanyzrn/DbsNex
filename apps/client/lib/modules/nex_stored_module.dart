import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../platform/nex_preferences.dart';
import '../platform/nex_services.dart';
import '../widgets/nex_dialog.dart';
import 'nex_module.dart';
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
  }) => preferences.setModuleOn(id, true);

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
    if (choice == 'delete') await services.moduleDeleteAll(id);
    await preferences.setModuleOn(id, false);
    return true;
  }

  @override
  Widget open({
    required NexServices services,
    required NexPreferences preferences,
  }) => screen(NexModuleStore(services, id));
}
