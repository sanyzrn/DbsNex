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

  /// Record kind: one box of a medicine, with the day it expires.
  static const box = 'box';

  /// Record kind: one place the medicine was found, what it cost and when.
  static const source = 'source';

  /// Record kind: the module's one preference record.
  static const settings = 'settings';

  /// How many reference times a medicine may list.
  static const timesLimit = 6;

  /// Days before running out that the cabinet warns — editable per
  /// medicine, this is the default the brief asks for.
  static const defaultWarnDays = 10;

  /// The longest "every N days" the editor accepts (a year).
  static const everyDaysLimit = 366;

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

  /// A stored calendar day — the day it was written, never shifted — or
  /// null when missing or impossible.
  static DateTime? readDay(Map<String, Object?> body, String key) {
    final value = body[key];
    if (value is! String) {
      return null;
    }
    return LocalValues.calendar(value);
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

  /// The days of the week the routine names, as Dart numbers
  /// (Monday 1 … Sunday 7). Anything else in the list is dropped.
  static List<int> readWeekdays(Map<String, Object?> body) {
    final raw = body['weekdays'];
    if (raw is! List) {
      return const [];
    }
    final days = <int>{};
    for (final value in raw) {
      if (value is int && value >= 1 && value <= 7) {
        days.add(value);
      }
    }
    return days.toList()..sort();
  }

  /// "Every N days": a whole number from 2 to [everyDaysLimit], or null
  /// when the person wrote nothing (every day).
  static int? readEveryDays(Map<String, Object?> body) {
    final value = readCount(body, 'everyDays');
    return value != null && value >= 2 && value <= everyDaysLimit
        ? value
        : null;
  }

  /// The early warning in days; the brief's default of ten when the person
  /// has not written one.
  static int readWarnDays(Map<String, Object?> body) =>
      readCount(body, 'warnDays') ?? defaultWarnDays;

  /// The person's own note that the medicine is hard to find lately. The
  /// module never decides this for them.
  static bool readHardToFind(Map<String, Object?> body) =>
      body['hardToFind'] == true;

  /// The person this medicine belongs to; '' means "me".
  /// Whose medicine it is; '' for "me". Stored as `{"name": …}`, the shape
  /// every module gives the other party (docs/18, rule 3, 2.8.4); a plain
  /// string, as the upgrade first wrote it, still reads.
  static String readPerson(Map<String, Object?> body) =>
      switch (body['person']) {
        {'name': final String name} => name.trim(),
        final String name => name.trim(),
        _ => '',
      };

  /// Whether the record is archived. A missing field is false.
  static bool readArchived(Map<String, Object?> body) =>
      body['archived'] == true;

  /// A calendar day as ISO text: the day the person means, with no time
  /// and no zone, so it can never land on the day before.
  static String dayText(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${_two(day.month)}-${_two(day.day)}';

  static String _two(int value) => value < 10 ? '0$value' : '$value';

  // -------------------------------------------------------------- writers

  /// The body of a medicine. [quantity] is in whatever units the person
  /// chose and counts in; null means they keep stock themselves. [doseUnits]
  /// is how many units one logged dose uses, when that is unambiguous;
  /// null means stock never falls automatically.
  ///
  /// [person] and the schedule fields were added after the first version;
  /// a record written before them simply lacks them, and reads as "me",
  /// every day, no dates and the default warning.
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
    String person = '',
    List<int> weekdays = const [],
    int? everyDays,
    DateTime? startsOn,
    DateTime? endsOn,
    int? warnDays,
    bool hardToFind = false,
  }) => {
    'v': 3,
    'name': name.trim(),
    'strength': strength.trim(),
    'package': packageUnit.trim(),
    'instructions': instructions,
    'times': times,
    'days': days.trim(),
    'purpose': purpose,
    if (person.trim().isNotEmpty) 'person': {'name': person.trim()},
    'quantity': ?quantity,
    'doseUnits': ?doseUnits,
    if (expiresAt != null) 'expiresAt': expiresAt.toIso8601String(),
    'refillThreshold': ?refillThreshold,
    if (weekdays.isNotEmpty) 'weekdays': weekdays,
    if (everyDays != null && everyDays >= 2) 'everyDays': everyDays,
    if (startsOn != null) 'startsOn': dayText(startsOn),
    if (endsOn != null) 'endsOn': dayText(endsOn),
    'warnDays': ?warnDays,
    if (hardToFind) 'hardToFind': true,
    'archived': archived,
  };

  /// The body of a logged dose. [takenUnits] is how much stock the log
  /// consumed, when it consumed any — deleting the log gives it back.
  /// [slot] names the routine time the log answers, when it was logged
  /// from that time rather than at any moment.
  static Map<String, Object?> doseBody({
    required String medicineId,
    required String action,
    required DateTime at,
    int? takenUnits,
    String? slot,
  }) => {
    'v': 1,
    'medicineId': medicineId,
    'action': action,
    'at': at.toUtc().toIso8601String(),
    if (takenUnits != null && takenUnits > 0) 'takenUnits': takenUnits,
    if (slot != null &&
        RegExp(r'^(?:[01][0-9]|2[0-3]):[0-5][0-9]$').hasMatch(slot))
      'slot': slot,
  };

  /// One box: the day it expires and, if the person counts it, how many
  /// units are inside. The module never sums boxes into stock — the one
  /// `quantity` stays the number a taken dose moves.
  static Map<String, Object?> boxBody({
    required String medicineId,
    required DateTime expiresAt,
    int? units,
    required DateTime addedAt,
  }) => {
    'v': 1,
    'medicineId': medicineId,
    'expiresAt': dayText(expiresAt),
    'units': ?units,
    'addedAt': addedAt.toUtc().toIso8601String(),
  };

  /// One place: where it was found, what it cost in whole rials (the unit
  /// the app stores money in, whatever the person says it in) and the day.
  static Map<String, Object?> sourceBody({
    required String medicineId,
    required String place,
    required int? priceRials,
    required DateTime at,
  }) => {
    'v': 1,
    'medicineId': medicineId,
    'place': place.trim(),
    // Money fields end in Rial (docs/18, rule 2; 2.8.4).
    'priceRial': ?priceRials,
    'at': dayText(at),
  };

  /// A place's price in whole rials; `price`, as the upgrade first wrote
  /// it, still reads.
  static int? readPriceRial(Map<String, Object?> body) =>
      readCount(body, 'priceRial') ?? readCount(body, 'price');

  /// The two words a dose log can carry: taken or skipped.
  static const taken = 'taken';
  static const skipped = 'skipped';
}
