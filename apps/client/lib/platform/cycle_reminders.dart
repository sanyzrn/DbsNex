import 'package:flutter/widgets.dart';

import '../l10n/app_localizations.dart';
import 'nex_preferences.dart';
import 'nex_services.dart';
import 'reminders.dart';

/// Arms «Cycle»'s reminders from the latest prediction, or takes them away.
///
/// Here rather than in [NexReminders] for the reason [DailyNudge] is: it
/// needs the app's words, and [NexReminders] schedules only what it is
/// handed. The words it hands over say nothing about a cycle — "Nex
/// reminder" and a line that could be about anything — because a lock
/// screen is read by whoever is holding the phone.
///
/// Run whenever a period or a reminder setting changes, and on every launch:
/// the next period moves as the history grows, and an OS alarm does not
/// survive a reinstall.
abstract final class CycleReminders {
  /// How many evenings of a period can be reminded: the alarm keys
  /// `log0`…`log9` in [NexReminders.cycleKeys].
  static const evenings = 10;

  static Future<void> apply({
    required BuildContext context,
    required NexServices services,
    required NexPreferences preferences,
  }) async {
    if (!NexReminders.supported) return;
    final l10n = AppLocalizations.of(context);
    final reminders = services.reminders;
    if (!preferences.cycleEnabled || !preferences.cycleSetUp) {
      await reminders.cancelCycle();
      return;
    }
    final prediction = await services.cyclePrediction();
    final title = l10n.cycleNotifyTitle;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Ten in the morning, two days ahead of the likeliest start.
    if (preferences.cycleRemindSoon &&
        prediction != null &&
        !prediction.inPeriod) {
      await reminders.scheduleCycle(
        'soon',
        at: prediction.nextStart
            .addDays(-2)
            .local
            .add(const Duration(hours: 10)),
        title: title,
        body: l10n.cycleNotifySoon,
      );
    } else {
      await reminders.cancelCycle('soon');
    }

    // Nine in the evening, each day of the period still to come — a day or
    // two past its usual length, and never more than ten, so a period
    // nobody marked as ended does not nag for ever.
    for (var i = 0; i < evenings; i++) {
      await reminders.cancelCycle('log$i');
    }
    if (preferences.cycleRemindLog &&
        prediction != null &&
        prediction.inPeriod) {
      final last = (prediction.averagePeriod + 1).clamp(1, evenings);
      for (var i = 0; i < last; i++) {
        final day = prediction.lastStart.addDays(i).local;
        if (day.isBefore(today)) continue;
        await reminders.scheduleCycle(
          'log$i',
          at: day.add(const Duration(hours: 21)),
          title: title,
          body: l10n.cycleNotifyLog,
        );
      }
    }

    if (preferences.cycleRemindPill) {
      await reminders.scheduleCycle(
        'pill',
        at: today.add(Duration(minutes: preferences.cyclePillMinutes)),
        title: title,
        body: l10n.cycleNotifyPill,
        daily: true,
      );
    } else {
      await reminders.cancelCycle('pill');
    }
  }
}
