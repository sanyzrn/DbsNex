import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/timeline_shelves.dart';
import 'package:nex_core/nex_core.dart';

/// The home arranged by kind or tag (2.7.0): which shelves there are, in
/// what order, how much each shows and what it says it holds.
void main() {
  final day = DateTime.utc(2026, 11, 1);
  var serial = 0;
  final work = Tag(id: 'w', name: 'work', createdAt: day);
  final home = Tag(id: 'h', name: 'home', createdAt: day);

  Note note(NoteType type, {List<Tag> tags = const [], bool pinned = false}) {
    serial++;
    return Note(
      id: 'n$serial',
      type: type,
      content: 'note $serial',
      createdAt: day,
      updatedAt: day.subtract(Duration(minutes: serial)),
      deviceId: 'test',
      rev: 1,
      syncState: SyncState.pending,
      tags: tags,
      pinnedAt: pinned ? day : null,
    );
  }

  List<String> keys(List<NexShelf> shelves) => [
    for (final shelf in shelves) shelf.key,
  ];

  group('by kind', () {
    test('pins first, then the kinds in their order, empty kinds left out', () {
      final notes = [
        note(NoteType.text, pinned: true),
        note(NoteType.photo),
        note(NoteType.text),
        note(NoteType.photo),
      ];
      final shelves = nexArrangeShelves(notes, by: NexTimelineArrangement.type);
      expect(keys(shelves), ['pinned', 'type:text', 'type:photo']);
      expect(shelves[2].notes.map((n) => n.id), ['n2', 'n4']);
      // A pinned note is on the pins' shelf only, not on its kind's too.
      expect(shelves[1].notes.map((n) => n.id), ['n3']);
    });

    test('a shelf shows its newest six of more, and counts them all', () {
      final notes = [
        for (var i = 0; i < 9; i++) note(NoteType.text),
        note(NoteType.link),
      ];
      final shelves = nexArrangeShelves(
        notes,
        by: NexTimelineArrangement.type,
        counts: {'type:text': 40, 'type:link': 1},
      );
      final text = shelves.first;
      expect(text.notes, hasLength(nexShelfPreview));
      expect(text.notes.first.id, notes.first.id, reason: 'newest first');
      expect(text.total, 40);
      expect(text.exact, isTrue);
      expect(text.more, isTrue);
      expect(shelves.last.more, isFalse);
      expect(nexShelvesGrow(shelves), isFalse);
    });

    test('a kind not loaded yet still has its shelf, from the count', () {
      final shelves = nexArrangeShelves(
        [note(NoteType.text)],
        by: NexTimelineArrangement.type,
        counts: {'type:text': 1, 'type:file': 3},
      );
      expect(keys(shelves), ['type:text', 'type:file']);
      expect(shelves.last.notes, isEmpty);
      expect(shelves.last.total, 3);
      expect(shelves.last.more, isTrue);
    });

    test('one shelf is the list: everything loaded, and it grows', () {
      final notes = [for (var i = 0; i < 12; i++) note(NoteType.photo)];
      final shelves = nexArrangeShelves(
        notes,
        by: NexTimelineArrangement.type,
        filtering: true,
      );
      expect(shelves.single.notes, hasLength(12));
      expect(nexShelvesGrow(shelves), isTrue);
    });

    test('while filtering, the library counts are not trusted', () {
      final notes = [
        for (var i = 0; i < 8; i++) note(NoteType.text),
        note(NoteType.photo),
      ];
      final shelves = nexArrangeShelves(
        notes,
        by: NexTimelineArrangement.type,
        counts: {'type:text': 99, 'type:photo': 50, 'type:file': 4},
        filtering: true,
      );
      expect(keys(shelves), ['type:text', 'type:photo']);
      expect(shelves.first.total, 8);
      expect(shelves.first.exact, isFalse);
      expect(shelves.last.more, isFalse);
    });

    test('a count read before a capture never claims less than is shown', () {
      final shelves = nexArrangeShelves(
        [note(NoteType.text), note(NoteType.text), note(NoteType.voice)],
        by: NexTimelineArrangement.type,
        counts: {'type:text': 1, 'type:voice': 1},
      );
      expect(shelves.first.total, 2);
      expect(shelves.first.more, isFalse);
    });
  });

  group('by tag', () {
    test('a note with two tags is on both shelves; untagged comes last', () {
      final both = note(NoteType.text, tags: [work, home]);
      final bare = note(NoteType.text);
      final shelves = nexArrangeShelves(
        [both, bare],
        by: NexTimelineArrangement.tag,
        tags: [home, work],
      );
      expect(keys(shelves), ['tag:h', 'tag:w', 'untagged']);
      expect(shelves[0].notes.single.id, both.id);
      expect(shelves[1].notes.single.id, both.id);
      expect(shelves[2].notes.single.id, bare.id);
      expect(shelves[0].tag, home);
    });

    test('a tag filter shows the chosen tags only, without untagged', () {
      final shelves = nexArrangeShelves(
        [
          note(NoteType.text, tags: [work, home]),
        ],
        by: NexTimelineArrangement.tag,
        tags: [work, home],
        selectedTagIds: {'w'},
        filtering: true,
      );
      expect(keys(shelves), ['tag:w']);
    });

    test('only untagged: the one shelf', () {
      final shelves = nexArrangeShelves(
        [note(NoteType.text)],
        by: NexTimelineArrangement.tag,
        tags: [work],
        onlyUntagged: true,
        filtering: true,
      );
      expect(keys(shelves), ['untagged']);
    });

    test('a tag the filter row has not listed yet still gets a shelf', () {
      final fresh = Tag(id: 'f', name: 'fresh', createdAt: day);
      final shelves = nexArrangeShelves(
        [
          note(NoteType.text, tags: [fresh]),
          note(NoteType.text),
        ],
        by: NexTimelineArrangement.tag,
        tags: [work],
      );
      expect(keys(shelves), ['tag:f', 'untagged']);
    });
  });

  group('the reader\'s order', () {
    test('named keys first, the rest in their default order', () {
      expect(
        nexOrderShelfKeys(
          ['type:text', 'type:voice', 'type:photo'],
          ['type:photo', 'type:gone'],
        ),
        ['type:photo', 'type:text', 'type:voice'],
      );
    });

    test('a move is one step and keeps keys that are not on screen', () {
      final next = nexMoveShelf(
        ['type:text', 'type:photo', 'type:link'],
        ['type:file'],
        'type:photo',
        -1,
      );
      expect(next, ['type:photo', 'type:text', 'type:link', 'type:file']);
      expect(nexMoveShelf(['a', 'b'], ['x'], 'a', -1), [
        'x',
      ], reason: 'the first cannot move up: nothing changes');
    });

    test('the order shapes the shelves, pins aside', () {
      final shelves = nexArrangeShelves(
        [
          note(NoteType.text, pinned: true),
          note(NoteType.text),
          note(NoteType.link),
        ],
        by: NexTimelineArrangement.type,
        order: ['type:link'],
      );
      expect(keys(shelves), ['pinned', 'type:link', 'type:text']);
    });
  });

  test('an unknown stored arrangement reads as time', () {
    expect(
      NexTimelineArrangement.fromWire('shelves'),
      NexTimelineArrangement.time,
    );
    expect(NexTimelineArrangement.fromWire(null), NexTimelineArrangement.time);
    expect(NexTimelineArrangement.fromWire('tag'), NexTimelineArrangement.tag);
  });
}
