import 'quit_model.dart';

/// What the dashboard shows for one quit attempt, and what it never shows:
/// a negative number, a false precision, or a claim about anyone's body.
///
/// Every estimate comes from the attempt's own baseline — cigarettes a day
/// before quitting, the price of a pack, cigarettes in a pack — and the
/// number of whole civil days since it started. All arithmetic is integer.
class SmokeProgress {
  const SmokeProgress({
    required this.days,
    required this.cigarettesAvoided,
    required this.rialsSaved,
    this.exactSaved,
  });

  /// Whole civil days since the attempt started. A quit at 23:00 yesterday
  /// and a glance at 07:00 today is one day, because the calendar turned.
  final int days;

  /// Estimated cigarettes not smoked: `days × cigarettesPerDay`.
  final int cigarettesAvoided;

  /// Estimated money kept, in integer rials, rounded **down**:
  /// `(days × cigarettesPerDay × pricePerPack) ~/ perPack`. Flooring never
  /// overstates savings; the exact remainder stays honestly unstated.
  final int rialsSaved;
  final BigInt? exactSaved;
  BigInt get moneySavedMinor => exactSaved ?? BigInt.from(rialsSaved);

  static const empty = SmokeProgress(
    days: 0,
    cigarettesAvoided: 0,
    rialsSaved: 0,
  );
}

/// The arithmetic of staying smoke-free. Plain, boring, auditable.
class SmokeMath {
  /// Whole civil days from the attempt's local start date to [today].
  ///
  /// Never negative: a start in the future (a clock gone wrong, or a date
  /// the input guard should have caught) reads as zero days, because a
  /// negative number on a quit dashboard is a small cruelty with no
  /// meaning behind it.
  static int elapsedDays(DateTime startedAt, DateTime now) {
    startedAt = startedAt.toLocal();
    now = now.toLocal();
    final start = DateTime.utc(startedAt.year, startedAt.month, startedAt.day);
    final today = DateTime.utc(now.year, now.month, now.day);
    final days = today.difference(start).inDays;
    return days < 0 ? 0 : days;
  }

  /// The dashboard's three numbers for [attempt] as of [now].
  static SmokeProgress progress(QuitAttempt attempt, DateTime now) {
    final days = elapsedDays(
      attempt.startedAt,
      attempt.endedAt != null && attempt.endedAt!.isBefore(now)
          ? attempt.endedAt!
          : now,
    );
    final cigarettes =
        days *
        (attempt.cigarettesPerDay < 0
            ? 0
            : attempt.cigarettesPerDay.clamp(0, 1000));
    final raw = attempt.perPack < 1 || attempt.pricePerPackMinor <= 0
        ? BigInt.zero
        : BigInt.from(cigarettes) *
              BigInt.from(attempt.pricePerPackMinor) ~/
              BigInt.from(attempt.perPack);
    final rials = raw > BigInt.from(9007199254740991)
        ? 9007199254740991
        : raw.toInt();
    return SmokeProgress(
      days: days,
      cigarettesAvoided: cigarettes,
      rialsSaved: rials < 0 ? 0 : rials,
      exactSaved: raw,
    );
  }

  /// The active attempt among [attempts] — the one with no end, newest
  /// start first — or null when there is none. Ties on the same start
  /// instant fall back to the record id, which the store issues in order,
  /// so the choice is deterministic instead of whichever quicksort saw last.
  static QuitAttempt? activeAttempt(List<QuitAttempt> attempts) {
    final running = [
      for (final a in attempts)
        if (a.isActive) a,
    ]..sort(compareAttemptsNewestFirst);
    return running.isEmpty ? null : running.first;
  }

  /// Past attempts, newest first: the history a lapse must never erase.
  static List<QuitAttempt> pastAttempts(List<QuitAttempt> attempts) => [
    for (final a in attempts)
      if (!a.isActive) a,
  ]..sort(compareAttemptsNewestFirst);

  /// Newest start first; the id breaks exact-instant ties so the order is
  /// deterministic. Store ids carry their creation time, so a later record
  /// also sorts later.
  static int compareAttemptsNewestFirst(QuitAttempt a, QuitAttempt b) {
    final byStart = b.startedAt.compareTo(a.startedAt);
    return byStart != 0 ? byStart : b.id.compareTo(a.id);
  }

  /// Cravings newest first for the list, with the same exact-instant tie
  /// discipline so two logs saved in the same millisecond never swap places
  /// between rebuilds.
  static List<Craving> cravingsNewestFirst(List<Craving> cravings) =>
      [...cravings]..sort((a, b) {
        final byAt = b.at.compareTo(a.at);
        return byAt != 0 ? byAt : b.id.compareTo(a.id);
      });

  /// How many calendar days an attempt ran before it ended — for the
  /// history list. An attempt that ended the day it started reads zero
  /// here, and the history says it in words rather than as a bare 0.
  static int attemptSpanDays(QuitAttempt attempt) => attempt.endedAt == null
      ? 0
      : elapsedDays(attempt.startedAt, attempt.endedAt!);

  /// Which day a craving falls on, relative to [now]: 0 today, 1
  /// yesterday, and so on — the honest grouping for the cravings list.
  static int cravingDayIndex(DateTime cravingAt, DateTime now) =>
      _daysBack(cravingAt, now);

  static int _daysBack(DateTime moment, DateTime now) {
    moment = moment.toLocal();
    now = now.toLocal();
    final day = DateTime.utc(moment.year, moment.month, moment.day);
    final today = DateTime.utc(now.year, now.month, now.day);
    return today.difference(day).inDays;
  }

  /// The counts of each trigger key among [cravings], most frequent first —
  /// the pattern behind the cravings, without a chart that pretends to be
  /// science.
  static List<MapEntry<String, int>> triggerCounts(List<Craving> cravings) {
    final counts = <String, int>{};
    for (final craving in cravings) {
      for (final trigger in craving.triggers.toSet().where(
        cravingTriggerKeys.contains,
      )) {
        counts[trigger] = (counts[trigger] ?? 0) + 1;
      }
    }
    final entries = counts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });
    return entries;
  }
}

/// How long an attempt has run, as the live counter says it: whole days,
/// then the hours and minutes into the day since it began. Never negative; an
/// attempt that has not started yet is [untilStart] away instead.
class QuitElapsed {
  const QuitElapsed(this.days, this.hours, this.minutes);

  final int days;
  final int hours;
  final int minutes;

  static QuitElapsed between(DateTime from, DateTime to) {
    final total = to.difference(from);
    if (total.isNegative) return const QuitElapsed(0, 0, 0);
    return QuitElapsed(total.inDays, total.inHours % 24, total.inMinutes % 60);
  }
}

/// The marks earned at [days] and the next one to reach, or null after the
/// last: a way to see where you are, never a rank.
({List<int> earned, int? next}) quitMilestonesAt(int days, List<int> marks) => (
  earned: [
    for (final m in marks)
      if (days >= m) m,
  ],
  next: marks.where((m) => days < m).firstOrNull,
);

/// A short supportive line keyed by elapsed days — deliberately non-medical:
/// no organ names, no recovery timelines, no clinical promises. Just
/// acknowledgment of effort, from a companion that cannot diagnose anyone.
String supportMessageKey(int days) {
  if (days <= 0) return 'supportDay0';
  if (days == 1) return 'supportDay1';
  if (days < 7) return 'supportDays';
  if (days < 30) return 'supportWeek';
  if (days < 365) return 'supportMonth';
  return 'supportYear';
}
