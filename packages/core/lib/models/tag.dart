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
