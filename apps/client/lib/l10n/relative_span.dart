import 'app_localizations.dart';

/// A rough span in the largest unit that still says something true.
///
/// Deliberately coarse: nobody setting up a yearly insurance renewal needs to
/// be told it is due in 312 days and 4 hours.
///
/// Lifted out of the recurring sheet, where it was written, once the daily
/// brief started writing its own lines. Both of them say "2 days overdue"
/// about the same commitment, and the alternative to sharing this was two
/// places in the app disagreeing about what to call the same Tuesday.
String nexRelativeSpan(AppLocalizations l10n, Duration span) {
  if (span.inMinutes < 60) return l10n.spanMinutes(span.inMinutes.clamp(1, 59));
  if (span.inHours < 48) return l10n.spanHours(span.inHours);
  if (span.inDays < 60) return l10n.spanDays(span.inDays);
  return l10n.spanMonths(span.inDays ~/ 30);
}
