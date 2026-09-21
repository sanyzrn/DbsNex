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

/// One thing worth mentioning, reduced to the facts about it.
class NexBriefEntry {
  const NexBriefEntry({
    required this.title,
    this.dueAt,
    this.recurring = false,
    this.remaining,
    this.total,
  });

  final String title;

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
  final local = now ?? DateTime.now();
  final at = local.toUtc();
  // Sorted once, here, so every group below comes out in a defined order
  // whatever order the library handed them over in. Newest first is the right
  // default for the groups that have no date of their own.
  final live = [
    for (final note in notes)
      if (note.deletedAt == null) note,
  ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  final overdue = <NexBriefEntry>[];
  final dueSoon = <NexBriefEntry>[];
  final unfinished = <NexBriefEntry>[];

  for (final commitment in commitments) {
    if (commitment.paused) continue;
    if (commitment.isOverdue(local)) {
      overdue.add(
        NexBriefEntry(
          title: commitment.title,
          dueAt: commitment.dueAt,
          recurring: true,
        ),
      );
    } else if (commitment.isWaiting(local)) {
      dueSoon.add(
        NexBriefEntry(
          title: commitment.title,
          dueAt: commitment.dueAt,
          recurring: true,
        ),
      );
    }
  }

  for (final note in live) {
    final title = note.displayText?.trim();
    if (title == null || title.isEmpty) continue;
    final due = note.dueAt;
    if (due != null) {
      final moment = due.toUtc();
      if (moment.isBefore(at)) {
        overdue.add(NexBriefEntry(title: title, dueAt: due));
        continue;
      }
      if (moment.isBefore(at.add(horizon))) {
        dueSoon.add(NexBriefEntry(title: title, dueAt: due));
        continue;
      }
    }
    // A checklist counts as unfinished whatever its date, but only once: a
    // list that is also overdue has already been said, and saying it twice
    // in a four-line brief spends half the brief on one item.
    if (note.type == NoteType.checklist) {
      final items = note.checklistItems;
      final left = items.where((item) => !item.done).length;
      if (left > 0) {
        unfinished.add(
          NexBriefEntry(
            title: title,
            remaining: left,
            total: items.length,
          ),
        );
      }
    }
  }

  overdue.sort((a, b) => a.dueAt!.compareTo(b.dueAt!));
  dueSoon.sort((a, b) => a.dueAt!.compareTo(b.dueAt!));

  return NexBriefFacts(
    overdue: overdue,
    dueSoon: dueSoon,
    unfinished: unfinished,
    notes: live.length,
  );
}
