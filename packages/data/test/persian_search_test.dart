import 'dart:io';

import 'package:nex_data/nex_data.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

/// Persian search finds a word however it was spelled (LOC-01, LOC-06):
/// Arabic yeh and kaf, harakat, tatweel, with or without a ZWNJ, and in any
/// of the three digit sets.
void main() {
  late Directory tmp;
  late String path;
  late NexDatabase db;
  late SqliteNoteRepository repo;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('nex_fold_');
    path = p.join(tmp.path, 'nex.sqlite');
    db = NexDatabase.open(path);
    repo = SqliteNoteRepository(db);
  });

  tearDown(() {
    db.close();
    tmp.deleteSync(recursive: true);
  });

  Note text(String content) {
    final now = DateTime.now().toUtc();
    return Note(
      id: newUuidV7(),
      type: NoteType.text,
      content: content,
      createdAt: now,
      updatedAt: now,
      deviceId: 'test-device',
      rev: 1,
      syncState: SyncState.pending,
    );
  }

  List<String?> find(String query) => [
    for (final note in repo.search(SearchFilters(query: query))) note.content,
  ];

  test('a Persian query finds Arabic-script spellings', () {
    repo.insert(text('كتاب قديمي'));
    expect(find('کتاب'), ['كتاب قديمي']);
    expect(find('قدیمی'), ['كتاب قديمي']);
  });

  test('an Arabic-script query finds the Persian spelling', () {
    repo.insert(text('یک کتاب'));
    expect(find('كتاب'), ['یک کتاب']);
  });

  test('harakat and tatweel do not hide a word', () {
    repo.insert(text('این خیلی مُهَمّ است'));
    repo.insert(text('کتـــاب'));
    expect(find('مهم'), ['این خیلی مُهَمّ است']);
    expect(find('کتاب'), ['کتـــاب']);
  });

  test('a ZWNJ word is found with and without the ZWNJ', () {
    repo.insert(text('یادداشت‌ها را مرور کن'));
    expect(find('یادداشتها'), hasLength(1));
    expect(find('یادداشت‌ها'), hasLength(1));
    expect(find('یادداشت مرور'), hasLength(1));
    expect(find('یادداشتها مرور'), hasLength(1));
  });

  test('digits match across Latin, Persian and Arabic-Indic', () {
    repo.insert(text('قسط ۵ میلیون'));
    repo.insert(text('room 12'));
    expect(find('5'), ['قسط ۵ میلیون']);
    expect(find('٥'), ['قسط ۵ میلیون']);
    expect(find('۱۲'), ['room 12']);
  });

  test('the note keeps the letters it was written with', () {
    final saved = repo.insert(text('كتاب'));
    expect(repo.getById(saved.id)!.content, 'كتاب');
  });

  test('a library indexed before 1.92.2 is folded once on open', () {
    final note = repo.insert(text('placeholder'));
    db.close();
    // An index row as an older version wrote it, and no record of folding.
    final raw = sqlite3.open(path);
    raw.execute('DELETE FROM notes_fts');
    raw.execute('INSERT INTO notes_fts (note_id, content) VALUES (?, ?)', [
      note.id,
      'كتاب‌ها',
    ]);
    raw.execute("DELETE FROM nex_meta WHERE key = 'search_index_folded'");
    raw.dispose();

    db = NexDatabase.open(path);
    repo = SqliteNoteRepository(db);
    expect(find('کتابها'), hasLength(1));
    expect(find('کتاب'), hasLength(1));
  });
}
