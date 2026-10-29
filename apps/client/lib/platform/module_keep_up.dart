import 'dart:ui' show Locale, PlatformDispatcher;

import '../l10n/app_localizations.dart';
import '../modules/module_registry.dart';
import '../modules/nex_module_store.dart';
import '../modules/nex_stored_module.dart';
import 'nex_preferences.dart';
import 'nex_services.dart';

/// Lets each module that is on keep itself up to date as Nex starts and
/// returns to the front (2.4.0) — Birthdays & occasions renews its alarms
/// here, so a date keeps ringing year after year without its screen being
/// opened. Quiet: a module that fails is left for the next time.
Future<void> nexKeepModulesUp(
  NexServices services,
  NexPreferences preferences,
) async {
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
