import 'parking_models.dart';

/// Everything the parking screen shows that can be worked out from a
/// session and a clock — kept free of widgets so it can be tested on its
/// own. Times are absolute instants (`toIso8601String()` in storage), so a
/// daylight-saving change or a midnight crossing never changes a duration.
class ParkingLogic {
  const ParkingLogic._();

  /// Whether [session] is still open — a session with no `foundAt`.
  static bool isActive(Map<String, Object?> session) =>
      !session.containsKey('foundAt') ||
      session['foundAt'] == null ||
      session['foundAt'] == '';

  static bool knownDuration(Map<String, Object?> body) {
    final start = ParkingModels.readDate(body, 'startedAt');
    final end = ParkingModels.readDate(body, 'foundAt');
    return start != null &&
        (isActive(body) || end != null && !end.isBefore(start));
  }

  /// How long the car sat (or has been sitting) there. Closed sessions
  /// measure from `startedAt` to `foundAt`; open ones from `startedAt` to
  /// [now], which is a foreground look at the clock, not a running job.
  static Duration elapsedOf(Map<String, Object?> session, DateTime now) {
    final started = ParkingModels.readDate(session, 'startedAt') ?? now;
    final end =
        ParkingModels.readDate(session, 'foundAt') ??
        (now.isBefore(started) ? started : now);
    return end.isBefore(started) ? Duration.zero : end.difference(started);
  }

  /// The open sessions that name the same vehicle as [vehicle] — the ones
  /// a new parking has to ask about before it starts.
  static List<Map<String, Object?>> activeForVehicle(
    Iterable<Map<String, Object?>> sessions,
    String vehicle,
  ) => [
    for (final session in sessions)
      if (isActive(session) &&
          ParkingModels.sameVehicle(
            ParkingModels.readString(session, 'vehicle'),
            vehicle,
          ))
        session,
  ];

  /// Whether [session] mentions [query] in any field a person would search
  /// by: the place, the vehicle, the floor, the spot and the landmark note.
  /// An empty or blank query matches everything.
  static bool matchesQuery(Map<String, Object?> session, String query) {
    final q = ParkingModels.fold(query);
    if (q.isEmpty) {
      return true;
    }
    for (final key in const ['place', 'vehicle', 'floor', 'spot', 'landmark']) {
      if (ParkingModels.fold(ParkingModels.readString(session, key))
          .contains(q)) {
        return true;
      }
    }
    return false;
  }

  /// The vehicle of the parking that began most recently, for «I parked».
  /// The store lists the most recently *saved* record first, so a corrected
  /// old entry would otherwise make one tap pick the wrong car.
  static String lastVehicle(Iterable<Map<String, Object?>> sessions) {
    String? latest;
    DateTime? at;
    for (final session in sessions) {
      final name = ParkingModels.readString(session, 'vehicle').trim();
      if (name.isEmpty) {
        continue;
      }
      final started = ParkingModels.readDate(session, 'startedAt');
      if (latest == null ||
          started != null && (at == null || started.isAfter(at))) {
        latest = name;
        at = started;
      }
    }
    return latest ?? '';
  }

  /// Closed sessions, the most recently started first. The store's own
  /// order is "most recently *saved*" — a just-edited old entry would jump
  /// the queue, so history is ordered by when the parking actually began.
  static List<Map<String, Object?>> historyOf(
    Iterable<Map<String, Object?>> sessions,
  ) {
    final closed =
        [
          for (final session in sessions)
            if (!isActive(session)) session,
        ]..sort((a, b) {
          final aStart = ParkingModels.readDate(a, 'startedAt');
          final bStart = ParkingModels.readDate(b, 'startedAt');
          return (bStart ?? DateTime(0)).compareTo(aStart ?? DateTime(0));
        });
    return closed;
  }

  // ------------------------------------------------------- expiry status

  /// What the screen can honestly say about the time the person said the
  /// parking ends. `remaining` is minutes still on the meter; `over` is
  /// minutes past it. Nothing fires in the background: this is read while
  /// the screen is open, from a time the person typed themselves.
  static ({bool over, int minutes, int seconds}) expiryOf(
    Map<String, Object?> session,
    DateTime now,
  ) {
    final expires = ParkingModels.readDate(session, 'expiresAt');
    if (expires == null) {
      return (over: false, minutes: 0, seconds: 0);
    }
    final diff = expires.difference(now);
    // The exact end moment counts as past: "may have ended just now" is
    // the honest thing to say when the time written has arrived.
    if (diff <= Duration.zero) {
      return (over: true, minutes: -diff.inMinutes, seconds: -diff.inSeconds);
    }
    return (over: false, minutes: diff.inMinutes, seconds: diff.inSeconds);
  }

  // ---------------------------------------------------------- reminders

  /// The moment a reminder should ring for a paid parking: [minutes] before
  /// the written end. Kept here so the arithmetic is tested without a
  /// widget; a reminder is never set in the past.
  static DateTime reminderAt(DateTime expiresAt, int minutes) =>
      expiresAt.subtract(Duration(minutes: minutes));

  /// Whether a reminder [minutes] before [expiresAt] still makes sense at
  /// [now]: a positive lead time whose moment is still ahead.
  static bool reminderFits(DateTime expiresAt, int minutes, DateTime now) =>
      minutes > 0 && reminderAt(expiresAt, minutes).isAfter(now);

  /// Whether a whole-minute reminder can still be offered: the end is more
  /// than a minute away, so at least a one-minute lead exists.
  static bool canRemind(DateTime expiresAt, DateTime now) =>
      reminderFits(expiresAt, 1, now);

  /// The lead a paid parking's reminder should open on. A familiar ten when
  /// it fits, five when ten is too long, and the largest whole minute left
  /// for a short stay; null when the end is a minute away or less.
  static int? suggestedReminderMinutes(DateTime expiresAt, DateTime now) {
    for (final minutes in const [10, 5]) {
      if (reminderFits(expiresAt, minutes, now)) return minutes;
    }
    final micros = expiresAt.difference(now).inMicroseconds;
    final max = (micros - 1) ~/ Duration.microsecondsPerMinute;
    return max < 1 ? null : max;
  }

  // ------------------------------------------------ duration formatting

  /// A duration split the way both languages show it: up to an hour in
  /// minutes, up to a day in hours and minutes, longer in days and hours.
  /// Rounded down to whole units — 89 seconds is a minute, not "1.5".
  static ({int days, int hours, int minutes}) split(Duration value) {
    final total = value.isNegative ? Duration.zero : value;
    final days = total.inDays;
    final hours = total.inHours % 24;
    final minutes = total.inMinutes % 60;
    return (days: days, hours: hours, minutes: minutes);
  }

  // ------------------------------------------------------ search history

  /// The queries worth offering again, the newest first and without
  /// duplicates, capped at [limit]. A fresh copy of a query already in the
  /// list moves it to the front rather than growing the list.
  static List<String> rememberQueries(
    Iterable<String> old,
    String fresh, {
    int limit = ParkingModels.searchHistoryLimit,
  }) {
    final q = fresh.trim();
    if (q.isEmpty) {
      return old.toList();
    }
    final key = ParkingModels.fold(q);
    return [
      q,
      for (final query in old)
        if (ParkingModels.fold(query) != key) query,
    ].take(limit).toList();
  }

  // ------------------------------------------------------ place templates

  /// Whether [a] and [b] describe the same remembered place: same place,
  /// floor and spot, ignoring case and space. The landmark note may differ
  /// between visits; the parking spot is what identifies it.
  static bool samePlace(Map<String, Object?> a, Map<String, Object?> b) {
    bool same(String key) =>
        ParkingModels.fold(ParkingModels.readString(a, key)) ==
        ParkingModels.fold(ParkingModels.readString(b, key));
    return same('place') && same('floor') && same('spot');
  }
}
