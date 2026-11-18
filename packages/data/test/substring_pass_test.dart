import 'dart:io';

import 'package:nex_data/nex_data.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The substring pass that catches what FTS's token index misses: a word
/// inside another word, and a Latin case gap. Its cost is bounded by the
/// library's text, so the pass itself must never do work the needle cannot
/// need — the case-folding `lower()` copy of every note is skipped for
/// needles with no cased letters (Persian after the fold, digits), which
/// changes no answer, only the price.
void main() {
  late Directory tmp;
  late NexDatabase db;
  late SqliteNoteRepository repo;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('nex_substring_');
    db = NexDatabase.open(p.join(tmp.path, 'nex.sqlite'));
    repo = SqliteNoteRepository(db, localDeviceId: 'd');
  });

  tearDown(() {
    db.close();
    tmp.deleteSync(recursive: true);
  });

  Note insert(String content) {
    final now = DateTime.now().toUtc();
    return repo.insert(
      Note(
        id: newUuidV7(),
        type: NoteType.text,
        content: content,
        createdAt: now,
        updatedAt: now,
        deviceId: 'test',
        rev: 1,
        syncState: SyncState.pending,
      ),
    );
  }

  List<String> searchIds(String query) =>
      repo.search(SearchFilters(query: query)).map((n) => n.id).toList();

  test('a Persian word inside another word is found mid-token', () {
    // 'لام' is not a token of its own anywhere: FTS cannot match it, and
    // the needle holds no cased letters, so this is exactly the pass that
    // runs without the case-folding copy.
    final match = insert('سلام دنیا');
    insert('خوش آمدید');

    expect(searchIds('لام'), [match.id]);
  });

  test('a Latin case gap still finds the note the index missed', () {
    // The 2.7.0 reason the pass exists: "NERA" finding "Generator" the
    // moment the FTS pass missed it. The needle is cased, so this is the
    // `lower()` arm.
    final match = insert('the Generator needs a service');
    insert('an unrelated note');

    expect(searchIds('nera'), [match.id]);
    expect(searchIds('NERA'), [match.id]);
  });

  test('a digit needle matches the digits as they are stored', () {
    final match = insert('invoice 1042 paid');
    insert('invoice 1043 unpaid');

    expect(searchIds('1042'), [match.id]);
  });

  test('a folded Persian spelling finds its normalised spelling', () {
    // The fold writes 'کتابها' for 'کتاب‌ها' (ZWNJ) at index time; a query
    // typed with the half-space folds to the same needle.
    final match = insert('کتاب‌ها را خواندم');
    insert('مجله خواندم');

    expect(searchIds('کتابها'), [match.id]);
    expect(searchIds('کتاب‌ها'), [match.id]);
  });

  test('the substring pass respects a type filter', () {
    final match = insert('the Generator needs a service');
    final checklist = repo.insert(
      Note(
        id: newUuidV7(),
        type: NoteType.checklist,
        content: 'Generator checklist',
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        deviceId: 'test',
        rev: 1,
        syncState: SyncState.pending,
      ),
    );

    expect(
      repo
          .search(
            const SearchFilters(query: 'nera', types: [NoteType.checklist]),
          )
          .map((n) => n.id),
      [checklist.id],
    );
    expect(
      repo
          .search(const SearchFilters(query: 'nera', types: [NoteType.text]))
          .map((n) => n.id),
      [match.id],
    );
  });
}
