import 'package:nex_core/nex_core.dart';

/// How the home screen sorts its notes into headings (2.7.0).
///
/// Time is what it always was: days, newest first. Kind and tag answer the
/// other way people remember a note — "it was a photo", "it was under work" —
/// when the day it was written is long gone. Pins stay on top in all three:
/// a pin is a promise to keep something in reach, whatever the arrangement.
enum NexTimelineArrangement {
  time,
  type,
  tag;

  static NexTimelineArrangement fromWire(String? wire) =>
      values.firstWhere((value) => value.name == wire, orElse: () => time);
}

/// What a shelf of an arranged home holds.
enum NexShelfKind { pinned, type, tag, untagged }

/// One heading of an arranged home and the notes under it.
class NexShelf {
  const NexShelf({
    required this.key,
    required this.kind,
    required this.notes,
    required this.total,
    required this.exact,
    this.type,
    this.tag,
  });

  /// Stable across launches and languages — what a fold and a place in the
  /// order are remembered against: `pinned`, `type:photo`, `tag:<id>`,
  /// `untagged`.
  final String key;
  final NexShelfKind kind;
  final NoteType? type;
  final Tag? tag;

  /// The notes shown, in the timeline's own order: newest change first.
  final List<Note> notes;

  /// How many notes the shelf holds in all — more than [notes] when it shows
  /// only its newest few, or when older ones are not loaded yet.
  final int total;

  /// Whether [total] is the library's count (true) or only what is loaded
  /// (false, while a filter is narrowing the list): a shelf says "See all 48"
  /// only when 48 is true.
  final bool exact;

  /// Whether there is more than the shelf shows.
  bool get more => total > notes.length;

  /// The shelf's place among the others is the reader's to change; the pins'
  /// is not.
  bool get movable => kind != NexShelfKind.pinned;
}

/// How many notes a shelf shows while there are other shelves beside it.
///
/// A shelf is a glance, not the list: the newest six of a kind are almost
/// always the one being looked for, and six keeps every kind within a thumb's
/// reach of the top. "See all" opens the rest as the whole screen.
const nexShelfPreview = 6;

/// The order the kinds come in until the reader moves them: writing first,
/// the files that are least often looked through last.
const nexShelfTypeOrder = [
  NoteType.text,
  NoteType.checklist,
  NoteType.voice,
  NoteType.photo,
  NoteType.link,
  NoteType.file,
];

/// Sorts [notes] — already in the timeline's order — into shelves.
///
/// - [counts]: whole-timeline counts (`type:…`, `tag:…`, `untagged`), from
///   `timelineShelfCounts`. Trusted only while nothing is [filtering]: a
///   filter narrows the list, and the library's count of a kind is not the
///   count of that kind among notes tagged "work".
/// - [tags]: every tag in the order the filter row shows them, most used
///   first; a tag shelf takes that place unless moved.
/// - [selectedTagIds], [onlyUntagged]: by tag, a tag filter shows the chosen
///   tags' shelves only — the other tags those notes carry are not what was
///   asked for.
/// - [order]: the reader's own order of shelf keys; a shelf it does not name
///   keeps its default place after the named ones.
///
/// While more than one shelf (pins aside) is on screen, each shows its newest
/// [nexShelfPreview]. With one — a kind or a tag chosen with "See all" or the
/// filter row — that shelf is the list, and shows everything loaded.
List<NexShelf> nexArrangeShelves(
  List<Note> notes, {
  required NexTimelineArrangement by,
  Map<String, int>? counts,
  List<Tag> tags = const [],
  Set<String> selectedTagIds = const {},
  bool onlyUntagged = false,
  bool filtering = false,
  List<String> order = const [],
}) {
  assert(by != NexTimelineArrangement.time, 'time is grouped by day');
  final pinned = <Note>[];
  final buckets = <String, List<Note>>{};
  final tagById = <String, Tag>{};
  final defaults = <String>[];

  if (by == NexTimelineArrangement.type) {
    for (final type in nexShelfTypeOrder) {
      defaults.add('type:${type.wireName}');
    }
  } else {
    final chosen = selectedTagIds.isNotEmpty;
    if (!onlyUntagged) {
      for (final tag in tags) {
        if (chosen && !selectedTagIds.contains(tag.id)) continue;
        tagById[tag.id] = tag;
        defaults.add('tag:${tag.id}');
      }
    }
    if (!chosen) defaults.add('untagged');
  }

  for (final note in notes) {
    if (note.pinnedAt != null) {
      pinned.add(note);
      continue;
    }
    if (by == NexTimelineArrangement.type) {
      (buckets['type:${note.type.wireName}'] ??= []).add(note);
      continue;
    }
    var placed = false;
    for (final tag in note.tags) {
      if (onlyUntagged) break;
      if (selectedTagIds.isNotEmpty && !selectedTagIds.contains(tag.id)) {
        continue;
      }
      final key = 'tag:${tag.id}';
      // A tag the filter row has not listed yet — made a moment ago, before
      // its counts were read — still gets its shelf, after the known ones.
      tagById.putIfAbsent(tag.id, () => tag);
      if (!defaults.contains(key)) {
        defaults.insert(
          defaults.contains('untagged') ? defaults.length - 1 : defaults.length,
          key,
        );
      }
      (buckets[key] ??= []).add(note);
      placed = true;
    }
    if (!placed && note.tags.isEmpty && selectedTagIds.isEmpty) {
      (buckets['untagged'] ??= []).add(note);
    }
  }

  final trusted = filtering ? null : counts;
  final keys = nexOrderShelfKeys(defaults, order).where((key) {
    final loaded = buckets[key]?.length ?? 0;
    return loaded > 0 || (trusted?[key] ?? 0) > 0;
  }).toList();
  final focused = keys.length <= 1;

  NexShelf shelf(String key) {
    final loaded = buckets[key] ?? const <Note>[];
    final known = trusted?[key];
    final shown = focused || loaded.length <= nexShelfPreview
        ? loaded
        : loaded.sublist(0, nexShelfPreview);
    return NexShelf(
      key: key,
      kind: key == 'untagged'
          ? NexShelfKind.untagged
          : key.startsWith('type:')
          ? NexShelfKind.type
          : NexShelfKind.tag,
      type: key.startsWith('type:')
          ? NoteType.fromWire(key.substring(5))
          : null,
      tag: key.startsWith('tag:') ? tagById[key.substring(4)] : null,
      notes: List.unmodifiable(shown),
      // Never fewer than are loaded: the count is read apart from the notes,
      // and a capture between the two must not make a shelf claim less than
      // it is showing.
      total: known == null || known < loaded.length ? loaded.length : known,
      exact: known != null,
    );
  }

  return [
    if (pinned.isNotEmpty)
      NexShelf(
        key: 'pinned',
        kind: NexShelfKind.pinned,
        notes: List.unmodifiable(pinned),
        total: pinned.length,
        exact: true,
      ),
    for (final key in keys) shelf(key),
  ];
}

/// [defaults] in the reader's [order]: the keys it names first, as it names
/// them, then the rest in their default order.
List<String> nexOrderShelfKeys(List<String> defaults, List<String> order) {
  final present = defaults.toSet();
  return [
    for (final key in order)
      if (present.contains(key)) key,
    for (final key in defaults)
      if (!order.contains(key)) key,
  ];
}

/// The order after moving [key] one place up ([step] -1) or down (+1) among
/// [shown], the movable shelves as they are on screen.
///
/// The whole visible order is written back, so the move means the same thing
/// tomorrow even after a tag that was in between has gone. Keys the reader
/// placed before and that are not on screen now — a tag whose notes are all
/// filtered out — keep their place after the visible ones.
List<String> nexMoveShelf(
  List<String> shown,
  List<String> saved,
  String key,
  int step,
) {
  final next = List.of(shown);
  final from = next.indexOf(key);
  final to = from + step;
  if (from < 0 || to < 0 || to >= next.length) return saved;
  next
    ..removeAt(from)
    ..insert(to, key);
  return [
    ...next,
    for (final old in saved)
      if (!next.contains(old)) old,
  ];
}

/// Whether the timeline may load older notes as the list nears its end.
///
/// Only when a single shelf (pins aside) is on screen: then new notes land
/// at its end, under the finger. With several, older notes would grow the
/// shelves above the one being read and push it down the screen — and each
/// shows only its newest few anyway, with "See all" for the rest.
bool nexShelvesGrow(List<NexShelf> shelves) =>
    shelves.where((shelf) => shelf.kind != NexShelfKind.pinned).length <= 1;
