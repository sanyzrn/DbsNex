import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/nex_widget.dart';
import 'package:nex_core/nex_core.dart';

/// The snapshot is the whole of what the home screen may know. These tests
/// hold the two rules that make that safe: the preview is exactly what a
/// timeline card would have shown, and a locked library's snapshot carries
/// no note content at all — not hidden content, no content.
void main() {
  final now = DateTime.utc(2026, 1, 15, 12);

  Note note(
    String id,
    NoteType type,
    String? content, {
    String? title,
    String? caption,
    String? transcriptText,
    DateTime? updatedAt,
  }) {
    return Note(
      id: id,
      type: type,
      content: content,
      title: title,
      caption: caption,
      transcriptText: transcriptText,
      createdAt: now,
      updatedAt: updatedAt ?? now,
      deviceId: 'test',
      rev: 1,
      syncState: SyncState.pending,
    );
  }

  group('NexWidgetSnapshot.build', () {
    test('carries the preview the timeline card would show', () {
      final snapshot = NexWidgetSnapshot.build(
        appLock: false,
        now: now,
        notes: [
          note('n1', NoteType.text, 'first line\nsecond line'),
          note('n2', NoteType.voice, null, transcriptText: 'spoken words'),
          note('n3', NoteType.text, null, title: 'the title wins'),
        ],
      );

      expect(snapshot.notes.map((n) => n.preview).toList(), [
        'first line second line',
        'spoken words',
        'the title wins',
      ]);
    });

    test('keeps the timeline order it was handed', () {
      final snapshot = NexWidgetSnapshot.build(
        appLock: false,
        now: now,
        notes: [
          note('pinned', NoteType.text, 'pinned first'),
          note('older', NoteType.text, 'then the rest'),
        ],
      );

      expect(snapshot.notes.map((n) => n.id).toList(), ['pinned', 'older']);
    });

    test('cuts a long note and never carries a multi-line preview', () {
      final long = 'word ' * 80;
      final snapshot = NexWidgetSnapshot.build(
        appLock: false,
        now: now,
        notes: [note('n1', NoteType.text, long)],
      );

      expect(snapshot.notes.single.preview.length, lessThan(long.length));
      expect(
        snapshot.notes.single.preview.length,
        NexWidgetSnapshot.maxPreviewLength,
      );
      expect(snapshot.notes.single.preview.contains('\n'), isFalse);
    });

    test('caps how much of the timeline the widget may see', () {
      final many = List.generate(
        NexWidgetSnapshot.maxNotes + 10,
        (i) => note('n$i', NoteType.text, 'note $i'),
      );
      final snapshot = NexWidgetSnapshot.build(appLock: false, now: now, notes: many);

      expect(snapshot.notes, hasLength(NexWidgetSnapshot.maxNotes));
    });

    test('a locked library produces a snapshot with no note content at all', () {
      final snapshot = NexWidgetSnapshot.build(
        appLock: true,
        now: now,
        notes: [
          note('n1', NoteType.text, 'something private'),
          note('n2', NoteType.photo, null, caption: 'a caption nobody may see'),
        ],
      );

      expect(snapshot.appLock, isTrue);
      expect(snapshot.notes, isEmpty);
      // The rule is about the file, not the widget: nothing here that a
      // reader could dig out, because nothing was written in.
    });

    test('an empty library still produces a usable snapshot', () {
      final snapshot = NexWidgetSnapshot.build(appLock: false, now: now, notes: const []);

      expect(snapshot.appLock, isFalse);
      expect(snapshot.notes, isEmpty);
    });

    test('round-trips through JSON with the fields the Android reader reads', () {
      final snapshot = NexWidgetSnapshot.build(
        appLock: false,
        now: now,
        notes: [note('n1', NoteType.checklist, '- [x] one\n- [ ] two')],
      );

      final json = snapshot.toJson();
      expect(json['version'], NexWidgetSnapshot.version);
      expect(json['appLock'], isFalse);
      final notes = (json['notes'] as List).single as Map<String, Object?>;
      // The row's display text is the checklist's items on one line — what
      // the card shows — never the raw markdown.
      expect(notes['preview'], 'one · two');
      expect(notes['type'], 'checklist');
      expect(notes['id'], 'n1');
      expect(notes['updatedAt'], now.millisecondsSinceEpoch);
    });
  });

  group('NexWidgetSnapshot.filter', () {
    final mixed = [
      note('a', NoteType.text, 'a thought'),
      note('b', NoteType.photo, null, caption: 'the receipt'),
      note('c', NoteType.checklist, '- [ ] milk'),
      note('d', NoteType.text, 'another thought'),
    ];

    test('no kinds chosen means no filter, not an empty widget', () {
      // The encoding this rests on: "none selected" cannot sensibly mean
      // "show nothing", because a permanently empty widget is not a thing
      // anyone would choose.
      expect(NexWidgetSnapshot.filter(mixed, const {}), mixed);
    });

    test('keeps only the kinds asked for, in the order they arrived', () {
      final photos = NexWidgetSnapshot.filter(mixed, const {'photo'});
      expect(photos.map((n) => n.id), ['b']);

      final both = NexWidgetSnapshot.filter(mixed, const {'text', 'checklist'});
      expect(
        both.map((n) => n.id),
        ['a', 'c', 'd'],
        reason: 'the widget shows the timeline, not a re-sorted copy of it',
      );
    });

    test('a kind the library has none of gives an empty widget, not a crash', () {
      expect(NexWidgetSnapshot.filter(mixed, const {'voice'}), isEmpty);
    });
  });

  group('NexWidgetSnapshot.byRecency', () {
    test('lets the pins go, newest first', () {
      // The list arrives in the timeline's order — pinned first, whatever
      // their dates — and comes back in the order the dates alone give.
      final pinnedButOld = note(
        'pinned',
        NoteType.text,
        'old',
        updatedAt: now.subtract(const Duration(days: 30)),
      );
      final middle = note(
        'middle',
        NoteType.text,
        'middle',
        updatedAt: now.subtract(const Duration(days: 2)),
      );
      final newest = note('newest', NoteType.text, 'new', updatedAt: now);

      expect(
        NexWidgetSnapshot.byRecency([
          pinnedButOld,
          newest,
          middle,
        ]).map((n) => n.id),
        ['newest', 'middle', 'pinned'],
      );
    });

    test('leaves the list it was given alone', () {
      // The caller's list is the timeline's own, and sorting it in place
      // would reorder whatever else is reading it.
      final given = [
        note('a', NoteType.text, 'a', updatedAt: now),
        note(
          'b',
          NoteType.text,
          'b',
          updatedAt: now.add(const Duration(days: 1)),
        ),
      ];
      NexWidgetSnapshot.byRecency(given);

      expect(given.map((n) => n.id), ['a', 'b']);
    });
  });

  group('NexWidgetSnapshot.hidesNotes', () {
    bool hides({
      bool lockEnabled = true,
      bool showWhenLocked = false,
      bool lockClosed = true,
    }) => NexWidgetSnapshot.hidesNotes(
      lockEnabled: lockEnabled,
      showWhenLocked: showWhenLocked,
      lockClosed: lockClosed,
    );

    test('no lock means nothing to hide from', () {
      expect(hides(lockEnabled: false), isFalse);
      expect(
        hides(lockEnabled: false, lockClosed: false),
        isFalse,
        reason: 'a library with no lock is never a locked one',
      );
    });

    test('an open lock shows the notes', () {
      // The bug this is here for: "lock after an hour" emptied the widget the
      // moment the lock was switched on, and kept it empty for the hour the
      // library was open. Someone who has not been away has not locked
      // anything.
      expect(hides(lockClosed: false), isFalse);
    });

    test('a closed lock takes the notes off the home screen', () {
      expect(hides(), isTrue);
    });

    test('unless the user said to leave them there', () {
      expect(hides(showWhenLocked: true), isFalse);
    });
  });
}
