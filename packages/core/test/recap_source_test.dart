import 'package:nex_core/nex_core.dart';
import 'package:test/test.dart';

/// The recap used to be handed the plain text of the twenty newest notes.
/// What is tested here is the two things that changed: that it is now told
/// facts a reminder can be built out of, and that the twenty it picks are
/// chosen rather than merely recent.
void main() {
  final now = DateTime.utc(2026, 7, 28, 9);

  Note note({
    required String id,
    String? content,
    NoteType type = NoteType.text,
    Duration age = Duration.zero,
    Duration? due,
    DateTime? deletedAt,
  }) {
    final written = now.subtract(age);
    return Note(
      id: id,
      type: type,
      content: content,
      createdAt: written,
      updatedAt: written,
      deletedAt: deletedAt,
      deviceId: 'test',
      rev: 1,
      syncState: SyncState.pending,
      dueAt: due == null ? null : now.add(due),
    );
  }

  List<String> linesOf(List<Note> notes, {int limit = 20}) =>
      nexRecapSource(notes, now: now, limit: limit)
          .split('\n')
          .where((line) => line.isNotEmpty)
          .toList();

  test('a note that is due is first, however old it is', () {
    // The case the old source could not represent at all. A reminder set last
    // month for tomorrow morning is the single most worth mentioning thing in
    // a library, and "the twenty newest notes" would never have included it.
    final notes = [
      for (var i = 0; i < 25; i++)
        note(id: 'recent$i', content: 'something $i', age: Duration(hours: i)),
      note(
        id: 'appointment',
        content: 'pick up the prescription',
        age: const Duration(days: 40),
        due: const Duration(hours: 6),
      ),
    ];

    final lines = linesOf(notes);
    expect(lines.first, 'DUE in 6h | text | pick up the prescription');
  });

  test('overdue comes before merely due, and both before the rest', () {
    final lines = linesOf([
      note(id: 'later', content: 'water the plants', due: const Duration(days: 3)),
      note(id: 'fresh', content: 'written this morning'),
      note(
        id: 'missed',
        content: 'call the plumber back',
        due: const Duration(days: -2),
      ),
    ]);

    expect(lines[0], 'DUE overdue 2d | text | call the plumber back');
    expect(lines[1], 'DUE in 3d | text | water the plants');
    expect(lines[2], 'today | text | written this morning');
  });

  test('a reminder far enough out is not something waiting', () {
    // Past the horizon it is a note with a date on it. Somebody opening the
    // app this morning does not need told about something due in three
    // months, and putting it at the top would push out what is.
    final lines = linesOf([
      note(
        id: 'someday',
        content: 'renew the passport',
        age: const Duration(days: 3),
        due: const Duration(days: 90),
      ),
      note(id: 'today', content: 'the boiler man is coming'),
    ]);

    // Described by when it was written, and not marked DUE at all — the
    // prompt tells the model every DUE line comes first, so a DUE line that
    // is not first would be the source contradicting its own instructions.
    expect(lines.first, 'today | text | the boiler man is coming');
    expect(lines[1], '3d ago | text | renew the passport');
  });

  test('an unfinished checklist says how much of it is left', () {
    // The one fact about a checklist that says whether it is finished
    // business, and the reason it outranks a plain note written later.
    final lines = linesOf([
      note(id: 'newer', content: 'a thought', age: const Duration(hours: 1)),
      note(
        id: 'shopping',
        type: NoteType.checklist,
        content: '- [x] milk\n- [ ] bread\n- [ ] call the plumber',
        age: const Duration(days: 2),
      ),
    ]);

    expect(lines.first, '2d ago | checklist 2/3 left | milk · bread · call the plumber');
    expect(lines[1], 'today | text | a thought');
  });

  test('a finished checklist is not unfinished business', () {
    final lines = linesOf([
      note(id: 'newer', content: 'a thought', age: const Duration(hours: 1)),
      note(
        id: 'done',
        type: NoteType.checklist,
        content: '- [x] milk\n- [x] bread',
        age: const Duration(days: 2),
      ),
    ]);

    expect(lines.first, 'today | text | a thought');
    expect(lines[1], '2d ago | checklist done | milk · bread');
  });

  test('a deleted note is not part of anything', () {
    final lines = linesOf([
      note(
        id: 'gone',
        content: 'thrown away',
        due: const Duration(hours: 2),
        deletedAt: now,
      ),
      note(id: 'kept', content: 'still here'),
    ]);

    expect(lines, ['today | text | still here']);
  });

  test('the source is bounded, in lines and in each line', () {
    // Every character here is a token spent on every recap, on a provider the
    // user is paying for. A long note would otherwise take the budget the
    // other nineteen were meant to share.
    final long = 'a' * 500;
    final lines = linesOf([
      note(id: 'long', content: long),
      for (var i = 0; i < 40; i++)
        note(id: 'n$i', content: 'note $i', age: Duration(hours: i + 1)),
    ], limit: 20);

    expect(lines, hasLength(20));
    expect(lines.first.length, lessThan(200));
    expect(lines.first, endsWith('…'));
  });

  test('a note with nothing readable in it is left out', () {
    // A photo with no caption and no OCR yet has no line to contribute, and
    // an empty one would read to the model as a note about nothing.
    final lines = linesOf([
      note(id: 'blank', type: NoteType.photo),
      note(id: 'said', content: 'something'),
    ]);

    expect(lines, ['today | text | something']);
  });
}
