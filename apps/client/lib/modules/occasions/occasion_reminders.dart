import 'package:nex_client/modules/module_api.dart';

import 'occasion_math.dart';
import 'occasion_model.dart';

/// An occasion's device alerts. A platform reminder is a one-time alarm, and
/// a yearly date has no honest yearly alarm in a module — so two are kept
/// ahead, for the next two times it falls, and they are made again whenever
/// the module opens or the occasion is saved. A date that is never opened
/// for two years goes quiet; the screen says so rather than promising more.
const _slots = ['a', 'b'];

String occasionReminderKey(String id, String slot) => 'occ:$id:$slot';

/// The alarms an occasion would have right now: the first two moments —
/// "[remindDays] days before, at the chosen time" — that are still ahead.
List<DateTime> occasionAlarms(Occasion occasion, DateTime now) {
  final days = occasion.remindDays;
  if (days == null || occasion.muted || occasion.archived || !occasion.valid) {
    return const [];
  }
  final hour = occasion.remindMinutes ~/ 60;
  final minute = occasion.remindMinutes % 60;
  final alarms = <DateTime>[];
  for (final day in upcomingDays(occasion, now, 4)) {
    final at = DateTime(
      day.date.year,
      day.date.month,
      day.date.day - days,
      hour,
      minute,
    );
    if (at.isAfter(now)) alarms.add(at);
    if (alarms.length == _slots.length) break;
  }
  return alarms;
}

/// Sets the occasion's alarms (and clears the ones it no longer has).
/// Returns false if any alarm could not be set — no permission, reminders
/// not yet available — which the caller may say, once, to the person.
Future<bool> armOccasionReminders(
  NexModuleStore store,
  Occasion occasion, {
  required DateTime now,
  required String title,
  required String body,
}) async {
  final alarms = occasionAlarms(occasion, now);
  var ok = true;
  for (var i = 0; i < _slots.length; i++) {
    final key = occasionReminderKey(occasion.id, _slots[i]);
    if (i < alarms.length) {
      final set = await store.setReminder(
        key,
        sourceKind: 'occasion',
        sourceId: occasion.id,
        at: alarms[i],
        title: title,
        body: body,
      );
      ok = ok && set;
    } else {
      await store.clearReminder(key);
    }
  }
  return ok;
}

Future<void> clearOccasionReminders(NexModuleStore store, String id) async {
  for (final slot in _slots) {
    await store.clearReminder(occasionReminderKey(id, slot));
  }
}
