import 'checklist.dart';
import 'tag.dart';

/// Note types. Generic `file` ships in Phase 2 (ADR-008 deferred out of v1).
///
/// `checklist` and `link` are text notes with a shape. Neither carries media,
/// and both keep everything they know in [Note.content] — a checklist as
/// markdown task lines, a link as the bare URL — which is what lets search,
/// sync, export and merge treat them as the ordinary text they are underneath.
/// The database no longer constrains this set; [fromWire] is the one gate.
enum NoteType {
  text,
  voice,
  photo,
  file,
  checklist,
  link;

  String get wireName => name;

  static NoteType fromWire(String value) {
    return NoteType.values.firstWhere(
      (t) => t.name == value,
      orElse: () =>
          throw ArgumentError.value(value, 'type', 'unknown note type'),
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
    this.title,
    this.linkExcerpt,
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

  /// An optional headline, on a note of any type.
  ///
  /// Deliberately not asked for at capture. Nex's whole promise is that a
  /// capture is finished the moment it exists, and a title field on the way in
  /// is a blank someone feels obliged to fill — which is the Save button back
  /// under another name. It is offered from the detail sheet afterwards, and
  /// on a link note it arrives pre-filled with the page's own title.
  final String? title;

  /// A linked page's own description, read off the page.
  ///
  /// The machine-derived text field for links, the way [transcriptText] is for
  /// voice and [ocrText] is for photos — never user-authored, never the same
  /// thing as [summaryText], which is what an AI provider made of the page.
  final String? linkExcerpt;

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
  String? get originalFilename => type == NoteType.file ? content : null;

  /// A link note's target, or null on every other type.
  String? get linkUrl => type == NoteType.link ? content?.trim() : null;

  /// A checklist note's items, parsed out of [content].
  ///
  /// Empty for every other type, so a caller can ask without checking first.
  List<ChecklistItem> get checklistItems =>
      type == NoteType.checklist ? parseChecklist(content) : const [];

  /// Text used for keyword search — original body or AI-derived text.
  String? get searchableDerivedText {
    switch (type) {
      case NoteType.text:
        return _joinSearchable([title, content]);
      case NoteType.voice:
        return _joinSearchable([title, transcriptText, caption]);
      case NoteType.photo:
        return _joinSearchable([title, ocrText, caption]);
      case NoteType.file:
        return _joinSearchable([title, content, caption]);
      // The markers are stripped: searching for "milk" should find a ticked
      // item, and nobody searches for "[x]".
      case NoteType.checklist:
        return _joinSearchable([
          title,
          for (final item in checklistItems) item.text,
        ]);
      // The URL is searchable too — looking a bookmark up by its domain is
      // the most obvious way to go back to one.
      case NoteType.link:
        return _joinSearchable([title, content, linkExcerpt, caption]);
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

  /// Text a card or the copy button shows as the note's own line: the
  /// caption once there is one, the AI-derived read of the media otherwise.
  ///
  /// Unlike [searchableDerivedText], this never joins the two — captioning a
  /// note is the user's own word on it, and it replaces the machine's
  /// reading on screen rather than sitting next to it. The transcript or OCR
  /// text stays reachable (and searchable) behind its own small copy icon;
  /// it just stops being the headline once someone has written one.
  ///
  /// A [title] outranks all of it. Someone who bothered to name a note named
  /// it because the first line was not what they wanted to see in the list.
  String? get displayText {
    final named = title?.trim();
    if (named != null && named.isNotEmpty) return named;
    switch (type) {
      case NoteType.text:
        return content;
      case NoteType.voice:
        return _firstNonEmpty([caption, transcriptText]);
      case NoteType.photo:
        return _firstNonEmpty([caption, ocrText]);
      case NoteType.file:
        return _firstNonEmpty([caption, content]);
      // The items themselves, in order, on one line — the card renders its own
      // ticked/unticked view, and this is what search results and screen
      // readers get.
      case NoteType.checklist:
        final items = checklistItems;
        return items.isEmpty
            ? null
            : items.map((item) => item.text).join(' · ');
      case NoteType.link:
        return _firstNonEmpty([caption, linkExcerpt, content]);
    }
  }

  static String? _firstNonEmpty(List<String?> parts) {
    for (final part in parts) {
      final text = part?.trim();
      if (text != null && text.isNotEmpty) return text;
    }
    return null;
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
    String? title,
    bool clearTitle = false,
    String? linkExcerpt,
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
      title: clearTitle ? null : (title ?? this.title),
      linkExcerpt: linkExcerpt ?? this.linkExcerpt,
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
    'title': title,
    'link_excerpt': linkExcerpt,
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
      title: row['title'] as String?,
      linkExcerpt: row['link_excerpt'] as String?,
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
