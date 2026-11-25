import 'quit_model.dart';

enum QuitDayStatus { unlogged, craving, lapse, outside, future }

/// Five full weeks, ending with the week that contains [now]. The grid starts
/// on [weekStartsOn] (Monday for English, Saturday for Persian) so the
/// columns keep the week's own order instead of rotating with today's date.
///
/// UTC civil ordinals avoid DST-length arithmetic; display days remain local.
List<({DateTime day, QuitDayStatus status})> quitCalendarDays(
  QuitAttempt current,
  List<QuitAttempt> past,
  List<Craving> cravings,
  DateTime now, {
  int weekStartsOn = DateTime.monday,
}) {
  DateTime ordinal(DateTime value) {
    final d = value.toLocal();
    return DateTime.utc(d.year, d.month, d.day);
  }

  final firstDay =
      weekStartsOn >= DateTime.monday && weekStartsOn <= DateTime.sunday
      ? weekStartsOn
      : DateTime.monday;
  final today = ordinal(now);
  final currentWeekStart = today.subtract(
    Duration(days: (today.weekday - firstDay + 7) % 7),
  );
  final first = currentWeekStart.subtract(const Duration(days: 28));
  final logged = {
    for (final c in cravings)
      if (!c.at.isAfter(now)) ordinal(c.at),
  };
  final lapses = {
    for (final a in past)
      if (a.endedWhy == 'lapse' &&
          a.endedAt != null &&
          !a.endedAt!.isAfter(now))
        ordinal(a.endedAt!),
  };
  final spans = [
    for (final a in [...past, current])
      (ordinal(a.startedAt), a.endedAt == null ? today : ordinal(a.endedAt!)),
  ];
  return [
    for (var i = 0; i < 35; i++)
      (() {
        final d = first.add(Duration(days: i));
        // Days after today are not a report and not an absence of one; they
        // are simply not yet. Keeping them separate stops the last row from
        // looking like an unexplained silence.
        final isFuture = d.isAfter(today);
        final inAttempt =
            !isFuture &&
            spans.any((span) => !d.isBefore(span.$1) && !d.isAfter(span.$2));
        final status = isFuture
            ? QuitDayStatus.future
            : lapses.contains(d)
            ? QuitDayStatus.lapse
            : logged.contains(d)
            ? QuitDayStatus.craving
            : inAttempt
            ? QuitDayStatus.unlogged
            : QuitDayStatus.outside;
        return (day: DateTime(d.year, d.month, d.day), status: status);
      })(),
  ];
}
