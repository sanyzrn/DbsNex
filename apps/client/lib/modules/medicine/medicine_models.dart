import 'local_values.dart';

/// Medicine cabinet — one folder, the module API and nothing else.
///
/// The record kinds, the stock arithmetic and the honest limits are
/// documented in `README.md`. Nothing in this module reaches past its
/// `NexModuleStore`, and nothing in it checks, advises or schedules
/// anything medical.
class MedicineModels {
  const MedicineModels._();

  /// Record kind: one medicine on the person's list.
  static const medicine = 'medicine';

  /// Record kind: one logged dose, taken or skipped.
  static const dose = 'dose';

  /// How many reference times a medicine may list.
  static const timesLimit = 6;

  // ------------------------------------------------------------- readers

  /// A string field, or '' when missing or wrong-typed.
  static String readString(Map<String, Object?> body, String key) {
    final value = body[key];
    return value is String ? value : '';
  }

  /// A stored ISO 8601 timestamp, or null when missing or unparsable.
  static DateTime? readDate(Map<String, Object?> body, String key) {
    final value = body[key];
    if (value is! String) {
      return null;
    }
    return key == 'expiresAt'
        ? LocalValues.calendar(value)
        : LocalValues.stamp(value);
  }

  /// A non-negative integer, or null when missing or invalid.
  static int? readCount(Map<String, Object?> body, String key) {
    final value = body[key];
    return LocalValues.count(value);
  }

  /// The times the person wrote, as they were stored; anything that is not
  /// a string in the list is dropped rather than guessed at.
  static List<String> readTimes(Map<String, Object?> body) => [
    for (final value
        in body['times'] is List ? body['times']! as List : const [])
      if (value is String &&
          RegExp(r'^(?:[01][0-9]|2[0-3]):[0-5][0-9]$').hasMatch(value))
        value,
  ];

  /// Whether the record is archived. A missing field is false.
  static bool readArchived(Map<String, Object?> body) =>
      body['archived'] == true;

  // -------------------------------------------------------------- writers

  /// The body of a medicine. [quantity] is in whatever units the person
  /// chose and counts in; null means they keep stock themselves. [doseUnits]
  /// is how many units one logged dose uses, when that is unambiguous;
  /// null means stock never falls automatically.
  static Map<String, Object?> medicineBody({
    required String name,
    required String strength,
    required String packageUnit,
    required String instructions,
    required List<String> times,
    required String days,
    required String purpose,
    required int? quantity,
    required int? doseUnits,
    required DateTime? expiresAt,
    required int? refillThreshold,
    required bool archived,
  }) => {
    'v': 1,
    'name': name.trim(),
    'strength': strength.trim(),
    'package': packageUnit.trim(),
    'instructions': instructions,
    'times': times,
    'days': days.trim(),
    'purpose': purpose,
    if (quantity != null) 'quantity': quantity,
    if (doseUnits != null) 'doseUnits': doseUnits,
    if (expiresAt != null) 'expiresAt': expiresAt.toIso8601String(),
    if (refillThreshold != null) 'refillThreshold': refillThreshold,
    'archived': archived,
  };

  /// The body of a logged dose. [takenUnits] is how much stock the log
  /// consumed, when it consumed any — deleting the log gives it back.
  static Map<String, Object?> doseBody({
    required String medicineId,
    required String action,
    required DateTime at,
    int? takenUnits,
  }) => {
    'v': 1,
    'medicineId': medicineId,
    'action': action,
    'at': at.toUtc().toIso8601String(),
    if (takenUnits != null && takenUnits > 0) 'takenUnits': takenUnits,
  };

  /// The two words a dose log can carry: taken or skipped.
  static const taken = 'taken';
  static const skipped = 'skipped';
}
