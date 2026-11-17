import 'quit_model.dart';

enum QuitDayStatus { unlogged, craving, lapse, outside }

/// UTC civil ordinals avoid DST-length arithmetic; display days remain local.
List<({DateTime day, QuitDayStatus status})> quitCalendarDays(
  QuitAttempt current,
  List<QuitAttempt> past,
  List<Craving> cravings,
  DateTime now,
) {
  DateTime ordinal(DateTime value) {
    final d = value.toLocal();
    return DateTime.utc(d.year, d.month, d.day);
  }

  final end = ordinal(now),
      first = ordinal(now).subtract(const Duration(days: 34));
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
      (ordinal(a.startedAt), a.endedAt == null ? end : ordinal(a.endedAt!)),
  ];
  return [
    for (var i = 0; i < 35; i++)
      (() {
        final d = first.add(Duration(days: i));
        final inAttempt = spans.any(
          (span) => !d.isBefore(span.$1) && !d.isAfter(span.$2),
        );
        final status = lapses.contains(d)
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
