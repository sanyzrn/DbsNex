import 'dart:io';

import 'package:nex_core/nex_core.dart' show ChecklistItem, formatChecklist;
import 'package:nex_data/nex_data.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The search index's contract: one row per live note, derived the same way
/// everywhere, and repairable when a crash between paired statements strands
/// it. Every failure below shipped at least once.
void main() {
  late Directory tmp;
  late NexDatabase db;
  late SqliteNoteRepository repo;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('nex_fts_');
    db = NexDatabase.open(p.join(tmp.path, 'nex.sqlite'));
    repo = SqliteNoteRepository(db);
  });

  tearDown(() {
    db.close();
    tmp.deleteSync(recursive: true);
  });

  Note insert(Note note) => repo.insert(note);

  Note makeText(String content, {String? title}) {
    final now = DateTime.now().toUtc();
    return Note(
      id: newUuidV7(),
      type: NoteType.text,
      content: content,
      title: title,
      createdAt: now,
      updatedAt: now,
      deviceId: 'test',
      rev: 1,
      syncState: SyncState.pending,
    );
  }

  Note makeChecklist(List<String> items) {
    final now = DateTime.now().toUtc();
    return Note(
      id: newUuidV7(),
      type: NoteType.checklist,
      content: formatChecklist([
        for (final item in items) ChecklistItem(text: item, done: false),
      ]),
      createdAt: now,
      updatedAt: now,
      deviceId: 'test',
      rev: 1,
      syncState: SyncState.pending,
    );
  }

  List<String> searchIds(String query) =>
      repo.search(SearchFilters(query: query)).map((n) => n.id).toList();

  test('editing the body keeps the title in the search row', () {
    final note = insert(makeText('first draft', title: 'Berlin trip'));
    expect(searchIds('berlin'), contains(note.id));

    repo.updateContent(note.id, 'second draft');

    // The content change used to replace the whole FTS row with the raw body,
    // dropping the title: the note stopped answering to its own name.
    expect(searchIds('berlin'), contains(note.id));
    expect(searchIds('second'), contains(note.id));
  });

  test('writing a transcript keeps title and caption findable', () {
    final note = insert(makeText('irrelevant', title: 'Berlin trip'));
    repo.db.execute(
      "UPDATE notes SET type = 'voice', media_uri = '/tmp/a.m4a' WHERE id = ?",
      [note.id],
    );
    repo.setTranscriptText(note.id, 'spoken words about trains');

    expect(searchIds('berlin'), contains(note.id));
    expect(searchIds('trains'), contains(note.id));
  });

  test('restoring a checklist from the trash makes it searchable again', () {
    final note = insert(makeChecklist(['buy oat milk']));
    repo.softDelete(note.id);
    expect(searchIds('oat'), isEmpty, reason: 'deleted is out of search');

    repo.undelete(note.id);

    expect(searchIds('oat'), contains(note.id));
  });

  test('a ticked item stays findable, and the marker is not the token', () {
    final note = insert(makeChecklist(['buy oat milk']));
    repo.toggleChecklistItem(note.id, 0);

    expect(searchIds('oat'), contains(note.id));
    expect(searchIds('[x]'), isEmpty);
  });

  test('repairSearchIndex restores rows lost to a simulated crash', () {
    final a = insert(makeText('alpha has words'));
    final b = insert(makeText('beta has words'));

    // Simulate the failure window: a paired DELETE+INSERT interrupted, and a
    // purge from a build that did not clean FTS.
    repo.db.execute('DELETE FROM notes_fts WHERE note_id = ?', [a.id]);
    repo.db.execute(
      "UPDATE notes SET deleted_at = '2020-01-01T00:00:00.000Z' WHERE id = ?",
      [b.id],
    );
    repo.db.execute(
      "DELETE FROM notes WHERE id = '${newUuidV7()}' AND 0",
    ); // no-op, keeps FKs honest
    final ghost = insert(makeText('ghost words'));
    repo.db.execute('DELETE FROM notes WHERE id = ?', [ghost.id]);

    repo.repairSearchIndex();

    // The lost row is back, derived like a fresh capture.
    expect(searchIds('alpha'), contains(a.id));
    // The note is gone; its index row must not answer searches.
    expect(searchIds('ghost'), isEmpty);
    // And the live-but-trashed note stays out.
    expect(searchIds('beta'), isEmpty);
  });

  test('repairSearchIndex is a no-op on a healthy library', () {
    final note = insert(makeText('healthy words'));
    final before = repo.db.select('SELECT COUNT(*) c FROM notes_fts').first['c'];
    repo.repairSearchIndex();
    final after = repo.db.select('SELECT COUNT(*) c FROM notes_fts').first['c'];
    expect(before, after);
    expect(searchIds('healthy'), contains(note.id));
  });
}
