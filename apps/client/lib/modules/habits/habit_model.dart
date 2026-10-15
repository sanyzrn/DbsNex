import 'package:nex_client/modules/module_api.dart';

/// One habit a person is building: a name, an optional note, and a simple
/// schedule — every day, or a target number of check-ins a week.
///
/// Kept as a JSON record in the module's store (kind `habit`), and rebuilt
/// defensively from it: a missing name falls back to an empty string the
/// screen replaces with placeholder words, an unknown schedule reads as
/// daily, and a target outside 1–7 is clamped, because a habit whose record
/// was written by an older version must still open.
class Habit {
  const Habit({
    required this.id,
    required this.name,
    required this.note,
    required this.weekly,
    required this.target,
    required this.archived,
    required this.createdAt,
  });

  /// From the store; every field is read defensively.
  factory Habit.fromRecord(ModuleRecord record) =>
      Habit.fromBody(record.id, record.body);

  /// From a record's body directly, for the screens that already hold it.
  factory Habit.fromBody(String id, Map<String, Object?> body) {
    final rawTarget = body['target'];
    final target = rawTarget is num && rawTarget.isFinite
        ? rawTarget.toInt()
        : 3;
    final rawSchedule = body['schedule'];
    final weekly = rawSchedule == 'weekly';
    return Habit(
      id: id,
      name: body['name'] is String ? body['name'] as String : '',
      note: body['note'] is String ? body['note'] as String : '',
      weekly: weekly,
      target: weekly ? target.clamp(1, 7) : 1,
      archived: body['archived'] == true,
      createdAt:
          DateTime.tryParse('${body['createdAt'] ?? ''}') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  final String id;

  /// The person's own words. Empty when an older record lost it.
  final String name;

  /// An optional short note. Empty means none.
  final String note;

  /// Whether the schedule is a weekly target rather than daily.
  final bool weekly;

  /// Check-ins a week that count, 1–7. Always 1 for a daily habit.
  final int target;

  /// Archived habits keep their history but leave the Today list.
  final bool archived;

  /// When the habit was created; used only for ordering and display.
  final DateTime createdAt;

  Map<String, Object?> toJson() => {
    'name': name,
    'note': note,
    'schedule': weekly ? 'weekly' : 'daily',
    'target': weekly ? target : 1,
    'archived': archived,
    'createdAt': createdAt.toIso8601String(),
  };

  Habit withFields({String? name, String? note, bool? weekly, int? target}) =>
      Habit(
        id: id,
        name: name ?? this.name,
        note: note ?? this.note,
        weekly: weekly ?? this.weekly,
        target: (weekly ?? this.weekly)
            ? (target ?? this.target).clamp(1, 7)
            : 1,
        archived: archived,
        createdAt: createdAt,
      );
}

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
  });

  factory HabitCheck.fromRecord(ModuleRecord record) {
    final body = record.body;
    return HabitCheck(
      id: record.id,
      habitId: body['habit'] is String ? body['habit'] as String : '',
      dateKey: _normaliseDateKey('${body['date'] ?? ''}'),
      at:
          DateTime.tryParse('${body['at'] ?? ''}') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
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

  Map<String, Object?> toJson() => {
    'habit': habitId,
    'date': dateKey,
    'at': at.toIso8601String(),
  };

  /// Accepts `2026-10-12` and the longer ISO forms, falling back to today's
  /// key so a malformed date never crashes a screen — it just reads as now.
  static String _normaliseDateKey(String raw) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(raw);
    if (match == null) return '';
    final key = raw.substring(0, 10);
    return tryParseDateKey(key) == null ? '' : key;
  }
}

/// The local civil date as `YYYY-MM-DD`.
///
/// Civil dates, not durations: a check-in at 23:59 and one at 00:01 are a
/// day apart because the calendar says so, not because 24 hours passed.
/// Arithmetic on keys goes through [DateTime.utc], which has no daylight
/// saving, so a civil day is always exactly one civil day.
String dateKeyOf(DateTime moment) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${moment.year}-${two(moment.month)}-${two(moment.day)}';
}

/// Parses a date key; null when it is not a real calendar date.
///
/// `DateTime.tryParse` accepts `2026-02-30` and quietly rolls it into
/// March, so the only honest test is whether the parsed date spells the
/// same day it was given.
DateTime? tryParseDateKey(String key) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(key)) return null;
  final date = DateTime.tryParse(key);
  if (date == null || dateKeyOf(date) != key) return null;
  return DateTime.utc(date.year, date.month, date.day);
}

/// Whole civil days from [later] back to [earlier]; negative when earlier is
/// after later. DST cannot shift the answer: both sides are UTC midnights.
int daysBetweenKeys(String earlier, String later) {
  final from = tryParseDateKey(earlier);
  final to = tryParseDateKey(later);
  if (from == null || to == null) return 0;
  return to.difference(from).inDays;
}
