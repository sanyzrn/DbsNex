/// Civil days are UTC coordinates, not elapsed local midnight durations.
String wordsIsoDay(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
DateTime? wordsParseDay(String value) {
  if (!RegExp(r'^[0-9]{4}-[0-9]{2}-[0-9]{2}$').hasMatch(value)) return null;
  final year = int.parse(value.substring(0, 4));
  if (year < 1) return null;
  final result = DateTime.utc(
    year,
    int.parse(value.substring(5, 7)),
    int.parse(value.substring(8, 10)),
  );
  return wordsIsoDay(result) == value ? result : null;
}

String? wordsValidStamp(String value) {
  if (value.length < 10 || wordsParseDay(value.substring(0, 10)) == null) {
    return null;
  }
  if (value.length > 10) {
    final match = RegExp(
      r'^[0-9]{4}-[0-9]{2}-[0-9]{2}T([0-9]{2}):([0-9]{2})(?::([0-9]{2})(?:\.[0-9]+)?)?(?:Z|[+-][0-9]{2}:?[0-9]{2})?$',
    ).firstMatch(value);
    if (match == null ||
        int.parse(match[1]!) > 23 ||
        int.parse(match[2]!) > 59 ||
        (match[3] != null && int.parse(match[3]!) > 59)) {
      return null;
    }
  }
  final offset = RegExp(r'[+-]([0-9]{2}):?([0-9]{2})$').firstMatch(value);
  if (offset != null &&
      (int.parse(offset[1]!) > 23 || int.parse(offset[2]!) > 59)) {
    return null;
  }
  return DateTime.tryParse(value) == null ? null : value;
}

String? wordsStampDay(String value) {
  if (wordsValidStamp(value) == null) return null;
  return wordsIsoDay(DateTime.parse(value).toLocal());
}
