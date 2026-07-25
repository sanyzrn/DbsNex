/// Note types. Generic `file` ships in Phase 2 (ADR-008 deferred out of v1).
enum NoteType {
  text,
  voice,
  photo,
  file;

  String get wireName => name;

  static NoteType fromWire(String value) {
    return NoteType.values.firstWhere(
      (t) => t.name == value,
      orElse: () => throw ArgumentError.value(value, 'type', 'unknown note type'),
    );
  }
}

/// Sync state present from v1 for sync-readiness (ADR-006); unused until v2.
enum SyncState {
  pending,
  synced,
  conflict;

  String get wireName => name;

  static SyncState fromWire(String value) {
    return SyncState.values.firstWhere(
      (s) => s.name == value,
      orElse: () =>
          throw ArgumentError.value(value, 'sync_state', 'unknown sync state'),
    );
  }
}

/// A captured note. Field names match `02-product-specification.md` Data Model.
///
/// AI-derived fields (`transcriptText`, `ocrText`, `summaryText`) are clearly
/// labeled and never overwrite original `content` / `mediaUri` (09-ai.md).
class Note {
  const Note({
    required this.id,
    required this.type,
    this.content,
    this.mediaUri,
    this.mediaHash,
    this.durationMs,
    this.transcriptText,
    this.ocrText,
    this.summaryText,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.deviceId,
    required this.rev,
    required this.syncState,
    this.tags = const [],
  });

  final String id;
  final NoteType type;
  final String? content;
  final String? mediaUri;
  final String? mediaHash;
  final int? durationMs;
  final String? transcriptText;
  final String? ocrText;
  final String? summaryText;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final String deviceId;
  final int rev;
  final SyncState syncState;
  final List<Tag> tags;

  bool get isDeleted => deletedAt != null;

  /// Text used for keyword search — original body or AI-derived text.
  String? get searchableDerivedText {
    switch (type) {
      case NoteType.text:
        return content;
      case NoteType.voice:
        return transcriptText;
      case NoteType.photo:
        return ocrText;
      case NoteType.file:
        return content;
    }
  }

  Note copyWith({
    String? content,
    String? mediaUri,
    String? mediaHash,
    int? durationMs,
    String? transcriptText,
    String? ocrText,
    String? summaryText,
    DateTime? updatedAt,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
    int? rev,
    SyncState? syncState,
    List<Tag>? tags,
  }) {
    return Note(
      id: id,
      type: type,
      content: content ?? this.content,
      mediaUri: mediaUri ?? this.mediaUri,
      mediaHash: mediaHash ?? this.mediaHash,
      durationMs: durationMs ?? this.durationMs,
      transcriptText: transcriptText ?? this.transcriptText,
      ocrText: ocrText ?? this.ocrText,
      summaryText: summaryText ?? this.summaryText,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
      deviceId: deviceId,
      rev: rev ?? this.rev,
      syncState: syncState ?? this.syncState,
      tags: tags ?? this.tags,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'type': type.wireName,
        'content': content,
        'media_uri': mediaUri,
        'media_hash': mediaHash,
        'duration_ms': durationMs,
        'transcript_text': transcriptText,
        'ocr_text': ocrText,
        'summary_text': summaryText,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
        'deleted_at': deletedAt?.toUtc().toIso8601String(),
        'device_id': deviceId,
        'rev': rev,
        'sync_state': syncState.wireName,
        'tags': tags.map((t) => t.toJson()).toList(),
      };

  factory Note.fromRow(Map<String, Object?> row, {List<Tag> tags = const []}) {
    return Note(
      id: row['id']! as String,
      type: NoteType.fromWire(row['type']! as String),
      content: row['content'] as String?,
      mediaUri: row['media_uri'] as String?,
      mediaHash: row['media_hash'] as String?,
      durationMs: row['duration_ms'] as int?,
      transcriptText: row['transcript_text'] as String?,
      ocrText: row['ocr_text'] as String?,
      summaryText: row['summary_text'] as String?,
      createdAt: DateTime.parse(row['created_at']! as String).toUtc(),
      updatedAt: DateTime.parse(row['updated_at']! as String).toUtc(),
      deletedAt: (row['deleted_at'] as String?) != null
          ? DateTime.parse(row['deleted_at']! as String).toUtc()
          : null,
      deviceId: row['device_id']! as String,
      rev: row['rev']! as int,
      syncState: SyncState.fromWire(row['sync_state']! as String),
      tags: tags,
    );
  }
}

/// A freeform tag (FR-3). `color` is optional accent (ADR-021).
class Tag {
  const Tag({
    required this.id,
    required this.name,
    this.color,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String? color;
  final DateTime createdAt;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'color': color,
        'created_at': createdAt.toUtc().toIso8601String(),
      };

  factory Tag.fromRow(Map<String, Object?> row) {
    return Tag(
      id: row['id']! as String,
      name: row['name']! as String,
      color: row['color'] as String?,
      createdAt: DateTime.parse(row['created_at']! as String).toUtc(),
    );
  }
}

/// Search filters layered on one surface (ADR-011 / FR-4).
class SearchFilters {
  const SearchFilters({
    this.query = '',
    this.tagIds = const [],
    this.createdFrom,
    this.createdTo,
    this.types = const [],
  });

  final String query;
  final List<String> tagIds;
  final DateTime? createdFrom;
  final DateTime? createdTo;
  final List<NoteType> types;

  bool get isEmpty =>
      query.trim().isEmpty &&
      tagIds.isEmpty &&
      createdFrom == null &&
      createdTo == null &&
      types.isEmpty;
}
