/// What a [MemoryRecord] is about (09-ai.md — Phase 2 local memory/profile).
enum MemoryKind {
  preference,
  fact,
  communicationStyle,
  habit,
  workContext,
  longTerm;

  String get wireName => name;

  static MemoryKind fromWire(String value) {
    return MemoryKind.values.firstWhere(
      (k) => k.name == value,
      orElse: () =>
          throw ArgumentError.value(value, 'kind', 'unknown memory kind'),
    );
  }
}

/// Where a [MemoryRecord] came from — kept so the user can always see, and
/// revoke, anything AI wrote about them (09-ai.md — "کاملاً شفاف و
/// کنترل‌شده توسط کاربر").
enum MemorySource {
  userDirect,
  inferred,
  crossAiImport;

  String get wireName => name;

  static MemorySource fromWire(String value) {
    return MemorySource.values.firstWhere(
      (s) => s.name == value,
      orElse: () =>
          throw ArgumentError.value(value, 'source', 'unknown memory source'),
    );
  }
}

/// One fact, preference, or learned pattern in the local memory/profile store.
///
/// Shaped like `Note` (id, timestamps, `deviceId`, `rev`, soft-delete —
/// ADR-006) so it can ride the same sync machinery later without a schema
/// redesign. Whether a *new* record can be written by a tool call is gated by
/// [AiEntitlement] (ADR-030); an existing record is always visible/editable
/// regardless of entitlement.
class MemoryRecord {
  const MemoryRecord({
    required this.id,
    required this.kind,
    this.key,
    required this.valueText,
    required this.source,
    this.confidence,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.deviceId,
    required this.rev,
  });

  final String id;
  final MemoryKind kind;

  /// Optional short label within [kind] (e.g. `"preferred_language"`).
  /// Null for freeform records that don't need one.
  final String? key;
  final String valueText;
  final MemorySource source;

  /// 0.0–1.0 when [source] is `inferred`; null for user-direct or imported
  /// records, which don't need a confidence score.
  final double? confidence;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final String deviceId;
  final int rev;

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.wireName,
    'key': key,
    'value_text': valueText,
    'source': source.wireName,
    'confidence': confidence,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'deleted_at': deletedAt?.toUtc().toIso8601String(),
    'device_id': deviceId,
    'rev': rev,
  };

  factory MemoryRecord.fromRow(Map<String, Object?> row) {
    return MemoryRecord(
      id: row['id']! as String,
      kind: MemoryKind.fromWire(row['kind']! as String),
      key: row['key'] as String?,
      valueText: row['value_text']! as String,
      source: MemorySource.fromWire(row['source']! as String),
      confidence: row['confidence'] as double?,
      createdAt: DateTime.parse(row['created_at']! as String).toUtc(),
      updatedAt: DateTime.parse(row['updated_at']! as String).toUtc(),
      deletedAt: (row['deleted_at'] as String?) != null
          ? DateTime.parse(row['deleted_at']! as String).toUtc()
          : null,
      deviceId: row['device_id']! as String,
      rev: row['rev']! as int,
    );
  }
}
