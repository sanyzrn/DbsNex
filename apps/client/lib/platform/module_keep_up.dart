import 'dart:ui' show Locale, PlatformDispatcher;

import '../l10n/app_localizations.dart';
import '../modules/module_registry.dart';
import '../modules/nex_module_store.dart';
import '../modules/nex_stored_module.dart';
import 'nex_preferences.dart';
import 'nex_services.dart';

final _refreshes = Expando<Future<void>>();

/// Renew module records before pruning OS alarms. Concurrent launch/resume
/// deliveries share one flight so a newly rearmed module alarm is not pruned
/// against a snapshot from before that renewal (cancel also clears its notice).
Future<void> nexRefreshReminders(
  NexServices services,
  NexPreferences preferences,
) {
  final pending = _refreshes[services];
  if (pending != null) return pending;
  final work = () async {
    await nexKeepModulesUp(services, preferences);
    await services.restoreReminders();
  }();
  return _refreshes[services] = work.whenComplete(
    () => _refreshes[services] = null,
  );
}

/// Lets each module that is on keep itself up to date as Nex starts and
/// returns to the front (2.4.0) — Birthdays & occasions renews its alarms
/// here, so a date keeps ringing year after year without its screen being
/// opened. Quiet: a module that fails is left for the next time.
Future<void> nexKeepModulesUp(
  NexServices services,
  NexPreferences preferences,
) async {
  await services.applyHabitActions();
  final l10n = _localizations(preferences);
  for (final module in nexModulesOn(preferences)) {
    if (module is! NexStoredModule) continue;
    try {
      await module.keepUp(NexModuleStore(services, module.id), l10n);
    } catch (_) {
      // The next start or return tries again.
    }
  }
}

AppLocalizations _localizations(NexPreferences preferences) {
  final locale = preferences.locale ?? PlatformDispatcher.instance.locale;
  try {
    return lookupAppLocalizations(Locale(locale.languageCode));
  } catch (_) {
    return lookupAppLocalizations(const Locale('en'));
  }
}
