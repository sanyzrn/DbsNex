import 'package:nex_core/nex_core.dart';

/// What the two «Cycle» home-screen widgets draw from: a few dates and
/// numbers, in a file of its own beside the notes snapshot.
///
/// Its own file rather than more fields in `nex_widget_snapshot.json`,
/// because the two are read by different widgets and hidden by different
/// rules: a timeline widget has no business carrying anyone's cycle, and a
/// person who turns «Cycle» off should find this file emptied without the
/// notes widget being touched.
///
/// Dates, not sentences. The widget works out "in 12 days" from today's date
/// each time it is drawn, so the number stays right on the days the app is
/// not opened — Android wakes the widget every few hours, and a count baked
/// in here would be yesterday's by morning. Never a day log, a note, a
/// symptom or a mood: only what the ring and its lines need.
abstract final class NexCycleWidgetSnapshot {
  /// Bumped when the field set changes; the reader accepts this and older.
  static const version = 1;

  static const fileName = 'nex_cycle_widget.json';

  static Map<String, Object?> build({
    required bool enabled,
    required bool setUp,
    required bool hidden,
    required CycleMode mode,
    required List<CyclePeriod> periods,
    required CyclePrediction? prediction,
    CycleDate? pregnancyStart,
  }) {
    Map<String, Object?> only(String state) => {
      'version': version,
      'state': state,
    };
    if (!enabled) return only('off');
    // Locked wins over everything below it: nothing about a cycle reaches
    // the file while the app lock is closed and the widgets were not told to
    // ignore it — the same rule the notes follow.
    if (hidden) return only('locked');
    if (!setUp) return only('setup');
    final last = periods.isEmpty ? null : periods.last;
    final p = mode.predicts ? prediction : null;
    return {
      'version': version,
      'state': 'ready',
      'mode': mode.name,
      if (mode == CycleMode.pregnant)
        'pregnancyStart': '${pregnancyStart ?? last?.start}',
      if (last != null) ...{
        'lastStart': '${last.start}',
        if (last.end case final end?) 'periodEnd': '$end',
      },
      if (p != null) ...{
        'averageCycle': p.averageCycle,
        'averagePeriod': p.averagePeriod,
        'nextStart': '${p.nextStart}',
        'fertileStart': '${p.fertile.start}',
        'fertileEnd': '${p.fertile.end}',
        'ovulation': '${p.ovulation}',
      },
    };
  }
}
