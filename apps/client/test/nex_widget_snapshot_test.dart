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
}
