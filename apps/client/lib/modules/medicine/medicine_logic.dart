import 'package:nex_client/modules/module_api.dart';

import 'local_values.dart';
import 'medicine_models.dart';

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

  /// Whether a new medicine may be written: a name, at least. The
  /// duplicate-name question is the screen's to ask, not the writer's to
  /// answer — a person may well keep two things with one name.
  static bool canSave(String name) => name.trim().isNotEmpty;

  /// Two names are the same entry when they match ignoring case and
  /// surrounding space — what a person would read as the same word.
  static bool sameName(String a, String b) =>
      a.trim().toLowerCase() == b.trim().toLowerCase();
}
