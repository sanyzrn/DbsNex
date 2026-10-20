import 'loan_model.dart';

DateTime? parseCivilDate(String key) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(key)) return null;
  final date = DateTime.tryParse(key);
  if (date == null || civilDateKey(date) != key) return null;
  return DateTime.utc(date.year, date.month, date.day);
}

/// Whole civil days from [from] to [to], so no DST shift can bend a
/// deadline. Null when either key is not a real date.
int? civilDaysBetween(String from, String to) {
  final start = parseCivilDate(from);
  final end = parseCivilDate(to);
  return start == null || end == null ? null : end.difference(start).inDays;
}

String shiftCivilDate(DateTime anchor, int days) =>
    civilDateKey(DateTime.utc(anchor.year, anchor.month, anchor.day + days));
