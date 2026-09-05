import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/reminders.dart';
import 'package:nex_core/nex_core.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// The scheduling math that never touches the platform: the next occurrence
/// of a repeating reminder, and the alarm-id space. Everything here used to
/// have a silent failure mode — a daily series older than ~26 months retired
/// itself, and a note id hashing to 0/1/2 fought the daily nudge for its
/// alarm slot forever.
void main() {
  group('computeNextOccurrence', () {
    test('a future one-off is returned as-is', () {
      final now = DateTime(2026, 1, 10, 12);
      final at = DateTime(2026, 1, 11, 9);
      // Compared as instants: a local and a UTC DateTime at the same moment
      // are the same moment.
      expect(
        NexReminders.computeNextOccurrence(at, NoteRepeat.once, now).toUtc(),
        at.toUtc(),
      );
    });

    test('a daily series advances to tomorrow at the same wall clock', () {
      final now = DateTime(2026, 1, 10, 12);
      final start = DateTime(2026, 1, 10, 9);
      final next = NexReminders.computeNextOccurrence(
        start,
        NoteRepeat.daily,
        now,
      ).toLocal();
      expect(next.day, 11);
      expect(next.hour, 9, reason: 'the clock face is kept, not 24 hours added');
    });

    test('a daily series started 900 days ago still schedules', () {
      // The old one-day-at-a-time walk hit its 800-step guard at ~26 months
      // and returned the still-past start, which schedule() then refused to
      // schedule: a reminder someone still wanted, silently retired.
      final now = DateTime(2026, 1, 10, 12);
      final start = DateTime(2023, 7, 15, 9);
      final next = NexReminders.computeNextOccurrence(
        start,
        NoteRepeat.daily,
        now,
      );
      expect(next.isAfter(now.toUtc()), isTrue);
      final local = next.toLocal();
      expect(local.hour, 9);
      expect(local.minute, 0);
    });

    test('a weekly series started years ago lands on the right weekday', () {
      final now = DateTime(2026, 1, 10, 12); // a Saturday
      final start = DateTime(2024, 2, 3, 8, 30); // also a Saturday
      final next = NexReminders.computeNextOccurrence(
        start,
        NoteRepeat.weekly,
        now,
      ).toLocal();
      expect(next.isAfter(now), isTrue);
      expect(next.weekday, start.weekday);
      expect(next.hour, 8);
      expect(next.minute, 30);
    });

    test('a start in the next DST-spring gap still lands after now', () {
      // Tehran abolished DST in 2022, but the wall-clock arithmetic has to
      // survive zones that still have it: a nonexistent wall time must not
      // produce a start that is somehow "before now" forever.
      final now = DateTime(2026, 3, 8, 12, 0); // US spring-forward morning
      final start = DateTime(2026, 3, 1, 2, 30); // daily at 2:30, in the gap
      final next = NexReminders.computeNextOccurrence(
        start,
        NoteRepeat.daily,
        now,
      );
      expect(next.isAfter(now.toUtc()), isTrue);
    });
  });

  group('scheduledDateFor', () {
    // The conversion that decides what the operating system is actually told,
    // and until now nothing here could execute it: `schedule` returns on its
    // first line off a phone, so every line below that — this one included —
    // was unreachable from the whole suite. Every other test in this file
    // also runs where the machine's zone is UTC, which makes `toLocal` and
    // `toUtc` do nothing, so no test has ever crossed a zone boundary either.
    setUpAll(tz_data.initializeTimeZones);

    test('the clock face the OS is given is the one that was picked', () {
      final tehran = tz.getLocation('Asia/Tehran');
      // Ten in the morning in Tehran, stored the way a reminder is stored:
      // as an instant, in UTC, which is 06:30 — a different clock face for
      // the same moment.
      final picked = tz.TZDateTime(tehran, 2026, 9, 4, 10, 0);
      final stored = picked.toUtc();
      expect(stored.hour, 6, reason: 'the stored instant is not 10 anywhere');

      final scheduled = NexReminders.scheduledDateFor(stored, tehran);

      expect(scheduled.hour, 10);
      expect(scheduled.minute, 0);
      expect(scheduled.location.name, 'Asia/Tehran');
      expect(
        scheduled.millisecondsSinceEpoch,
        picked.millisecondsSinceEpoch,
        reason: 'the moment must not move, only the way it is written',
      );
    });

    test('a half-hour zone is not rounded to the hour', () {
      // Tehran is +03:30. A conversion that only ever handled whole hours
      // would land this on the hour and nothing else in the suite would
      // notice, because the suite runs in UTC where the offset is zero.
      final tehran = tz.getLocation('Asia/Tehran');
      final picked = tz.TZDateTime(tehran, 2026, 9, 4, 9, 15);
      final scheduled = NexReminders.scheduledDateFor(picked.toUtc(), tehran);
      expect(scheduled.hour, 9);
      expect(scheduled.minute, 15);
    });

    test('a zone that failed to load keeps the instant, loses the face', () {
      // What happens when `FlutterTimezone` hands back a name the database
      // does not know: `tz.local` stays UTC. The one-off firing survives that
      // — it is an instant — which is exactly why the gap went unnoticed for
      // so long. A repeat does not: it matches on the clock face below, and
      // that face is no longer the one anybody chose.
      final tehran = tz.getLocation('Asia/Tehran');
      final picked = tz.TZDateTime(tehran, 2026, 9, 4, 10, 0);

      final scheduled = NexReminders.scheduledDateFor(picked.toUtc(), tz.UTC);

      expect(
        scheduled.millisecondsSinceEpoch,
        picked.millisecondsSinceEpoch,
        reason: 'the first firing is still the right moment',
      );
      expect(scheduled.hour, 6, reason: 'but the clock face is not 10');
    });
  });

  group('idFor', () {
    test('no hash in the reserved block survives as a reserved id', () {
      // 0 is the daily nudge, 1 and 2 the diagnostics, 3 the update
      // download. A note reminder keyed on a hash can land on any of them,
      // and sharing an id means each silently cancels the other forever.
      //
      // Driven through `unreserved` rather than `idFor`, because a test that
      // hopes some string hashes into a four-id window never reaches the
      // arithmetic it is about — which is how the bump went on adding 3 to a
      // block that had grown to four, mapping a hash of 0 straight onto the
      // download notification.
      for (var id = 0; id < NexReminders.reservedIds + 2; id++) {
        expect(
          NexReminders.unreserved(id),
          greaterThanOrEqualTo(NexReminders.reservedIds),
          reason: 'hash $id landed inside the reserved block',
        );
      }
    });

    test('leaves an id outside the block alone', () {
      // The bump is for the block, not a general offset: every other note
      // must keep the id its hash already gave it, or upgrading the app
      // would orphan every alarm the OS is already holding.
      expect(
        NexReminders.unreserved(NexReminders.reservedIds),
        NexReminders.reservedIds,
      );
      expect(NexReminders.unreserved(4242), 4242);
    });

    test('is stable for the same note id', () {
      expect(NexReminders.idFor('abc'), NexReminders.idFor('abc'));
    });
  });

  group('scheduleModeFor', () {
    // `schedule` returns early on anything that is not Android, so this
    // decision is unreachable from a test host through the normal path —
    // which is how `alarmClock` shipped and stayed.
    test('an exact-alarm phone gets an exact, Doze-exempt alarm', () {
      expect(
        NexReminders.scheduleModeFor(exactAllowed: true),
        AndroidScheduleMode.exactAllowWhileIdle,
      );
    });

    test('a phone that refuses exact alarms still gets a reminder', () {
      // Late is bad; never is worse. The fallback is what makes the
      // exact-alarm permission optional rather than load-bearing.
      expect(
        NexReminders.scheduleModeFor(exactAllowed: false),
        AndroidScheduleMode.inexactAllowWhileIdle,
      );
    });

    test('a reminder is never scheduled as an alarm clock', () {
      // The one that would have caught the report. `alarmClock` becomes
      // `AlarmManager.setAlarmClock`, which Android documents as telling the
      // user about the alarm: the status-bar alarm icon and the quick
      // settings tile, showing the next alarm clock on the *device*. Every
      // note reminder sooner than the owner's real alarm replaced it there,
      // and tapping it opened Nex instead of the clock — the plugin passes
      // the notification's own intent as the `AlarmClockInfo` show intent.
      //
      // Asserted for both answers, because the bug was in one branch of a
      // two-branch decision and a case that only drives the other proves
      // nothing about it.
      for (final exactAllowed in [true, false]) {
        expect(
          NexReminders.scheduleModeFor(exactAllowed: exactAllowed),
          isNot(AndroidScheduleMode.alarmClock),
          reason: 'a note is not an alarm clock (exactAllowed: $exactAllowed)',
        );
      }
    });
  });
}
