import 'package:flutter/widgets.dart';
import 'package:nex_ui/nex_ui.dart';

import '../l10n/app_localizations.dart';
import 'nex_preferences.dart';
import 'reminders.dart';

/// Schedules the once-a-day notification, or takes it away.
///
/// Kept apart from [NexReminders] because it is the only part of this that
/// needs the app's own words and the user's own name, and [NexReminders]
/// deliberately knows neither — it schedules what it is handed.
///
/// Called from two places, and both are necessary. Settings calls it because
/// the switch and the time are what it is about. The timeline calls it when
/// the daily recap resolves, because that recap *is* the body: a notification
/// fires while the app is not running, so nothing can generate a sentence at
/// the moment it appears. What arrives tomorrow morning is what Nex last knew,
/// which is why this runs again every time the app is open.
abstract final class DailyNudge {
  static Future<void> apply({
    required BuildContext context,
    required NexPreferences preferences,
    required NexReminders reminders,
    String? recap,
  }) async {
    if (!NexReminders.supported) return;
    if (!preferences.dailyNudge) {
      await reminders.cancelDaily();
      return;
    }
    final minutes = preferences.dailyNudgeMinutes;
    final l10n = AppLocalizations.of(context);
    await reminders.scheduleDaily(
      hour: minutes ~/ 60,
      minute: minutes % 60,
      title: _greeting(preferences, minutes),
      body: (recap ?? '').trim().isEmpty ? l10n.nudgeNothing : recap!.trim(),
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
  static String _greeting(NexPreferences preferences, int minutes) {
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
