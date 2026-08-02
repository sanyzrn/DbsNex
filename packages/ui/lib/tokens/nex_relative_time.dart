/// Which bucket a moment falls into relative to now, and how many of that
/// unit — "8h" is [NexRelativeUnit.hours] with a count of 8.
enum NexRelativeUnit { now, minutes, hours, days, weeks, months, years }

/// A moment bucketed for display, without an opinion on the words: `now`,
/// `Xm`, `Xh`, `Xd`, `Xw`, `Xmo`, `Xy` in English, "الان", "X دقیقه قبل" and so
/// on in Persian — the app supplies those, this package carries no
/// localisations of its own (see [NexCardStrings]).
class NexRelativeTime {
  const NexRelativeTime(this.unit, this.count);

  final NexRelativeUnit unit;

  /// 0 for [NexRelativeUnit.now]; otherwise how many of [unit] have passed.
  final int count;
}

/// Buckets [value] against [now] (defaults to the real clock — overridable so
/// a test is not racing the wall clock for the one minute a case is on the
/// wrong side of a boundary).
///
/// A future [value] — clock skew, or a note whose timestamp has not synced
/// yet — reads as `now` rather than a negative count nobody can parse.
NexRelativeTime nexRelativeTimeOf(DateTime value, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final diff = reference.difference(value);
  if (diff.isNegative) return const NexRelativeTime(NexRelativeUnit.now, 0);

  final minutes = diff.inMinutes;
  if (minutes < 1) return const NexRelativeTime(NexRelativeUnit.now, 0);
  if (minutes < 60) return NexRelativeTime(NexRelativeUnit.minutes, minutes);

  final hours = diff.inHours;
  if (hours < 24) return NexRelativeTime(NexRelativeUnit.hours, hours);

  final days = diff.inDays;
  if (days < 7) return NexRelativeTime(NexRelativeUnit.days, days);
  // Up to four weeks — past that, "5w" reads less naturally than "1mo".
  if (days < 30) return NexRelativeTime(NexRelativeUnit.weeks, days ~/ 7);
  if (days < 365) return NexRelativeTime(NexRelativeUnit.months, days ~/ 30);
  return NexRelativeTime(NexRelativeUnit.years, days ~/ 365);
}
