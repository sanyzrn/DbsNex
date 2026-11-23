import 'dart:math' as math;

import 'cycle_models.dart';

/// How far a prediction can be trusted.
enum CycleConfidence {
  /// Nothing learned yet: the typical lengths given at the start, or the
  /// textbook ones.
  low,

  /// A couple of cycles, or cycles that vary.
  medium,

  /// Three or more cycles that agree within a couple of days.
  high,
}

/// Something worth a word with a doctor — said gently, never as a
/// diagnosis.
enum CycleAlert {
  /// More than ten days past the latest predicted start.
  late,

  /// A period going on, or that went on, for more than eight days.
  longPeriod,

  /// The last cycle was shorter than 21 days.
  shortCycle,

  /// The last cycle was longer than 38 days.
  longCycle,

  /// Cycle lengths that vary by more than a week.
  irregular,
}

/// Where a day falls in the cycle, as the screen names it.
///
/// The textbook four, by the calendar: the period; the days after it while
/// the body builds up again; the fertile window round the estimated
/// ovulation; and the days after it until the next period. Estimates, like
/// everything here, and said as such.
enum CycleStage { period, follicular, fertile, luteal, unknown }

/// A predicted period or fertile window: [start] to [end], inclusive.
typedef CycleSpan = ({CycleDate start, CycleDate end});

/// One predicted cycle: its period, the fertile window round ovulation, and
/// the ovulation day itself. What the calendar draws for any month it is
/// turned to.
typedef CycleForecast = ({
  CycleSpan period,
  CycleSpan fertile,
  CycleDate ovulation,
});

/// Everything the cycle screen shows, computed from what was logged.
class CyclePrediction {
  const CyclePrediction({
    required this.today,
    required this.lastStart,
    required this.cycleDay,
    required this.inPeriod,
    required this.nextStart,
    required this.nextEarliest,
    required this.nextLatest,
    required this.averageCycle,
    required this.averagePeriod,
    required this.cyclesUsed,
    required this.variability,
    required this.confidence,
    required this.alerts,
  });

  final CycleDate today;

  /// Where the current cycle began.
  final CycleDate lastStart;

  /// Day of the current cycle, 1 on the day it started.
  final int cycleDay;
  final bool inPeriod;

  /// The most likely start of the next period, and how wide the honest
  /// answer is on either side of it.
  final CycleDate nextStart;
  final CycleDate nextEarliest;
  final CycleDate nextLatest;

  final int averageCycle;
  final int averagePeriod;

  /// Completed cycles the averages came from (0: the given defaults).
  final int cyclesUsed;

  /// Standard deviation of those cycles, in days.
  final double variability;
  final CycleConfidence confidence;
  final Set<CycleAlert> alerts;

  /// After the projected range has passed, another logged start is needed
  /// before either period or fertility dates can be estimated again.
  bool get forecastExpired => today.isAfter(nextLatest);

  /// The current cycle's calendar estimate, which ends at [nextStart].
  CycleForecast? get nextForecast => forecastExpired ? null : _forecast(0);

  /// The next three forecast entries from the same dates the calendar uses.
  List<CycleForecast> get upcoming =>
      forecastExpired ? const [] : [for (var i = 0; i < 3; i++) _forecast(i)];

  CycleForecast _forecast(int index) {
    final start = nextStart.addDays(averageCycle * index);
    final ovulation = start.addDays(-14);
    return (
      period: (start: start, end: start.addDays(averagePeriod - 1)),
      fertile: (start: ovulation.addDays(-5), end: ovulation.addDays(1)),
      ovulation: ovulation,
    );
  }

  /// Days until [nextStart]; negative when it is late.
  int get daysUntilNext => nextStart.daysSince(today);

  /// Every predicted cycle that shares a day with [from]..[to].
  ///
  /// [upcoming] stops after three cycles. The calendar can look further
  /// ahead from the same fixed anchor while the forecast is current.
  List<CycleForecast> forecastBetween(CycleDate from, CycleDate to) {
    if (forecastExpired || to.isBefore(from) || averageCycle < 1) {
      return const [];
    }
    // The earliest start whose period can still reach `from`, and the
    // latest whose fertile window can still begin before `to`.
    final before = from.addDays(-math.max(averagePeriod - 1, 13));
    final after = to.addDays(19);
    var first = math.max(
      0,
      _ceilDiv(before.daysSince(nextStart), averageCycle),
    );
    final last = _floorDiv(after.daysSince(nextStart), averageCycle);
    if (last < first) return const [];
    if (last - first > 240) first = last - 240;
    final out = <CycleForecast>[];
    for (var k = first; k <= last; k++) {
      final forecast = _forecast(k);
      if (_spans(from, to, forecast.period) ||
          _spans(from, to, forecast.fertile)) {
        out.add(forecast);
      }
    }
    return out;
  }

  static bool _spans(CycleDate from, CycleDate to, CycleSpan span) =>
      !span.start.isAfter(to) && !span.end.isBefore(from);

  /// The phase of [day]: by its place in the cycle that began at
  /// [lastStart], for any day from then until the next period.
  CycleStage stageOn(CycleDate day) {
    // Today is known — the period has been logged as going or ended — and
    // every other day is read from the averages.
    final bleeding = day == today
        ? inPeriod
        : day.daysSince(lastStart) < averagePeriod;
    if (bleeding) return CycleStage.period;
    final fertile = nextForecast?.fertile;
    if (fertile == null) return CycleStage.unknown;
    if (!day.isBefore(fertile.start) && !day.isAfter(fertile.end)) {
      return CycleStage.fertile;
    }
    return day.isBefore(fertile.start)
        ? CycleStage.follicular
        : CycleStage.luteal;
  }

  /// Today's stage.
  CycleStage get stage => stageOn(today);
}

/// Predicts from the person's own history, not from a fixed 28.
///
/// The arithmetic is the plain calendar method every cycle app starts
/// from: average the recent cycles, count forward from the last start, and
/// put ovulation fourteen days before the next one. What makes it honest
/// is the rest — a range rather than a date, widening with how much the
/// cycles vary, and a confidence that says when there is not enough to go
/// on. None of this is contraception, and the screen says so.
abstract final class CyclePredictor {
  /// Cycles shorter or longer than this are taken as a period that was
  /// missed in the log, or logged twice, rather than as a real cycle.
  static const minCycle = 15;
  static const maxCycle = 60;

  /// How many recent cycles the averages use: enough to smooth one odd
  /// month, few enough to follow a change.
  static const window = 6;

  /// Null until a period has been logged.
  static CyclePrediction? predict({
    required List<CyclePeriod> periods,
    required CycleDate today,
    int typicalCycle = 28,
    int typicalPeriod = 5,
  }) {
    if (periods.isEmpty) return null;
    final sorted = [...periods]..sort((a, b) => a.start.compareTo(b.start));
    // A start in the future is a mistake in the log, not a cycle yet.
    final past = sorted.where((p) => !p.start.isAfter(today)).toList();
    if (past.isEmpty) return null;

    final all = _plausibleLengths(past);
    // A gap about twice the usual can be a missed entry.
    final usual = _median(all);
    final lengths = _withoutLikelyMissedLogs(all, usual);
    final recent = lengths.length > window
        ? lengths.sublist(lengths.length - window)
        : lengths;

    final averageCycle = recent.isEmpty
        ? typicalCycle.clamp(minCycle, maxCycle)
        : (recent.reduce((a, b) => a + b) / recent.length).round();
    final variability = _deviation(recent);

    final periodLengths = [
      for (final p in past)
        if (p.length case final l? when l >= 1 && l <= 15) l,
    ];
    final recentPeriods = periodLengths.length > window
        ? periodLengths.sublist(periodLengths.length - window)
        : periodLengths;
    final averagePeriod = recentPeriods.isEmpty
        ? typicalPeriod.clamp(1, 15)
        : (recentPeriods.reduce((a, b) => a + b) / recentPeriods.length)
              .round();

    final confidence = recent.length >= 3 && variability <= 2
        ? CycleConfidence.high
        : recent.length >= 2 && variability <= 4
        ? CycleConfidence.medium
        : CycleConfidence.low;
    final spread = switch (confidence) {
      CycleConfidence.high => 1,
      CycleConfidence.medium => 2,
      CycleConfidence.low => math.max(3, variability.ceil()),
    };

    final last = past.last;
    final nextStart = last.start.addDays(averageCycle);
    final inPeriod =
        last.contains(today) &&
        (last.end != null || today.daysSince(last.start) < 15);

    final alerts = <CycleAlert>{};
    final latest = nextStart.addDays(spread);
    if (!inPeriod && today.daysSince(latest) > 10) alerts.add(CycleAlert.late);
    final openFor = last.isOpen ? today.daysSince(last.start) + 1 : 0;
    if (openFor > 8 || (last.length ?? 0) > 8) {
      alerts.add(CycleAlert.longPeriod);
    }
    if (lengths.isNotEmpty) {
      final latestCycle = past.last.start.daysSince(
        past[past.length - 2].start,
      );
      // Read as a period that was never logged, as the averages read it —
      // not as a long cycle to see a doctor about.
      final missedLog =
          all.length >= 3 &&
          latestCycle >= usual * 1.75 &&
          latestCycle <= usual * 2.25;
      if (latestCycle >= minCycle && latestCycle < 21) {
        alerts.add(CycleAlert.shortCycle);
      }
      if (latestCycle > 38 && latestCycle <= maxCycle && !missedLog) {
        alerts.add(CycleAlert.longCycle);
      }
    }
    if (recent.length >= 3 && variability > 7) alerts.add(CycleAlert.irregular);

    return CyclePrediction(
      today: today,
      lastStart: last.start,
      cycleDay: today.daysSince(last.start) + 1,
      inPeriod: inPeriod,
      nextStart: nextStart,
      nextEarliest: nextStart.addDays(-spread),
      nextLatest: latest,
      averageCycle: averageCycle,
      averagePeriod: averagePeriod,
      cyclesUsed: recent.length,
      variability: variability,
      confidence: confidence,
      alerts: alerts,
    );
  }

  /// The lengths between consecutive period starts, oldest first, at most
  /// [limit] of them.
  ///
  /// Shown as a small chart beside the averages: a number is easier to trust
  /// when the run that produced it is visible. Gaps the predictor would read
  /// as a mistyped date rather than a cycle are left out for the same reason
  /// they are left out of the average — a chart that disagrees with the
  /// number above it teaches nobody anything.
  ///
  /// [today], when given, leaves out a start logged after it, as [predict]
  /// does (2.8.19): a period mistyped into next week drew a bar the average
  /// never counted.
  static List<int> intervals(
    List<CyclePeriod> periods, {
    int limit = 8,
    CycleDate? today,
  }) {
    if (limit <= 0) return const [];
    final sorted = [
      for (final p in periods)
        if (today == null || !p.start.isAfter(today)) p,
    ]..sort((a, b) => a.start.compareTo(b.start));
    final all = _plausibleLengths(sorted);
    final lengths = _withoutLikelyMissedLogs(all, _median(all));
    return lengths.length > limit
        ? lengths.sublist(lengths.length - limit)
        : lengths;
  }

  static List<int> _plausibleLengths(List<CyclePeriod> periods) => [
    for (var i = 1; i < periods.length; i++)
      if (periods[i].start.daysSince(periods[i - 1].start) case final days
          when days >= minCycle && days <= maxCycle)
        days,
  ];

  static List<int> _withoutLikelyMissedLogs(List<int> all, double usual) => [
    for (final length in all)
      if (all.length < 3 || length < usual * 1.75 || length > usual * 2.25)
        length,
  ];

  static double _median(List<int> values) {
    if (values.isEmpty) return 0;
    final sorted = [...values]..sort();
    final mid = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[mid].toDouble()
        : (sorted[mid - 1] + sorted[mid]) / 2;
  }

  static double _deviation(List<int> values) {
    if (values.length < 2) return 0;
    final mean = values.reduce((a, b) => a + b) / values.length;
    final sum = values.fold<double>(0, (s, v) => s + (v - mean) * (v - mean));
    return math.sqrt(sum / (values.length - 1));
  }
}

/// [a] ÷ [b] rounded down, for a negative [a] too.
int _floorDiv(int a, int b) => (a - a % b) ~/ b;

/// [a] ÷ [b] rounded up, for a negative [a] too.
int _ceilDiv(int a, int b) {
  final down = _floorDiv(a, b);
  return down * b == a ? down : down + 1;
}
