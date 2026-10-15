part of 'options.dart';

/// A comparison the person chose to keep, options and all.
class SavedComparison {
  SavedComparison({
    required this.id,
    required this.date,
    required this.options,
    this.commonUnitKey,
    this.source,
  });

  final String id;
  final DateTime date;
  final List<PriceOption> options;
  final String? commonUnitKey;
  final Map<String, Object?>? source;

  Map<String, Object?> toBody() => {
    'date': date.toIso8601String(),
    if (commonUnitKey != null) 'commonUnit': commonUnitKey,
    'options': [for (final option in options) option.toBody()],
    'schema': 2,
  };

  static SavedComparison? fromBody(String id, Map<String, Object?> body) {
    final dateRaw = _stringOf(body, 'date');
    final date = dateRaw == null ? null : priceCalendar(dateRaw);
    final rawOptions = body['options'];
    if (date == null ||
        rawOptions is! List ||
        rawOptions.length < 2 ||
        rawOptions.length > 4) {
      return null;
    }
    final options = <PriceOption>[];
    for (final raw in rawOptions) {
      if (raw is Map<String, Object?>) {
        options.add(PriceOption.fromBody('saved-$id-${options.length}', raw));
      }
    }
    if (options.length != rawOptions.length || options.isEmpty) return null;
    final common = body['commonUnit'];
    if (common != null && (common is! String || priceUnitOf(common) == null)) {
      return null;
    }
    return SavedComparison(
      id: id,
      date: date,
      options: options,
      commonUnitKey: common as String?,
      source: Map.of(body),
    );
  }
}
