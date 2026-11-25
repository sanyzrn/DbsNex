/// One reading of the library that both intelligence surfaces are built from.
///
/// The daily brief and the daily nudge grew separately: the brief was given
/// `nexBriefFacts` — dates, checklists, commitments — and the notification was
/// given its own walk over the same notes with a different horizon, a different
/// rank and its own idea of what "overdue" means. Two readings of one library
/// is a bug waiting for the first rule that changes in one of them: the brief
/// called a reminder due at 11:20 "coming up" while the notification, reading
/// the same note through `computeNextOccurrence`, could call it something else
/// on the same morning.
///
/// This is the one reading. It answers, for every note and every standing
/// commitment, what its state is *now* — overdue, due today, due within the
/// horizon, or not waiting at all — and how much it deserves attention. It
/// deliberately says nothing about wording, layout, how many lines to spend or
/// which of the two surfaces is asking: those are the independent policies the
/// brief and the nudge are supposed to have.
///
/// Two things it refuses to conflate, because the brief got them wrong:
///
/// - **A date in the future is not a thing done, missed or reminded.** An item
///   due at 11:20 read at 10:30 is [NexAttentionKind.today] and nothing else.
///   [NexAttentionItem.state] says so in one word for a prompt or a test.
/// - **"Can be ticked off early" is not "near" and not "overdue"**. A recurring
///   item has an early-completion window of its own (2.9.0); whether that
///   window is open is [NexAttentionItem.canCompleteEarly], a flag beside the
///   status rather than a status.
///
/// Pure: no storage, no clock of its own, no wording.
library;

import '../models/commitment.dart';
import '../models/note.dart';

/// What an item's date means at the moment it was read.
enum NexAttentionKind {
  /// Its moment has passed and nobody has answered it.
  overdue,

  /// It falls due later on the same local calendar day.
  today,

  /// It falls due after today and inside the horizon.
  soon,

  /// It has a date, but beyond the horizon: a note with a day on it, not
  /// something this morning needs to raise.
  upcoming,

  /// A checklist with something still unticked, and no date pulling it into
  /// one of the groups above.
  unfinished,

  /// Nothing is due on it and nothing is unticked. It is here because what it
  /// says may be worth surfacing — a plan, a decision, an idea.
  idea,
}

/// Whether a fact came from a note or from a standing commitment.
enum NexAttentionSource { note, commitment }

/// One thing the library contains, reduced to what a surface may say about it.
class NexAttentionItem {
  const NexAttentionItem({
    required this.id,
    required this.source,
    required this.kind,
    required this.title,
    required this.updatedAt,
    required this.waiting,
    this.noteId,
    this.commitmentId,
    this.dueAt,
    this.opensAt,
    this.canCompleteEarly = false,
    this.urgent = false,
    this.recurring = false,
    this.remaining,
    this.total,
    this.stale = false,
    this.score = 0,
    this.cluster = '',
  });

  /// Stable and prefixed — `note:<id>`, `commitment:<id>` — so one row can
  /// never be mistaken for the other, the same convention the reminder
  /// payloads use.
  final String id;
  final NexAttentionSource source;
  final NexAttentionKind kind;
  final String title;
  final String? noteId;
  final String? commitmentId;

  /// When it falls due, or null.
  final DateTime? dueAt;

  /// When its current occurrence may first be marked done. Null for notes and
  /// for a commitment whose window is already open.
  final DateTime? opensAt;

  /// Whether a recurring item's early-completion window is open right now —
  /// a fact about the item, never a substitute for [kind].
  final bool canCompleteEarly;

  /// The person's own priority mark. Kept apart from [kind] so an urgent note
  /// that is also overdue is still counted as overdue by the brief.
  final bool urgent;

  final bool recurring;

  /// Unticked items, and how many there were, for a checklist.
  final int? remaining;
  final int? total;

  /// How recently the note was touched, for the "not worth saying yet" rule
  /// and for a deterministic tie-break.
  final DateTime updatedAt;

  /// Whether the item is inside its own waking/lead window at the time it was
  /// read. A commitment stops being `unfinished`-like when it is not waiting;
  /// this is what the brief's dueSoon is built from, and it is why a yearly
  /// renewal seven days out is in the brief while a monthly one ten days out
  /// is not.
  final bool waiting;

  /// Overdue long enough that the notification treats it as history rather
  /// than as news. The brief still carries it: a wrong date does not stop
  /// mattering because it is old. The nudge has a medium of four lines and a
  /// person who has ignored something for a month has answered it in their
  /// own way.
  final bool stale;

  /// How much this deserves attention, highest first. Deterministic: the same
  /// library read at the same moment scores the same way on every device.
  final int score;

  /// The topic group this item belongs to, or its own id when it belongs to
  /// one alone. Grouping never merges records; it only says which of them are
  /// about the same thing.
  final String cluster;

  /// One word for a prompt, a test or a log: the status, not a suggestion.
  String get state => switch (kind) {
    NexAttentionKind.overdue => 'overdue',
    NexAttentionKind.today => 'due-today',
    NexAttentionKind.soon => 'due-soon',
    NexAttentionKind.upcoming => 'upcoming',
    NexAttentionKind.unfinished => 'unfinished',
    NexAttentionKind.idea => 'note',
  };

  /// Whether it is waiting on somebody at all.
  bool get isWaiting =>
      kind != NexAttentionKind.upcoming && kind != NexAttentionKind.idea;
}

/// Two or more items about the same thing — the same word, the same tag.
///
/// The members keep their own ids, titles and dates. This is a reading aid for
/// a model that cannot see the whole set at once, and for a surface that wants
/// to say "three things for the trip" without turning three notes into one.
class NexAttentionCluster {
  const NexAttentionCluster({
    required this.id,
    required this.label,
    required this.items,
  });

  final String id;
  final String label;
  final List<NexAttentionItem> items;
}

/// The library, read once.
class NexAttention {
  const NexAttention({
    required this.at,
    required this.items,
    required this.clusters,
    required this.liveNotes,
    required this.hasData,
  });

  final DateTime at;
  final List<NexAttentionItem> items;
  final List<NexAttentionCluster> clusters;
  final int liveNotes;

  /// Whether there is a library at all, as opposed to a library with nothing
  /// due in it. The difference is the difference between "how to begin" and
  /// silence.
  final bool hasData;

  List<NexAttentionItem> ofKind(NexAttentionKind kind) => [
    for (final item in items)
      if (item.kind == kind) item,
  ];

  List<NexAttentionItem> get overdue => ofKind(NexAttentionKind.overdue);
  List<NexAttentionItem> get today => ofKind(NexAttentionKind.today);
  List<NexAttentionItem> get soon => ofKind(NexAttentionKind.soon);
  List<NexAttentionItem> get upcoming => ofKind(NexAttentionKind.upcoming);
  List<NexAttentionItem> get unfinished => ofKind(NexAttentionKind.unfinished);
  List<NexAttentionItem> get ideas => ofKind(NexAttentionKind.idea);

  /// Everything that is waiting, in attention order.
  List<NexAttentionItem> get waiting => [
    for (final item in items)
      if (item.isWaiting) item,
  ];

  NexAttentionItem? byId(String id) {
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }
}

/// What a single date means at [now] — the classifier both surfaces use.
///
/// It exists on its own because a surface sometimes has a *computed* date to
/// classify: the nudge reads a repeating reminder at its next occurrence, not
/// at the anchor it was set for. The rule must still be the same rule, or the
/// two surfaces disagree about the same afternoon.
NexAttentionKind nexAttentionKindFor(
  DateTime? due, {
  required DateTime now,
  Duration horizon = const Duration(days: 7),
  bool hasOpenItems = false,
}) {
  if (due == null) {
    return hasOpenItems ? NexAttentionKind.unfinished : NexAttentionKind.idea;
  }
  final local = now.toLocal();
  final moment = due.toLocal();
  if (moment.isBefore(now)) return NexAttentionKind.overdue;
  if (moment.year == local.year &&
      moment.month == local.month &&
      moment.day == local.day) {
    return NexAttentionKind.today;
  }
  if (moment.isBefore(now.add(horizon))) return NexAttentionKind.soon;
  return NexAttentionKind.upcoming;
}

/// Reads [notes] and [commitments] as of [now].
///
/// [horizon] is how far ahead a date is still "soon". It is the brief's
/// horizon by default, and the nudge passes its own — that difference is a
/// policy, not a disagreement about the facts.
///
/// [includeIdeas] adds notes with nothing due and nothing unticked. The nudge
/// wants them as optional depth behind a real fact; the brief's report style
/// already has its own recent-note pass, so it leaves them out.
NexAttention nexAttention(
  List<Note> notes, {
  List<NexCommitment> commitments = const [],
  DateTime? now,
  Duration horizon = const Duration(days: 7),
  bool includeIdeas = true,
  Duration ideaWindow = const Duration(days: 7),
}) {
  final local = now ?? DateTime.now();
  final at = local.toUtc();
  DateTime zoned(DateTime value) =>
      local.isUtc ? value.toUtc() : value.toLocal();

  final live = [
    for (final note in notes)
      if (!note.isDeleted && !note.isSetAside(local)) note,
  ];

  final items = <NexAttentionItem>[];

  NexAttentionItem noteItem(Note note) {
    final title = _titleOf(note);
    final due = note.dueAt;
    final items = note.checklistItems;
    final left = items.where((item) => !item.done).length;
    final hasOpenItems =
        note.type == NoteType.checklist && items.isNotEmpty && left > 0;
    NexAttentionKind kind;
    var waiting = false;
    var stale = false;
    if (due != null) {
      final moment = due.toUtc();
      if (moment.isBefore(at)) {
        kind = NexAttentionKind.overdue;
        waiting = true;
        stale = at.difference(moment) > const Duration(days: 7);
      } else if (_dayGap(zoned(local), zoned(due)) == 0) {
        kind = NexAttentionKind.today;
        waiting = true;
      } else if (moment.isBefore(at.add(horizon))) {
        kind = NexAttentionKind.soon;
        waiting = true;
      } else {
        kind = NexAttentionKind.upcoming;
      }
    } else if (hasOpenItems) {
      kind = NexAttentionKind.unfinished;
      waiting = true;
    } else {
      kind = NexAttentionKind.idea;
    }
    if (kind == NexAttentionKind.idea &&
        local.difference(note.updatedAt.toLocal()) > ideaWindow) {
      // An old note with no date on it is not an idea this morning. It is
      // still in the library and still searchable; it is just not news.
      return NexAttentionItem(
        id: 'note:${note.id}',
        source: NexAttentionSource.note,
        kind: NexAttentionKind.idea,
        title: title,
        updatedAt: note.updatedAt,
        waiting: false,
        noteId: note.id,
        remaining: hasOpenItems ? left : null,
        total: hasOpenItems ? items.length : null,
        score: 0,
      );
    }
    return NexAttentionItem(
      id: 'note:${note.id}',
      source: NexAttentionSource.note,
      kind: kind,
      title: title,
      updatedAt: note.updatedAt,
      waiting: waiting,
      noteId: note.id,
      dueAt: due,
      urgent: note.isUrgent,
      remaining: hasOpenItems ? left : null,
      total: hasOpenItems ? items.length : null,
      stale: stale,
      score: _scoreFor(
        kind: kind,
        urgent: note.isUrgent,
        local: local,
        due: due,
        updatedAt: note.updatedAt,
        remaining: left,
        total: items.length,
        title: title,
      ),
    );
  }

  for (final note in live) {
    if (_titleOf(note).isEmpty) continue;
    final item = noteItem(note);
    if (!includeIdeas && item.kind == NexAttentionKind.idea) continue;
    items.add(item);
  }

  for (final commitment in commitments) {
    if (commitment.paused) continue;
    final due = commitment.dueAt;
    final overdue = commitment.isOverdue(local);
    final sameDay = _dayGap(zoned(local), zoned(due)) == 0;
    final kind = overdue
        ? NexAttentionKind.overdue
        : sameDay
        ? NexAttentionKind.today
        : due.isBefore(local.add(horizon))
        ? NexAttentionKind.soon
        : NexAttentionKind.upcoming;
    // `waiting` keeps the brief's own rule: a commitment enters the brief by
    // its lead time, not by the horizon. A monthly renewal ten days out is a
    // date on a list; the same renewal two days out is this morning's news.
    final waiting = overdue || commitment.isWaiting(local);
    final open = commitment.canComplete(local);
    items.add(
      NexAttentionItem(
        id: 'commitment:${commitment.id}',
        source: NexAttentionSource.commitment,
        kind: kind,
        title: commitment.title.trim(),
        updatedAt: commitment.updatedAt,
        waiting: waiting,
        commitmentId: commitment.id,
        dueAt: due,
        opensAt: open ? null : commitment.completionOpensAt,
        canCompleteEarly: open && !overdue,
        recurring: true,
        stale: overdue && local.difference(due) > const Duration(days: 7),
        score: _scoreFor(
          kind: kind,
          urgent: false,
          local: local,
          due: due,
          updatedAt: commitment.updatedAt,
          remaining: null,
          total: null,
          title: commitment.title,
          recurring: true,
        ),
      ),
    );
  }

  items.sort((a, b) {
    final byScore = b.score.compareTo(a.score);
    if (byScore != 0) return byScore;
    final aDue = a.dueAt, bDue = b.dueAt;
    if (aDue != null && bDue != null && aDue != bDue) {
      return aDue.compareTo(bDue);
    }
    return a.id.compareTo(b.id);
  });

  final clusters = _clusters(items);

  return NexAttention(
    at: local,
    items: clusters.items,
    clusters: clusters.groups,
    // The library's size, not the waiting count: a note set aside for later
    // is still in the library. This is the number the brief reports, so it
    // counts exactly what the brief used to count.
    liveNotes: notes.where((note) => !note.isDeleted).length,
    hasData: live.isNotEmpty || commitments.isNotEmpty,
  );
}

/// What a note is called when it has no words of its own: a checklist's
/// unticked items, or the kind of media it is. Never an empty quotation.
String _titleOf(Note note) {
  // The card's own precedence first, so a fact in the brief and the same note
  // on the timeline are called the same thing. A checklist whose stored lines
  // are all blank falls back to the unticked ones, then to its kind.
  final titled = note.displayText?.trim() ?? '';
  if (titled.isNotEmpty) return titled;
  if (note.type == NoteType.checklist) {
    final open = [
      for (final item in note.checklistItems)
        if (!item.done && item.text.trim().isNotEmpty) item.text,
    ].take(3).join(' · ');
    if (open.isNotEmpty) return open;
  }
  return switch (note.type) {
    NoteType.photo => 'Photo note',
    NoteType.voice => 'Voice note',
    NoteType.video => 'Video',
    NoteType.file => note.originalFilename ?? 'File',
    NoteType.checklist => 'Checklist',
    _ => 'Note',
  };
}

/// The ordering rule, in one place.
///
/// Status first — an overdue item outranks a future one, and an important
/// unfinished one outranks a distant date — then urgency, then how close the
/// moment is, then how substantial or recent the thing is. The numbers are
/// arbitrary on purpose: they only have to stay in this order, and every
/// comparison is made inside one library at one moment.
int _scoreFor({
  required NexAttentionKind kind,
  required bool urgent,
  required DateTime local,
  required DateTime? due,
  required DateTime updatedAt,
  required int? remaining,
  required int? total,
  required String title,
  bool recurring = false,
}) {
  var score = switch (kind) {
    NexAttentionKind.overdue => 800,
    NexAttentionKind.today => 700,
    NexAttentionKind.soon => 600,
    NexAttentionKind.upcoming => 300,
    NexAttentionKind.unfinished => 450,
    NexAttentionKind.idea => 200,
  };
  if (urgent) score += 200;
  if (recurring) score += 10;
  switch (kind) {
    case NexAttentionKind.overdue:
      final days = local.difference(due ?? local).inDays.clamp(0, 30);
      // The most overdue is not always the most important, but it is the one
      // that has been ignored longest: two points a day, enough to order
      // them, not enough to bury a fresh one under a year-old one.
      score -= days * 2;
    case NexAttentionKind.today:
      final minutes = (due ?? local).difference(local).inMinutes;
      score += (60 - minutes).clamp(0, 60);
    case NexAttentionKind.soon:
      final days = (due ?? local).difference(local).inDays;
      score += (7 - days.clamp(0, 7)) * 10;
    case NexAttentionKind.unfinished:
      final done = (total ?? 0) - (remaining ?? 0);
      final ratio = (total ?? 0) == 0 ? 0.0 : done / total!;
      score += (ratio * 60).round();
      final age = local.difference(updatedAt.toLocal()).inHours;
      score += (48 - age.clamp(0, 48)) ~/ 2;
    case NexAttentionKind.idea:
      final age = local.difference(updatedAt.toLocal()).inHours;
      score += (72 - age.clamp(0, 72)) ~/ 3;
      // A note with something in it is worth more than a two-word one.
      score += title.length.clamp(0, 40) ~/ 2;
    case NexAttentionKind.upcoming:
      break;
  }
  return score;
}

/// Groups items that share a meaningful word, without merging any of them.
///
/// A union-find over title tokens and tags: two notes about "the trip" end in
/// one cluster even when they arrive through different words. Bucketed by
/// token, so a large library costs one pass per token rather than a comparison
/// per pair.
({List<NexAttentionItem> items, List<NexAttentionCluster> groups}) _clusters(
  List<NexAttentionItem> items,
) {
  final parent = <String, String>{for (final item in items) item.id: item.id};
  String find(String id) {
    var root = id;
    while (parent[root] != root) {
      root = parent[root]!;
    }
    var cursor = id;
    while (cursor != root) {
      final next = parent[cursor]!;
      parent[cursor] = root;
      cursor = next;
    }
    return root;
  }

  void union(String a, String b) {
    final ra = find(a), rb = find(b);
    if (ra != rb) parent[rb] = ra;
  }

  final byToken = <String, List<String>>{};
  final tokensById = <String, List<String>>{};
  for (final item in items) {
    final tokens = nexAttentionTokens(item.title);
    tokensById[item.id] = tokens;
    for (final token in tokens) {
      byToken.putIfAbsent(token, () => []).add(item.id);
    }
  }
  for (final ids in byToken.values) {
    for (var i = 1; i < ids.length; i++) {
      union(ids.first, ids[i]);
    }
  }

  final members = <String, List<NexAttentionItem>>{};
  for (final item in items) {
    members.putIfAbsent(find(item.id), () => []).add(item);
  }
  final labelOf = <String, String>{};
  for (final entry in members.entries) {
    if (entry.value.length < 2) continue;
    final counts = <String, int>{};
    for (final item in entry.value) {
      for (final token in tokensById[item.id] ?? const <String>[]) {
        counts[token] = (counts[token] ?? 0) + 1;
      }
    }
    final best = counts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });
    labelOf[entry.key] = best.isEmpty ? '' : best.first.key;
  }

  final groups = <NexAttentionCluster>[];
  for (final entry in members.entries) {
    final label = labelOf[entry.key];
    if (label == null || label.isEmpty) continue;
    groups.add(
      NexAttentionCluster(id: entry.key, label: label, items: entry.value),
    );
  }
  groups.sort((a, b) => b.items.length.compareTo(a.items.length));

  return (
    items: [
      for (final item in items)
        NexAttentionItem(
          id: item.id,
          source: item.source,
          kind: item.kind,
          title: item.title,
          noteId: item.noteId,
          commitmentId: item.commitmentId,
          dueAt: item.dueAt,
          opensAt: item.opensAt,
          canCompleteEarly: item.canCompleteEarly,
          urgent: item.urgent,
          recurring: item.recurring,
          remaining: item.remaining,
          total: item.total,
          updatedAt: item.updatedAt,
          waiting: item.waiting,
          stale: item.stale,
          score: item.score,
          cluster: labelOf[find(item.id)] ?? item.id,
        ),
    ],
    groups: groups,
  );
}

/// The words of [text] that can group two items: lower-cased, four letters or
/// more, minus the words that appear in everything.
List<String> nexAttentionTokens(String text) {
  final tokens = <String>{};
  for (final match in RegExp(
    r'[\p{L}\p{N}]+',
    unicode: true,
  ).allMatches(text.toLowerCase())) {
    final token = match.group(0)!;
    if (token.length < 3) continue;
    if (_stopWords.contains(token)) continue;
    tokens.add(token);
  }
  return [...tokens];
}

const _stopWords = {
  // English
  'the', 'and', 'for', 'with', 'that', 'this', 'from', 'have', 'has', 'had',
  'was', 'were', 'are', 'not', 'but', 'his', 'her', 'their', 'our', 'you',
  'your', 'about', 'into', 'over', 'after', 'before', 'when', 'what', 'who',
  'will', 'would', 'should', 'could', 'there', 'then', 'than', 'them', 'they',
  'she', 'him', 'its', 'all', 'any', 'can', 'just', 'get', 'got', 'one',
  'two', 'new', 'day', 'today', 'tomorrow', 'call', 'note', 'notes',
  // Persian — the words that appear in every second note
  'برای', 'از', 'به', 'که', 'این', 'آن', 'با', 'را', 'در', 'و', 'یا', 'تا',
  'هم', 'یک', 'دو', 'روز', 'امروز', 'فردا', 'یادداشت', 'کار', 'های', 'ها',
  'می', 'شود', 'کرد', 'است', 'بود', 'شد', 'کردن', 'تهیه', 'خرید',
};

/// Whole calendar days from [from] to [to], negative when [to] is earlier.
int _dayGap(DateTime from, DateTime to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

/// The facts a model is given, as a block rather than as prose to interpret.
///
/// Every line states the status the app computed. A model reading "upcoming"
/// cannot reasonably call the same item done; a model told the counts cannot
/// invent an overdue one. The brief formats these again for the reader, in the
/// reader's language — this block is deliberately in English and terse,
/// because it is prompt material, not copy.
String nexAttentionLedger(NexAttention attention) {
  final counts = [
    '${attention.overdue.length} overdue',
    '${attention.today.length} due today',
    '${attention.soon.length} due within the horizon',
    '${attention.unfinished.length} unfinished checklists',
  ];
  final lines = <String>[
    'FACTS COMPUTED BY THE APP (authoritative; never contradict them):',
    '- ${counts.join(', ')}.',
  ];
  for (final item in attention.items.take(24)) {
    if (!item.isWaiting) continue;
    final when = item.dueAt == null
        ? ''
        : ' | ${_clock(attention.at.isUtc ? item.dueAt!.toUtc() : item.dueAt!.toLocal())}';
    final progress = item.remaining == null
        ? ''
        : ' | ${item.remaining}/${item.total} left';
    final early = item.canCompleteEarly ? ' | window open to tick it off' : '';
    lines.add(
      '- ${item.state.toUpperCase()}$when$progress$early | '
      '${item.urgent ? 'URGENT ' : ''}"${item.title}"',
    );
  }
  for (final group in attention.clusters.take(6)) {
    lines.add(
      '- RELATED: ${group.items.length} items about "${group.label}" — '
      '${group.items.map((item) => '"${item.title}"').join(', ')}',
    );
  }
  return lines.join('\n');
}

String _clock(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}';

/// Whether a generated brief says something the facts contradict.
///
/// Narrow on purpose. It does not judge style, usefulness or completeness —
/// those are the model's job — and it does not try to check every date in a
/// sentence, which would reject correct rephrasing. It catches the two claims
/// that are worse than a bad line because they are *actionable*: calling
/// nothing overdue when something is, and calling the day clear when it is
/// not. A brief that fails this is not shown; the locally written facts stand
/// in for it.
///
/// [text] is the model's answer, already joined with the local lines.
bool nexAttentionContradicts(String text, NexAttention attention) {
  if (text.trim().isEmpty) return false;
  final lower = text.toLowerCase();
  bool claims(List<String> words) => words.any(lower.contains);

  // "Nothing overdue" is a claim about the library; on a library with an
  // overdue item it is false whichever way the rest of the line reads.
  if (claims(_clearOfOverdue) && attention.overdue.isNotEmpty) return true;

  // "Nothing is due" / "everything is done" on a day with items waiting.
  final clearClaim =
      claims(_dayIsClear) &&
      !claims(const ['but ', 'except', 'only ', 'however', 'اما ', 'ولی ']);
  if (clearClaim && attention.waiting.isNotEmpty) return true;

  return false;
}

/// Stems that mean "nothing has slipped" on their own.
const _clearOfOverdue = [
  'nothing overdue',
  'no overdue',
  'overdue: none',
  'چیزی عقب نیفتاده',
  'هیچ موردی عقب نیفتاده',
  'هیچ عقب‌افتادگی',
];

const _dayIsClear = [
  'nothing is due',
  'nothing due',
  'nothing is waiting',
  'nothing waiting',
  'all caught up',
  'everything is done',
  'everything is finished',
  'all done',
  'چیزی برای انجام نمانده',
  'هیچ کاری نمانده',
  'همه انجام شده',
  'همه‌چیز انجام شده',
  'چیزی سررسید نشده',
];
