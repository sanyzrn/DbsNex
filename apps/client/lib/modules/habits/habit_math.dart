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
    this.dueToday = true,
    this.todayAmount = 0,
    this.strength = 0,
    this.best = 0,
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

  /// Whether today is one of the habit's days. A weekly target is due every
  /// day of a week until it is met.
  final bool dueToday;

  /// How much is logged today, towards the goal (the goal itself when the
  /// day is ticked).
  final int todayAmount;

  /// 0–100: how steadily the habit has been kept lately (2.4.0). Each due
  /// day nudges it towards done or not done, so one missed day lowers it a
  /// little and never wipes it out — a streak's honest companion.
  final int strength;

  /// The longest streak, by the same rule as [streak].
  final int best;
}

/// What a single day was for a habit, for the calendar and the heat map:
/// done, partly done, missed, not one of its days, still to come, or today
/// and not yet done.
enum HabitDayState { done, partial, missed, off, future, pending }

/// How many of the days (or weeks) a habit has really been going were met.
///
/// The denominator is only the time since the habit began — its creation
/// day, or its first check-in if that is earlier — so a month the habit did
/// not yet exist is never counted as a miss.
class HabitRate {
  const HabitRate(this.done, this.possible);

  final int done;
  final int possible;

  /// Whole percent, rounded; 0 when nothing was possible yet.
  int get percent => possible == 0 ? 0 : (done * 100 / possible).round();
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
  /// Amount-aware entry point used by all habit screens.
  static HabitStanding fromChecks(
    Habit habit,
    Iterable<HabitCheck> checks,
    DateTime today, {
    int firstDay = DateTime.saturday,
  }) {
    final logged = loggedDays(habit, checks, today);
    final amounts = {for (final e in logged.entries) dateKeyOf(e.key): e.value};
    return standing(
      habit,
      amounts.keys,
      today,
      firstDay: firstDay,
      amounts: amounts,
    );
  }

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

  /// Whether [day] is one of [habit]'s days (2.4.0). A weekly target may be
  /// met on any day, so every day is one of its days; a habit kept every N
  /// days counts them from the day it began.
  static bool dueOn(Habit habit, DateTime day) => switch (habit.plan) {
    HabitPlan.daily || HabitPlan.weekly => true,
    HabitPlan.days => habit.days.contains(day.weekday),
    HabitPlan.every => _everyDue(habit, day),
  };

  static bool _everyDue(Habit habit, DateTime day) {
    final start = _startDay(habit);
    if (start == null) return true;
    final diff = DateTime.utc(
      day.year,
      day.month,
      day.day,
    ).difference(start).inDays;
    return diff >= 0 && diff % habit.every == 0;
  }

  static DateTime? _startDay(Habit habit) =>
      habit.createdAt.millisecondsSinceEpoch > 0
      ? DateTime.utc(
          habit.createdAt.year,
          habit.createdAt.month,
          habit.createdAt.day,
        )
      : null;

  /// The days that reached the habit's goal, and the amount logged on every
  /// day that has a check-in, keyed by civil day. Future days are dropped:
  /// they count nowhere and break nothing.
  static ({Set<DateTime> done, Map<DateTime, int> logged}) _days(
    Habit habit,
    Iterable<String> dateKeys,
    Map<String, int>? amounts,
    DateTime todayUtc,
  ) {
    final done = <DateTime>{};
    final logged = <DateTime, int>{};
    for (final key in dateKeys) {
      final day = tryParseDateKey(key);
      if (day == null || day.isAfter(todayUtc)) continue;
      final amount = amounts?[key] ?? habit.goal;
      logged[day] = amount;
      if (amount >= habit.goal) done.add(day);
    }
    return (done: done, logged: logged);
  }

  /// The whole standing of [habit] against its check-ins on [today].
  ///
  /// [amounts] holds the amount logged on a day, for a habit with an amount
  /// goal; a day with a check-in and no amount is a whole day done, as every
  /// version-1 check-in is.
  static HabitStanding standing(
    Habit habit,
    Iterable<String> dateKeys,
    DateTime today, {
    int firstDay = DateTime.saturday,
    Map<String, int>? amounts,
  }) {
    final todayUtc = DateTime.utc(today.year, today.month, today.day);
    final days = _days(habit, dateKeys, amounts, todayUtc);
    final done = days.done;
    final recent = List.generate(recentDays, (offset) {
      final day = todayUtc.subtract(Duration(days: recentDays - 1 - offset));
      return done.contains(day);
    });
    final dueToday = dueOn(habit, todayUtc);
    final todayAmount = days.logged[todayUtc] ?? 0;
    if (done.isEmpty) {
      return HabitStanding(
        streak: 0,
        graceNow: false,
        graceInside: false,
        todayDone: false,
        weekCount: 0,
        total: 0,
        recent: recent,
        dueToday: dueToday,
        todayAmount: todayAmount,
        strength: strength(
          habit,
          dateKeys,
          today,
          amounts: amounts,
          firstDay: firstDay,
        ),
      );
    }

    final thisWeek = weekStartOf(todayUtc, firstDay: firstDay);
    final weekCount = done
        .where((d) => weekStartOf(d, firstDay: firstDay) == thisWeek)
        .length;
    final streak = habit.weekly
        ? _weeklyStreak(habit, done, todayUtc, firstDay)
        : _scheduledStreak(habit, done, todayUtc);
    return HabitStanding(
      streak: streak.streak,
      graceNow: streak.graceNow,
      graceInside: streak.graceInside,
      todayDone: done.contains(todayUtc),
      weekCount: weekCount,
      total: done.length,
      recent: recent,
      dueToday: dueToday,
      todayAmount: todayAmount,
      strength: strength(
        habit,
        dateKeys,
        today,
        amounts: amounts,
        firstDay: firstDay,
      ),
      best: habit.weekly
          ? _bestWeekly(habit, done, firstDay)
          : _bestScheduled(habit, done, todayUtc),
    );
  }

  /// The habit's days, oldest first, from the day it began (or its first
  /// check-in, when that is earlier) up to [todayUtc].
  static List<DateTime> _occurrences(
    Habit habit,
    Set<DateTime> done,
    DateTime todayUtc,
  ) {
    final since = _since(habit, done);
    if (since == null) return const [];
    return [
      for (
        var day = since;
        !day.isAfter(todayUtc);
        day = DateTime.utc(day.year, day.month, day.day + 1)
      )
        if (dueOn(habit, day)) day,
    ];
  }

  /// The daily rule, over the habit's own days (2.4.0): a day that is not
  /// one of them is neither kept nor missed, so a Monday-Wednesday-Friday
  /// habit's streak is not broken by Tuesday. Every day is one of a daily
  /// habit's days, so for it this is exactly the old rule.
  static ({int streak, bool graceNow, bool graceInside}) _scheduledStreak(
    Habit habit,
    Set<DateTime> done,
    DateTime todayUtc,
  ) {
    final occurrences = _occurrences(habit, done, todayUtc);
    final index = <DateTime, int>{
      for (final (i, day) in occurrences.indexed) day: i,
    };
    final kept = [for (final day in done) ?index[day]]..sort();
    if (kept.isEmpty || occurrences.isEmpty) {
      return (streak: 0, graceNow: false, graceInside: false);
    }
    final age = occurrences.length - 1 - kept.last;
    // Two whole due days since the last one kept: the run is over.
    if (age > 2) {
      return (streak: 0, graceNow: false, graceInside: false);
    }
    return _run([for (final i in kept) DateTime.utc(2000, 1, 1 + i)], age, 1);
  }

  /// The longest run by the same rule, anywhere in the history.
  static int _bestScheduled(
    Habit habit,
    Set<DateTime> done,
    DateTime todayUtc,
  ) {
    final occurrences = _occurrences(habit, done, todayUtc);
    final index = <DateTime, int>{
      for (final (i, day) in occurrences.indexed) day: i,
    };
    final kept = [for (final day in done) ?index[day]]..sort();
    return _bestRun(kept);
  }

  static int _bestWeekly(Habit habit, Set<DateTime> done, int firstDay) {
    final counts = <DateTime, int>{};
    for (final day in done) {
      final week = weekStartOf(day, firstDay: firstDay);
      counts[week] = (counts[week] ?? 0) + 1;
    }
    final met = [
      for (final entry in counts.entries)
        if (entry.value >= habit.target)
          entry.key.difference(_epoch).inDays ~/ 7,
    ]..sort();
    return _bestRun(met);
  }

  static final _epoch = DateTime.utc(2000, 1, 1);

  /// Longest run of indices with at most one missing index forgiven inside
  /// it, as [_run] counts a run.
  static int _bestRun(List<int> kept) {
    if (kept.isEmpty) return 0;
    var best = 1;
    for (var end = 0; end < kept.length; end++) {
      var count = 1;
      var graceUsed = false;
      for (var i = end; i > 0; i--) {
        final gap = kept[i] - kept[i - 1];
        if (gap > 2 || (gap == 2 && graceUsed)) break;
        if (gap == 2) graceUsed = true;
        count++;
      }
      if (count > best) best = count;
    }
    return best;
  }

  /// 0–100, how steadily the habit has been kept (2.4.0).
  ///
  /// An exponential average over the habit's own days, oldest first: each
  /// due day moves it a step towards 1 when kept, a part of the way when
  /// partly kept, and towards 0 when missed. Today counts only once it is
  /// done — a day still being lived is not a miss. For a weekly target, each
  /// finished week moves it by how much of the target was met.
  static int strength(
    Habit habit,
    Iterable<String> dateKeys,
    DateTime today, {
    Map<String, int>? amounts,
    int firstDay = DateTime.saturday,
  }) {
    final todayUtc = DateTime.utc(today.year, today.month, today.day);
    final days = _days(habit, dateKeys, amounts, todayUtc);
    final values = <double>[];
    if (habit.weekly) {
      final since = _since(habit, days.done);
      if (since == null) return 0;
      final thisWeek = weekStartOf(todayUtc, firstDay: firstDay);
      for (
        var week = weekStartOf(since, firstDay: firstDay);
        week.isBefore(thisWeek);
        week = week.add(const Duration(days: 7))
      ) {
        final count = days.done
            .where((d) => weekStartOf(d, firstDay: firstDay) == week)
            .length;
        values.add((count / habit.target).clamp(0.0, 1.0));
      }
      final now = days.done
          .where((d) => weekStartOf(d, firstDay: firstDay) == thisWeek)
          .length;
      if (now >= habit.target) values.add(1);
    } else {
      for (final day in _occurrences(habit, days.done, todayUtc)) {
        final logged = days.logged[day] ?? 0;
        if (day == todayUtc && logged < habit.goal) continue;
        values.add((logged / habit.goal).clamp(0.0, 1.0));
      }
    }
    if (values.isEmpty) return 0;
    // About the last three weeks of due days carry most of the weight.
    const alpha = 2 / (21 + 1);
    var score = 0.0;
    for (final value in values) {
      score += alpha * (value - score);
    }
    return (score * 100).round();
  }

  /// What [day] was for [habit] — for the calendar and the heat map.
  static HabitDayState dayState(
    Habit habit,
    DateTime day,
    Map<DateTime, int> logged,
    DateTime today,
  ) {
    final todayUtc = DateTime.utc(today.year, today.month, today.day);
    final at = DateTime.utc(day.year, day.month, day.day);
    if (at.isAfter(todayUtc)) return HabitDayState.future;
    final amount = logged[at] ?? 0;
    if (amount >= habit.goal) return HabitDayState.done;
    if (amount > 0) return HabitDayState.partial;
    final start = _startDay(habit);
    if (start != null && at.isBefore(start)) return HabitDayState.off;
    if (!habit.weekly && !dueOn(habit, at)) return HabitDayState.off;
    if (at == todayUtc) return HabitDayState.pending;
    // A weekly target is not missed on a day; only a week can miss it.
    return habit.weekly ? HabitDayState.off : HabitDayState.missed;
  }

  /// Logged amounts by civil day, ignoring the future — what [dayState]
  /// reads.
  static Map<DateTime, int> loggedDays(
    Habit habit,
    Iterable<HabitCheck> checks,
    DateTime today,
  ) {
    final todayUtc = DateTime.utc(today.year, today.month, today.day);
    return {
      for (final check in checks)
        if (tryParseDateKey(check.dateKey) case final day?)
          if (!day.isAfter(todayUtc)) day: check.progressFor(habit.goal),
    };
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

  /// The first civil day the habit counts from: its creation day, or its
  /// earliest check-in when that is earlier (or the creation day is
  /// unknown). Null when there is neither.
  static DateTime? _since(Habit habit, Set<DateTime> done) {
    DateTime? since = habit.createdAt.millisecondsSinceEpoch > 0
        ? DateTime.utc(
            habit.createdAt.year,
            habit.createdAt.month,
            habit.createdAt.day,
          )
        : null;
    for (final day in done) {
      if (since == null || day.isBefore(since)) since = day;
    }
    return since;
  }

  /// Due days kept of the last [days] days — a daily (or chosen-days, or
  /// every-N-days) habit's completion rate. Only the habit's own days count,
  /// and today only once it is done: a day still being lived is not a miss.
  static HabitRate dailyRate(
    Habit habit,
    Iterable<String> dateKeys,
    DateTime today,
    int days, {
    Map<String, int>? amounts,
  }) {
    final todayUtc = DateTime.utc(today.year, today.month, today.day);
    final logged = _days(habit, dateKeys, amounts, todayUtc);
    final done = logged.done;
    final since = _since(habit, done);
    if (since == null) return const HabitRate(0, 0);
    final windowStart = todayUtc.subtract(Duration(days: days - 1));
    final from = since.isAfter(windowStart) ? since : windowStart;
    var possible = 0, met = 0;
    for (
      var day = from;
      !day.isAfter(todayUtc);
      day = DateTime.utc(day.year, day.month, day.day + 1)
    ) {
      final kept = done.contains(day);
      if (!dueOn(habit, day) && !kept) continue;
      if (day == todayUtc && !kept) continue;
      possible++;
      if (kept) met++;
    }
    return HabitRate(met, possible);
  }

  /// Weeks that met the target among the last [weeks] **finished** weeks —
  /// a weekly habit's completion rate. The week still being written never
  /// counts against it, and neither does a first week that began mid-week.
  static HabitRate weeklyRate(
    Habit habit,
    Iterable<String> dateKeys,
    DateTime today, {
    Map<String, int>? amounts,
    int weeks = 12,
    int firstDay = DateTime.saturday,
  }) {
    final todayUtc = DateTime.utc(today.year, today.month, today.day);
    final done = _days(habit, dateKeys, amounts, todayUtc).done;
    final since = _since(habit, done);
    if (since == null) return const HabitRate(0, 0);
    final thisWeek = weekStartOf(todayUtc, firstDay: firstDay);
    var week = thisWeek.subtract(Duration(days: 7 * weeks));
    final sinceWeek = weekStartOf(since, firstDay: firstDay);
    final firstFull = sinceWeek == since
        ? sinceWeek
        : sinceWeek.add(const Duration(days: 7));
    if (firstFull.isAfter(week)) week = firstFull;
    var possible = 0, met = 0;
    for (; week.isBefore(thisWeek); week = week.add(const Duration(days: 7))) {
      possible++;
      final count = done
          .where((d) => weekStartOf(d, firstDay: firstDay) == week)
          .length;
      if (count >= habit.target) met++;
    }
    return HabitRate(met, possible);
  }
}
