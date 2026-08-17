import 'dart:io';

import 'package:nex_data/nex_data.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late NexDatabase db;
  late SqliteNoteRepository repo;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('nex_due_');
    db = NexDatabase.open(p.join(tmp.path, 'nex.sqlite'));
    repo = SqliteNoteRepository(db);
  });

  tearDown(() {
    db.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Note textNote(String id) {
    final now = DateTime.now().toUtc();
    return Note(
      id: id,
      type: NoteType.text,
      content: 'regas the cooler',
      createdAt: now,
      updatedAt: now,
      deviceId: 'test',
      rev: 1,
      syncState: SyncState.pending,
    );
  }

  test('a due date round-trips, and clears', () {
    repo.insert(textNote('n1'));
    final when = DateTime.now().toUtc().add(const Duration(hours: 3));
    repo.setDueAt('n1', when);
    expect(
      repo.getById('n1')!.dueAt!.millisecondsSinceEpoch,
      closeTo(when.millisecondsSinceEpoch, 1000),
    );
    repo.setDueAt('n1', null);
    expect(repo.getById('n1')!.dueAt, isNull);
  });

  test('setting a reminder does not touch the note itself', () {
    // A reminder is something the user asked the app to do, not an edit to
    // what the note says — re-sorting the timeline because someone set an
    // alarm would move a note they were not writing to.
    repo.insert(textNote('n1'));
    final before = repo.getById('n1')!;
    repo.setDueAt('n1', DateTime.now().toUtc().add(const Duration(days: 1)));
    final after = repo.getById('n1')!;
    expect(after.rev, before.rev);
    expect(after.updatedAt, before.updatedAt);
  });

  test('only reminders still ahead are listed, soonest first', () {
    final now = DateTime.now().toUtc();
    for (final (id, offset) in [
      ('past', const Duration(hours: -2)),
      ('soon', Duration(minutes: 30)),
      ('later', const Duration(days: 2)),
      ('none', Duration.zero),
    ]) {
      repo.insert(textNote(id));
      if (id != 'none') repo.setDueAt(id, now.add(offset));
    }
    expect(
      repo.listUpcomingReminders().map((n) => n.id),
      ['soon', 'later'],
      reason: 'a lapsed reminder must not be rescheduled at launch',
    );
  });

  test('a deleted note keeps no reminder to reschedule', () {
    repo.insert(textNote('n1'));
    repo.setDueAt('n1', DateTime.now().toUtc().add(const Duration(days: 1)));
    repo.softDelete('n1');
    expect(repo.listUpcomingReminders(), isEmpty);
  });

  test('a due date survives a backup and restore', () {
    repo.insert(textNote('n1'));
    final when = DateTime.now().toUtc().add(const Duration(days: 1));
    repo.setDueAt('n1', when);
    final mediaDir = p.join(tmp.path, 'media');
    Directory(mediaDir).createSync(recursive: true);
    final backup = repo.backup(p.join(tmp.path, 'backups'), mediaDir: mediaDir);
    db.close();
    File(p.join(tmp.path, 'nex.sqlite')).deleteSync();

    NexBackupArchive.restore(
      liveDbPath: p.join(tmp.path, 'nex.sqlite'),
      mediaDir: mediaDir,
      backupFile: backup.path,
    );
    db = NexDatabase.open(p.join(tmp.path, 'nex.sqlite'));
    repo = SqliteNoteRepository(db);
    expect(repo.listUpcomingReminders().single.id, 'n1');
  });
}
