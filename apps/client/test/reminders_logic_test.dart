import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/reminders.dart';
import 'package:nex_core/nex_core.dart';

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
}
