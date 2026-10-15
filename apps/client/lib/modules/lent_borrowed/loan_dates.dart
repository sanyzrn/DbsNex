import 'loan_model.dart';

DateTime? parseCivilDate(String key) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(key)) return null;
  final date = DateTime.tryParse(key);
  if (date == null || civilDateKey(date) != key) return null;
  return DateTime.utc(date.year, date.month, date.day);
}

int? civilDaysBetween(String from, String to) {
  final start = parseCivilDate(from);
  final end = parseCivilDate(to);
  return start == null || end == null ? null : end.difference(start).inDays;
}

String shiftCivilDate(DateTime anchor, int days) =>
    civilDateKey(DateTime.utc(anchor.year, anchor.month, anchor.day + days));

/// Relative inputs are anchored when the editor opens. A title-only edit,
/// even across midnight, preserves both stored dates exactly.
class LoanDates {
  LoanDates(this.anchor, this.loan);
  final DateTime anchor;
  final Loan? loan;

  int get issueOffset => loan == null
      ? 0
      : civilDaysBetween(loan!.issued, civilDateKey(anchor)) ?? 0;
  int? get dueOffset => loan?.due == null
      ? null
      : civilDaysBetween(civilDateKey(anchor), loan!.due!);

  String issued(int daysAgo) => loan != null && daysAgo == issueOffset
      ? loan!.issued
      : shiftCivilDate(anchor, -daysAgo);
  String? due(int? daysFromToday) => daysFromToday == null
      ? null
      : loan?.due != null && daysFromToday == dueOffset
      ? loan!.due
      : shiftCivilDate(anchor, daysFromToday);
}
