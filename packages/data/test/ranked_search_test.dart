import 'dart:io';

import 'package:nex_core/nex_core.dart';
import 'package:nex_data/nex_data.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// W2.2 in the database: a typed search is ranked by how well notes match,
/// meaning hits join the same list under the same filters.
void main() {
  late Directory tmp;
  late NexDatabase db;
  late SqliteNoteRepository repo;
  late CaptureService capture;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('nex_ranked_');
    db = NexDatabase.open(p.join(tmp.path, 'nex.sqlite'));
    repo = SqliteNoteRepository(db, localDeviceId: 'd');
    capture = CaptureService(repo, deviceId: 'd');
  });

  tearDown(() {
    db.close();
    tmp.deleteSync(recursive: true);
  });

  test('the best match leads, not the newest', () {
    final strong = capture.submitTextCapture(
      'Boiler service: boiler pressure, boiler code 4471',
    )!;
    capture.submitTextCapture('Groceries and a note to call about the boiler');
    for (var i = 0; i < 5; i++) {
      capture.submitTextCapture('Something else entirely $i');
    }
    final results = repo.search(const SearchFilters(query: 'boiler'));
    expect(results.first.id, strong.id);
    expect(results, hasLength(2));
  });

  test('a substring still finds the middle of a word, after whole words', () {
    final word = capture.submitTextCapture('A tor is a hill')!;
    final middle = capture.submitTextCapture('The generator is loud')!;
    final results = repo.search(const SearchFilters(query: 'tor'));
    expect(results.map((n) => n.id), [word.id, middle.id]);
  });

  test('meaning hits join the list, under the same filters', () {
    final keyword = capture.submitTextCapture('invoice for March')!;
    final meaning = capture.submitTextCapture('the bill from the plumber')!;
    final link = capture.submitLinkCapture('https://example.com/bills')!;
    final both = repo.rankedSearch(
      const SearchFilters(query: 'invoice'),
      semantic: [meaning.id, link.id],
    );
    expect(both.map((n) => n.id), containsAll([keyword.id, meaning.id]));

    final onlyText = repo.rankedSearch(
      const SearchFilters(query: 'invoice', types: [NoteType.text]),
      semantic: [meaning.id, link.id],
    );
    expect(onlyText.map((n) => n.id), isNot(contains(link.id)));

    repo.softDelete(meaning.id);
    expect(
      repo
          .rankedSearch(
            const SearchFilters(query: 'invoice'),
            semantic: [meaning.id],
          )
          .map((n) => n.id),
      [keyword.id],
    );
  });

  test('filters without a query keep the timeline order', () {
    final a = capture.submitTextCapture('first')!;
    final b = capture.submitTextCapture('second')!;
    expect(
      repo.search(const SearchFilters(types: [NoteType.text])).map((n) => n.id),
      [b.id, a.id],
    );
  });
}
