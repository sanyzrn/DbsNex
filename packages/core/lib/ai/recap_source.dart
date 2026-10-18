import '../models/commitment.dart';
import '../models/note.dart';

/// What the daily recap is given to work from.
///
/// The recap used to be handed the plain text of the twenty newest notes and
/// nothing else — no dates, no reminders, no note types, no checklist state.
/// That is the whole reason it could only ever be an observation about what
/// someone had been writing: asked to remind them of anything, it had nothing
/// to remind them *with*, and a model with no facts and an instruction to be
/// useful invents them.
///
/// So this sends facts. One line per note:
///
/// ```
/// DUE overdue 2 days, was Sunday 09:00 | checklist 1/3 left | milk · bread
/// DUE today 15:00 | text | pick up the prescription
/// DUE Friday 09:00, in 3 days | text | edit the tax file
/// today | photo | receipt from the garage
/// 4 days ago | text | the flat above is being rewired on the 14th
/// ```
///
/// A DUE line says the day and the clock time rather than a count of hours,
/// and counts days by the calendar (2.1.6). "DUE in 4d" for a reminder on
/// Wednesday at 9, read on Friday evening, was four days by the clock and
/// five by the calendar; the brief said "four days", and with nothing but a
/// span to go on it also read the reminder as a deadline. The day and time
/// are also what stays true while a brief sits cached for an hour: "in 15
/// hours" is wrong for most of that hour, "tomorrow at 9" for none of it.
///
/// The shape is repeated to the model in the prompt, so the abbreviations do
/// not have to be guessed at. It is deliberately terse: every character here
/// is a token spent on every recap, on a provider the user is paying for.
///
/// Selection changes too, and that is the other half of the point. "The
/// twenty newest" is the wrong twenty for a recap whose job is to say what is
/// waiting: a reminder set last month for tomorrow morning is the single most
/// worth mentioning thing in the library and would never have been in it.
///
/// But not *only* what is waiting. With enough reminders and open lists the
/// waiting kind filled every line, and what somebody wrote this morning —
/// a plan, an idea, a date mentioned in passing with no reminder on it —
/// never reached the recap at all. So a share of the lines, a quarter, is
/// kept for notes of the last [recentWindow] that nobody is waiting on.
///
/// A note's tags ride in the middle column as `#name`: they say what a note
/// is about in the words its writer chose, which is what lets the recap say
/// "three things left for the trip" rather than list them one by one.
String nexRecapSource(
  List<Note> notes, {
  List<NexCommitment> commitments = const [],
  DateTime? now,
  int limit = 20,
  bool forFingerprint = false,
  Duration horizon = const Duration(days: 7),
  int maxTextLength = 160,
  Duration recentWindow = const Duration(hours: 48),
}) => _recapLines(
  notes,
  commitments: commitments,
  now: now,
  limit: limit,
  forFingerprint: forFingerprint,
  horizon: horizon,
  maxTextLength: maxTextLength,
  recentWindow: recentWindow,
).map((line) => line.$1).join('\n');

/// The notes [nexRecapSource] chose its lines from, with the same arguments —
/// what the disclosure log names for the brief that is written from them.
List<String> nexRecapNoteIds(
  List<Note> notes, {
  List<NexCommitment> commitments = const [],
  DateTime? now,
  int limit = 20,
  Duration horizon = const Duration(days: 7),
  Duration recentWindow = const Duration(hours: 48),
}) => [
  for (final (_, id) in _recapLines(
    notes,
    commitments: commitments,
    now: now,
    limit: limit,
    horizon: horizon,
    recentWindow: recentWindow,
  ))
    ?id,
];

List<(String, String?)> _recapLines(
  List<Note> notes, {

  /// The recurring obligations — the insurance, the rent, the tablet — that
  /// are not notes and are not on the timeline, but are exactly the sort of
  /// thing a brief exists to raise.
  ///
  /// Only the ones actually waiting are sent, by each one's own lead time, so
  /// an insurance renewal eleven months out costs nothing and the same
  /// renewal five days out is in front of the notes. See
  /// [NexCommitment.isWaiting].
  List<NexCommitment> commitments = const [],
  DateTime? now,
  int limit = 20,

  /// Absolute facts for cache identity; relative age alone is not new data.
  bool forFingerprint = false,

  /// How far ahead a reminder still counts as "waiting". Past this it is
  /// simply a note with a date on it: something due in three months is not
  /// what anyone opening the app this morning needs told.
  Duration horizon = const Duration(days: 7),

  /// Per note. A long note would otherwise take the budget the other
  /// nineteen were meant to share.
  int maxTextLength = 160,

  /// How recent a note has to be to have a line kept for it.
  Duration recentWindow = const Duration(hours: 48),
}) {
  final local = now ?? DateTime.now();
  final at = local.toUtc();
  // Calendar days are counted in the zone [now] is in: the phone's own in the
  // app, UTC in a test that passes a UTC clock.
  DateTime zoned(DateTime value) =>
      local.isUtc ? value.toUtc() : value.toLocal();
  final live = [
    for (final note in notes)
      if (note.deletedAt == null) note,
  ];

  bool waiting(Note note) {
    final due = note.dueAt;
    return due != null && due.toUtc().isBefore(at.add(horizon));
  }

  bool unfinished(Note note) =>
      note.type == NoteType.checklist &&
      note.checklistItems.any((item) => !item.done);

  // Three passes rather than one sort with a composite key: the groups are
  // ordered by different things — the due ones by when they are due, the rest
  // by when they were written — and a single comparator that tries to say
  // that is a comparator nobody can read.
  final due = [
    for (final note in live)
      if (waiting(note)) note,
  ]..sort((a, b) => a.dueAt!.compareTo(b.dueAt!));
  final open = [
    for (final note in live)
      if (!waiting(note) && unfinished(note)) note,
  ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  final rest = [
    for (final note in live)
      if (!waiting(note) && !unfinished(note)) note,
  ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  final pressing = <(String, String?)>[];
  // Commitments first, unconditionally. Every one that reaches this point is
  // already past its lead time — that is what put it here — so it is by
  // construction more pressing than a note somebody wrote on Tuesday. They
  // are few (one line each, and only the waiting ones) so they cannot crowd
  // the notes out of the budget the way a long library could.
  final waitingNow = [
    for (final commitment in commitments)
      if (commitment.isWaiting(local)) commitment,
  ]..sort((a, b) => a.dueAt.compareTo(b.dueAt));
  for (final commitment in waitingNow) {
    pressing.add((
      forFingerprint
          ? '${commitment.id}|${commitment.dueAt.toUtc().toIso8601String()}|'
                '${commitment.dueAt.isBefore(local) ? 'overdue' : 'upcoming'}|'
                '${_dayGap(local, zoned(commitment.dueAt))}|'
                '${_cadenceLabel(commitment)}|${commitment.timesPerDay}|'
                '${commitment.metOn(local)}|${_oneLine(commitment.title, 80)}'
          : _commitmentLine(commitment, local, zoned(commitment.dueAt)),
      null,
    ));
  }

  String? line(Note note) {
    final text = _oneLine(note.displayText, maxTextLength);
    if (text.isEmpty) return null;
    // The day a reminder falls on is part of the fingerprint, so a brief that
    // says "tomorrow at 9" is written again once the calendar turns and that
    // has become "today at 9". Only for what is waiting: a note nobody is
    // waiting on asks for no new brief at midnight.
    final when = forFingerprint
        ? '${note.id}|${note.dueAt?.toUtc().toIso8601String() ?? ''}|'
              '${waiting(note) ? '${note.dueAt!.toUtc().isBefore(at) ? 'overdue' : 'upcoming'}|${_dayGap(local, zoned(note.dueAt!))}' : ''}'
        : _when(note, local, zoned, due: waiting(note));
    return '$when | ${_kind(note)}${_tags(note)} | $text';
  }

  for (final note in [...due, ...open]) {
    if (line(note) case final text?) pressing.add((text, note.id));
  }
  final others = [
    for (final note in rest)
      if (line(note) case final text?) (text, note),
  ];
  // The lines kept back for what was just written: never more than there
  // are recent notes to fill them, and never more than a quarter, so a
  // morning with a dozen things overdue still leads with them.
  final recent = others
      .where(
        (entry) => at.difference(entry.$2.updatedAt.toUtc()) < recentWindow,
      )
      .length;
  final kept = recent.clamp(0, limit ~/ 4);
  final lines = [
    ...pressing.take((limit - kept).clamp(0, limit)),
    for (final entry in others) (entry.$1, entry.$2.id),
  ];
  final selected = lines.take(limit).toList();
  if (forFingerprint) selected.sort((a, b) => a.$1.compareTo(b.$1));
  return selected;
}

/// The note's tags, as ` #name` each, after the kind. Spaces inside a name
/// become underscores so that one tag reads as one word.
String _tags(Note note) {
  if (note.tags.isEmpty) return '';
  return [
    for (final tag in note.tags.take(3))
      ' #${tag.name.trim().replaceAll(RegExp(r'\s+'), '_')}',
  ].join();
}

/// One commitment, in the same three-column shape the notes use.
///
/// ```
/// DUE Sunday 09:00, in 5 days | every year | car insurance
/// DUE overdue 2 days, was Sunday 09:00 | every month | rent
/// DUE now | every 2h · 3 of 7 today | drink water
/// ```
///
/// The middle column carries the cadence rather than a note type, because
/// that is the fact that tells the model how to talk about it: "the insurance
/// is due in five days" and "you have had three glasses today" are different
/// sentences, and the difference is entirely in how often the thing happens.
///
/// The hourly ones carry their tally and are deliberately one line, not one
/// line per glass. Six identical entries saying water is due is not a brief,
/// it is a broken one.
String _commitmentLine(NexCommitment commitment, DateTime now, DateTime due) {
  final when = _due(due, now);
  final cadence = _cadenceLabel(commitment);
  final tally = commitment.timesPerDay;
  final middle = tally == null
      ? cadence
      : '$cadence · ${commitment.metOn(now)} of $tally today';
  return '$when | $middle | ${_oneLine(commitment.title, 80)}';
}

String _cadenceLabel(NexCommitment commitment) {
  final unit = switch (commitment.cadence) {
    NexCadence.hours => 'h',
    NexCadence.days => 'd',
    NexCadence.weeks => 'w',
    NexCadence.months => 'month',
    NexCadence.years => 'year',
  };
  if (commitment.every == 1) {
    return switch (commitment.cadence) {
      NexCadence.hours => 'every hour',
      NexCadence.days => 'every day',
      NexCadence.weeks => 'every week',
      NexCadence.months => 'every month',
      NexCadence.years => 'every year',
    };
  }
  return 'every ${commitment.every}$unit';
}

/// The left column: when it is due, or failing that, when it was written.
///
/// [due] is the caller's answer, not this function's, and the two must agree:
/// the prompt tells the model that every DUE line comes first, so a note that
/// carries a reminder past the horizon — and is therefore sorted with the
/// ordinary ones — must not be marked DUE either. It is described by when it
/// was written, like anything else nobody is waiting on.
///
/// "today" and "yesterday" are calendar days, not the last 24 hours. A note
/// written at eleven last night that says "tomorrow" means today, and the
/// prompt tells the model to count such words from the day it was written.
String _when(
  Note note,
  DateTime now,
  DateTime Function(DateTime) zoned, {
  required bool due,
}) {
  final moment = note.dueAt == null ? null : zoned(note.dueAt!);
  if (due && moment != null) return _due(moment, now);
  final gap = _dayGap(zoned(note.updatedAt), now);
  final written = gap <= 0
      ? 'today'
      : gap == 1
      ? 'yesterday'
      : '$gap days ago';
  // A reminder past the horizon is still a reminder. Without this the brief
  // saw an important date with nothing set for it and advised setting a
  // reminder that was already there, a week ahead.
  if (moment != null && moment.isAfter(now)) {
    return '$written · reminder in ${_dayGap(now, moment)} days';
  }
  return written;
}

/// When a reminder or a commitment falls due: the calendar day and the clock.
///
/// ```
/// DUE today 15:00
/// DUE tomorrow 09:00
/// DUE Friday 09:00, in 3 days
/// DUE next Tuesday 09:00, in 7 days
/// DUE overdue, was yesterday 09:00
/// DUE overdue 2 days, was Sunday 09:00
/// DUE overdue 12 days
/// ```
///
/// The weekday and the count together past tomorrow: the weekday is how
/// somebody says it, the count is what stops a model working it out wrong.
/// [due] and [now] are in the same zone — see `zoned` in [nexRecapSource].
String _due(DateTime due, DateTime now) {
  final days = _dayGap(now, due);
  final clock = '${_two(due.hour)}:${_two(due.minute)}';
  final weekday = _weekdays[due.weekday - 1];
  if (due.isBefore(now)) {
    final ago = -days;
    if (ago <= 0) return 'DUE overdue, was today $clock';
    if (ago == 1) return 'DUE overdue, was yesterday $clock';
    if (ago < 7) return 'DUE overdue $ago days, was $weekday $clock';
    return 'DUE overdue $ago days';
  }
  if (due.difference(now).inMinutes < 1) return 'DUE now';
  if (days <= 0) return 'DUE today $clock';
  if (days == 1) return 'DUE tomorrow $clock';
  if (days < 7) return 'DUE $weekday $clock, in $days days';
  return 'DUE next $weekday $clock, in $days days';
}

/// Whole calendar days from [from] to [to], negative when [to] is earlier.
///
/// Through UTC midnights so that a clock change in between cannot make a day
/// 23 hours long and the count come out one short.
int _dayGap(DateTime from, DateTime to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

String _two(int value) => value.toString().padLeft(2, '0');

const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// The middle column: what sort of note, and for a checklist how much of it
/// is still outstanding — which is the one thing about a checklist that says
/// whether it is finished business or not.
String _kind(Note note) {
  final name = note.type.name;
  if (note.type != NoteType.checklist) return name;
  final items = note.checklistItems;
  if (items.isEmpty) return name;
  final left = items.where((item) => !item.done).length;
  return left == 0 ? '$name done' : '$name $left/${items.length} left';
}

String _oneLine(String? text, int max) {
  final flat = (text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (flat.length <= max) return flat;
  return '${flat.substring(0, max).trimRight()}…';
}
