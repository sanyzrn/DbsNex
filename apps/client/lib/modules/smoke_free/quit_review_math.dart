import 'quit_model.dart';

/// Which part of the local day a report belongs to. Four wide buckets, so a
/// handful of logs can say something without pretending to be a sleep or
/// work schedule.
String cravingPeriodKey(DateTime at) {
  final hour = at.toLocal().hour;
  if (hour >= 5 && hour < 12) return 'morning';
  if (hour >= 12 && hour < 17) return 'afternoon';
  if (hour >= 17 && hour < 22) return 'evening';
  return 'night';
}

/// A bounded time window over explicit reports, never inferred abstinence.
class QuitInsights {
  QuitInsights(List<Craving> cravings, DateTime now) {
    now = now.toLocal();
    final today = DateTime.utc(now.year, now.month, now.day);
    final first = today.subtract(const Duration(days: 29));
    for (final craving in cravings) {
      final at = craving.at.toLocal();
      final day = DateTime.utc(at.year, at.month, at.day);
      if (at.isAfter(now) || day.isBefore(first) || day.isAfter(today)) {
        continue;
      }
      recent.add(craving);
      final period = cravingPeriodKey(at);
      periodCounts[period] = (periodCounts[period] ?? 0) + 1;
      if (craving.afterIntensity != null) {
        rated++;
        if (craving.afterIntensity! < craving.intensity) eased++;
      }
    }
  }
  final recent = <Craving>[];
  final periodCounts = <String, int>{};
  int rated = 0, eased = 0;

  /// The one part of the day with the most reports, if it is both meaningful
  /// (at least two) and ahead of every other part. A tie says nothing.
  String? get peakPeriod {
    final entries = periodCounts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });
    if (entries.isEmpty || entries.first.value < 2) return null;
    if (entries.length > 1 && entries[1].value == entries.first.value) {
      return null;
    }
    return entries.first.key;
  }

  int get peakPeriodCount => periodCounts[peakPeriod] ?? 0;
}
