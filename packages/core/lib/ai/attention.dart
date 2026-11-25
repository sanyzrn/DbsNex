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
    this.tags = const [],
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

  /// The note's own tags, by name.
  ///
  /// They are here because a tag is the person's own statement that two
  /// records are about one thing — the strongest grouping signal there is,
  /// and the one that needs no guessing about which words matter. The
  /// grouping doc comment promised them before this field existed.
  final List<String> tags;

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
///
/// [semanticPairs] are note-id pairs the caller's stored embeddings say are
/// about the same thing — the local meaning the library already has, read
/// without a provider. They group exactly like a shared tag does: the records
/// keep their own ids, titles and dates, and only the reading aid merges.
NexAttention nexAttention(
  List<Note> notes, {
  List<NexCommitment> commitments = const [],
  DateTime? now,
  Duration horizon = const Duration(days: 7),
  bool includeIdeas = true,
  Duration ideaWindow = const Duration(days: 7),
  List<({String a, String b})> semanticPairs = const [],
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
      tags: [for (final tag in note.tags) tag.name],
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

  final clusters = _clusters(items, semanticPairs);

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

/// Groups items that share a meaningful word, a tag, or a stored embedding's
/// judgement that they are about one thing — without merging any of them.
///
/// A union-find over title tokens, tags and semantic pairs: two notes about
/// "the trip" end in one cluster even when they arrive through different
/// words. Bucketed by token, so a large library costs one pass per token
/// rather than a comparison per pair.
({List<NexAttentionItem> items, List<NexAttentionCluster> groups}) _clusters(
  List<NexAttentionItem> items,
  List<({String a, String b})> semanticPairs,
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

  // A word every third note carries ("shopping", "work") says nothing about
  // two notes being about one thing, so it is not allowed to merge them. A
  // tag always is: it is the person's own word for the subject.
  final byToken = <String, List<String>>{};
  final tokensById = <String, List<String>>{};
  final tagsById = <String, List<String>>{};
  for (final item in items) {
    final tokens = nexAttentionTokens(item.title);
    tokensById[item.id] = tokens;
    tagsById[item.id] = [for (final tag in item.tags) nexAttentionStem(tag)];
    for (final token in tokens) {
      byToken.putIfAbsent(token, () => []).add(item.id);
    }
  }
  final tooCommon = (items.length / 3).ceil().clamp(3, 1 << 30);
  bool distinct(String token) => (byToken[token]?.length ?? 0) < tooCommon;
  for (final entry in byToken.entries) {
    if (!distinct(entry.key)) continue;
    final ids = entry.value;
    for (var i = 1; i < ids.length; i++) {
      union(ids.first, ids[i]);
    }
  }
  // Two notes that share a tag are about the same thing even when neither
  // title carries a word the other does — the tag *is* that word.
  final byTag = <String, List<String>>{};
  for (final entry in tagsById.entries) {
    for (final tag in entry.value) {
      byTag.putIfAbsent(tag, () => []).add(entry.key);
    }
  }
  for (final ids in byTag.values) {
    for (var i = 1; i < ids.length; i++) {
      union(ids.first, ids[i]);
    }
  }
  // Two notes the library's own vectors call one subject group even when no
  // word or tag says so — «چکاپ دندان» beside «وقت دندانپزشکی», "the dentist"
  // beside "tooth appointment". The pair is only honoured when both records
  // are in this reading; a vector for a note the brief cannot see groups
  // nothing.
  for (final pair in semanticPairs) {
    final a = 'note:${pair.a}', b = 'note:${pair.b}';
    if (parent.containsKey(a) && parent.containsKey(b)) union(a, b);
  }

  final members = <String, List<NexAttentionItem>>{};
  for (final item in items) {
    members.putIfAbsent(find(item.id), () => []).add(item);
  }
  final labelOf = <String, String>{};
  for (final entry in members.entries) {
    if (entry.value.length < 2) continue;
    // The tag first — it is a name the person chose — then the word the most
    // members share, with the rarer word winning a tie: "tabriz" says more
    // than "trip" does about which trip.
    final tags = <String, int>{};
    final counts = <String, int>{};
    for (final item in entry.value) {
      for (final tag in tagsById[item.id] ?? const <String>[]) {
        tags[tag] = (tags[tag] ?? 0) + 1;
      }
      for (final token in tokensById[item.id] ?? const <String>[]) {
        counts[token] = (counts[token] ?? 0) + 1;
      }
    }
    MapEntry<String, int>? pick(Map<String, int> from) {
      final sorted = from.entries.toList()
        ..sort((a, b) {
          final byCount = b.value.compareTo(a.value);
          if (byCount != 0) return byCount;
          final byRarity = (byToken[a.key]?.length ?? 0).compareTo(
            byToken[b.key]?.length ?? 0,
          );
          return byRarity != 0 ? byRarity : a.key.compareTo(b.key);
        });
      return sorted.isEmpty ? null : sorted.first;
    }

    final tag = pick(tags);
    if (tag != null && tag.value > 1) {
      labelOf[entry.key] = tag.key;
      continue;
    }
    final best = pick(counts);
    labelOf[entry.key] = best == null ? '' : best.key;
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
          tags: item.tags,
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

/// The words of [text] that can group two items: folded, stemmed, three
/// letters or more, minus the words that appear in everything.
List<String> nexAttentionTokens(String text) {
  final tokens = <String>{};
  for (final match in RegExp(
    r'[\p{L}\p{N}]+',
    unicode: true,
  ).allMatches(text)) {
    final token = nexAttentionStem(match.group(0)!);
    if (token.length < 3) continue;
    if (_stopWords.contains(token)) continue;
    tokens.add(token);
  }
  return [...tokens];
}

/// [text] with the differences two keyboards make erased: the two letter
/// forms Persian types interchangeably, the diacritics most people leave out,
/// the zero-width non-joiner some keyboards insert and others do not, the
/// tatweel nobody means, and the digits of both scripts.
///
/// Grouping used to compare raw strings, so «خريد» and «خرید» — the same
/// word — never met, and neither did «می‌شود» and «میشود». This is the local
/// half of "meaning": the same subject written two ways, without a model,
/// without a network and without reading anything the person did not write.
String nexAttentionFold(String text) {
  final buffer = StringBuffer();
  for (final rune in text.runes) {
    // Combining marks, the two joiners and the tatweel carry no meaning a
    // token needs, and every one of them splits a word that should match.
    if (rune >= 0x064B && rune <= 0x065F) continue;
    if (rune == 0x0670 || rune == 0x0640) continue;
    if (rune == 0x200C || rune == 0x200D || rune == 0xFEFF) continue;
    if (rune >= 0x06F0 && rune <= 0x06F9) {
      buffer.writeCharCode(0x30 + (rune - 0x06F0)); // ۰-۹
      continue;
    }
    if (rune >= 0x0660 && rune <= 0x0669) {
      buffer.writeCharCode(0x30 + (rune - 0x0660)); // ٠-٩
      continue;
    }
    const forms = {
      0x064A: 0x06CC, // ي -> ی
      0x0643: 0x06A9, // ك -> ک
      0x0623: 0x0627, // أ -> ا
      0x0625: 0x0627, // إ -> ا
      0x0622: 0x0627, // آ -> ا
      0x0629: 0x0647, // ة -> ه
      0x0624: 0x0648, // ؤ -> و
      0x0626: 0x06CC, // ئ -> ی
    };
    buffer.writeCharCode(forms[rune] ?? rune);
  }
  return buffer.toString().toLowerCase();
}

/// One word, reduced to the form two notes about the same subject share.
///
/// Plural forms are the common case in both languages — «خریدها» beside
/// «خرید», "invoices" beside "invoice" — and a plural is not a different
/// subject. Only the shortest endings are removed, and only when what is left
/// is still a word: over-stemming («کارت» to «کار») would invent a relation
/// that is not there.
String nexAttentionStem(String word) {
  var value = nexAttentionFold(word);
  if (value.length > 4) {
    for (final suffix in _faSuffixes) {
      if (value.endsWith(suffix) && value.length - suffix.length >= 3) {
        value = value.substring(0, value.length - suffix.length);
        break;
      }
    }
    value = _englishStem(value);
  }
  return value;
}

/// English plurals and progressives, reduced the way a person reads them.
///
/// The plural of "invoice" is "invoices", not "invoic": an "es" is only a
/// plural ending of its own after a sibilant, and everywhere else the "s" is.
/// A doubled consonant before "ing" is the same kind of rule — "shopping" is
/// "shop", not "shopp" — and keeping both is what makes two notes about one
/// subject meet.
String _englishStem(String value) {
  String cut(int n) => value.substring(0, value.length - n);
  bool keeps(int n) => value.length - n >= 4;
  String dedouble(String stem) =>
      stem.length > 2 && stem[stem.length - 1] == stem[stem.length - 2]
      ? stem.substring(0, stem.length - 1)
      : stem;

  if (value.endsWith('ies') && keeps(3)) {
    return '${cut(3)}y';
  }
  if (value.endsWith('ing') && keeps(3)) return dedouble(cut(3));
  if (value.endsWith('es') && keeps(2) && _sibilant(cut(2))) return cut(2);
  if (value.endsWith('s') && keeps(1)) return cut(1);
  return value;
}

bool _sibilant(String stem) {
  if (stem.isEmpty) return false;
  final last = stem[stem.length - 1];
  return last == 's' || last == 'x' || last == 'z' || last == 'h';
}

/// Longest first: «های» before «ها», or the shorter one eats the longer.
const _faSuffixes = ['هایم', 'هایت', 'هایش', 'های', 'ها', 'شان', 'مان', 'تان'];

const _stopWords = {
  // English, stemmed the way nexAttentionStem leaves them.
  'the', 'and', 'for', 'with', 'that', 'thi', 'from', 'have', 'has', 'had',
  'was', 'were', 'are', 'not', 'but', 'his', 'her', 'their', 'our', 'you',
  'your', 'about', 'into', 'over', 'after', 'before', 'when', 'what', 'who',
  'will', 'would', 'should', 'could', 'there', 'then', 'than', 'them', 'they',
  'she', 'him', 'its', 'all', 'any', 'can', 'just', 'get', 'got', 'one',
  'two', 'new', 'day', 'today', 'tomorrow', 'call', 'note', 'notes',
  // Persian — the words that appear in every second note.
  'برای', 'از', 'به', 'که', 'این', 'آن', 'با', 'را', 'در', 'و', 'یا', 'تا',
  'هم', 'یک', 'دو', 'روز', 'امروز', 'فردا', 'یادداشت', 'کار', 'های', 'ها',
  'می', 'شود', 'کرد', 'است', 'بود', 'شد', 'کردن', 'تهیه', 'خرید', 'باید',
  'شده', 'دیگه', 'چیز', 'موقع', 'وقت',
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
String nexAttentionLedger(NexAttention attention, {int budget = 3200}) {
  final counts = [
    '${attention.overdue.length} overdue',
    '${attention.today.length} due today',
    '${attention.soon.length} due within the horizon',
    '${attention.upcoming.length} beyond it',
    '${attention.unfinished.length} unfinished checklists',
  ];
  final lines = <String>[
    'FACTS COMPUTED BY THE APP (authoritative; never contradict them):',
    '- ${counts.join(', ')}.',
  ];
  var used = lines.first.length + lines.last.length + 2;
  var hidden = 0;
  for (final item in attention.items) {
    if (!item.isWaiting) continue;
    final when = item.dueAt == null
        ? ''
        : ' | ${_clock(attention.at.isUtc ? item.dueAt!.toUtc() : item.dueAt!.toLocal())}';
    final progress = item.remaining == null
        ? ''
        : ' | ${item.remaining}/${item.total} left';
    final early = item.canCompleteEarly ? ' | window open to tick it off' : '';
    final line =
        '- ${item.state.toUpperCase()}$when$progress$early | '
        '${item.urgent ? 'URGENT ' : ''}"${item.title}"';
    // Bounded by a budget rather than by a fixed number of items, and what
    // does not fit is counted out loud. The old cut at twenty-four was a
    // third of a busy day: the model was asked to describe the day from a
    // slice it had no way to know was a slice.
    if (used + line.length + 1 > budget) {
      hidden++;
      continue;
    }
    lines.add(line);
    used += line.length + 1;
  }
  if (hidden > 0) {
    lines.add(
      '- ($hidden more waiting and not listed here: do not count them, do '
      'not invent them, and do not say there are none.)',
    );
  }
  for (final group in attention.clusters) {
    final line =
        '- RELATED: ${group.items.length} items about "${group.label}" — '
        '${group.items.map((item) => '"${item.title}"').join(', ')}';
    if (used + line.length + 1 > budget) break;
    lines.add(line);
    used += line.length + 1;
  }
  return lines.join('\n');
}

/// The next instant at which what [attention] says stops being true.
///
/// Nothing in the database changes at any of these moments, which is exactly
/// why a cache keyed only on the data cannot notice them: a note due at 11:20
/// is `due-today` at 11:19 and `overdue` at 11:21 with every stored field
/// identical, a recurring item's tick becomes available when its early window
/// opens, and at midnight "today at 09:00" names the wrong day. A surface
/// that shows words computed from these facts can therefore time its own
/// wake-up from here instead of polling or waiting for a write.
DateTime? nexAttentionNextBoundary(NexAttention attention) {
  final at = attention.at;
  DateTime? next;
  void consider(DateTime? when) {
    if (when == null || !when.isAfter(at)) return;
    if (next == null || when.isBefore(next!)) next = when;
  }

  for (final item in attention.items) {
    consider(item.dueAt);
    consider(item.opensAt);
  }
  // The day is the coarsest status there is, and the one every relative
  // phrase in a brief is written against.
  consider(DateTime(at.year, at.month, at.day + 1));
  return next;
}

String _clock(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}';

/// One thing a generated brief says that the facts it was given contradict.
///
/// The reason is written for the log, the line for the record: together they
/// say which sentence was refused and against which fact.
class NexAttentionViolation {
  const NexAttentionViolation(this.reason, this.line);

  final String reason;
  final String line;

  @override
  String toString() => '$reason: $line';
}

/// Every claim in [text] that the computed facts contradict.
///
/// This replaced a check against a list of fixed phrases, which could only
/// ever recognise the sentences somebody had thought of — and which passed a
/// brief that said "the 11:20 call was missed" at ten thirty, because nobody
/// had thought of that one. The ledger states, for every item that matters,
/// its status and its clock, so the question becomes a comparison with *this*
/// library instead of a comparison with a vocabulary.
///
/// Four kinds of claim are decided that way, each per line:
///
/// - **nothing has slipped**, on a day that has something overdue;
/// - **the day is clear**, on a day with something waiting;
/// - **the wrong count** — "2 overdue" when the app counted one;
/// - **the wrong tense** — a future item's clock paired with a past-tense
///   claim, which is the shape of "the 11:20 call was missed" at 10:30, and
///   the same claim with no clock at all: "the bank call was missed", caught
///   by the distinctive words of the item's own title.
///
/// Narrow on purpose, and it errs towards silence: it does not judge style,
/// usefulness or coverage, it ignores a time or a name it does not recognise
/// (a brief may mention a note the ledger had no room for), and one line that
/// also cites an item that really has slipped is left alone, because the past
/// tense in it may be about that item.
List<NexAttentionViolation> nexAttentionViolations(
  String text,
  NexAttention attention,
) {
  if (text.trim().isEmpty) return const [];
  final violations = <NexAttentionViolation>[];
  final at = attention.at;

  // What the ledger says, by the clock a line could name it by.
  final byClock = <String, List<NexAttentionItem>>{};
  final slipped = <String>{};
  final slippedNames = <List<String>>[];
  // How many titles carry each word, so a word every third note shares
  // cannot convict a line that merely happens to contain it.
  final documentFrequency = <String, int>{};
  for (final item in attention.items) {
    for (final token in nexAttentionTokens(item.title)) {
      documentFrequency[token] = (documentFrequency[token] ?? 0) + 1;
    }
  }
  final tooCommon = (attention.items.length / 3).ceil().clamp(3, 1 << 30);
  // The still-ahead items, by the distinctive words a line could name them
  // by: a past tense about one of these is the same false claim the clock
  // check catches, with no clock in the sentence at all.
  final aheadNames = <List<String>>[];
  for (final item in attention.items) {
    final due = item.dueAt;
    if (due == null) continue;
    final clock = _clock(at.isUtc ? due.toUtc() : due.toLocal());
    byClock.putIfAbsent(clock, () => []).add(item);
    if (item.kind == NexAttentionKind.overdue) {
      slipped.add(clock);
      final stems = nexAttentionTokens(item.title);
      if (stems.isNotEmpty) slippedNames.add(stems);
    } else if (item.kind == NexAttentionKind.today ||
        item.kind == NexAttentionKind.soon) {
      final stems = [
        for (final token in nexAttentionTokens(item.title))
          if ((documentFrequency[token] ?? 0) < tooCommon) token,
      ];
      if (stems.isNotEmpty) aheadNames.add(stems);
    }
  }

  /// Whether the line names something that really has slipped. A sentence
  /// that says "the rent is overdue, and the 11:20 call" is talking about two
  /// things, and the past tense belongs to the first.
  bool namesSlipped(String line) {
    for (final stems in slippedNames) {
      final hits = stems.where(line.contains).length;
      if (hits >= (stems.length == 1 ? 1 : 2)) return true;
    }
    return false;
  }

  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final folded = nexAttentionFold(line);
    final excepted = _anyIn(folded, _exceptions);

    if (attention.overdue.isNotEmpty &&
        !excepted &&
        _anyIn(folded, _clearOfOverdue)) {
      violations.add(NexAttentionViolation('claims nothing is overdue', line));
      continue;
    }

    if (attention.waiting.isNotEmpty &&
        !excepted &&
        _anyIn(folded, _dayIsClear)) {
      violations.add(NexAttentionViolation('claims the day is clear', line));
      continue;
    }

    for (final claim in _countClaims(folded)) {
      final truth = switch (claim.unit) {
        _CountUnit.overdue => attention.overdue.length,
        _CountUnit.today => attention.today.length,
      };
      if (claim.count != truth) {
        violations.add(
          NexAttentionViolation(
            'says ${claim.count} ${claim.unit.label} where the app counted '
            '$truth',
            line,
          ),
        );
      }
    }

    final cited = _clocksIn(folded);
    if (!_pastCue(folded)) continue;
    if (namesSlipped(folded)) continue;
    if (cited.isEmpty) {
      // No clock in the sentence: a still-ahead item named in the past tense
      // is the same false claim, one the clock check could never see. Two
      // distinctive words convict, or one when the title has only one — the
      // same rule the slipped-name exemption uses.
      for (final stems in aheadNames) {
        final hits = stems.where(folded.contains).length;
        if (hits >= (stems.length == 1 ? 1 : 2)) {
          violations.add(
            NexAttentionViolation(
              'calls a still-ahead item past by name',
              line,
            ),
          );
          break;
        }
      }
      continue;
    }
    if (cited.any(slipped.contains)) continue;
    for (final clock in cited) {
      final items = byClock[clock];
      if (items == null || items.isEmpty) continue;
      if (items.every((item) => item.kind != NexAttentionKind.overdue)) {
        violations.add(
          NexAttentionViolation(
            'calls the $clock item past while it is still ahead',
            line,
          ),
        );
        break;
      }
    }
  }
  return violations;
}

/// Whether a generated brief says something the facts contradict — the
/// question the timeline asks before a model's words may be cached, shown or
/// published. [text] is the model's answer, already joined with the local
/// lines.
bool nexAttentionContradicts(String text, NexAttention attention) =>
    nexAttentionViolations(text, attention).isNotEmpty;

/// Whether any needle appears in [text]. The text is already folded, so each
/// needle is folded too — written the way a person types it, matched the way
/// the line was normalised — rather than requiring every list below to be
/// kept in its folded form by hand.
bool _anyIn(String text, List<String> needles) =>
    needles.any((needle) => text.contains(nexAttentionFold(needle)));

/// Phrases that make a blanket claim narrower: "all done, except the rent".
const _exceptions = [
  'but ',
  'except',
  'only ',
  'however',
  'apart from',
  'اما ',
  'ولی ',
  'به جز',
  'فقط',
];

/// Stems that mean "nothing has slipped" on their own.
const _clearOfOverdue = [
  'nothing overdue',
  'no overdue',
  'overdue: none',
  'nothing is overdue',
  'none overdue',
  'چیزی عقب نیفتاده',
  'هیچ موردی عقب نیفتاده',
  'هیچ عقب‌افتادگی',
  'عقب افتاده‌ای نداری',
  'هیچ چیز عقب',
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
  'nothing left',
  'چیزی برای انجام نمانده',
  'هیچ کاری نمانده',
  'همه انجام شده',
  'همه‌چیز انجام شده',
  'چیزی سررسید نشده',
  'کاری برای انجام نمانده',
];

/// What a sentence says has already happened, in either language, in the
/// forms a line about a past item takes.
const _pastCues = [
  'done',
  'completed',
  'finished',
  'missed',
  'overdue',
  'passed',
  'went past',
  'already',
  'reminded',
  'forgot',
  'forgotten',
  'was due',
  'should have',
  'skipped',
  'expired',
  'lapsed',
  'انجام شد',
  'انجام شده',
  'تمام شد',
  'گذشت',
  'گذشته',
  'عقب',
  'فراموش',
  'یادآوری شد',
  'از دست رفت',
  'پرید',
  'دیر شده',
];

/// Words that turn a past cue into its opposite: "not done", "هنوز انجام نشده".
const _negations = [
  'not ',
  "n't",
  'no ',
  'never',
  'yet',
  'هنوز',
  'نشده',
  'نکرد',
  'نه ',
  'بدون',
  'قرار نیست',
];

bool _pastCue(String folded) =>
    !_anyIn(folded, _negations) && _anyIn(folded, _pastCues);

/// Every `HH:MM` the line names, in the 24-hour form the ledger uses.
Iterable<String> _clocksIn(String folded) sync* {
  for (final match in RegExp(
    r'(?<!\d)([01]?\d|2[0-3])[:.]([0-5]\d)(?!\d)',
  ).allMatches(folded)) {
    final hour = int.tryParse(match.group(1)!);
    if (hour == null) continue;
    yield '${hour.toString().padLeft(2, '0')}:${match.group(2)}';
  }
}

enum _CountUnit {
  overdue('overdue'),
  today('due today');

  const _CountUnit(this.label);
  final String label;
}

/// A number stated next to a status the app computed. Only the two counts a
/// line can state without ambiguity are read: "3 unfinished items" may mean
/// items inside one list rather than lists, and guessing would refuse honest
/// sentences.
Iterable<({int count, _CountUnit unit})> _countClaims(String folded) sync* {
  for (final match in RegExp(
    r'(\d{1,3})\s*(?:items?\s+|مورد\s+)?(overdue|due today|عقب ?افتاده|برای امروز)',
  ).allMatches(folded)) {
    final count = int.tryParse(match.group(1)!);
    if (count == null) continue;
    final word = match.group(2)!;
    yield (
      count: count,
      unit: word.contains('today') || word.contains('امروز')
          ? _CountUnit.today
          : _CountUnit.overdue,
    );
  }
}
