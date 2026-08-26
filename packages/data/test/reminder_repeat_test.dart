import 'dart:io';

import 'package:nex_core/nex_core.dart';
import 'package:nex_data/nex_data.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A reminder that could only ever fire once could not say "the bins, every
/// Tuesday" — which is most of what people set reminders for. The shortcut
/// list offered four one-off times and nothing else.
void main() {
  late Directory tmp;
  late NexDatabase db;
  late SqliteNoteRepository repo;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('nex_repeat_');
    db = NexDatabase.open(p.join(tmp.path, 'nex.sqlite'));
    repo = SqliteNoteRepository(db);
  });

  tearDown(() {
    db.close();
    tmp.deleteSync(recursive: true);
  });

  Note capture() {
    final now = DateTime.now().toUtc();
    return repo.insert(
      Note(
        id: newUuidV7(),
        type: NoteType.text,
        content: 'call the plumber',
        createdAt: now,
        updatedAt: now,
        deviceId: 'test-device',
        rev: 1,
        syncState: SyncState.pending,
      ),
    );
  }

  test('a repeat is stored with its reminder and read back', () {
    final note = capture();
    final at = DateTime.utc(2026, 9, 1, 9);
    repo.setDueAt(note.id, at, repeat: NoteRepeat.weekly);

    final reloaded = repo.getById(note.id)!;
    expect(reloaded.dueAt, at);
    expect(reloaded.dueRepeat, NoteRepeat.weekly);
  });

  test('clearing the reminder clears the repeat with it', () {
    final note = capture();
    repo.setDueAt(
      note.id,
      DateTime.utc(2026, 9, 1, 9),
      repeat: NoteRepeat.daily,
    );
    repo.setDueAt(note.id, null);

    // A repeat left behind on a note with no reminder is a rule with nothing
    // to apply to — and it would come back the next time one was set.
    final reloaded = repo.getById(note.id)!;
    expect(reloaded.dueAt, isNull);
    expect(reloaded.dueRepeat, NoteRepeat.once);
  });

  test('a due date written before this version reads as a one-off', () {
    final note = capture();
    // Exactly what an upgraded database holds: a due date from an older
    // build, with the new column still null.
    db.db.execute(
      'UPDATE notes SET due_at = ?, due_repeat = NULL WHERE id = ?',
      [DateTime.utc(2026, 9, 1, 9).toIso8601String(), note.id],
    );

    expect(repo.getById(note.id)!.dueRepeat, NoteRepeat.once);
  });

  test('an unknown repeat from a newer build still gives a reminder', () {
    // Forwards, not just backwards: a value this build has never heard of has
    // to degrade to a reminder that fires once, not to a note that fails to
    // parse and vanishes from the timeline.
    expect(NoteRepeat.fromWire('every-third-tuesday'), NoteRepeat.once);
  });
}
