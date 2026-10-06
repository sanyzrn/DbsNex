import 'cycle_models.dart';

/// Where in a cycle a day falls, for patterns.
enum CyclePhase {
  /// A logged period day.
  period,

  /// The five days before the next period.
  beforePeriod,

  /// Around ovulation: twelve to sixteen days before the next period.
  ovulation,
}

/// "Headaches usually come about two days before your period."
class CyclePattern {
  const CyclePattern({
    required this.symptom,
    required this.phase,
    required this.cycles,
    required this.daysBefore,
  });

  final CycleSymptom symptom;
  final CyclePhase phase;

  /// How many different cycles it was logged in, in that phase.
  final int cycles;

  /// For [CyclePhase.beforePeriod]: on average how many days before the
  /// period it came, rounded; otherwise 0.
  final int daysBefore;
}

/// Finds the symptoms that keep coming back at the same point in the cycle.
///
/// Only completed cycles count, so "before your period" is measured against
/// a period that really came rather than one predicted. A pattern needs the
/// symptom in the same phase in at least [minCycles] different cycles, and
/// in that phase at least half the times it was logged at all — so a
/// headache that comes whenever is not reported as a premenstrual one.
abstract final class CyclePatterns {
  static const minCycles = 2;

  static List<CyclePattern> find({
    required List<CyclePeriod> periods,
    required List<CycleDayLog> logs,
  }) {
    final sorted = [...periods]..sort((a, b) => a.start.compareTo(b.start));
    if (sorted.length < 2) return const [];

    // symptom -> phase -> {cycle index}
    final seen = <CycleSymptom, Map<CyclePhase, Set<int>>>{};
    final before = <CycleSymptom, List<int>>{};
    final total = <CycleSymptom, int>{};

    for (final log in logs) {
      if (log.symptoms.isEmpty) continue;
      // The cycle this day belongs to: the last start on or before it, with
      // a next start after it.
      var index = -1;
      for (var i = 0; i < sorted.length - 1; i++) {
        if (!log.day.isBefore(sorted[i].start) &&
            log.day.isBefore(sorted[i + 1].start)) {
          index = i;
          break;
        }
      }
      for (final symptom in log.symptoms) {
        total[symptom] = (total[symptom] ?? 0) + 1;
      }
      if (index < 0) continue;
      final cycle = sorted[index];
      final next = sorted[index + 1].start;
      final until = next.daysSince(log.day);
      final phase = cycle.contains(log.day)
          ? CyclePhase.period
          : until >= 1 && until <= 5
          ? CyclePhase.beforePeriod
          : until >= 12 && until <= 16
          ? CyclePhase.ovulation
          : null;
      if (phase == null) continue;
      for (final symptom in log.symptoms) {
        seen
            .putIfAbsent(symptom, () => {})
            .putIfAbsent(phase, () => {})
            .add(index);
        if (phase == CyclePhase.beforePeriod) {
          before.putIfAbsent(symptom, () => []).add(until);
        }
      }
    }

    final patterns = <CyclePattern>[];
    seen.forEach((symptom, phases) {
      phases.forEach((phase, cycles) {
        if (cycles.length < minCycles) return;
        final inPhase = phase == CyclePhase.beforePeriod
            ? before[symptom]!.length
            : cycles.length;
        if (inPhase * 2 < (total[symptom] ?? 0)) return;
        final days = phase == CyclePhase.beforePeriod
            ? (before[symptom]!.reduce((a, b) => a + b) /
                      before[symptom]!.length)
                  .round()
            : 0;
        patterns.add(
          CyclePattern(
            symptom: symptom,
            phase: phase,
            cycles: cycles.length,
            daysBefore: days,
          ),
        );
      });
    });
    patterns.sort((a, b) => b.cycles.compareTo(a.cycles));
    return patterns;
  }
}
