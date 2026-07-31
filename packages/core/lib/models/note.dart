import 'tag.dart';

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
    this.caption,
    this.mimeType,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.deviceId,
    required this.rev,
    required this.syncState,
    this.tags = const [],
    this.pinnedAt,
    this.sortOrder,
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
  /// Optional user-authored description on photo/voice/file (never at capture).
  final String? caption;
  /// MIME type from share-intent / file pick when known.
  final String? mimeType;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final String deviceId;
  final int rev;
  final SyncState syncState;
  final List<Tag> tags;

  /// Set on at most one note at a time (see [NoteRepository.pinNote]).
  ///
  /// Local only — never synced or exported, the same as [sortOrder]: both
  /// are how *this device* likes its own timeline arranged, not something
  /// that means anything to another device or survives a JSON export.
  final DateTime? pinnedAt;

  /// Manual position, set by dragging in Rearrange mode. Null means "not
  /// manually placed" — such notes sort by [updatedAt] ahead of any that
  /// have been (see [NoteRepository.listTimeline]), so a fresh capture still
  /// surfaces at the top rather than waiting at the bottom of a hand-ordered
  /// list it was never part of arranging.
  final int? sortOrder;

  bool get isDeleted => deletedAt != null;

  /// Display filename for file notes (stored in [content]).
  String? get originalFilename =>
      type == NoteType.file ? content : null;

  /// Text used for keyword search — original body or AI-derived text.
  String? get searchableDerivedText {
    switch (type) {
      case NoteType.text:
        return content;
      case NoteType.voice:
        return _joinSearchable([transcriptText, caption]);
      case NoteType.photo:
        return _joinSearchable([ocrText, caption]);
      case NoteType.file:
        return _joinSearchable([content, caption]);
    }
  }

  static String? _joinSearchable(List<String?> parts) {
    final joined = parts
        .whereType<String>()
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .join(' ');
    return joined.isEmpty ? null : joined;
  }

  Note copyWith({
    String? content,
    String? mediaUri,
    String? mediaHash,
    int? durationMs,
    String? transcriptText,
    String? ocrText,
    String? summaryText,
    String? caption,
    bool clearCaption = false,
    String? mimeType,
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
      caption: clearCaption ? null : (caption ?? this.caption),
      mimeType: mimeType ?? this.mimeType,
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
        'caption': caption,
        'mime_type': mimeType,
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
      caption: row['caption'] as String?,
      mimeType: row['mime_type'] as String?,
      createdAt: DateTime.parse(row['created_at']! as String).toUtc(),
      updatedAt: DateTime.parse(row['updated_at']! as String).toUtc(),
      deletedAt: (row['deleted_at'] as String?) != null
          ? DateTime.parse(row['deleted_at']! as String).toUtc()
          : null,
      deviceId: row['device_id']! as String,
      rev: row['rev']! as int,
      syncState: SyncState.fromWire(row['sync_state']! as String),
      tags: tags,
      pinnedAt: (row['pinned_at'] as String?) != null
          ? DateTime.parse(row['pinned_at']! as String).toUtc()
          : null,
      sortOrder: row['sort_order'] as int?,
    );
  }
}
