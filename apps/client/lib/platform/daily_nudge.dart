import 'package:flutter/widgets.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import 'nex_preferences.dart';
import 'nex_services.dart';

/// Schedules the once-a-day notification, or takes it away.
///
/// Keeps the local scheduling entry point and the private greeting together.
///
/// The service rebuilds a local dated plan when library data or preferences
/// change. A fresh, source-matched summary is optional; no AI request is made.
/// Native Android delivery selects today's text and retains the once-per-day
/// receipt even when the app is closed or the selected time changes.
abstract final class DailyNudge {
  /// Returns null when the alarm is scheduled, and the OS's own words when
  /// it is not.
  static Future<String?> apply({
    required NexServices services,
    bool freshlyGeneratedSummary = false,
  }) async {
    return services.updateDailyNudge(
      freshlyGeneratedSummary: freshlyGeneratedSummary,
    );
  }

  /// The line the notification opens with.
  ///
  /// Built here, from the name on this device, and never sent anywhere — the
  /// same rule the timeline's greeting follows. It is also why the recap
  /// underneath never contains the name: that half comes from a model, and the
  /// model is not told who it is writing to.
  ///
  /// Greeted in the language the name is written in rather than the interface
  /// language, because "صبح بخیر, Saeed" and "Good morning, سعید" are both
  /// sentences nobody writes.
  static String greeting(NexPreferences preferences, int minutes) {
    final name = preferences.shortDisplayName;
    final l10n = nexDirectionOf(name ?? '') == TextDirection.rtl
        ? lookupAppLocalizations(const Locale('fa'))
        : lookupAppLocalizations(const Locale('en'));
    if (name == null) return l10n.nudgeGreetingPlain;
    return minutes < 12 * 60
        ? l10n.nudgeGreetingMorning(name)
        : l10n.nudgeGreetingDay(name);
  }
}
