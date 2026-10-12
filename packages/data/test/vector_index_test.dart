import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:nex_data/nex_data.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// W2.1: vectors as BLOBs, searched through an in-memory quantised index and
/// scored exactly — which must give the same answer as scoring every vector.
void main() {
  late Directory tmp;
  late String path;
  late NexDatabase db;
  late SqliteNoteRepository repo;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('nex_vectors_');
    path = p.join(tmp.path, 'nex.sqlite');
    db = NexDatabase.open(path);
    repo = SqliteNoteRepository(db, localDeviceId: 'd');
  });

  tearDown(() {
    db.close();
    tmp.deleteSync(recursive: true);
  });

  void addNote(String id) {
    final now = DateTime.now().toUtc().toIso8601String();
    db.db.execute(
      "INSERT INTO notes (id, type, content, created_at, updated_at, "
      "device_id, rev, sync_state) VALUES (?, 'text', ?, ?, ?, 'd', 1, "
      "'pending')",
      [id, 'note $id', now, now],
    );
  }

  double cosine(List<double> a, List<double> b) {
    var dot = 0.0, na = 0.0, nb = 0.0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      na += a[i] * a[i];
      nb += b[i] * b[i];
    }
    return dot / sqrt(na * nb);
  }

  test('a vector survives the round trip, at unit length', () {
    final encoded = VectorCodec.encode([3, 4, 0])!;
    final back = VectorCodec.decode(encoded.vec);
    expect(back[0], closeTo(0.6, 1e-6));
    expect(back[1], closeTo(0.8, 1e-6));
    expect(VectorCodec.encode(const []), isNull);
    expect(VectorCodec.encode([0, 0]), isNull);
  });

  test('the two-stage search finds exactly what scoring everything finds', () {
    final rnd = Random(7);
    const dims = 64;
    final vectors = <String, List<double>>{};
    for (var i = 0; i < 2000; i++) {
      final id = 'n$i';
      addNote(id);
      final v = List.generate(dims, (_) => rnd.nextDouble() * 2 - 1);
      vectors[id] = v;
      repo.setEmbedding(id, v);
    }
    for (var trial = 0; trial < 20; trial++) {
      final query = List.generate(dims, (_) => rnd.nextDouble() * 2 - 1);
      final expected =
          vectors.entries
              .map((e) => (id: e.key, score: cosine(query, e.value)))
              .toList()
            ..sort((a, b) => b.score.compareTo(a.score));
      final got = repo.nearestEmbeddings(query, limit: 10, minScore: -1);
      expect(
        got.map((h) => h.noteId).toList(),
        expected.take(10).map((e) => e.id).toList(),
      );
      for (var i = 0; i < got.length; i++) {
        expect(got[i].score, closeTo(expected[i].score, 1e-5));
      }
    }
  });

  test('deleted notes, the excluded note and weak matches are left out', () {
    for (final id in ['a', 'b', 'c']) {
      addNote(id);
    }
    repo.setEmbedding('a', [1, 0, 0]);
    repo.setEmbedding('b', [0.9, 0.1, 0]);
    repo.setEmbedding('c', [0, 1, 0]);
    expect(
      repo.nearestEmbeddings([1, 0, 0], minScore: 0.5).map((h) => h.noteId),
      ['a', 'b'],
    );
    expect(
      repo
          .nearestEmbeddings([1, 0, 0], minScore: 0.5, excludeNoteId: 'a')
          .map((h) => h.noteId),
      ['b'],
    );
    repo.softDelete('b');
    expect(
      repo.nearestEmbeddings([1, 0, 0], minScore: 0.5).map((h) => h.noteId),
      ['a'],
    );
  });

  test('when nothing stands out, only the plainly close few come back', () {
    // A library like a real one: every note leans the same way, and none
    // of them is about the query more than the others.
    final rnd = Random(3);
    const dims = 32;
    for (var i = 0; i < 40; i++) {
      addNote('n$i');
      repo.setEmbedding('n$i', [
        for (var d = 0; d < dims; d++)
          (d == 0 ? 1.0 : 0.0) + (rnd.nextDouble() * 2 - 1) * 0.3,
      ]);
    }
    final query = [
      for (var d = 0; d < dims; d++) d == 0 ? 0.8 : (d == 1 ? 0.6 : 0.0),
    ];
    final found = repo.nearestEmbeddings(
      query,
      limit: 20,
      minScore: 0.5,
      standout: true,
    );
    expect(found, isNotEmpty, reason: 'meaning search does not go silent');
    expect(found.length, lessThanOrEqualTo(3));
    for (final hit in found) {
      expect(hit.score, greaterThanOrEqualTo(0.6));
    }
    // A query nothing is close to still finds nothing.
    expect(
      repo.nearestEmbeddings(
        [for (var d = 0; d < dims; d++) d == 2 ? 1.0 : 0.0],
        minScore: 0.5,
        standout: true,
      ),
      isEmpty,
    );
  });

  test('re-embedding and edits keep the index in step', () {
    addNote('a');
    addNote('b');
    repo.setEmbedding('a', [1, 0]);
    repo.setEmbedding('b', [0, 1]);
    expect(repo.nearestEmbeddings([1, 0], limit: 1).single.noteId, 'a');
    repo.setEmbedding('b', [1, 0.01]);
    repo.setEmbedding('a', [0, 1]);
    expect(repo.nearestEmbeddings([1, 0], limit: 1).single.noteId, 'b');
    // An empty answer is a marker, not a vector.
    repo.setEmbedding('b', const []);
    expect(repo.getEmbedding('b'), isEmpty);
    expect(
      repo.nearestEmbeddings([1, 0], minScore: 0.5).map((h) => h.noteId),
      isEmpty,
    );
  });

  test('a vector written by another connection is found', () {
    addNote('a');
    addNote('b');
    repo.setEmbedding('a', [0, 1]);
    expect(repo.nearestEmbeddings([1, 0], minScore: 0.5), isEmpty);
    final other = NexDatabase.open(path);
    SqliteNoteRepository(
      other,
      localDeviceId: 'share',
    ).setEmbedding('b', [1, 0]);
    other.close();
    expect(repo.nearestEmbeddings([1, 0], minScore: 0.5).single.noteId, 'b');
  });

  test('vectors stored as JSON by older versions are moved on open', () {
    addNote('a');
    db.db.execute(
      "INSERT INTO note_embeddings (note_id, dims, values_json, updated_at) "
      "VALUES ('a', 3, '[0.0, 2.0, 0.0]', '2026-01-01T00:00:00Z')",
    );
    db.close();
    db = NexDatabase.open(path);
    repo = SqliteNoteRepository(db, localDeviceId: 'd');
    final row = db.db
        .select("SELECT vec, values_json FROM note_embeddings")
        .single;
    expect(row['values_json'], '');
    expect(row['vec'], isA<Uint8List>());
    expect(repo.getEmbedding('a'), [0.0, 1.0, 0.0]);
    expect(repo.nearestEmbeddings([0, 1, 0]).single.noteId, 'a');
  });

  test('a large library, searched by sign first, still finds what matters', () {
    // Past VectorIndex.binaryThreshold only the rows closest by sign get the
    // int8 pass. Real embeddings cluster by topic; so does this library, and
    // the closest notes to a query about a topic have to survive the cut.
    final rnd = Random(11);
    const dims = 128;
    const topics = 60;
    List<double> around(List<double> centre, double spread) => [
      for (final v in centre) v + (rnd.nextDouble() * 2 - 1) * spread,
    ];
    final centres = [
      for (var t = 0; t < topics; t++)
        List.generate(dims, (_) => rnd.nextDouble() * 2 - 1),
    ];
    final vectors = <String, List<double>>{};
    db.db.beginImmediate();
    for (var i = 0; i < VectorIndex.binaryThreshold + 2000; i++) {
      final id = 'n$i';
      addNote(id);
      final v = around(centres[i % topics], 0.8);
      vectors[id] = v;
      repo.setEmbedding(id, v);
    }
    db.db.execute('COMMIT');

    var found = 0;
    var wanted = 0;
    for (var trial = 0; trial < 30; trial++) {
      final query = around(centres[trial % topics], 0.8);
      final expected =
          (vectors.entries
                  .map((e) => (id: e.key, score: cosine(query, e.value)))
                  .toList()
                ..sort((a, b) => b.score.compareTo(a.score)))
              .take(10)
              .map((e) => e.id)
              .toSet();
      final got = repo
          .nearestEmbeddings(query, limit: 10, minScore: -1)
          .map((h) => h.noteId)
          .toSet();
      found += got.intersection(expected).length;
      wanted += expected.length;
    }
    expect(found / wanted, greaterThanOrEqualTo(0.95));
  });

  group('standing out', () {
    // A library shaped like the owner's (1.99.81): every note shares one
    // strong direction — the language, the app, the length — thirty notes
    // each lean towards a subject of their own, and five short, generic
    // ones are almost nothing but the shared direction.
    const dims = 64;
    final random = Random(7);
    List<double> vector(Map<int, double> parts, {double noise = 0.05}) => [
      for (var i = 0; i < dims; i++)
        (parts[i] ?? 0) + (random.nextDouble() - 0.5) * 2 * noise,
    ];
    Float32List unit(List<double> values) => VectorCodec.unit(values)!;

    late VectorIndex index;
    setUp(() {
      index = VectorIndex(dims);
      for (var k = 1; k <= 30; k++) {
        final code = VectorCodec.encode(vector({0: 0.7, k: 0.7}))!;
        index.put('topic$k', code.q8, code.scale);
      }
      for (var h = 0; h < 5; h++) {
        final code = VectorCodec.encode(vector({0: 0.97}))!;
        index.put('generic$h', code.q8, code.scale);
      }
    });

    test('plain similarity lists the generic notes for anything', () {
      final unrelated = unit(vector({0: 0.8, 50: 0.6}, noise: 0));
      final plain = index.nearest(unrelated, 5).map((hit) => hit.id);
      expect(plain.where((id) => id.startsWith('generic')), hasLength(5));
    });

    test('a related query finds its note, and nothing generic', () {
      final query = unit(vector({0: 0.75, 3: 0.6}, noise: 0));
      final found = index.standout(query, 10).map((hit) => hit.id).toList();
      expect(found.first, 'topic3');
      expect(found.where((id) => id.startsWith('generic')), isEmpty);
      expect(found.length, lessThanOrEqualTo(2));
    });

    test('an unrelated query finds nothing at all', () {
      final unrelated = unit(vector({0: 0.8, 50: 0.6}, noise: 0));
      expect(index.standout(unrelated, 10), isEmpty);
    });

    test('a library too small to measure answers nothing here', () {
      final small = VectorIndex(dims);
      final code = VectorCodec.encode(vector({0: 0.7, 1: 0.7}))!;
      small.put('only', code.q8, code.scale);
      expect(small.standout(unit(vector({0: 0.7, 1: 0.7})), 5), isEmpty);
    });

    test('adding a note moves the centre with it', () {
      final query = unit(vector({0: 0.75, 31: 0.6}, noise: 0));
      expect(index.standout(query, 10), isEmpty);
      final code = VectorCodec.encode(vector({0: 0.7, 31: 0.7}))!;
      index.put('topic31', code.q8, code.scale);
      expect(index.standout(query, 10).first.id, 'topic31');
    });
  });
}
