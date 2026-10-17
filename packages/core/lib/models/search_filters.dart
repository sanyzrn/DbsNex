import 'note.dart';

/// Search filters layered on one surface (ADR-011 / FR-4).
class SearchFilters {
  const SearchFilters({
    this.query = '',
    this.tagIds = const [],
    this.createdFrom,
    this.createdTo,
    this.types = const [],
    this.pageSize,
    this.offset = 0,
  });

  final String query;
  final List<String> tagIds;
  final DateTime? createdFrom;
  final DateTime? createdTo;
  final List<NoteType> types;

  /// Optional filter-only paging. Null preserves callers which need the full
  /// filtered set (assistant tools); the interactive search always supplies it.
  final int? pageSize;
  final int offset;

  bool get isEmpty =>
      query.trim().isEmpty &&
      tagIds.isEmpty &&
      createdFrom == null &&
      createdTo == null &&
      types.isEmpty;
}
