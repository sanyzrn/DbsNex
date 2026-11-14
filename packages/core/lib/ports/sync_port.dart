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
    this.rejected = const [],
    this.skippedUnknownTypes = 0,
  });

  final int pushed;
  final int pulled;

  /// Ids the server merged rather than accepting verbatim.
  final List<String> mergedIds;

  /// Ids whose media the server recognised by hash and did not store twice.
  final List<String> mediaDeduped;

  /// Ids the server refused — a note id owned by another account, or an item
  /// it could not take. They stay in the outbox and are retried, so the count
  /// being visible (rather than indistinguishable from success) is the only
  /// thing that stops a permanently-stuck item from looking like a quiet life.
  final List<String> rejected;

  /// Notes the pull carried whose type this build does not know. They are
  /// skipped rather than applied, because `NoteType.fromWire` has no
  /// representation for them — but the cycle keeps going, so one note from a
  /// newer peer can no longer wedge the cursor behind it forever.
  final int skippedUnknownTypes;
}

/// Transport contract for v2 sync. Declared in core; implemented in data.
///
/// `/sync/pull` returns a monotonic sequence cursor, and that is what the
/// client persists — see `SqliteNoteRepository.syncCursor`. It used to keep a
/// timestamp watermark instead, which clock skew between the Node process and
/// PostgreSQL could skip rows past; the cursor, the `tag_remap` response and
/// page draining are all wired through now.
///
/// Sync is not a shipped feature: there is no pairing flow, and the only way
/// to reach it is by pasting a base URL and a token into Settings.
abstract interface class SyncPort {
  Future<SyncResult> sync();

  void close();
}
