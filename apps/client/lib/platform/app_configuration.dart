import 'nex_preferences.dart';
import 'package:flutter/widgets.dart';
import '../l10n/app_localizations.dart';

Locale? nexSystemLocale(BuildContext context) {
  for (final locale in View.of(context).platformDispatcher.locales) {
    for (final supported in AppLocalizations.supportedLocales) {
      if (supported.languageCode == locale.languageCode) return supported;
    }
  }
  return null;
}

/// Values rendered by the application root. Feature preferences are observed
/// by their consumers without rebuilding MaterialApp and both themes.
Object nexAppConfiguration(NexPreferences prefs) => (
  prefs.locale,
  prefs.appearanceMode,
  prefs.themePreset,
  prefs.accentSeed,
  prefs.comfortMode,
  prefs.liquidGlass,
  prefs.backgroundPattern,
  prefs.cardDensity,
  prefs.uiScale,
  prefs.solarCalendar,
  prefs.onboardingComplete,
);
