import 'package:nex_core/nex_core.dart';
import 'package:test/test.dart';

/// `nexSameNote` is what lets a screen that just re-read the database stay
/// quiet when the answer has not moved — a re-read always makes fresh
/// objects, so identity is useless and the fields have to speak. The
/// timeline's own comparator is private to its model; this is the shared
/// copy the collection pages use, and it must not miss a field a card or a
/// collection row can draw — above all the AI-derived ones, which the
/// database does not always announce with `rev` or `updatedAt`.
void main() {
  // The same row, read twice: every field equal, nothing shared.
  Note note({
    String? content = 'the words',
    String? summary,
    String? transcript,
    String? ocr,
    bool urgent = false,
    DateTime? pinnedAt,
    DateTime? dueAt,
    List<Tag> tags = const [],
    int rev = 3,
    DateTime? deletedAt,
    int attachmentCount = 0,
  }) => Note(
    id: 'n1',
    type: NoteType.text,
    content: content,
    summaryText: summary,
    transcriptText: transcript,
    ocrText: ocr,
    isUrgent: urgent,
    pinnedAt: pinnedAt,
    dueAt: dueAt,
    tags: tags,
    rev: rev,
    deletedAt: deletedAt,
    attachmentCount: attachmentCount,
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 2),
    deviceId: 'd1',
    syncState: SyncState.synced,
  );

  test('identical instances are the same without any field read', () {
    final a = note();
    expect(nexSameNote(a, a), isTrue);
    expect(nexSameNotes([a], [a]), isTrue);
  });

  test('a re-read with equal fields is the same note', () {
    expect(nexSameNote(note(), note()), isTrue);
  });

  test('an AI summary that arrived without bumping rev is a change', () {
    expect(nexSameNote(note(), note(summary: 'now summarized')), isFalse);
  });

  test('transcript and OCR are each their own change', () {
    expect(nexSameNote(note(), note(transcript: 'spoken')), isFalse);
    expect(nexSameNote(note(), note(ocr: 'read off')), isFalse);
  });

  test('local-only metadata is a change: urgent, pin, reminder, delete', () {
    expect(nexSameNote(note(), note(urgent: true)), isFalse);
    expect(
      nexSameNote(note(), note(pinnedAt: DateTime.utc(2026, 2, 1))),
      isFalse,
    );
    expect(
      nexSameNote(note(), note(dueAt: DateTime.utc(2026, 3, 1))),
      isFalse,
    );
    expect(
      nexSameNote(note(), note(deletedAt: DateTime.utc(2026, 2, 2))),
      isFalse,
    );
  });

  test('a moved row is a change: rev, content, attachments', () {
    expect(nexSameNote(note(), note(rev: 4)), isFalse);
    expect(nexSameNote(note(), note(content: 'edited')), isFalse);
    expect(nexSameNote(note(), note(attachmentCount: 2)), isFalse);
  });

  test('tags are compared by what a pill draws: id, name, colour', () {
    final tag = Tag(
      id: 't1',
      name: 'work',
      createdAt: DateTime.utc(2026),
    );
    expect(nexSameNote(note(tags: [tag]), note(tags: [tag])), isTrue);
    expect(
      nexSameNote(
        note(tags: [tag]),
        note(
          tags: [
            Tag(id: 't1', name: 'home', createdAt: DateTime.utc(2026)),
          ],
        ),
      ),
      isFalse,
    );
    expect(nexSameNote(note(tags: [tag]), note(tags: const [])), isFalse);
  });

  test('sync state alone is not a change', () {
    final changed = Note(
      id: 'n1',
      type: NoteType.text,
      content: 'the words',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 2),
      deviceId: 'd1',
      rev: 3,
      syncState: SyncState.pending,
    );
    expect(nexSameNote(note(), changed), isTrue);
  });

  test('lists: length, order and content each decide', () {
    final a = note();
    final b = note();
    expect(nexSameNotes([a], [b]), isTrue);
    expect(nexSameNotes([a], [b, b]), isFalse);
    final distinct = note(content: 'different');
    expect(
      nexSameNotes([a, distinct], [distinct, a]),
      isFalse,
      reason: 'order is what the list shows',
    );
    expect(nexSameNotes([a], []), isFalse);
  });
}
