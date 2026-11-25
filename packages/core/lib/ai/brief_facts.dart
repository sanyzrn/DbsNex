/// Everything the brief can say that the app already knows, with nothing
/// asked of anybody.
///
/// The daily brief used to be one thing: the library, flattened into lines,
/// handed to a model, and whatever came back. That is the right shape for the
/// half of a brief that is judgement — "the dentist and the school run are
/// both at 3" is a sentence only something that can see the whole set can
/// write. It is the wrong shape for the other half. Which items are overdue,
/// by how long, what falls due this week and how much of a checklist is left
/// are facts this app holds exactly, and sending them out to be rephrased
/// buys nothing and costs three things: a request, a provider, and the chance
/// that the date comes back wrong. A wrong date in a brief is a missed
/// appointment.
///
/// So the facts are computed here, once, and every brief style is a different
/// answer to what is done with them — see `NexBriefStyle`. The style that
/// asks nothing of a model is built from this alone, which is also why it
/// works with no network, no key and no provider.
///
/// Pure and in core on purpose: no wording, no locale, no `BuildContext`.
/// What each of these *reads as* is a client concern, and the client has the
/// strings.
library;

import '../models/commitment.dart';
import '../models/note.dart';
import 'attention.dart';

/// One thing worth mentioning, reduced to the facts about it.
class NexBriefEntry {
  const NexBriefEntry({
    required this.title,
    this.dueAt,
    this.recurring = false,
    this.remaining,
    this.total,
    this.noteId,
  });

  final String title;

  /// The note this fact is about, so a line written from it can lead back to
  /// it. Null for a standing commitment, which is not a note.
  final String? noteId;

  /// When it falls due, for the two groups that have a date.
  final DateTime? dueAt;

  /// A standing commitment — the rent, a renewal, a tablet — rather than a
  /// note. Worth keeping apart because they are said differently: "the rent
  /// is due on Friday", not "you have a monthly commitment".
  final bool recurring;

  /// Unticked items, and how many there were, for a checklist.
  final int? remaining;
  final int? total;
}

/// The four groups, already sorted, plus what they were counted out of.
class NexBriefFacts {
  const NexBriefFacts({
    required this.overdue,
    required this.dueSoon,
    required this.unfinished,
    required this.notes,
  });

  /// Past its date, most overdue first. The only group whose order is not
  /// the order of the dates: what has slipped furthest is what has been
  /// ignored longest.
  final List<NexBriefEntry> overdue;

  /// Inside the horizon, soonest first.
  final List<NexBriefEntry> dueSoon;

  /// Checklists with something still unticked, most recently touched first.
  final List<NexBriefEntry> unfinished;

  /// How many live notes there are altogether — the denominator the groups
  /// above are a slice of.
  final int notes;

  /// Nothing is waiting. Not the same as having no notes, and the difference
  /// is the whole point of saying it: a quiet day is an answer.
  bool get nothingWaiting =>
      overdue.isEmpty && dueSoon.isEmpty && unfinished.isEmpty;

  int get waiting => overdue.length + dueSoon.length + unfinished.length;
}

/// Sorts [notes] and [commitments] into the groups a brief is built from.
///
/// [horizon] is how far ahead a date still counts as waiting. Past it a
/// reminder is simply a note with a date on it: something due in three months
/// is not what anyone opening the app this morning needs told. It is the same
/// horizon `nexRecapSource` uses, and deliberately so — the two must agree
/// about what "soon" means, or a brief with a model in it and a brief without
/// one would disagree about the same day.
NexBriefFacts nexBriefFacts(
  List<Note> notes, {
  List<NexCommitment> commitments = const [],
  DateTime? now,
  Duration horizon = const Duration(days: 7),
}) {
  // One reading of the library, shared with the daily nudge — see
  // `attention.dart`. This function is only the projection into the brief's
  // three groups; it does not classify anything itself, so the two surfaces
  // cannot drift apart about what "overdue" or "today" means.
  final attention = nexAttention(
    notes,
    commitments: commitments,
    now: now,
    horizon: horizon,
    includeIdeas: false,
  );

  NexBriefEntry entry(NexAttentionItem item) => NexBriefEntry(
    title: item.title,
    dueAt: item.dueAt,
    recurring: item.recurring,
    remaining: item.remaining,
    total: item.total,
    noteId: item.noteId,
  );

  final overdue = [
    for (final item in attention.overdue)
      if (item.source == NexAttentionSource.note || item.waiting) entry(item),
  ]..sort((a, b) => a.dueAt!.compareTo(b.dueAt!));
  final dueSoon = [
    for (final item in attention.items)
      if ((item.kind == NexAttentionKind.today ||
              item.kind == NexAttentionKind.soon) &&
          item.waiting)
        entry(item),
  ]..sort((a, b) => a.dueAt!.compareTo(b.dueAt!));
  // A checklist is unfinished whether or not it has a date, so long as that
  // date is not already one of the dated groups above: a list due in three
  // weeks is still a list with items left on it, and the brief has always
  // said so rather than waiting three weeks to mention it.
  final unfinished = [
    for (final item in attention.items)
      if (item.source == NexAttentionSource.note &&
          (item.remaining ?? 0) > 0 &&
          (item.kind == NexAttentionKind.unfinished ||
              item.kind == NexAttentionKind.upcoming))
        entry(item),
  ];

  return NexBriefFacts(
    overdue: overdue,
    dueSoon: dueSoon,
    unfinished: unfinished,
    notes: attention.liveNotes,
  );
}
