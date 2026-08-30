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
    test('never collides with the reserved low ids', () {
      // 0 is the daily nudge; 1 and 2 are the diagnostics. The old claim
      // that "zero is not a hash any string produces" was simply false, and
      // a note id landing there would have traded alarms with the nudge on
      // every schedule.
      for (final reserved in const {0, 1, 2}) {
        expect(NexReminders.idFor('note-$reserved'), isNot(reserved));
      }
    });

    test('is stable for the same note id', () {
      expect(NexReminders.idFor('abc'), NexReminders.idFor('abc'));
    });
  });
}
