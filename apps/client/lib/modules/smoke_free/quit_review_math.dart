import 'quit_model.dart';

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
      if (craving.afterIntensity != null) {
        rated++;
        if (craving.afterIntensity! < craving.intensity) eased++;
      }
    }
  }
  final recent = <Craving>[];
  int rated = 0, eased = 0;
}
