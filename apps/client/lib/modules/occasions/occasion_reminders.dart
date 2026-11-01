import 'package:nex_client/modules/module_api.dart';

import 'module.dart';
import 'occasion_math.dart';
import 'occasion_model.dart';

/// An occasion's device alerts.
///
/// A platform reminder is a one-time alarm, and a yearly date has no honest
/// yearly alarm in a module — so the alarms for the next two times it falls
/// are kept ahead, and made again whenever Nex starts or comes back to the
/// front (through the module's `keepUp`, 2.4.0), when the module opens and
/// when the occasion is saved. A date keeps ringing year after year without
/// its screen being opened.
///
/// Two kinds (2.4.0): «N days before», when the person chose a day ahead, and
/// always on the day itself — the moment a greeting is actually sent. Before,
/// a reminder a day ahead was the only one, and the day itself went silent.
enum OccasionAlarmKind { before, onDay }

typedef OccasionAlarm = ({
  DateTime at,
  OccasionAlarmKind kind,
  OccasionDay day,
});

const _beforeSlots = ['a', 'b'];
const _onDaySlots = ['c', 'd'];

String occasionReminderKey(String id, String slot) => 'occ:$id:$slot';

/// The alarms an occasion has right now: for each kind, the first two
/// moments still ahead, at the chosen time of day.
List<OccasionAlarm> occasionAlarmPlan(Occasion occasion, DateTime now) {
  final days = occasion.remindDays;
  if (days == null || occasion.muted || occasion.archived || !occasion.valid) {
    return const [];
  }
  final hour = occasion.remindMinutes ~/ 60;
  final minute = occasion.remindMinutes % 60;
  final before = <OccasionAlarm>[];
  final onDay = <OccasionAlarm>[];
  for (final day in upcomingDays(occasion, now, 4)) {
    DateTime at(int ahead) => DateTime(
      day.date.year,
      day.date.month,
      day.date.day - ahead,
      hour,
      minute,
    );
    if (days > 0 && before.length < _beforeSlots.length) {
      final when = at(days);
      if (when.isAfter(now)) {
        before.add((at: when, kind: OccasionAlarmKind.before, day: day));
      }
    }
    if (onDay.length < _onDaySlots.length) {
      final when = at(0);
      if (when.isAfter(now)) {
        onDay.add((at: when, kind: OccasionAlarmKind.onDay, day: day));
      }
    }
  }
  return [...before, ...onDay]..sort((a, b) => a.at.compareTo(b.at));
}

/// When the alarms ring, earliest first.
List<DateTime> occasionAlarms(Occasion occasion, DateTime now) => [
  for (final alarm in occasionAlarmPlan(occasion, now)) alarm.at,
];

/// The notification for [alarm]: the occasion's name with its mark, and when
/// it is, with the age it comes to. A remembrance stays neutral on a lock
/// screen, and so does an occasion with no name.
({String title, String body}) occasionNotification(
  AppLocalizations l10n,
  Occasion occasion,
  OccasionAlarm alarm,
) {
  final strings = occasionsStrings;
  if (occasion.kind == OccasionKind.memorial || occasion.title.isEmpty) {
    return (
      title: strings.text(l10n, 'title'),
      body: strings.text(l10n, 'notifNeutral'),
    );
  }
  final mark = switch (occasion.kind) {
    OccasionKind.birthday => '🎂',
    OccasionKind.anniversary => '💞',
    _ => '📅',
  };
  final years = yearsAt(occasion, alarm.day);
  final age = years == null
      ? ''
      : strings.text(l10n, 'notifAge', {
          'what': strings.text(
            l10n,
            occasion.kind == OccasionKind.birthday ? 'turns' : 'yearN',
            {'n': years},
          ),
        });
  final ahead = alarm.kind == OccasionAlarmKind.onDay
      ? 0
      : occasion.remindDays ?? 0;
  return (
    title: '$mark ${occasion.title}',
    body: switch (ahead) {
      0 => strings.text(l10n, 'notifBodyToday', {'age': age}),
      1 => strings.text(l10n, 'notifBodyTomorrow', {'age': age}),
      _ => strings.text(l10n, 'notifBodyDays', {'n': ahead, 'age': age}),
    },
  );
}

/// Sets the occasion's alarms (and clears the ones it no longer has).
/// Returns false if any alarm could not be set — no permission, reminders
/// not yet available — which the caller may say, once, to the person.
Future<bool> armOccasionReminders(
  NexModuleStore store,
  Occasion occasion, {
  required DateTime now,
  required AppLocalizations l10n,
  bool preserveShown = false,
}) async {
  final plan = occasionAlarmPlan(occasion, now);
  var ok = true;
  for (final (kind, slots) in [
    (OccasionAlarmKind.before, _beforeSlots),
    (OccasionAlarmKind.onDay, _onDaySlots),
  ]) {
    final alarms = plan.where((a) => a.kind == kind).toList();
    for (var i = 0; i < slots.length; i++) {
      final key = occasionReminderKey(occasion.id, slots[i]);
      if (i < alarms.length) {
        final text = occasionNotification(l10n, occasion, alarms[i]);
        final set = await store.setReminder(
          key,
          sourceKind: 'occasion',
          sourceId: occasion.id,
          at: alarms[i].at,
          title: text.title,
          body: text.body,
        );
        ok = ok && set;
      } else {
        await (preserveShown
            ? store.withdrawReminder(key)
            : store.clearReminder(key));
      }
    }
  }
  return ok;
}

/// Every occasion's alarms, made again — as Nex starts, as it returns, and
/// as the module opens. Quiet: a failure is left for the next time.
Future<void> renewOccasionReminders(
  NexModuleStore store,
  AppLocalizations l10n, {
  DateTime? now,
}) async {
  for (final record in await store.list('occasion')) {
    final occasion = Occasion.fromRecord(record);
    if (occasion.remindDays == null) continue;
    try {
      await armOccasionReminders(
        store,
        occasion,
        now: now ?? DateTime.now(),
        l10n: l10n,
        preserveShown: true,
      );
    } catch (_) {
      /* The next time tries again. */
    }
  }
}

Future<void> clearOccasionReminders(NexModuleStore store, String id) async {
  for (final slot in [..._beforeSlots, ..._onDaySlots]) {
    await store.clearReminder(occasionReminderKey(id, slot));
  }
}
