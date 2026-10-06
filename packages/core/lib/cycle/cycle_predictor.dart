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

/// A predicted period or fertile window: [start] to [end], inclusive.
typedef CycleSpan = ({CycleDate start, CycleDate end});

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
    required this.ovulation,
    required this.fertile,
    required this.averageCycle,
    required this.averagePeriod,
    required this.cyclesUsed,
    required this.variability,
    required this.confidence,
    required this.alerts,
    required this.upcoming,
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

  /// Estimated, about fourteen days before the next period.
  final CycleDate ovulation;

  /// The five days before ovulation, the day itself and the day after.
  final CycleSpan fertile;

  final int averageCycle;
  final int averagePeriod;

  /// Completed cycles the averages came from (0: the given defaults).
  final int cyclesUsed;

  /// Standard deviation of those cycles, in days.
  final double variability;
  final CycleConfidence confidence;
  final Set<CycleAlert> alerts;

  /// The next three predicted periods and fertile windows, for the calendar.
  final List<({CycleSpan period, CycleSpan fertile})> upcoming;

  /// Days until [nextStart]; negative when it is late.
  int get daysUntilNext => nextStart.daysSince(today);
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

    final all = <int>[
      for (var i = 1; i < past.length; i++)
        past[i].start.daysSince(past[i - 1].start),
    ].where((d) => d >= minCycle && d <= maxCycle).toList();
    // A gap about twice the usual is a period that was never logged — two
    // cycles, not one long one — and would drag every prediction late.
    final usual = _median(all);
    final lengths = [
      for (final l in all)
        if (all.length < 3 || l < usual * 1.75 || l > usual * 2.25) l,
    ];
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
    final ovulation = nextStart.addDays(-14);
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
      if (latestCycle >= minCycle && latestCycle < 21) {
        alerts.add(CycleAlert.shortCycle);
      }
      if (latestCycle > 38 && latestCycle <= maxCycle) {
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
      ovulation: ovulation,
      fertile: (start: ovulation.addDays(-5), end: ovulation.addDays(1)),
      averageCycle: averageCycle,
      averagePeriod: averagePeriod,
      cyclesUsed: recent.length,
      variability: variability,
      confidence: confidence,
      alerts: alerts,
      upcoming: [
        for (var k = 0; k < 3; k++)
          () {
            final start = nextStart.addDays(averageCycle * k);
            final ov = start.addDays(-14);
            return (
              period: (start: start, end: start.addDays(averagePeriod - 1)),
              fertile: (start: ov.addDays(-5), end: ov.addDays(1)),
            );
          }(),
      ],
    );
  }

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
