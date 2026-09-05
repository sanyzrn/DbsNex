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
/// DUE overdue 2d | checklist 1/3 left | milk · bread · call the plumber
/// DUE in 6h | text | pick up the prescription
/// today | photo | receipt from the garage
/// 4d ago | text | the flat above is being rewired on the 14th
/// ```
///
/// The shape is repeated to the model in the prompt, so the abbreviations do
/// not have to be guessed at. It is deliberately terse: every character here
/// is a token spent on every recap, on a provider the user is paying for.
///
/// Selection changes too, and that is the other half of the point. "The
/// twenty newest" is the wrong twenty for a recap whose job is to say what is
/// waiting: a reminder set last month for tomorrow morning is the single most
/// worth mentioning thing in the library and would never have been in it.
String nexRecapSource(
  List<Note> notes, {
  DateTime? now,
  int limit = 20,

  /// How far ahead a reminder still counts as "waiting". Past this it is
  /// simply a note with a date on it: something due in three months is not
  /// what anyone opening the app this morning needs told.
  Duration horizon = const Duration(days: 7),

  /// Per note. A long note would otherwise take the budget the other
  /// nineteen were meant to share.
  int maxTextLength = 160,
}) {
  final at = (now ?? DateTime.now()).toUtc();
  final live = [for (final note in notes) if (note.deletedAt == null) note];

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
  final due = [for (final note in live) if (waiting(note)) note]
    ..sort((a, b) => a.dueAt!.compareTo(b.dueAt!));
  final open = [
    for (final note in live)
      if (!waiting(note) && unfinished(note)) note,
  ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  final rest = [
    for (final note in live)
      if (!waiting(note) && !unfinished(note)) note,
  ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  final lines = <String>[];
  for (final note in [...due, ...open, ...rest]) {
    if (lines.length >= limit) break;
    final text = _oneLine(note.displayText, maxTextLength);
    if (text.isEmpty) continue;
    final when = _when(note, at, due: waiting(note));
    lines.add('$when | ${_kind(note)} | $text');
  }
  return lines.join('\n');
}

/// The left column: when it is due, or failing that, when it was written.
///
/// [due] is the caller's answer, not this function's, and the two must agree:
/// the prompt tells the model that every DUE line comes first, so a note that
/// carries a reminder past the horizon — and is therefore sorted with the
/// ordinary ones — must not be marked DUE either. It is described by when it
/// was written, like anything else nobody is waiting on.
String _when(Note note, DateTime at, {required bool due}) {
  final moment = note.dueAt?.toUtc();
  if (due && moment != null) {
    final away = moment.difference(at);
    if (away.isNegative) return 'DUE overdue ${_span(-away)}';
    return 'DUE in ${_span(away)}';
  }
  final age = at.difference(note.updatedAt.toUtc());
  return age.inHours < 24 ? 'today' : '${_span(age)} ago';
}

/// Whole units only. A recap does not need to know something is due in four
/// hours and eleven minutes, and the minutes cost tokens to say.
String _span(Duration span) {
  if (span.inHours < 1) return '${span.inMinutes.clamp(1, 59)}m';
  if (span.inHours < 48) return '${span.inHours}h';
  return '${span.inDays}d';
}

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
