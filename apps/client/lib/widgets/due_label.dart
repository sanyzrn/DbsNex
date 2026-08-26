import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// When a reminder is due, said two ways.
///
/// A reminder that has been set was invisible except as a bell: the card said
/// one was there, the sheet said one was there, and neither said *when*. The
/// only thing you could do to a reminder you could not read was delete it.
///
/// Every app that does this shows the time on the note itself — Keep puts a
/// chip under the text, Reminders and Todoist put a date label on the row —
/// and opens the picker with the current value in view. That is what these
/// two functions are for: [nexDueCountdown] is the version that fits on a
/// card, [nexDueExact] the version for anywhere with room for the truth.

/// "in 2 hours", "in 3 days", or "Overdue".
///
/// Built from the strings the reminder confirmation already uses, so the card
/// answers the same question in the same words the app used when the reminder
/// was set. Compact on purpose: it shares one line with the note's own
/// timestamp and its preview.
String nexDueCountdown(AppLocalizations l10n, DateTime due) {
  final left = due.toLocal().difference(DateTime.now());
  if (left.isNegative) return l10n.remindOverdue;
  // The short forms, not the sentences the confirmation uses. This shares one
  // line with the note's own words, and "13 hours" took enough of it to push
  // them off the card — which is the whole reason the timestamp gave up its
  // slot to this in the first place.
  if (left.inHours >= 24) return l10n.timeDaysShort((left.inHours / 24).ceil());
  if (left.inMinutes >= 60) {
    return l10n.timeHoursShort((left.inMinutes / 60).ceil());
  }
  return l10n.timeMinutesShort(
    left.inSeconds <= 0 ? 0 : (left.inSeconds / 60).ceil(),
  );
}

/// "Today at 09:00", "Tomorrow at 09:00", "Wed, Aug 26 at 09:00".
///
/// The day words and the date come from [MaterialLocalizations] rather than
/// from a format string of our own: it already knows this locale's month
/// names and, for the time, whether this phone is set to 24 hours.
String nexDueExact(BuildContext context, DateTime due) {
  final l10n = AppLocalizations.of(context);
  final material = MaterialLocalizations.of(context);
  final local = due.toLocal();
  final time = material.formatTimeOfDay(
    TimeOfDay.fromDateTime(local),
    alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
  );
  final days = DateUtils.dateOnly(
    local,
  ).difference(DateUtils.dateOnly(DateTime.now())).inDays;
  if (days == 0) return l10n.remindWhenToday(time);
  if (days == 1) return l10n.remindWhenTomorrow(time);
  return l10n.remindWhenOn(material.formatMediumDate(local), time);
}
