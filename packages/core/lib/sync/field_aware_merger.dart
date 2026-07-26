import 'package:nex_data/nex_data.dart';

/// Snapshot of a note used for field-aware merge (ADR-020).
class NoteRevision {
  const NoteRevision({
    required this.id,
    required this.type,
    this.content,
    this.mediaUri,
    this.mediaHash,
    this.durationMs,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.deviceId,
    required this.rev,
    required this.tagIds,
  });

  final String id;
  final NoteType type;
  final String? content;
  final String? mediaUri;
  final String? mediaHash;
  final int? durationMs;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final String deviceId;
  final int rev;
  final Set<String> tagIds;

  bool get isDeleted => deletedAt != null;

  factory NoteRevision.fromNote(Note note) => NoteRevision(
        id: note.id,
        type: note.type,
        content: note.content,
        mediaUri: note.mediaUri,
        mediaHash: note.mediaHash,
        durationMs: note.durationMs,
        createdAt: note.createdAt,
        updatedAt: note.updatedAt,
        deletedAt: note.deletedAt,
        deviceId: note.deviceId,
        rev: note.rev,
        tagIds: note.tags.map((t) => t.id).toSet(),
      );
}

/// Result of merging two concurrent revisions of the same note.
class MergedNote {
  const MergedNote({
    required this.id,
    required this.type,
    this.content,
    this.mediaUri,
    this.mediaHash,
    this.durationMs,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.deviceId,
    required this.rev,
    required this.tagIds,
  });

  final String id;
  final NoteType type;
  final String? content;
  final String? mediaUri;
  final String? mediaHash;
  final int? durationMs;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final String deviceId;
  final int rev;
  final Set<String> tagIds;
}

/// Field-aware conflict resolution (ADR-020 / 04-architecture.md):
/// - Scalars (`content`, `media_uri`, `media_hash`, `duration_ms`): LWW by
///   `updated_at`, then `rev`.
/// - Tags: **union-merge** — never drop a tag that lost a whole-record race.
/// - Delete vs edit: deletion (tombstone) wins.
class FieldAwareMerger {
  const FieldAwareMerger();

  MergedNote merge(NoteRevision a, NoteRevision b) {
    assert(a.id == b.id, 'can only merge revisions of the same note');

    // Deletion wins over concurrent edit (04-architecture.md).
    if (a.isDeleted || b.isDeleted) {
      final tombstone = a.isDeleted && b.isDeleted
          ? _later(a, b)
          : (a.isDeleted ? a : b);
      final other = identical(tombstone, a) ? b : a;
      return MergedNote(
        id: a.id,
        type: tombstone.type,
        content: tombstone.content,
        mediaUri: tombstone.mediaUri,
        mediaHash: tombstone.mediaHash,
        durationMs: tombstone.durationMs,
        createdAt: _earlierCreated(a, b),
        updatedAt: _maxTime(a.updatedAt, b.updatedAt),
        deletedAt: tombstone.deletedAt,
        deviceId: tombstone.deviceId,
        rev: a.rev > b.rev ? a.rev : b.rev,
        // Union tags even under tombstone so a revive+history path keeps them.
        tagIds: {...a.tagIds, ...b.tagIds, ...other.tagIds},
      );
    }

    final winner = _later(a, b);
    final loser = identical(winner, a) ? b : a;

    // Same-device sequential edits: later tag set wins (allows removals).
    // Concurrent multi-device: ADR-020 union-merge — never drop a tag that
    // only one side still holds.
    final tagIds = a.deviceId == b.deviceId
        ? {...winner.tagIds}
        : {...a.tagIds, ...b.tagIds};

    return MergedNote(
      id: a.id,
      type: winner.type,
      // Scalar LWW
      content: winner.content,
      mediaUri: winner.mediaUri,
      mediaHash: winner.mediaHash ?? loser.mediaHash,
      durationMs: winner.durationMs ?? loser.durationMs,
      createdAt: _earlierCreated(a, b),
      updatedAt: winner.updatedAt,
      deletedAt: null,
      deviceId: winner.deviceId,
      rev: a.rev > b.rev ? a.rev : b.rev,
      tagIds: tagIds,
    );
  }

  /// Media dedupe: identical hashes mean one store key (ADR-019).
  static bool isDuplicateMedia(String? hashA, String? hashB) =>
      hashA != null && hashB != null && hashA == hashB;

  /// Invariant: `_later(a, b)` and `_later(b, a)` always return the same
  /// revision (commutativity). When `updated_at` and `rev` both tie, break
  /// by lexical `device_id` so argument order cannot disagree across devices.
  NoteRevision _later(NoteRevision a, NoteRevision b) {
    final byTime = a.updatedAt.compareTo(b.updatedAt);
    if (byTime > 0) return a;
    if (byTime < 0) return b;
    if (a.rev != b.rev) return a.rev > b.rev ? a : b;
    final byDevice = a.deviceId.compareTo(b.deviceId);
    if (byDevice > 0) return a;
    if (byDevice < 0) return b;
    // Identical timestamps, revs, and device ids — either side is fine;
    // prefer `a` only after all order-independent keys matched.
    return a;
  }

  DateTime _earlierCreated(NoteRevision a, NoteRevision b) =>
      a.createdAt.isBefore(b.createdAt) ? a.createdAt : b.createdAt;

  DateTime _maxTime(DateTime a, DateTime b) => a.isAfter(b) ? a : b;
}
