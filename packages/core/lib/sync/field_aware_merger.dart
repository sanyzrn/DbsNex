import '../models/note.dart';

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

  /// Builds a revision from the server's `NoteRow` wire form — the same shape
  /// `spec/merge-conformance.json` stores, so both languages read one corpus.
  factory NoteRevision.fromJson(Map<String, Object?> json) => NoteRevision(
        id: json['id']! as String,
        type: NoteType.fromWire(json['type']! as String),
        content: json['content'] as String?,
        mediaUri: json['media_uri'] as String?,
        mediaHash: json['media_hash'] as String?,
        durationMs: json['duration_ms'] as int?,
        createdAt: DateTime.parse(json['created_at']! as String).toUtc(),
        updatedAt: DateTime.parse(json['updated_at']! as String).toUtc(),
        deletedAt: json['deleted_at'] == null
            ? null
            : DateTime.parse(json['deleted_at']! as String).toUtc(),
        deviceId: json['device_id']! as String,
        rev: json['rev']! as int,
        tagIds: ((json['tag_ids'] as List?) ?? const [])
            .cast<String>()
            .toSet(),
      );

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

  /// Sorted. Unlike [NoteRevision.tagIds] this is a list, because it is the
  /// wire form and its order has to be deterministic across devices.
  final List<String> tagIds;

  /// Wire form. Keys and value shapes match the server's `NoteRow`, which is
  /// what makes `spec/merge-conformance.json` readable by both languages.
  Map<String, Object?> toJson() => {
        'id': id,
        'type': type.wireName,
        'content': content,
        'media_uri': mediaUri,
        'media_hash': mediaHash,
        'duration_ms': durationMs,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
        'deleted_at': deletedAt?.toUtc().toIso8601String(),
        'device_id': deviceId,
        'rev': rev,
        'tag_ids': tagIds,
      };
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
      return MergedNote(
        id: a.id,
        type: tombstone.type,
        // Deletion means deletion: the payload is erased at merge time rather
        // than retained forever behind a deleted_at flag. This branch used to
        // keep the tombstone's content and union the tag sets, disagreeing with
        // the server on every delete — the conformance suite that exists to
        // catch exactly this had never compiled, so nothing reported it.
        content: null,
        mediaUri: null,
        mediaHash: null,
        durationMs: null,
        createdAt: _earlierCreated(a, b),
        updatedAt: _maxTime(a.updatedAt, b.updatedAt),
        deletedAt: tombstone.deletedAt,
        deviceId: tombstone.deviceId,
        rev: a.rev > b.rev ? a.rev : b.rev,
        tagIds: const [],
      );
    }

    final winner = _later(a, b);
    final loser = identical(winner, a) ? b : a;

    // Same-device sequential edits: later tag set wins (allows removals).
    // Concurrent multi-device: ADR-020 union-merge — never drop a tag that
    // only one side still holds.
    //
    // Sorted so the wire form is order-independent: a Set preserves insertion
    // order, which made {a,b} and {b,a} serialise differently and broke
    // commutativity against the shared corpus.
    final tagIds = a.deviceId == b.deviceId
        ? (winner.tagIds.toList()..sort())
        : ({...a.tagIds, ...b.tagIds}.toList()..sort());

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
