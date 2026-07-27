/// Outcome of one sync cycle.
///
/// There used to be two unrelated classes with this name — one here, one in
/// `packages/data/lib/sync_client/sync_client.dart` — so any file importing both
/// libraries failed to compile with `ambiguous_import`. This is the single
/// definition, and its fields are the ones the client actually produces and the
/// callers actually read.
class SyncResult {
  const SyncResult({
    required this.pushed,
    required this.pulled,
    this.mergedIds = const [],
    this.mediaDeduped = const [],
  });

  final int pushed;
  final int pulled;

  /// Ids the server merged rather than accepting verbatim.
  final List<String> mergedIds;

  /// Ids whose media the server recognised by hash and did not store twice.
  final List<String> mediaDeduped;
}

/// Transport contract for v2 sync. Declared in core; implemented in data.
///
/// `/sync/pull` returns a monotonic sequence cursor, and that is what a correct
/// client must persist. `SyncClient` still tracks a timestamp watermark, so
/// clock skew between the Node process and PostgreSQL can drop rows. Wiring the
/// cursor through, along with the `tag_remap` response, is tracked as Phase 3 in
/// `docs/13-outstanding-work.md`.
abstract interface class SyncPort {
  Future<SyncResult> sync();

  void close();
}
