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
  }) async {
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
    if (ok) await _remember(store, id, minutes);
    return ok;
  }

  /// Takes the reminder back, and forgets its minutes.
  static Future<void> disarm(NexModuleStore store, String id) async {
    await store.clearReminder(key(id));
    await _remember(store, id, null);
  }

  /// After [id] was saved with a new paid time: the reminder moves with it,
  /// or goes when it no longer fits. A parking whose reminder was set for a
  /// moment of its own (no minutes kept) is left as it is.
  static Future<void> follow(
    BuildContext context,
    NexModuleStore store,
    String id,
  ) async {
    final body = await store.get(ParkingModels.session, id);
    if (body == null) return;
    final minutes = minutesOf(body);
    if (minutes == null) return;
    final expiresAt = ParkingModels.readDate(body, 'expiresAt');
    if (expiresAt == null ||
        !ParkingLogic.isActive(body) ||
        !ParkingLogic.reminderFits(expiresAt, minutes, DateTime.now())) {
      await disarm(store, id);
      return;
    }
    if (!context.mounted) return;
    final ok = await arm(
      context,
      store,
      id,
      expiresAt: expiresAt,
      minutes: minutes,
      place: ParkingModels.readString(body, 'place'),
    );
    if (!ok) await disarm(store, id);
  }

  static Future<void> _remember(
    NexModuleStore store,
    String id,
    int? minutes,
  ) => LocalWrites.serial(store, () async {
    final raw = await store.get(ParkingModels.session, id);
    if (raw == null) return;
    final next = {...raw};
    if (minutes == null) {
      if (!next.containsKey('remindMinutes')) return;
      next.remove('remindMinutes');
    } else {
      if (next['remindMinutes'] == minutes) return;
      next['remindMinutes'] = minutes;
    }
    await LocalWrites.apply(store, [
      (kind: ParkingModels.session, id: id, body: next),
    ]);
  });
}
