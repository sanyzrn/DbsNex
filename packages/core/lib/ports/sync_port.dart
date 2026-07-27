/// Outcome of one sync cycle.
class SyncResult {
  const SyncResult({
    required this.pushed,
    required this.pulled,
    required this.cursor,
    this.hasMore = false,
  });

  final int pushed;
  final int pulled;

  /// Opaque server cursor. This is a monotonic sequence value, not a timestamp:
  /// the previous protocol compared a Node-generated timestamp against
  /// PostgreSQL-generated row stamps, and any clock skew dropped rows forever.
  final String cursor;

  final bool hasMore;
}

/// Transport contract for v2 sync. Declared in core; implemented in data.
abstract interface class SyncPort {
  Future<SyncResult> sync();

  void close();
}
