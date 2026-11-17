import 'dart:io';

import 'package:nex_core/nex_core.dart';
import 'package:nex_data/nex_data.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// 2.8.4: a one-time reminder can take its note to Recently deleted once it
/// is answered. The choice lives beside the reminder's time and goes with it.
void main() {
  late Directory tmp;
  late NexDatabase db;
  late SqliteNoteRepository repo;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('nex_clears_');
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
        content: 'buy stamps',
        createdAt: now,
        updatedAt: now,
        deviceId: 'test-device',
        rev: 1,
        syncState: SyncState.pending,
      ),
    );
  }

  final at = DateTime.utc(2026, 12, 1, 9);

  test('kept with a one-time reminder and read back', () {
    final note = capture();
    repo.setDueAt(note.id, at, clears: true);
    expect(repo.getById(note.id)!.dueClears, isTrue);
  });

  test('a repeating reminder never clears its note', () {
    final note = capture();
    repo.setDueAt(note.id, at, repeat: NoteRepeat.daily, clears: true);
    expect(repo.getById(note.id)!.dueClears, isFalse);
  });

  test('goes with the time: cleared, or replaced by an ordinary reminder', () {
    final note = capture();
    repo.setDueAt(note.id, at, clears: true);
    repo.setDueAt(note.id, null);
    expect(repo.getById(note.id)!.dueClears, isFalse);
    repo.setDueAt(note.id, at, clears: true);
    repo.setDueAt(note.id, at.add(const Duration(days: 1)));
    expect(repo.getById(note.id)!.dueClears, isFalse);
  });

  test('a moved note is not a different reminder: copyWith keeps it', () {
    final note = capture();
    repo.setDueAt(note.id, at, clears: true);
    final read = repo.getById(note.id)!;
    expect(read.copyWith(content: 'x').dueClears, isTrue);
    expect(read.copyWith(dueClears: false).dueClears, isFalse);
  });
}
