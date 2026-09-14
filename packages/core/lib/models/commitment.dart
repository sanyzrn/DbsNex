/// The things that come back round: the insurance every year, the rent every
/// month, the tablet every eight hours, the glass of water every two.
///
/// These are deliberately **not notes**, and the reasons are worth stating
/// because "it could be a note with a repeating reminder" is the first thing
/// anybody proposes.
///
/// - A note belongs on the timeline. These do not. A tablet every eight hours
///   is three rows a day, every day, for as long as the course lasts; water is
///   six. Inside a month that is two hundred rows of a stream whose whole
///   claim is that it is worth scrolling.
/// - "Done" means something different. A note's reminder, once it has rung
///   and been seen, is spent. A commitment that has been met is not finished —
///   it is due again, and the useful thing the app can do at that moment is
///   work out when.
/// - They carry a notion a note has no field for: how far in advance being
///   reminded is any use. A year's insurance is worth raising a week out. Two
///   days out is right for the rent, and useless for the water.
///
/// Everything here is pure and has no storage in it, so the arithmetic — the
/// part that is actually hard — is tested without a database and without a
/// clock.
library;

/// The unit a commitment repeats in. Paired with a count, so "every 8 hours"
/// and "every 3 months" are both expressible without an entry per shape.
enum NexCadence {
  hours,
  days,
  weeks,
  months,
  years;

  static NexCadence fromWire(String? wire) => values.firstWhere(
    (value) => value.name == wire,
    orElse: () => NexCadence.days,
  );

  String get wireName => name;
}

/// One recurring obligation.
///
/// Immutable, like everything else in core. Editing produces a new one
/// through [copyWith]; rolling one forward produces a new one through [met].
class NexCommitment {
  const NexCommitment({
    required this.id,
    required this.title,
    required this.cadence,
    required this.every,
    required this.dueAt,
    required this.createdAt,
    required this.updatedAt,
    this.lead,
    this.windowStart,
    this.windowEnd,
    this.lastMetAt,
    this.metToday = 0,
    this.metTodayOn,
    this.paused = false,
    this.notify = true,
    this.rev = 1,
  });

  final String id;
  final String title;
  final NexCadence cadence;

  /// How many [cadence] units between occurrences. Always at least one.
  final int every;

  /// When it next comes round. Local time, because every one of these is
  /// something a person does at an hour they think of in their own day —
  /// "the first of the month", "eight in the morning" — and a UTC instant
  /// would drift against that across a daylight-saving boundary.
  final DateTime dueAt;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// How far ahead of [dueAt] this is worth raising, or null to take the
  /// default for its cadence — see [nexDefaultLead].
  ///
  /// Null rather than the resolved value, so that a commitment left alone
  /// follows the app's judgement as that judgement improves, and one the user
  /// has set is left exactly where they set it. The same reasoning the
  /// widget's filters follow.
  final Duration? lead;

  /// The hours of the day an [NexCadence.hours] commitment may fall in, as
  /// minutes past midnight. Null on both means "any hour".
  ///
  /// Water every two hours is twelve times a day without this, three of them
  /// while you are asleep. It is not a general-purpose schedule — it exists
  /// because the one cadence fine enough to be useful is also the one fine
  /// enough to be absurd.
  final int? windowStart;
  final int? windowEnd;

  final DateTime? lastMetAt;

  /// How many times it has been met on [metTodayOn].
  ///
  /// Two fields rather than a list of every completion, because the only
  /// question anybody asks of an hourly commitment is "how am I doing today"
  /// and the answer stops mattering at midnight. A row per glass of water is
  /// a log nobody reads, growing forever.
  final int metToday;
  final String? metTodayOn;

  final bool paused;

  /// Whether this one rings when it falls due.
  ///
  /// On by default, because setting something up to come back round and not
  /// wanting to be told is the unusual case — but it is a real case, and the
  /// hourly cadences are why. Water every two hours is seven notifications a
  /// day, which is the difference between a useful app and one somebody
  /// silences at the OS level, taking every other reminder with it.
  final bool notify;

  /// Bumped on every local change, so these rows can ride the same sync
  /// machinery the notes do when it reaches them. Nothing reads it yet.
  final int rev;

  /// How far ahead this one is worth raising.
  Duration get effectiveLead => lead ?? nexDefaultLead(cadence, every);

  /// The gap between occurrences, where that is a fixed length of time.
  ///
  /// Null for months and years, which are not: a month is 28 to 31 days and
  /// a year is 365 or 366. Those two advance by calendar arithmetic in
  /// [nexAdvance] instead, which is the whole reason this returns null rather
  /// than an approximation somebody would later treat as exact.
  Duration? get period => switch (cadence) {
    NexCadence.hours => Duration(hours: every),
    NexCadence.days => Duration(days: every),
    NexCadence.weeks => Duration(days: 7 * every),
    NexCadence.months || NexCadence.years => null,
  };

  /// Whether it is already past due at [now].
  bool isOverdue(DateTime now) => !paused && dueAt.isBefore(now);

  /// Whether it is close enough to say something about at [now].
  ///
  /// The whole point of [lead]: an insurance renewal eleven months out is not
  /// news, and the same renewal five days out is the most useful sentence the
  /// app has. Overdue always counts — something missed does not stop being
  /// worth saying because its moment has passed.
  bool isWaiting(DateTime now) {
    if (paused) return false;
    if (dueAt.isBefore(now)) return true;
    return dueAt.difference(now) <= effectiveLead;
  }

  /// How many times a day this one comes round, for the hourly ones.
  ///
  /// Null for everything else, where the question is meaningless. Used by the
  /// brief to say "3 of 6 today" rather than listing six separate glasses of
  /// water as six separate things waiting on somebody.
  int? get timesPerDay {
    if (cadence != NexCadence.hours) return null;
    final span = _windowMinutes ?? 24 * 60;
    final step = every * 60;
    if (step <= 0) return null;
    return (span ~/ step).clamp(1, 24);
  }

  int? get _windowMinutes {
    final start = windowStart;
    final end = windowEnd;
    if (start == null || end == null) return null;
    // A window that wraps past midnight is a night shift, and is legitimate.
    return end > start ? end - start : (24 * 60) - start + end;
  }

  /// How many times it has been met on the day [now] falls in.
  ///
  /// Zero once the day rolls over, without anything having to run at
  /// midnight to reset it — the stored day key simply stops matching.
  int metOn(DateTime now) =>
      metTodayOn == nexDayKey(now) ? metToday : 0;

  /// The same commitment, met at [at] and rolled forward to its next turn.
  NexCommitment met(DateTime at) {
    final next = nexAdvance(this, after: at);
    final today = nexDayKey(at);
    return copyWith(
      dueAt: next,
      lastMetAt: at,
      metToday: (metTodayOn == today ? metToday : 0) + 1,
      metTodayOn: today,
      updatedAt: at,
    );
  }

  NexCommitment copyWith({
    String? title,
    NexCadence? cadence,
    int? every,
    DateTime? dueAt,
    Duration? lead,
    bool clearLead = false,
    int? windowStart,
    int? windowEnd,
    bool clearWindow = false,
    DateTime? lastMetAt,
    int? metToday,
    String? metTodayOn,
    bool? paused,
    bool? notify,
    DateTime? updatedAt,
  }) => NexCommitment(
    id: id,
    title: title ?? this.title,
    cadence: cadence ?? this.cadence,
    every: every ?? this.every,
    dueAt: dueAt ?? this.dueAt,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    lead: clearLead ? null : (lead ?? this.lead),
    windowStart: clearWindow ? null : (windowStart ?? this.windowStart),
    windowEnd: clearWindow ? null : (windowEnd ?? this.windowEnd),
    lastMetAt: lastMetAt ?? this.lastMetAt,
    metToday: metToday ?? this.metToday,
    metTodayOn: metTodayOn ?? this.metTodayOn,
    paused: paused ?? this.paused,
    notify: notify ?? this.notify,
    rev: rev + 1,
  );
}

/// How far ahead a commitment of this shape is worth raising, by default.
///
/// From the cadence rather than asked for one item at a time, because the
/// right answer is a property of how often the thing happens and nobody wants
/// to be asked. A year's notice needs a week; a month's needs a couple of
/// days; a week's needs a day; anything daily or finer is only news when it
/// is actually due.
///
/// It is a default and not a rule — [NexCommitment.lead] overrides it, and a
/// commitment that has never been told otherwise follows this as it changes.
Duration nexDefaultLead(NexCadence cadence, int every) => switch (cadence) {
  NexCadence.years => const Duration(days: 7),
  NexCadence.months => Duration(days: every >= 3 ? 5 : 2),
  NexCadence.weeks => const Duration(days: 1),
  NexCadence.days => const Duration(hours: 6),
  // A quarter of the gap, rather than a fixed span or none at all. Zero was
  // the first answer and it was wrong for exactly the case these exist for: a
  // tablet every eight hours would never be mentioned until the moment it was
  // already due, so the morning brief could not tell you the next one is at
  // four. A quarter scales the right way in both directions — two hours'
  // notice on the tablet, half an hour on water every two hours, which is as
  // much warning as a glass of water can possibly need.
  NexCadence.hours => Duration(minutes: every * 15),
};

/// When [commitment] next comes round, given it was met at [after].
///
/// Three rules, and each one is a way this goes wrong without it:
///
/// - **It always lands in the future.** Advancing by exactly one period from
///   a due date that is three weeks stale produces a date that is two weeks
///   stale, and the commitment stays overdue forever however many times it is
///   ticked off. So it keeps going until it clears [after].
/// - **It keeps its place in the cycle.** Counting from the *due* date rather
///   than from the moment it was met is what keeps the rent on the first of
///   the month when it is paid on the third.
/// - **It counts months from the original date, never from the last clamped
///   one.** This is the subtle one. Stepping a monthly commitment one month
///   at a time takes the 31st of January to the 28th of February — correctly,
///   since there is no 31st — and then takes *that* to the 28th of March, and
///   the 31st is gone for good. Somebody whose rent is due on the 31st would
///   find it quietly moved to the 28th after one February and stay there.
///   Counting n months from the anchor instead gives back the 31st in every
///   month that has one. The same arithmetic returns the 29th of February to
///   a yearly commitment every fourth year.
DateTime nexAdvance(NexCommitment commitment, {required DateTime after}) {
  final period = commitment.period;
  if (period != null) {
    var next = commitment.dueAt.add(period);
    var guard = 0;
    while (!next.isAfter(after)) {
      if (++guard > _maxSteps) {
        // Missed for so long that continuing the old cycle is no service to
        // anybody. Start again from the moment it was met.
        next = after.add(period);
        break;
      }
      next = next.add(period);
    }
    return _intoWindow(commitment, next);
  }
  final months = commitment.cadence == NexCadence.years
      ? 12 * commitment.every
      : commitment.every;
  for (var turn = 1; turn <= _maxSteps; turn++) {
    final next = _addMonths(commitment.dueAt, months * turn);
    if (next.isAfter(after)) return next;
  }
  return _addMonths(after, months);
}

/// How many turns of the cycle to try before giving up and counting from the
/// present. A hundred covers eight years of monthly and a fortnight of
/// two-hourly; past that the old cycle has stopped meaning anything.
const _maxSteps = 100;

/// [months] calendar months on from [from], clamped to the month's length.
///
/// The 31st of January plus one month is the 28th of February, not the 3rd of
/// March. `DateTime(2026, 2, 31)` silently rolls over into March, which for a
/// monthly commitment means the rent walking forward a few days every
/// February and never coming back.
DateTime _addMonths(DateTime from, int months) {
  final total = from.month - 1 + months;
  final year = from.year + (total ~/ 12);
  final month = (total % 12) + 1;
  final day = from.day.clamp(1, _daysInMonth(year, month));
  return DateTime(year, month, day, from.hour, from.minute, from.second);
}

int _daysInMonth(int year, int month) =>
    DateTime(year, month + 1, 0).day;

/// Moves an hourly occurrence that landed outside its waking window to the
/// next moment inside one.
///
/// Only the hourly cadence has a window, and only the hourly cadence needs
/// one: it is the one fine enough to fire while somebody is asleep.
DateTime _intoWindow(NexCommitment commitment, DateTime when) {
  if (commitment.cadence != NexCadence.hours) return when;
  final start = commitment.windowStart;
  final end = commitment.windowEnd;
  if (start == null || end == null) return when;
  final minutes = when.hour * 60 + when.minute;
  if (_insideWindow(minutes, start, end)) return when;
  // The next opening of the window: today's if it has not passed, else
  // tomorrow's.
  final openingToday = DateTime(
    when.year,
    when.month,
    when.day,
  ).add(Duration(minutes: start));
  return openingToday.isAfter(when)
      ? openingToday
      : openingToday.add(const Duration(days: 1));
}

bool _insideWindow(int minutes, int start, int end) =>
    end > start
    ? minutes >= start && minutes <= end
    // Wraps past midnight — a night shift.
    : minutes >= start || minutes <= end;

/// The local calendar day [when] falls in, as `YYYY-MM-DD`.
///
/// The same shape the daily recap files itself under, and for the same
/// reason: a day is the unit people think in, and a UTC instant is not one.
String nexDayKey(DateTime when) =>
    '${when.year.toString().padLeft(4, '0')}-'
    '${when.month.toString().padLeft(2, '0')}-'
    '${when.day.toString().padLeft(2, '0')}';
