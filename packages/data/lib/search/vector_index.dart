import 'dart:math' as math;
import 'dart:typed_data';

/// How a note's embedding is stored and searched (W2.1).
///
/// It used to be a JSON array in a TEXT column, and every semantic search
/// selected every row and parsed every number: five seconds for ten thousand
/// notes on a desktop, most of it `double.parse`, and a database three times
/// the size of the vectors in it.
///
/// Now each vector is stored twice, both as BLOBs:
///
/// - `vec`: the vector scaled to unit length, as little-endian float32. Cosine
///   similarity only depends on direction, so unit length turns it into a
///   plain dot product, and float32 is all the precision an embedding has.
/// - `q8`: the same unit vector quantised to one signed byte per dimension,
///   with one float (`scale`) to undo it. A quarter of the size, and what the
///   first pass of a search reads.
///
/// A search scans the quantised copies in memory for the best few hundred,
/// then scores only those exactly against their float32 vectors. No native
/// vector extension: `packages/data` stays pure Dart.
class VectorCodec {
  const VectorCodec._();

  /// The unit-length float32 bytes, the int8 codes and their scale — or null
  /// for a vector with no direction (empty, or all zeros).
  static ({Uint8List vec, Uint8List q8, double scale})? encode(
    List<double> values,
  ) {
    if (values.isEmpty) return null;
    var norm = 0.0;
    for (final v in values) {
      norm += v * v;
    }
    if (norm == 0 || norm.isNaN || norm.isInfinite) return null;
    norm = math.sqrt(norm);
    final unit = Float32List(values.length);
    var maxAbs = 0.0;
    for (var i = 0; i < values.length; i++) {
      final v = values[i] / norm;
      unit[i] = v;
      final a = v.abs();
      if (a > maxAbs) maxAbs = a;
    }
    final scale = maxAbs / 127;
    final codes = Int8List(values.length);
    for (var i = 0; i < values.length; i++) {
      codes[i] = (unit[i] / scale).round().clamp(-127, 127);
    }
    final bytes = ByteData(values.length * 4);
    for (var i = 0; i < values.length; i++) {
      bytes.setFloat32(i * 4, unit[i], Endian.little);
    }
    return (
      vec: bytes.buffer.asUint8List(),
      q8: codes.buffer.asUint8List(),
      scale: scale,
    );
  }

  /// A stored `vec` back to numbers. Read through [ByteData] because a BLOB
  /// can arrive at any alignment.
  static Float32List decode(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    final out = Float32List(bytes.length ~/ 4);
    for (var i = 0; i < out.length; i++) {
      out[i] = data.getFloat32(i * 4, Endian.little);
    }
    return out;
  }

  /// [values] at unit length, as float32 — how a query is compared.
  static Float32List? unit(List<double> values) {
    final encoded = encode(values);
    return encoded == null ? null : decode(encoded.vec);
  }
}

/// The quantised vectors of one embedding space, held in memory by the
/// database isolate so a search never reads them from disk (W2.1).
///
/// One row per note, replaced in place when a note is re-embedded and
/// swap-removed when it goes. Only vectors of [dims] dimensions are kept: the
/// library only ever holds one space at a time (see `setEmbeddingSpace`), and
/// anything else could not be compared anyway.
class VectorIndex {
  VectorIndex(this.dims);

  final int dims;
  final _ids = <String>[];
  final _codes = <Int8List>[];
  final _scales = <double>[];
  final _bits = <Uint32List>[];
  final _slot = <String, int>{};

  /// Below this many rows every vector gets the int8 pass and the answer is
  /// exact; above it a sign pass chooses which do (W2.3).
  static const binaryThreshold = 4000;

  /// The sign of each dimension, packed 32 to a word. Two vectors pointing
  /// the same way agree on most signs, so the Hamming distance between these
  /// ranks candidates by angle at a small fraction of a dot product's cost.
  static Uint32List _signs(List<num> values) {
    final bits = Uint32List((values.length + 31) >> 5);
    for (var i = 0; i < values.length; i++) {
      if (values[i] > 0) bits[i >> 5] |= 1 << (i & 31);
    }
    return bits;
  }

  static int _popcount(int x) {
    x = x - ((x >> 1) & 0x55555555);
    x = (x & 0x33333333) + ((x >> 2) & 0x33333333);
    x = (x + (x >> 4)) & 0x0F0F0F0F;
    return ((x * 0x01010101) & 0xFFFFFFFF) >> 24;
  }

  int get length => _ids.length;

  bool contains(String id) => _slot.containsKey(id);

  void put(String id, Uint8List q8, double scale) {
    if (q8.length != dims) {
      remove(id);
      return;
    }
    final codes = Int8List.fromList(
      q8.buffer.asInt8List(q8.offsetInBytes, q8.length),
    );
    final bits = _signs(codes);
    final at = _slot[id];
    if (at != null) {
      _codes[at] = codes;
      _scales[at] = scale;
      _bits[at] = bits;
      return;
    }
    _slot[id] = _ids.length;
    _ids.add(id);
    _codes.add(codes);
    _scales.add(scale);
    _bits.add(bits);
  }

  void remove(String id) {
    final at = _slot.remove(id);
    if (at == null) return;
    final last = _ids.length - 1;
    if (at != last) {
      _ids[at] = _ids[last];
      _codes[at] = _codes[last];
      _scales[at] = _scales[last];
      _bits[at] = _bits[last];
      _slot[_ids[at]] = at;
    }
    _ids.removeLast();
    _codes.removeLast();
    _scales.removeLast();
    _bits.removeLast();
  }

  /// The [k] rows closest to [query] (unit length, [dims] long) by the
  /// quantised dot product, best first. An approximation, only ever used to
  /// choose what to score exactly.
  List<({String id, double score})> nearest(
    Float32List query,
    int k, {
    Set<String>? exclude,
  }) {
    if (query.length != dims || k <= 0 || _ids.isEmpty) return const [];
    // Which rows get the int8 pass: all of them in a small library, the
    // closest by sign in a large one — a tenth of the library, at least 400
    // and at most 3,000, far wider than the handful a caller keeps.
    final rows = _ids.length > binaryThreshold
        ? _closestBySign(_signs(query), (_ids.length ~/ 10).clamp(400, 3000))
        : null;
    final count = rows?.length ?? _ids.length;
    // A bounded min-heap would be tidier; with k in the hundreds a sorted
    // insert into a short list costs less than it saves.
    final best = <({String id, double score})>[];
    var floor = double.negativeInfinity;
    final n = dims;
    for (var r = 0; r < count; r++) {
      final row = rows == null ? r : rows[r];
      final codes = _codes[row];
      var dot = 0.0;
      for (var i = 0; i < n; i++) {
        dot += codes[i] * query[i];
      }
      final score = dot * _scales[row];
      if (best.length >= k && score <= floor) continue;
      final id = _ids[row];
      if (exclude != null && exclude.contains(id)) continue;
      var at = best.length;
      while (at > 0 && best[at - 1].score < score) {
        at--;
      }
      best.insert(at, (id: id, score: score));
      if (best.length > k) best.removeLast();
      if (best.length >= k) floor = best.last.score;
    }
    return best;
  }

  /// The rows whose sign bits differ least from [query]'s — at least [keep]
  /// of them (all of those tied at the cut-off distance).
  List<int> _closestBySign(Uint32List query, int keep) {
    final words = query.length;
    // Distances are small integers, so a histogram finds the cut-off in one
    // pass instead of sorting fifty thousand rows.
    final distance = Int32List(_ids.length);
    final histogram = Int32List(words * 32 + 1);
    for (var row = 0; row < _ids.length; row++) {
      final bits = _bits[row];
      var d = 0;
      for (var w = 0; w < words; w++) {
        d += _popcount(bits[w] ^ query[w]);
      }
      distance[row] = d;
      histogram[d]++;
    }
    var cutoff = 0;
    var total = 0;
    while (cutoff < histogram.length) {
      total += histogram[cutoff];
      if (total >= keep) break;
      cutoff++;
    }
    return [
      for (var row = 0; row < _ids.length; row++)
        if (distance[row] <= cutoff) row,
    ];
  }
}
