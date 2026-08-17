import 'dart:io';

import 'package:nex_core/nex_core.dart';
import 'package:nex_data/nex_data.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

/// The storage side of checklists, links and titles.
///
/// Checklists and links deliberately have no tables of their own: a checklist
/// keeps its items in the note's `content` as markdown task lines, and a link
/// keeps its URL there. What that buys is everything below — search, revision
/// bumps and the outbox all work on them without knowing they exist.
void main() {
  late NexDatabase db;
  late SqliteNoteRepository repo;

  Note capture(NoteType type, String content) => repo.insert(
    Note(
      id: 'n-${DateTime.now().microsecondsSinceEpoch}-${type.name}',
      type: type,
      content: content,
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
      deviceId: 'test',
      rev: 1,
      syncState: SyncState.pending,
    ),
  );

  setUp(() {
    db = NexDatabase.openInMemory();
    repo = SqliteNoteRepository(db);
  });

  tearDown(() => db.close());

  test('a checklist stores and reloads its items', () {
    final note = capture(NoteType.checklist, '- [ ] milk\n- [ ] bread');

    expect(repo.getById(note.id)!.checklistItems, [
      const ChecklistItem(text: 'milk', done: false),
      const ChecklistItem(text: 'bread', done: false),
    ]);
  });

  test('ticking an item bumps the revision and re-queues the note', () {
    final note = capture(NoteType.checklist, '- [ ] milk\n- [ ] bread');
    // Land it as synced first, so "went back to pending" means something.
    repo.markSynced(note.id);
    expect(repo.getById(note.id)!.syncState, SyncState.synced);

    repo.toggleChecklistItem(note.id, 1);

    final after = repo.getById(note.id)!;
    expect(after.checklistItems.map((i) => i.done), [false, true]);
    expect(after.rev, greaterThan(note.rev));
    // A checklist rides the same outbox as any other edit, because ticking a
    // box *is* an edit to the note's content.
    expect(after.syncState, SyncState.pending);
  });

  test('toggling an index that is no longer there does nothing', () {
    final note = capture(NoteType.checklist, '- [ ] only one');

    repo.toggleChecklistItem(note.id, 7);
    repo.toggleChecklistItem(note.id, -1);

    expect(repo.getById(note.id)!.checklistItems, hasLength(1));
    expect(repo.getById(note.id)!.checklistItems.single.done, isFalse);
  });

  test('only a checklist can be toggled', () {
    final note = capture(NoteType.text, '- [ ] this is prose');
    repo.toggleChecklistItem(note.id, 0);

    expect(repo.getById(note.id)!.content, '- [ ] this is prose');
  });

  test('a checklist is searchable by its items, without the markers', () {
    capture(NoteType.checklist, '- [x] sourdough\n- [ ] olives');

    expect(repo.search(const SearchFilters(query: 'sourdough')), hasLength(1));
    expect(repo.search(const SearchFilters(query: 'olives')), hasLength(1));
  });

  test('a title is searchable, clears when emptied, and outranks the body', () {
    final note = capture(NoteType.text, 'call the landlord about the leak');

    repo.setTitle(note.id, '  Rent  ');
    expect(repo.getById(note.id)!.title, 'Rent');
    expect(repo.getById(note.id)!.displayText, 'Rent');
    expect(repo.search(const SearchFilters(query: 'Rent')), hasLength(1));
    // Naming a note must not hide what is inside it.
    expect(repo.search(const SearchFilters(query: 'landlord')), hasLength(1));

    repo.setTitle(note.id, '   ');
    expect(repo.getById(note.id)!.title, isNull);
    expect(repo.getById(note.id)!.displayText, contains('landlord'));
  });

  test('link metadata is written once and never erased by a later failure', () {
    final note = capture(NoteType.link, 'https://example.com/article');

    repo.setLinkMetadata(
      note.id,
      title: 'An Article',
      excerpt: 'What the article is about',
    );
    expect(repo.getById(note.id)!.title, 'An Article');
    expect(repo.getById(note.id)!.linkExcerpt, 'What the article is about');
    expect(
      repo.search(const SearchFilters(query: 'example.com')),
      hasLength(1),
    );

    // A later fetch that only got half an answer leaves the other half alone:
    // a page that stops responding should not erase what was read from it.
    repo.setLinkMetadata(note.id, excerpt: 'A better description');
    expect(repo.getById(note.id)!.title, 'An Article');
    expect(repo.getById(note.id)!.linkExcerpt, 'A better description');

    // And a fetch that got nothing at all is not a write.
    final before = repo.getById(note.id)!.rev;
    repo.setLinkMetadata(note.id);
    expect(repo.getById(note.id)!.rev, before);
  });

  test('a database from before these types can still store one', () {
    // v1's schema pinned `CHECK (type IN ('text','voice','photo','file'))`, and
    // SQLite cannot drop a constraint in place — so without the rebuild in
    // _dropLegacyTypeCheck, every existing install would reject a checklist no
    // matter what the Dart side believed. This builds that old table by hand
    // and re-opens it through the migration.
    final file = File(
      '${Directory.systemTemp.createTempSync('nex_legacy_').path}/legacy.sqlite',
    );
    final legacy = sqlite3.open(file.path);
    legacy.execute('''
CREATE TABLE notes (
  id TEXT PRIMARY KEY NOT NULL,
  type TEXT NOT NULL CHECK (type IN ('text', 'voice', 'photo', 'file')),
  content TEXT,
  media_uri TEXT,
  media_hash TEXT,
  duration_ms INTEGER,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT,
  device_id TEXT NOT NULL,
  rev INTEGER NOT NULL,
  sync_state TEXT NOT NULL CHECK (sync_state IN ('pending', 'synced', 'conflict'))
);
''');
    legacy.execute(
      "INSERT INTO notes VALUES ('old', 'text', 'a note from before', NULL, "
      "NULL, NULL, '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z', "
      "NULL, 'test', 1, 'synced')",
    );
    legacy.dispose();

    final upgraded = NexDatabase.open(file.path);
    addTearDown(() {
      upgraded.close();
      file.parent.deleteSync(recursive: true);
    });
    final upgradedRepo = SqliteNoteRepository(upgraded);

    // The note that was already there came through the rebuild intact.
    expect(upgradedRepo.getById('old')!.content, 'a note from before');

    final list = upgradedRepo.insert(
      Note(
        id: 'new-checklist',
        type: NoteType.checklist,
        content: '- [ ] this would have failed the old CHECK',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        deviceId: 'test',
        rev: 1,
        syncState: SyncState.pending,
      ),
    );
    expect(list.checklistItems, hasLength(1));

    // And it is not done twice: re-opening the same file is a no-op now.
    upgraded.close();
    final reopened = NexDatabase.open(file.path);
    expect(SqliteNoteRepository(reopened).getById('new-checklist'), isNotNull);
    reopened.close();
  });
}
