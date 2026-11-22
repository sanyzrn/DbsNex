import 'package:nex_client/modules/module_api.dart';

/// How often a habit is meant to happen (2.4.0).
///
///  * daily — every day;
///  * weekly — a number of times a week, on any days;
///  * days — on chosen weekdays only;
///  * every — every N days, counted from the day it began.
enum HabitPlan { daily, weekly, days, every }

/// A stretch of rest days for a habit: travel, illness, a hard week, the
/// days around Nowruz. Inclusive civil dates stored as `YYYY-MM-DD`; a
/// paused day is neither due nor missed, so a rest never breaks a streak.
class HabitPause {
  const HabitPause({required this.from, required this.to});

  /// First day of the rest, `YYYY-MM-DD`.
  final String from;

  /// Last day of the rest, `YYYY-MM-DD`.
  final String to;

  bool contains(String key) =>
      key.compareTo(from) >= 0 && key.compareTo(to) <= 0;

  Map<String, Object?> toJson() => {'from': from, 'to': to};

  @override
  bool operator ==(Object other) =>
      other is HabitPause && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);
}

/// The fields this version knows. Anything else in a stored body is kept in
/// [Habit.extra] and written back untouched — a later version, or the
/// platform, may have put it there.
const _knownHabitKeys = {
  'v',
  'name',
  'note',
  'schedule',
  'weekly',
  'target',
  'days',
  'every',
  'goal',
  'unit',
  'icon',
  'hue',
  'archived',
  'createdAt',
  'pauses',
};

/// How many rest stretches a habit keeps; older ones are folded away so a
/// record cannot grow without bound.
const habitMaxPauses = 40;

/// Whether two stretches are the same, overlap, or sit next to each other —
/// in which case they are one rest, not two.
bool _touches(HabitPause a, HabitPause b) {
  final aFrom = tryParseDateKey(a.from), aTo = tryParseDateKey(a.to);
  final bFrom = tryParseDateKey(b.from), bTo = tryParseDateKey(b.to);
  if (aFrom == null || aTo == null || bFrom == null || bTo == null) {
    return false;
  }
  return !aFrom.isAfter(bTo.add(const Duration(days: 1))) &&
      !bFrom.isAfter(aTo.add(const Duration(days: 1)));
}

/// One habit a person is building: a name, an optional note, how often it is
/// meant to happen, and what counts as done — a tick, or an amount (eight
/// glasses, twenty pages).
///
/// Kept as a JSON record in the module's store (kind `habit`), and rebuilt
/// defensively from it: a missing name falls back to an empty string the
/// screen replaces with placeholder words, an unknown schedule reads as
/// daily, and every number is clamped, because a habit whose record was
/// written by an older version must still open. Version-1 records (daily or
/// weekly, a tick) read exactly as they did.
class Habit {
  const Habit({
    required this.id,
    required this.name,
    required this.note,
    required this.weekly,
    required this.target,
    required this.archived,
    required this.createdAt,
    this._plan,
    this.days = const {},
    this.every = 2,
    this.goal = 1,
    this.unit = '',
    this.icon = '',
    this.hue = 0,
    this.pauses = const [],
    this.extra = const {},
  });

  /// From the store; every field is read defensively.
  factory Habit.fromRecord(ModuleRecord record) =>
      Habit.fromBody(record.id, record.body);

  /// From a record's body directly, for the screens that already hold it.
  factory Habit.fromBody(String id, Map<String, Object?> body) {
    int whole(Object? value, int fallback) =>
        value is num && value.isFinite ? value.toInt() : fallback;
    final rawTarget = whole(body['target'], 3);
    // `schedule` is the v2 spelling; a record written before it said
    // `weekly: true` instead and must still open as the weekly habit it was.
    final plan = switch (body['schedule']) {
      'weekly' => HabitPlan.weekly,
      'days' => HabitPlan.days,
      'every' => HabitPlan.every,
      'daily' => HabitPlan.daily,
      _ => body['weekly'] == true ? HabitPlan.weekly : HabitPlan.daily,
    };
    final rawDays = body['days'];
    final days = <int>{
      if (rawDays is List)
        for (final day in rawDays)
          if (day is num && day >= 1 && day <= 7) day.toInt(),
    };
    final rawUnit = body['unit'];
    final rawIcon = body['icon'];
    return Habit(
      id: id,
      name: body['name'] is String ? body['name'] as String : '',
      note: body['note'] is String ? body['note'] as String : '',
      weekly: plan == HabitPlan.weekly,
      target: plan == HabitPlan.weekly ? rawTarget.clamp(1, 7) : 1,
      archived: body['archived'] == true,
      createdAt:
          DateTime.tryParse('${body['createdAt'] ?? ''}') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      // Chosen weekdays with none chosen is every day: a habit that can
      // never fall due would be a habit that can never be kept.
      plan: plan == HabitPlan.days && days.isEmpty ? HabitPlan.daily : plan,
      days: days,
      every: whole(body['every'], 2).clamp(2, 30),
      goal: whole(body['goal'], 1).clamp(1, 9999),
      unit: rawUnit is String ? rawUnit.trim() : '',
      icon: rawIcon is String ? rawIcon : '',
      hue: whole(body['hue'], 0).clamp(0, 7),
      pauses: _readPauses(body['pauses']),
      extra: {
        for (final entry in body.entries)
          if (!_knownHabitKeys.contains(entry.key)) entry.key: entry.value,
      },
    );
  }

  /// Rest stretches, read defensively: a malformed one is dropped rather
  /// than read as a wrong day, and only the newest [habitMaxPauses] stay.
  static List<HabitPause> _readPauses(Object? raw) {
    if (raw is! List) return const [];
    final pauses = <HabitPause>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final a = tryParseDateKey('${entry['from'] ?? ''}');
      final b = tryParseDateKey('${entry['to'] ?? ''}');
      if (a == null || b == null) continue;
      final first = dateKeyOf(a), last = dateKeyOf(b);
      pauses.add(
        first.compareTo(last) <= 0
            ? HabitPause(from: first, to: last)
            : HabitPause(from: last, to: first),
      );
    }
    return _mergePauses(pauses);
  }

  static List<HabitPause> _mergePauses(List<HabitPause> pauses) {
    pauses.sort((a, b) => a.from.compareTo(b.from));
    final merged = <HabitPause>[];
    for (final pause in pauses) {
      if (merged.isNotEmpty && _touches(merged.last, pause)) {
        final last = merged.last;
        if (pause.to.compareTo(last.to) > 0) {
          merged[merged.length - 1] = HabitPause(from: last.from, to: pause.to);
        }
      } else {
        merged.add(pause);
      }
    }
    final from = (merged.length - habitMaxPauses).clamp(0, merged.length);
    return List.unmodifiable(merged.skip(from));
  }

  final String id;

  /// The person's own words. Empty when an older record lost it.
  final String name;

  /// An optional short note. Empty means none.
  final String note;

  /// Whether the schedule is a weekly target rather than daily.
  final bool weekly;

  /// Check-ins a week that count, 1–7. Always 1 for any other plan.
  final int target;

  /// Archived habits keep their history but leave the Today list.
  final bool archived;

  /// When the habit was created; used only for ordering and display.
  final DateTime createdAt;

  final HabitPlan? _plan;

  /// How often it is meant to happen.
  HabitPlan get plan => _plan ?? (weekly ? HabitPlan.weekly : HabitPlan.daily);

  /// The weekdays (Dart's 1 Monday … 7 Sunday) of a [HabitPlan.days] habit.
  final Set<int> days;

  /// The N of a [HabitPlan.every] habit: every N days.
  final int every;

  /// What a day must reach to count as done: 1 is a tick; more is an amount
  /// — eight glasses, twenty pages — logged a little at a time.
  final int goal;

  /// What the amount counts, in the person's words: «glasses», «pages».
  final String unit;

  /// The habit's mark, from [habitIcons]; empty for the default.
  final String icon;

  /// Its colour, an index into [habitHues].
  final int hue;

  /// Rest stretches already taken (2.8.14). Their days are neither due nor
  /// missed, so a rest leaves every streak and rate untouched.
  final List<HabitPause> pauses;

  /// Fields this version does not know, kept so editing, archiving or
  /// pausing never drops a later version's data.
  final Map<String, Object?> extra;

  /// Whether a day is done by reaching an amount rather than by a tick.
  bool get counted => goal > 1;

  /// Whether [day] falls inside a rest stretch.
  bool isPausedOn(DateTime day) => pauseOn(day) != null;

  /// The rest stretch [day] falls in, or null.
  HabitPause? pauseOn(DateTime day) {
    if (pauses.isEmpty) return null;
    final key = dateKeyOf(day);
    for (final pause in pauses) {
      if (pause.contains(key)) return pause;
    }
    return null;
  }

  /// The same habit resting from [from] to [to] inclusive. A stretch that
  /// touches or overlaps this one is merged, so pausing twice extends one
  /// rest instead of leaving two records of it.
  Habit pauseUntil(DateTime from, DateTime to) {
    final fromKey = dateKeyOf(from), toKey = dateKeyOf(to);
    if (toKey.compareTo(fromKey) < 0) return this;
    return withFields(
      pauses: _mergePauses([...pauses, HabitPause(from: fromKey, to: toKey)]),
    );
  }

  /// Ends the rest covering [today]: a rest that began today disappears, an
  /// earlier one stops yesterday, so the day itself is a habit day again.
  Habit endPause(DateTime today) {
    if (pauses.isEmpty) return this;
    final key = dateKeyOf(today);
    final yesterday = dateKeyOf(
      DateTime.utc(today.year, today.month, today.day - 1),
    );
    final kept = <HabitPause>[];
    for (final pause in pauses) {
      if (!pause.contains(key)) {
        kept.add(pause);
      } else if (key != pause.from) {
        kept.add(HabitPause(from: pause.from, to: yesterday));
      }
    }
    return withFields(pauses: kept);
  }

  Map<String, Object?> toJson() => {
    ...extra,
    'v': 2,
    'name': name,
    'note': note,
    'schedule': plan.name,
    'target': weekly ? target : 1,
    if (plan == HabitPlan.days) 'days': (days.toList()..sort()),
    if (plan == HabitPlan.every) 'every': every,
    'goal': goal,
    if (unit.isNotEmpty) 'unit': unit,
    if (icon.isNotEmpty) 'icon': icon,
    'hue': hue,
    'archived': archived,
    'createdAt': createdAt.toIso8601String(),
    if (pauses.isNotEmpty)
      'pauses': [for (final pause in pauses) pause.toJson()],
  };

  Habit withFields({
    String? name,
    String? note,
    bool? weekly,
    int? target,
    HabitPlan? plan,
    Set<int>? days,
    int? every,
    int? goal,
    String? unit,
    String? icon,
    int? hue,
    List<HabitPause>? pauses,
    Map<String, Object?>? extra,
  }) {
    final nextPlan =
        plan ??
        (weekly == null
            ? this.plan
            : weekly
            ? HabitPlan.weekly
            : HabitPlan.daily);
    final isWeekly = nextPlan == HabitPlan.weekly;
    return Habit(
      id: id,
      name: name ?? this.name,
      note: note ?? this.note,
      weekly: isWeekly,
      target: isWeekly ? (target ?? this.target).clamp(1, 7) : 1,
      archived: archived,
      createdAt: createdAt,
      plan: nextPlan,
      days: days ?? this.days,
      every: (every ?? this.every).clamp(2, 30),
      goal: (goal ?? this.goal).clamp(1, 9999),
      unit: unit ?? this.unit,
      icon: icon ?? this.icon,
      hue: (hue ?? this.hue).clamp(0, 7),
      pauses: pauses ?? this.pauses,
      extra: extra ?? this.extra,
    );
  }
}

/// The civil-date prefix a check-in's date is read from, compiled once for
/// the load that reads every record.
final RegExp _dateKeyPrefix = RegExp(r'^(\d{4})-(\d{2})-(\d{2})');

/// One check-in: the habit, and the **local civil date** it counts for.
///
/// A check-in is keyed by `habitId:date` in the store (kind `check`), so
/// tapping twice on the same day updates the same record instead of adding a
/// second one — the record id itself makes duplicates impossible.
class HabitCheck {
  const HabitCheck({
    required this.id,
    required this.habitId,
    required this.dateKey,
    required this.at,
    this.amount,
    this.extra = const {},
  });

  factory HabitCheck.fromRecord(ModuleRecord record) =>
      HabitCheck.fromBody(record.id, record.body);

  /// From a record's body directly, for the screens that already hold it.
  factory HabitCheck.fromBody(String id, Map<String, Object?> body) {
    return HabitCheck(
      id: id,
      habitId: body['habit'] is String ? body['habit'] as String : '',
      dateKey: _normaliseDateKey('${body['date'] ?? ''}'),
      at:
          DateTime.tryParse('${body['at'] ?? ''}') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      amount: body['amount'] is num && (body['amount'] as num).isFinite
          ? (body['amount'] as num).toInt().clamp(0, 99999)
          : null,
      // A check-in written by a later version keeps its own fields when
      // this one rewrites the amount.
      extra: {
        for (final entry in body.entries)
          if (entry.key != 'habit' &&
              entry.key != 'date' &&
              entry.key != 'at' &&
              entry.key != 'amount')
            entry.key: entry.value,
      },
    );
  }

  /// `habitId:date`, the stable id of a day's check-in for one habit.
  static String idFor(String habitId, String dateKey) => '$habitId:$dateKey';

  final String id;
  final String habitId;

  /// `2026-10-12` — the local civil date, stored as text so no clock
  /// arithmetic can move a check-in across a day.
  final String dateKey;

  /// When it happened, for the recent-activity list.
  final DateTime at;

  /// How much was logged that day, for a habit with an amount goal. Null
  /// is a plain check-in — the whole day done, as every version-1 record is.
  final int? amount;

  /// Fields this version does not know, written back untouched.
  final Map<String, Object?> extra;

  /// What the day counts towards [goal]: the logged amount, or the whole
  /// goal for a plain check-in.
  int progressFor(int goal) => amount ?? goal;

  Map<String, Object?> toJson() => {
    ...extra,
    'habit': habitId,
    'date': dateKey,
    'at': at.toIso8601String(),
    'amount': ?amount,
  };

  /// Accepts `2026-10-12` and the longer ISO forms, keeping the civil-date
  /// prefix of a real date. Anything else reads as unknown (`""`) — never
  /// today, never a crash — so a malformed record can only fail to exist.
  static String _normaliseDateKey(String raw) {
    final match = _dateKeyPrefix.firstMatch(raw);
    if (match == null) return '';
    final key = raw.substring(0, 10);
    return tryParseDateKey(key) == null ? '' : key;
  }
}

/// Habits newest-first: the most recently created first. Two habits
/// created at the very same moment — a bulk import, or an old record with
/// no creation date — fall back to the store's time-ordered id, so the
/// list keeps one stable order from one load to the next.
int newestFirst(Habit a, Habit b) {
  final byCreated = b.createdAt.compareTo(a.createdAt);
  return byCreated != 0 ? byCreated : a.id.compareTo(b.id);
}

/// Check-ins newest-first: by the day each counts for, then by when it was
/// written — so legacy records that share a day keep one stable order.
int newestCheckFirst(HabitCheck a, HabitCheck b) {
  final byDay = b.dateKey.compareTo(a.dateKey);
  return byDay != 0 ? byDay : b.at.compareTo(a.at);
}

/// The local civil date as `YYYY-MM-DD`.
///
/// Civil dates, not durations: a check-in at 23:59 and one at 00:01 are a
/// day apart because the calendar says so, not because 24 hours passed.
/// Arithmetic on keys goes through [DateTime.utc], which has no daylight
/// saving, so a civil day is always exactly one civil day.
String dateKeyOf(DateTime moment) {
  return '${moment.year}-${nexPad2(moment.month)}-${nexPad2(moment.day)}';
}

/// Parses a date key; null when it is not a real calendar date.
///
/// `DateTime.tryParse` accepts `2026-02-30` and quietly rolls it into
/// March, so the only honest test is whether the parsed date spells the
/// same day it was given. The pattern is compiled once — this runs for
/// every check-in of every habit on every load of the Today list, the
/// dates card and the pinned glance.
final RegExp _dateKeyPattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

DateTime? tryParseDateKey(String key) {
  if (!_dateKeyPattern.hasMatch(key)) return null;
  final date = DateTime.tryParse(key);
  if (date == null || dateKeyOf(date) != key) return null;
  return DateTime.utc(date.year, date.month, date.day);
}

/// The civil date of [key] as a local [DateTime], for the platform calendar
/// to draw.
///
/// Keys are UTC midnights and stay that way in every count; a label is a
/// person's own calendar day, so it is rebuilt in local time before
/// `nexModuleDateLabel` formats it — otherwise a western time zone would
/// print the day before.
DateTime? civilOfKey(String key) {
  final date = tryParseDateKey(key);
  if (date == null) return null;
  return DateTime(date.year, date.month, date.day);
}

/// Whole civil days from [later] back to [earlier]; negative when earlier is
/// after later. DST cannot shift the answer: both sides are UTC midnights.
int daysBetweenKeys(String earlier, String later) {
  final from = tryParseDateKey(earlier);
  final to = tryParseDateKey(later);
  if (from == null || to == null) return 0;
  return to.difference(from).inDays;
}
