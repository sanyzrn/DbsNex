import 'local_values.dart';

/// Reading back what the editor's fields hold, kept apart so it can be
/// tested on its own. Nothing here guesses: a value that does not parse
/// says so through its sentinel rather than becoming something plausible.
class ParkingParse {
  const ParkingParse._();

  /// A stand-in the editor compares against: a real parse can never
  /// produce it, so "equal to [invalid]" means "did not parse".
  static final DateTime invalid = DateTime(1800);

  /// A coordinate as written: null when the field is empty (no
  /// coordinate given), [double.nan] when what is written is not a usable
  /// number, and the value otherwise.
  static double? coordinate(String text, double min, double max) {
    if (text.trim().isEmpty) {
      return null;
    }
    final value = double.tryParse(LocalValues.ascii(text.trim()));
    if (value == null || !value.isFinite || value < min || value > max) {
      return double.nan;
    }
    return value;
  }

  static DateTime? expiry(String dateText, String timeText) {
    if (dateText.trim().isEmpty && timeText.trim().isEmpty) {
      return null;
    }
    final date = LocalValues.day(dateText);
    final m = RegExp(
      r'^(\d{1,2}):(\d{1,2})$',
    ).firstMatch(LocalValues.ascii(timeText.trim()));
    if (date == null || m == null) {
      return invalid;
    }
    final hour = int.parse(m[1]!);
    final minute = int.parse(m[2]!);
    if (hour > 23 || minute > 59) {
      return invalid;
    }
    final stamp = DateTime(date.year, date.month, date.day, hour, minute);
    if (stamp.hour != hour || stamp.minute != minute) {
      return invalid;
    }
    return stamp;
  }

  /// A number as it is typed for editing again: no trailing zeros.
  static String coordinateText(double value) {
    return value.toString();
  }

  /// A stored instant as the editor's two fields hold it.
  static (String, String) expiryText(DateTime stamp) {
    final value = stamp.toLocal();
    return (
      '${value.year}/${value.month}/${value.day}',
      '${value.hour}:${value.minute.toString().padLeft(2, '0')}',
    );
  }
}
