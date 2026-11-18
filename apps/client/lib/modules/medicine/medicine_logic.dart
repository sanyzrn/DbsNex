import 'package:nex_client/modules/module_api.dart';

import 'local_values.dart';
import 'medicine_models.dart';
import 'medicine_schedule.dart';

/// Everything the medicine screens work out from a record and a clock —
/// kept free of widgets so it can be tested on its own. No function here
/// knows anything medical: the stock arithmetic only ever uses the
/// person's own numbers, and the expiry and refill states are things to
/// read while the app is open, never alerts that fire.
class MedicineLogic {
  const MedicineLogic._();

  /// A time as the person wrote it, read as a 24-hour "HH:MM" — tolerant of
  /// Persian digits, missing zeros and surrounding space — or null when it
  /// is not a time. "8:3" is 08:03; "25:00" is not a time.
  static String? normalizeTime(String written) {
    final text = LocalValues.ascii(written.trim());
    final match = RegExp(r'^(\d{1,2})[:.](\d{1,2})$').firstMatch(text);
    if (match == null) {
      return null;
    }
    final hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    if (hour > 23 || minute > 59) {
      return null;
    }
    return '${hour < 10 ? '0$hour' : '$hour'}:'
        '${minute < 10 ? '0$minute' : '$minute'}';
  }

  // ------------------------------------------------------- stock

  /// Stock after a logged dose: the person's own `doseUnits` taken off
  /// their own `quantity`, never below zero. Null when either number is
  /// absent — in which case stock does not move at all.
  static int? reduceStock(int? quantity, int? doseUnits) {
    if (quantity == null || doseUnits == null || doseUnits <= 0) {
      return quantity;
    }
    return quantity - doseUnits < 0 ? 0 : quantity - doseUnits;
  }

  /// Stock after a logged dose is deleted: what the log took comes back.
  static int? restoreStock(int? quantity, int? takenUnits) {
    if (quantity == null || takenUnits == null || takenUnits <= 0) {
      return quantity;
    }
    final sum = BigInt.from(quantity) + BigInt.from(takenUnits);
    if (sum > BigInt.from(LocalValues.maxExact)) {
      throw StateError('Stock outside exact range');
    }
    return sum.toInt();
  }

  /// About how many days the recorded stock lasts at the recorded
  /// routine: quantity ÷ (units per dose × times a day × how much of the
  /// week the schedule covers). Null unless the person wrote the stock,
  /// the units per dose and at least one time — the module never invents
  /// a use rate. This is arithmetic on their numbers, not medical advice.
  static int? runsOutInDays({
    required int? quantity,
    required int? doseUnits,
    required MedicineSchedule schedule,
  }) {
    if (quantity == null || quantity <= 0) {
      return quantity == 0 ? 0 : null;
    }
    final perDay = schedule.unitsPerDay(doseUnits);
    if (perDay == null || perDay <= 0) {
      return null;
    }
    final days = (quantity / perDay).floor();
    return days < 0 ? 0 : days;
  }

  /// The person's early warning: at or under the days they chose (ten by
  /// default), it is time to start looking for more.
  static bool runoutWarning(int? days, int warnDays) =>
      days != null && days <= warnDays;

  // ------------------------------------------------------- states

  /// What the list can honestly say about the expiry date the person
  /// wrote: past it, within a week of it, or nothing. Read while the app
  /// is open; nothing fires in the background.
  static ({bool expired, bool soon}) expiryOf(
    DateTime? expiresAt,
    DateTime now,
  ) {
    if (expiresAt == null) {
      return (expired: false, soon: false);
    }
    final today = LocalValues.civil(now.toLocal());
    final day = LocalValues.civil(expiresAt);
    if (!day.isAfter(today)) {
      return (expired: true, soon: false);
    }
    return (expired: false, soon: day.difference(today).inDays <= 7);
  }

  /// The cabinet's longer view of one box: already expired, inside the
  /// next [soonDays], or neither.
  static ({bool expired, bool soon}) expiryBucket(
    DateTime expiresAt,
    DateTime now, {
    int soonDays = 90,
  }) {
    final today = LocalValues.civil(now.toLocal());
    final day = LocalValues.civil(expiresAt);
    if (!day.isAfter(today)) {
      return (expired: true, soon: false);
    }
    return (expired: false, soon: day.difference(today).inDays <= soonDays);
  }

  /// Whether the quantity has reached the refill threshold the person
  /// wrote. False when either number is absent.
  static bool needsRefill(int? quantity, int? refillThreshold) {
    if (quantity == null || refillThreshold == null) {
      return false;
    }
    return quantity <= refillThreshold;
  }

  /// The doses that belong to [medicineId], the newest first, in the order
  /// the store returned them. A log whose `medicineId` is missing or
  /// wrong-typed belongs to no medicine — it is dropped rather than guessed
  /// onto someone's list.
  static List<ModuleRecord> dosesFor(
    Iterable<ModuleRecord> doses,
    String medicineId,
  ) => [
    for (final dose in doses)
      if (MedicineModels.readString(dose.body, 'medicineId') == medicineId)
        dose,
  ];

  /// The boxes that belong to [medicineId], newest first as the store
  /// returned them.
  static List<ModuleRecord> boxesFor(
    Iterable<ModuleRecord> boxes,
    String medicineId,
  ) => [
    for (final box in boxes)
      if (MedicineModels.readString(box.body, 'medicineId') == medicineId) box,
  ];

  /// The places logged for [medicineId], newest first as the store
  /// returned them.
  static List<ModuleRecord> sourcesFor(
    Iterable<ModuleRecord> sources,
    String medicineId,
  ) => [
    for (final source in sources)
      if (MedicineModels.readString(source.body, 'medicineId') == medicineId)
        source,
  ];

  /// Whether a new medicine may be written: a name, at least. The
  /// duplicate-name question is the screen's to ask, not the writer's to
  /// answer — a person may well keep two things with one name.
  static bool canSave(String name) => name.trim().isNotEmpty;

  /// Two names are the same entry when they match ignoring case and
  /// surrounding space — what a person would read as the same word.
  static bool sameName(String a, String b) =>
      a.trim().toLowerCase() == b.trim().toLowerCase();

  /// Whether a routine time named [time] on [day] is still ahead.
  static bool isAhead(DateTime time, DateTime now) => time.isAfter(now);
}
