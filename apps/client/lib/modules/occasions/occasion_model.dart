import 'package:nex_client/modules/module_api.dart';

/// What an occasion is. Only a label and an icon: none of them changes
/// how the date repeats.
enum OccasionKind { birthday, anniversary, memorial, other }

/// The calendar a date is *kept* in. A Jalali birthday returns on the same
/// Jalali day every year, whichever calendar the app is showing; the
/// Gregorian date it falls on moves.
enum OccasionCalendar { jalali, gregorian }

/// One date that matters, as the person wrote it: a title, a day and month
/// in a calendar, a year if they know it, and what to do about it.
///
/// Kept as a record of kind `occasion`, rebuilt defensively: an unknown kind
/// reads as «other», an unknown calendar as Gregorian, and a missing or
/// impossible month or day makes the record [valid] = false — it is listed
/// so it can be fixed or deleted, never silently given a date.
class Occasion {
  const Occasion({
    required this.id,
    required this.title,
    required this.kind,
    required this.calendar,
    required this.month,
    required this.day,
    this.year,
    this.nextDayInShortYears = false,
    this.note = '',
    this.favorite = false,
    this.muted = false,
    this.archived = false,
    this.remindDays,
    this.remindMinutes = defaultRemindMinutes,
    required this.createdAt,
  });

  factory Occasion.fromRecord(ModuleRecord record) =>
      Occasion.fromBody(record.id, record.body);

  factory Occasion.fromBody(String id, Map<String, Object?> body) {
    int? whole(Object? value) =>
        value is num && value.isFinite && value == value.truncate()
        ? value.toInt()
        : null;
    final remind = whole(body['remindDays']);
    final minutes = whole(body['remindMinutes']);
    return Occasion(
      id: id,
      title: body['title'] is String ? (body['title'] as String).trim() : '',
      kind:
          OccasionKind.values
              .where((k) => k.name == body['kind'])
              .firstOrNull ??
          OccasionKind.other,
      calendar: body['calendar'] == 'jalali'
          ? OccasionCalendar.jalali
          : OccasionCalendar.gregorian,
      month: whole(body['month']) ?? 0,
      day: whole(body['day']) ?? 0,
      year: body['yearKnown'] == false ? null : whole(body['year']),
      nextDayInShortYears: body['leapPolicy'] == 'nextDay',
      note: body['note'] is String ? body['note'] as String : '',
      favorite: body['favorite'] == true,
      muted: body['muted'] == true,
      archived: body['archived'] == true,
      remindDays: remind != null && remind >= 0 && remind <= 30 ? remind : null,
      remindMinutes: minutes != null && minutes >= 0 && minutes < 1440
          ? minutes
          : defaultRemindMinutes,
      createdAt:
          DateTime.tryParse('${body['createdAt'] ?? ''}') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  static const defaultRemindMinutes = 9 * 60;

  final String id;
  final String title;
  final OccasionKind kind;
  final OccasionCalendar calendar;
  final int month;
  final int day;

  /// The year it began (born, married) in [calendar]; null when unknown —
  /// no age is then shown, and none is guessed.
  final int? year;

  /// For 30 Esfand (or 29 February) in a year that does not have it: the
  /// first day of the next month instead of the last day of the month.
  final bool nextDayInShortYears;
  final String note;
  final bool favorite;
  final bool muted;
  final bool archived;

  /// Days before to remind (0 = on the day); null = no reminder.
  final int? remindDays;

  /// Minutes after midnight the reminder rings at.
  final int remindMinutes;
  final DateTime createdAt;

  bool get valid => month >= 1 && month <= 12 && day >= 1 && day <= 31;

  Map<String, Object?> toJson() => {
    'v': 1,
    'title': title,
    'kind': kind.name,
    'calendar': calendar.name,
    'month': month,
    'day': day,
    'yearKnown': year != null,
    if (year != null) 'year': year,
    'leapPolicy': nextDayInShortYears ? 'nextDay' : 'lastDay',
    'note': note,
    'favorite': favorite,
    'muted': muted,
    'archived': archived,
    if (remindDays != null) 'remindDays': remindDays,
    'remindMinutes': remindMinutes,
    'createdAt': createdAt.toIso8601String(),
  };

  Occasion copyWith({bool? favorite, bool? muted, bool? archived}) => Occasion(
    id: id,
    title: title,
    kind: kind,
    calendar: calendar,
    month: month,
    day: day,
    year: year,
    nextDayInShortYears: nextDayInShortYears,
    note: note,
    favorite: favorite ?? this.favorite,
    muted: muted ?? this.muted,
    archived: archived ?? this.archived,
    remindDays: remindDays,
    remindMinutes: remindMinutes,
    createdAt: createdAt,
  );
}
