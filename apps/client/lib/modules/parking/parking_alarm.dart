import 'package:flutter/widgets.dart';
import 'package:nex_client/modules/module_api.dart';

import 'local_writes.dart';
import 'parking_logic.dart';
import 'parking_models.dart';
import 'parking_strings.dart';

/// The reminder a paid parking sets some minutes before its end (2.8.4).
///
/// The minutes are kept on the parking itself (`remindMinutes`), so the
/// reminder follows the paid time when it is changed: moved to the new end,
/// or taken back when the new end leaves no room for it or the paid time is
/// gone. Before, an edited end left the alarm ringing at the old one.
abstract final class ParkingAlarm {
  static String key(String id) => '${ParkingModels.session}:$id';

  /// The minutes a parking's reminder rings before its end; null for none.
  static int? minutesOf(Map<String, Object?> body) {
    final value = body['remindMinutes'];
    return value is int && value > 0 ? value : null;
  }

  /// Sets the reminder [minutes] before [expiresAt] and remembers the
  /// minutes on the record. False when the system refused it.
  static Future<bool> arm(
    BuildContext context,
    NexModuleStore store,
    String id, {
    required DateTime expiresAt,
    required int minutes,
    required String place,
  }) => LocalWrites.serial(store, () async {
    final end = _activeEnd(await store.get(ParkingModels.session, id));
    if (!context.mounted ||
        end == null ||
        !end.isAtSameMomentAs(expiresAt) ||
        !ParkingLogic.reminderFits(end, minutes, DateTime.now())) {
      return false;
    }
    return _arm(context, store, id, end, minutes, place);
  });

  static Future<bool> _arm(
    BuildContext context,
    NexModuleStore store,
    String id,
    DateTime expiresAt,
    int minutes,
    String place,
  ) async {
    final where = place.trim().isEmpty
        ? parkingStrings(context, 'detailsTitle')
        : place.trim();
    final ok = await store.setReminder(
      key(id),
      sourceKind: ParkingModels.session,
      sourceId: id,
      at: ParkingLogic.reminderAt(expiresAt, minutes),
      // What it is and when, in its own words (docs/18, rule 7).
      title: parkingStrings(context, 'reminderTitle', {'minutes': minutes}),
      body: parkingStrings(context, 'reminderBody', {'place': where}),
    );
    if (!ok) return false;
    if (await _remember(store, id, minutes, expectedEnd: expiresAt)) {
      return true;
    }
    // A backup or another writer can replace the session while the device
    // is asking for permission. Do not leave the stale alarm scheduled.
    await store.clearReminder(key(id));
    return false;
  }

  /// Takes the reminder back, and forgets its minutes.
  static Future<void> disarm(NexModuleStore store, String id) =>
      LocalWrites.serial(store, () async {
        await store.clearReminder(key(id));
        await _remember(store, id, null);
      });

  /// Moves a paid-time reminder after its parking was edited.
  static Future<void> follow(
    BuildContext context,
    NexModuleStore store,
    String id,
  ) => LocalWrites.serial(store, () async {
    final body = await store.get(ParkingModels.session, id);
    if (body == null) return;
    final minutes = minutesOf(body);
    if (minutes == null) return;
    final expiresAt = _activeEnd(body);
    if (expiresAt != null &&
        ParkingLogic.reminderFits(expiresAt, minutes, DateTime.now())) {
      if (!context.mounted) return;
      final ok = await _arm(
        context,
        store,
        id,
        expiresAt,
        minutes,
        ParkingModels.readString(body, 'place'),
      );
      if (ok) return;
    }
    await store.clearReminder(key(id));
    await _remember(store, id, null);
  });

  static DateTime? _activeEnd(Map<String, Object?>? body) =>
      body == null || !ParkingLogic.isActive(body)
      ? null
      : ParkingModels.readDate(body, 'expiresAt');

  /// Called only while this store's writes are serialized.
  static Future<bool> _remember(
    NexModuleStore store,
    String id,
    int? minutes, {
    DateTime? expectedEnd,
  }) async {
    final raw = await store.get(ParkingModels.session, id);
    if (raw == null) return false;
    if (expectedEnd != null &&
        _activeEnd(raw)?.isAtSameMomentAs(expectedEnd) != true) {
      return false;
    }
    final next = {...raw};
    if (minutes == null) {
      if (!next.containsKey('remindMinutes')) return true;
      next.remove('remindMinutes');
    } else {
      if (next['remindMinutes'] == minutes) return true;
      next['remindMinutes'] = minutes;
    }
    await LocalWrites.apply(store, [
      (kind: ParkingModels.session, id: id, body: next),
    ]);
    return true;
  }
}
