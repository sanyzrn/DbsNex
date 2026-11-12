import 'package:nex_data/nex_data.dart';
import 'package:test/test.dart';

/// "On this day" for the daily nudge: what the snapshot offers it.
void main() {
  late NexDatabase db;
  late SqliteNoteRepository repo;

  setUp(() {
    db = NexDatabase.openInMemory();
    repo = SqliteNoteRepository(db, localDeviceId: 'memories');
  });

  tearDown(() => db.close());

  var serial = 0;
  String write(
    DateTime createdLocal, {
    String type = 'text',
    String? content = 'a line worth keeping',
    String? caption,
    bool deleted = false,
    bool setAside = false,
  }) {
    final id = 'note-${serial++}';
    final at = createdLocal.toUtc().toIso8601String();
    db.db.execute(
      'INSERT INTO notes (id, type, content, caption, created_at, updated_at, '
      'deleted_at, set_aside_at, device_id, rev, sync_state) '
      "VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'memories', 1, 'pending')",
      [
        id,
        type,
        content,
        caption,
        at,
        at,
        deleted ? at : null,
        setAside ? at : null,
      ],
    );
    return id;
  }

  List<String> memories() => [
    for (final note in repo.nudgeSnapshot(const []).memories) note.id,
  ];

  test('a note from this day in an earlier year is offered', () {
    final now = DateTime.now();
    final lastYear = write(DateTime(now.year - 1, now.month, now.day, 12));
    final threeYears = write(DateTime(now.year - 3, now.month, now.day, 8));
    expect(memories(), containsAll([lastYear, threeYears]));
  });

  test('this year, another season and too long ago are not', () {
    final now = DateTime.now();
    write(DateTime(now.year, now.month, now.day, 0, 1));
    write(DateTime(now.year - 1, now.month, now.day + 60, 12));
    write(DateTime(now.year - 1, now.month, now.day - 60, 12));
    write(
      DateTime(
        now.year - SqliteNoteRepository.nudgeMemoryYears - 1,
        now.month,
        now.day,
        12,
      ),
    );
    expect(memories(), isEmpty);
  });

  test('the window reaches a fortnight ahead and two days behind', () {
    final now = DateTime.now();
    final ahead = write(
      DateTime(
        now.year - 1,
        now.month,
        now.day + SqliteNoteRepository.nudgeMemoryDaysAhead,
        23,
        59,
      ),
    );
    final behind = write(
      DateTime(
        now.year - 1,
        now.month,
        now.day - SqliteNoteRepository.nudgeMemoryDaysBehind,
        0,
        1,
      ),
    );
    write(
      DateTime(
        now.year - 1,
        now.month,
        now.day + SqliteNoteRepository.nudgeMemoryDaysAhead + 1,
        0,
        1,
      ),
    );
    expect(memories(), unorderedEquals([ahead, behind]));
  });

  test('only live notes with words of their own', () {
    final now = DateTime.now();
    final day = DateTime(now.year - 2, now.month, now.day, 10);
    write(day, deleted: true);
    write(day, setAside: true);
    write(day, type: 'photo', content: null);
    write(day, type: 'checklist', content: '[{"text":"milk","done":false}]');
    write(day, type: 'link', content: 'https://example.com');
    write(day, content: '   ');
    final captioned = write(
      day,
      type: 'photo',
      content: null,
      caption: 'the garden in spring',
    );
    expect(memories(), [captioned]);
  });

  test('a busy day offers its two longest notes, not all of them', () {
    final now = DateTime.now();
    final day = DateTime(now.year - 1, now.month, now.day, 9);
    for (var i = 0; i < 30; i++) {
      write(day.add(Duration(minutes: i)), content: 'short $i');
    }
    final long = write(day, content: 'x' * 400);
    final longer = write(day, content: 'y' * 500);
    expect(memories(), [longer, long]);
  });

  test('each day is a narrow read of the creation index', () {
    final plan = db.db
        .select('EXPLAIN QUERY PLAN ${SqliteNoteRepository.nudgeMemoriesSql}', [
          '2024-01-01T00:00:00.000Z',
          '2024-01-02T00:00:00.000Z',
        ])
        .map((row) => row['detail'] as String)
        .join('\n');
    expect(plan, contains('idx_notes_created_at'));
    expect(plan, contains('created_at>? AND created_at<?'));
  });

  test('memories are notes, with everything a note carries', () {
    final now = DateTime.now();
    write(DateTime(now.year - 1, now.month, now.day, 12), content: 'kept');
    final note = repo.nudgeSnapshot(const []).memories.single;
    expect(note.type, NoteType.text);
    expect(note.content, 'kept');
  });
}
