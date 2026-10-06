import 'package:nex_core/nex_core.dart';

import 'nex_preferences.dart';
import 'nex_services.dart';

/// What the assistant is told when it asks about «Cycle».
///
/// Nothing at all unless the person turned on "Let the assistant read
/// Cycle" — and «Cycle» itself — in which case it is a short factual
/// summary: where the cycle is, the next period and fertile window, the
/// averages, the recent periods, the symptoms of the last three months and
/// any patterns. Never the day notes, which are the person's own words
/// about their body and were not written for a model to read.
Future<String> nexCycleSummaryForAssistant({
  required NexServices services,
  required NexPreferences preferences,
  DateTime? now,
}) async {
  if (!preferences.cycleEnabled || !preferences.cycleAssistantAccess) {
    return 'Cycle: not shared. The user has not allowed the assistant to '
        'read Cycle. If they want this, it is "Let the assistant read Cycle" '
        "in Cycle's settings.";
  }
  final at = now ?? DateTime.now();
  final today = DateTime(at.year, at.month, at.day);
  final periods = await services.cyclePeriods();
  final logs = await services.cycleDays(DateTime(2000), today);
  final mode = preferences.cycleMode;
  final out = StringBuffer(
    'Cycle (menstrual cycle data the user chose to share; answer kindly '
    'and never as a diagnosis):\n',
  );
  out.writeln('Mode: ${mode.name}');
  out.writeln('Today: ${CycleDate.of(today)}');
  if (mode == CycleMode.pregnant) {
    final start =
        preferences.cyclePregnancyStart ??
        (periods.isEmpty ? null : periods.last.start);
    if (start != null) {
      final p = CyclePregnancy(lastPeriod: start, today: CycleDate.of(today));
      out.writeln(
        'Pregnancy: week ${p.weeks}, day ${p.days}; due ${p.dueDate}; '
        'trimester ${p.trimester}',
      );
    }
  }
  final prediction = CyclePredictor.predict(
    periods: periods,
    today: CycleDate.of(today),
    typicalCycle: preferences.cycleTypicalLength,
    typicalPeriod: preferences.cycleTypicalPeriod,
  );
  if (prediction != null && mode.predicts) {
    final p = prediction;
    out.writeln(
      'Cycle day ${p.cycleDay}; ${p.inPeriod ? 'in a period' : 'not in a period'}',
    );
    out.writeln(
      'Next period: likely ${p.nextStart} '
      '(${p.nextEarliest} to ${p.nextLatest}), confidence ${p.confidence.name}',
    );
    out.writeln(
      'Fertile window: ${p.fertile.start} to ${p.fertile.end}; '
      'likely ovulation ${p.ovulation}',
    );
    if (p.alerts.isNotEmpty) {
      out.writeln('Worth noting: ${p.alerts.map((a) => a.name).join(', ')}');
    }
  }
  if (prediction != null) {
    out.writeln(
      'Averages: cycle ${prediction.averageCycle} days '
      '(±${prediction.variability.toStringAsFixed(1)}), period '
      '${prediction.averagePeriod} days, from ${prediction.cyclesUsed} cycles',
    );
  }
  if (periods.isEmpty) {
    out.writeln('No periods logged yet.');
  } else {
    out.writeln('Recent periods:');
    for (final p in periods.reversed.take(6)) {
      out.writeln(
        '- ${p.start} to ${p.end ?? 'ongoing'}'
        '${p.length == null ? '' : ' (${p.length} days)'}',
      );
    }
  }
  final since = CycleDate.of(today).addDays(-90);
  final counts = <CycleSymptom, int>{};
  for (final log in logs) {
    if (log.day.isBefore(since)) continue;
    for (final s in log.symptoms) {
      counts[s] = (counts[s] ?? 0) + 1;
    }
  }
  if (counts.isNotEmpty) {
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    out.writeln(
      'Symptoms, last 90 days: '
      '${sorted.map((e) => '${e.key.name} ×${e.value}').join(', ')}',
    );
  }
  final patterns = CyclePatterns.find(periods: periods, logs: logs);
  if (patterns.isNotEmpty) {
    out.writeln(
      'Patterns: ${patterns.take(6).map((p) => switch (p.phase) {
        CyclePhase.beforePeriod => '${p.symptom.name} about ${p.daysBefore} days before the period',
        CyclePhase.period => '${p.symptom.name} during the period',
        CyclePhase.ovulation => '${p.symptom.name} around ovulation',
      }).join('; ')}',
    );
  }
  return out.toString().trim();
}
