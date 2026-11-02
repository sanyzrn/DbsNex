import '../l10n/app_localizations.dart';

/// A truthful countdown independent of the recurrence cadence. Hourly items
/// still need to say when the next turn is, beside their completion tally.
String nexRecurringCountdown(
  AppLocalizations l10n,
  DateTime due,
  DateTime now,
) {
  final remaining = due.difference(now);
  if (remaining == Duration.zero) return l10n.commitmentDueNow;
  if (remaining.isNegative) {
    return l10n.commitmentOverdue(_span(l10n, -remaining));
  }
  return l10n.commitmentDueIn(_span(l10n, remaining));
}

String _span(AppLocalizations l10n, Duration span) {
  // Round up as a unit before splitting, so 59m 59s is one hour, never 0m.
  final minutes = (span.inMicroseconds / Duration.microsecondsPerMinute).ceil();
  final days = minutes ~/ (24 * 60);
  final hours = (minutes ~/ 60) % 24;
  final rest = minutes % 60;
  if (days >= 7) return l10n.spanDays(days);
  if (days > 0) {
    return [
      l10n.spanDays(days),
      if (hours > 0) l10n.spanHours(hours),
    ].join(' · ');
  }
  if (hours > 0) {
    return [
      l10n.spanHours(hours),
      if (rest > 0) l10n.spanMinutes(rest),
    ].join(' · ');
  }
  return l10n.spanMinutes(minutes.clamp(1, 59));
}
