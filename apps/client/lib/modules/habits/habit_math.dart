import 'habit_model.dart';

/// How a habit stands today: its streak, whether that streak is standing on
/// its one forgiven interval, and how far along this week is. Pure civil-date
/// arithmetic — see `habit_model.dart` for why nothing here touches a clock.
class HabitStanding {
  const HabitStanding({
    required this.streak,
    required this.graceNow,
    required this.graceInside,
    required this.todayDone,
    required this.weekCount,
    required this.total,
    required this.recent,
  });

  /// Consecutive completed intervals, counting only completed ones. A
  /// forgiven interval is never added to this number.
  final int streak;

  /// The newest completion is one whole interval old and the one after it
  /// was missed: the streak is standing on its grace interval right now,
  /// and today (or this week) keeps it alive.
  final bool graceNow;

  /// Somewhere inside the current run an interval was missed and forgiven.
  final bool graceInside;

  /// Whether the habit is checked in for today.
  final bool todayDone;

  /// Check-ins in the current week.
  final int weekCount;

  /// Check-ins ever, ignoring future dates.
  final int total;

  /// The last [HabitMath.recentDays] days, oldest first, each marked done or
  /// not — what the dot row on the detail page draws.
  final List<bool> recent;

  /// Nothing checked in yet — today, waiting for the person.
  static const empty = HabitStanding(
    streak: 0,
    graceNow: false,
    graceInside: false,
    todayDone: false,
    weekCount: 0,
    total: 0,
    recent: [],
  );
}

/// Streaks, weekly targets and summaries.
///
/// One rule, applied to days for a daily habit and to weeks for a weekly
/// target: a streak is a run of completed intervals in which **at most one
/// missed interval** may sit between two completed ones. That missed
/// interval keeps the run alive — it is *forgiven*, never counted — and a
/// second missed interval in a row ends the run.
///
/// A run is alive when its newest completed interval is this interval, the
/// one before (still pending), or — standing on its grace — two intervals
/// back. Weeks run Saturday to Friday (see [weekStartOf]) whatever language
/// the app is in, so the same history always has the same streak.
class HabitMath {
  /// How many days the detail page's dot row shows.
  static const recentDays = 14;

  /// The Saturday that starts the week [date] falls in.
  ///
  /// Nex is Persian-first and the Iranian week begins on Saturday, so that
  /// is the one fixed boundary every weekly target is measured against — in
  /// Persian and in English alike.
  static DateTime weekStartOf(
    DateTime date, {
    int firstDay = DateTime.saturday,
  }) {
    // Dart's weekday: Monday 1 … Saturday 6, Sunday 7.
    final sinceSaturday = (date.weekday - firstDay.clamp(1, 7)) % 7;
    return DateTime.utc(date.year, date.month, date.day - sinceSaturday);
  }

  /// The Saturday-start week of [dateKey], as that Saturday's date key.
  static String weekKeyOf(String dateKey, {int firstDay = DateTime.saturday}) {
    final date = tryParseDateKey(dateKey);
    if (date == null) {
      return dateKey;
    }
    return _keyOf(weekStartOf(date, firstDay: firstDay));
  }

  static String _keyOf(DateTime date) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)}';
  }

  /// The whole standing of [habit] against its check-ins on [today].
  static HabitStanding standing(
    Habit habit,
    Iterable<String> dateKeys,
    DateTime today, {
    int firstDay = DateTime.saturday,
  }) {
    final todayUtc = DateTime.utc(today.year, today.month, today.day);
    // Future check-ins — a clock gone wrong, or a day set ahead — are
    // ignored everywhere: they count nowhere and break nothing.
    final done = dateKeys
        .map(tryParseDateKey)
        .whereType<DateTime>()
        .where((d) => !d.isAfter(todayUtc))
        .toSet();
    final recent = List.generate(recentDays, (offset) {
      final day = todayUtc.subtract(Duration(days: recentDays - 1 - offset));
      return done.contains(day);
    });
    if (done.isEmpty) {
      return HabitStanding(
        streak: 0,
        graceNow: false,
        graceInside: false,
        todayDone: false,
        weekCount: 0,
        total: 0,
        recent: recent,
      );
    }

    final thisWeek = weekStartOf(todayUtc, firstDay: firstDay);
    final weekCount = done
        .where((d) => weekStartOf(d, firstDay: firstDay) == thisWeek)
        .length;
    final streak = habit.weekly
        ? _weeklyStreak(habit, done, todayUtc, firstDay)
        : _dailyStreak(done, todayUtc);
    return HabitStanding(
      streak: streak.streak,
      graceNow: streak.graceNow,
      graceInside: streak.graceInside,
      todayDone: done.contains(todayUtc),
      weekCount: weekCount,
      total: done.length,
      recent: recent,
    );
  }

  /// The daily rule: walk back from the newest completed day to the oldest,
  /// forgiving a single missed day between completions.
  static ({int streak, bool graceNow, bool graceInside}) _dailyStreak(
    Set<DateTime> done,
    DateTime todayUtc,
  ) {
    final newest = done.reduce((a, b) => b.isAfter(a) ? b : a);
    final age = todayUtc.difference(newest).inDays;
    // Three days since the last check-in means two whole days were missed:
    // the run is over, whatever happened before it.
    if (age > 2) {
      return (streak: 0, graceNow: false, graceInside: false);
    }

    return _run(done.toList()..sort(), age, 1);
  }

  /// The weekly rule, the same shape: weeks that met the target, one
  /// forgiven unmet week between them.
  static ({int streak, bool graceNow, bool graceInside}) _weeklyStreak(
    Habit habit,
    Set<DateTime> done,
    DateTime todayUtc,
    int firstDay,
  ) {
    final counts = <DateTime, int>{};
    for (final day in done) {
      final week = weekStartOf(day, firstDay: firstDay);
      counts[week] = (counts[week] ?? 0) + 1;
    }
    final metWeeks = [
      for (final entry in counts.entries)
        if (entry.value >= habit.target) entry.key,
    ]..sort();
    if (metWeeks.isEmpty) {
      return (streak: 0, graceNow: false, graceInside: false);
    }

    final newestMet = metWeeks.last;
    final weeksSinceMet =
        weekStartOf(
          todayUtc,
          firstDay: firstDay,
        ).difference(newestMet).inDays ~/
        7;
    // The current week is still being written. What a streak cannot survive
    // is two finished weeks since the last one that met its target.
    if (weeksSinceMet > 2) {
      return (streak: 0, graceNow: false, graceInside: false);
    }

    return _run(metWeeks, weeksSinceMet, 7);
  }

  // Exactly one grace interval in the whole displayed run, including an
  // outstanding grace. Walk completions, not every day in a corrupt history.
  static ({int streak, bool graceNow, bool graceInside}) _run(
    List<DateTime> completed,
    int age,
    int intervalDays,
  ) {
    var count = 1;
    var graceUsed = age == 2;
    var graceInside = false;
    for (var i = completed.length - 1; i > 0; i--) {
      final gap =
          completed[i].difference(completed[i - 1]).inDays ~/ intervalDays;
      if (gap > 2 || (gap == 2 && graceUsed)) break;
      if (gap == 2) {
        graceUsed = true;
        graceInside = true;
      }
      count++;
    }
    return (streak: count, graceNow: age == 2, graceInside: graceInside);
  }
}
