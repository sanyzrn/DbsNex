import 'dart:io';

import 'package:nex_data/nex_data.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// `similarNotePairs` is the brief's grouping beyond shared words: the
/// library's own stored vectors, read locally, saying which records are
/// about one subject. What is tested here is the similarity floor, the
/// exclusions, and the bound that keeps the read cheap on any library.
void main() {
  late Directory tmp;
  late NexDatabase db;
  late SqliteNoteRepository repo;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('nex_semantic_pairs_');
    db = NexDatabase.open(p.join(tmp.path, 'nex.sqlite'));
    repo = SqliteNoteRepository(db);
  });

  tearDown(() {
    db.close();
    tmp.deleteSync(recursive: true);
  });

  Note capture(String id, String content) => repo.insert(
    Note(
      id: id,
      type: NoteType.text,
      content: content,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      deviceId: 'test-device',
      rev: 1,
      syncState: SyncState.pending,
    ),
  );

  test('close vectors pair, distant ones do not', () {
    capture('a', 'the dentist');
    capture('b', 'tooth appointment');
    capture('c', 'buy milk');
    repo.setEmbedding('a', [1, 0, 0]);
    repo.setEmbedding('b', [0.95, 0.1, 0]);
    repo.setEmbedding('c', [0, 1, 0]);

    final pairs = repo.similarNotePairs(['a', 'b', 'c']);

    expect(pairs, hasLength(1));
    expect(pairs.single.a, 'a');
    expect(pairs.single.b, 'b');
    expect(pairs.single.score, greaterThan(0.9));
  });

  test('the floor is a clustering floor, not a search floor', () {
    capture('a', 'one');
    capture('b', 'two');
    repo.setEmbedding('a', [1, 0, 0]);
    // Cosine 0.6: a search might offer it; a cluster must not merge on it.
    repo.setEmbedding('b', [0.6, 0.8, 0]);

    expect(repo.similarNotePairs(['a', 'b']), isEmpty);
    expect(repo.similarNotePairs(['a', 'b'], minScore: 0.5), hasLength(1));
  });

  test('deleted and not-yet-arrived notes pair with nothing', () {
    capture('a', 'kept');
    capture('gone', 'deleted');
    capture('waiting', 'not arrived');
    repo.setEmbedding('a', [1, 0, 0]);
    repo.setEmbedding('gone', [1, 0, 0]);
    repo.setEmbedding('waiting', [1, 0, 0]);
    repo.softDelete('gone');
    db.db.execute('UPDATE notes SET scheduled_until = ? WHERE id = ?', [
      DateTime.now().add(const Duration(days: 1)).toUtc().toIso8601String(),
      'waiting',
    ]);

    expect(repo.similarNotePairs(['a', 'gone', 'waiting']), isEmpty);
  });

  test('a note with no vector is simply not in the reading', () {
    capture('a', 'embedded');
    capture('b', 'never embedded');
    repo.setEmbedding('a', [1, 0, 0]);

    expect(repo.similarNotePairs(['a', 'b']), isEmpty);
    expect(repo.similarNotePairs(['a']), isEmpty);
    expect(repo.similarNotePairs(const []), isEmpty);
  });

  test('the read is bounded, keeping the front of the caller\'s order', () {
    // 130 identical vectors: every pair among the first 120 is a match,
    // and the ten behind the bound are not read at all.
    for (var i = 0; i < 130; i++) {
      capture('n$i', 'note $i');
      repo.setEmbedding('n$i', [1, 0, 0]);
    }
    final ids = [for (var i = 0; i < 130; i++) 'n$i'];

    final pairs = repo.similarNotePairs(ids);

    expect(pairs, hasLength(120 * 119 ~/ 2));
    expect(pairs.every((pair) => pair.a != 'n129' && pair.b != 'n129'), isTrue);
  });
}
