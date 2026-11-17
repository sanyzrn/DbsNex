import 'local_values.dart';
import 'medicine_models.dart';

/// The routine the person wrote down — when they mean to take it — and
/// nothing medical: it decides which moments a reminder may ring and how
/// much stock a day is expected to use, both from the person's own numbers.
///
/// A schedule is any mix of: times in a day, chosen days of the week, an
/// every-N-days rule, and a start and end date. Writing none of them means
/// every day, with no times and so no reminder.
class MedicineSchedule {
  const MedicineSchedule({
    required this.times,
    this.weekdays = const [],
    this.everyDays,
    this.startsOn,
    this.endsOn,
    this.anchor,
  });

  factory MedicineSchedule.of(Map<String, Object?> body) => MedicineSchedule(
    times: MedicineModels.readTimes(body)..sort(),
    weekdays: MedicineModels.readWeekdays(body),
    everyDays: MedicineModels.readEveryDays(body),
    startsOn: MedicineModels.readDay(body, 'startsOn'),
    endsOn: MedicineModels.readDay(body, 'endsOn'),
    anchor: MedicineModels.readDay(body, 'scheduleFrom'),
  );

  /// The times of day the person wrote, "HH:MM", in order.
  final List<String> times;

  /// Chosen days of the week, Dart numbering (Monday 1 … Sunday 7).
  final List<int> weekdays;

  /// Every N days, or null for every day.
  final int? everyDays;

  final DateTime? startsOn;
  final DateTime? endsOn;

  /// The day an every-N-days count started, so editing the record later
  /// does not silently move the days it lands on.
  final DateTime? anchor;

  bool get hasTimes => times.isNotEmpty;

  /// Whether any part of the schedule was written at all.
  bool get isWritten =>
      times.isNotEmpty ||
      weekdays.isNotEmpty ||
      everyDays != null ||
      startsOn != null ||
      endsOn != null;

  /// Whether the person's own start and end dates allow this day.
  bool withinBounds(DateTime day) {
    final date = LocalValues.civil(day);
    if (startsOn != null && date.isBefore(LocalValues.civil(startsOn!))) {
      return false;
    }
    if (endsOn != null && date.isAfter(LocalValues.civil(endsOn!))) {
      return false;
    }
    return true;
  }

  /// Whether the weekly or every-N-days rule picks [day]. Every day when
  /// neither is written; an every-N count counts from the anchor day, or
  /// from the first day the schedule allows when there is no anchor.
  bool matchesDay(DateTime day) {
    final date = LocalValues.civil(day);
    if (weekdays.isNotEmpty) {
      return weekdays.contains(date.weekday);
    }
    final n = everyDays;
    if (n != null && n >= 2) {
      final from = LocalValues.civil(anchor ?? startsOn ?? date);
      final diff = date.difference(from).inDays;
      if (diff < 0) {
        return false;
      }
      return diff % n == 0;
    }
    return true;
  }

  /// Whether this day is part of the routine at all.
  bool runsOn(DateTime day) => withinBounds(day) && matchesDay(day);

  /// What share of days the routine covers: seven of seven is 1, three of
  /// seven is 3/7, every third day is 1/3.
  double get dailyFactor {
    if (weekdays.isNotEmpty) {
      return weekdays.length / 7;
    }
    final n = everyDays;
    if (n != null && n >= 2) {
      return 1 / n;
    }
    return 1;
  }

  /// Units the routine is expected to use in a day, from the person's own
  /// units per dose and times. Null when they did not write both, because
  /// then there is nothing honest to divide by.
  double? unitsPerDay(int? doseUnits) {
    if (doseUnits == null || doseUnits <= 0 || times.isEmpty) {
      return null;
    }
    return doseUnits * times.length * dailyFactor;
  }

  /// The moments this routine names from [from] on, at most [limit], in
  /// order. A moment exactly at [from] does not count again.
  List<DateTime> occurrences({
    required DateTime from,
    DateTime? until,
    int limit = 200,
  }) {
    if (times.isEmpty || limit <= 0) {
      return const [];
    }
    final out = <DateTime>[];
    // The person's times in clock order, whatever order they reached us in.
    final ordered = [...times]..sort();
    final start = LocalValues.civil(from);
    final last = LocalValues.civil(
      until ?? DateTime(from.year + 1, from.month, from.day),
    );
    var day = start;
    while (!day.isAfter(last) && out.length < limit) {
      if (runsOn(day)) {
        for (final time in ordered) {
          final moment = at(day, time);
          if (moment != null && moment.isAfter(from)) {
            out.add(moment);
            if (out.length >= limit) {
              break;
            }
          }
        }
      }
      day = day.add(const Duration(days: 1));
    }
    return out;
  }

  /// The next moment this routine names after [from], or null when it
  /// names none in the next year.
  DateTime? nextAfter(DateTime from) {
    final next = occurrences(from: from, limit: 1);
    return next.isEmpty ? null : next.first;
  }

  /// [time] on [day] as a local instant, or null when the time is not one.
  static DateTime? at(DateTime day, String time) {
    final parts = time.split(':');
    if (parts.length != 2) {
      return null;
    }
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null ||
        minute == null ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59) {
      return null;
    }
    return DateTime(day.year, day.month, day.day, hour, minute);
  }
}
