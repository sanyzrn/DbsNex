import 'package:nex_core/nex_core.dart';
import 'package:test/test.dart';

/// The date arithmetic is the whole of this feature. Everything else about a
/// commitment is a row in a table; what makes it worth having is that ticking
/// one off puts it back in the right place, and "the right place" is a
/// surprisingly sharp question once months, leap years and sleep are involved.
void main() {
  NexCommitment make({
    required NexCadence cadence,
    required int every,
    required DateTime dueAt,
    Duration? lead,
    int? windowStart,
    int? windowEnd,
    int metToday = 0,
    String? metTodayOn,
    bool paused = false,
  }) => NexCommitment(
    id: 'c1',
    title: 'a thing',
    cadence: cadence,
    every: every,
    dueAt: dueAt,
    lead: lead,
    windowStart: windowStart,
    windowEnd: windowEnd,
    metToday: metToday,
    metTodayOn: metTodayOn,
    paused: paused,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  group('rolling forward', () {
    test('keeps its place in the cycle, not the day it was done', () {
      // Rent due on the 1st, paid on the 3rd. Next month it is still the 1st.
      // Counting from the moment it was met would walk it two days later
      // every single month until it had lapped the calendar.
      final rent = make(
        cadence: NexCadence.months,
        every: 1,
        dueAt: DateTime(2026, 3, 1, 9),
      );
      expect(rent.met(DateTime(2026, 3, 3, 18)).dueAt, DateTime(2026, 4, 1, 9));
    });

    test('the 31st survives February', () {
      // The subtle one, and the reason months are counted from the original
      // date rather than one step at a time. Stepping takes 31 Jan to 28 Feb
      // — correctly — and then takes *that* to 28 March, and the 31st is gone
      // for good: somebody's rent quietly moved three days earlier, forever.
      final monthly = make(
        cadence: NexCadence.months,
        every: 1,
        dueAt: DateTime(2026, 1, 31, 9),
      );
      final february = monthly.met(DateTime(2026, 1, 31, 10));
      expect(february.dueAt, DateTime(2026, 2, 28, 9));

      final march = february.met(DateTime(2026, 2, 28, 10));
      expect(
        march.dueAt,
        DateTime(2026, 3, 28, 9),
        reason: 'from the 28th, the next month is the 28th',
      );
    });

    test('a yearly commitment gets the 29th of February back', () {
      // Same arithmetic, seen from four years away.
      final leap = make(
        cadence: NexCadence.years,
        every: 1,
        dueAt: DateTime(2024, 2, 29, 9),
      );
      expect(leap.met(DateTime(2024, 3)).dueAt, DateTime(2025, 2, 28, 9));
    });

    test('something missed for a year still lands in the future', () {
      // Advancing by exactly one period from a date thirteen months stale
      // gives a date twelve months stale, and the commitment is overdue
      // forever however many times it is ticked off.
      final stale = make(
        cadence: NexCadence.months,
        every: 1,
        dueAt: DateTime(2025, 1, 1, 9),
      );
      final next = stale.met(DateTime(2026, 3, 15, 12)).dueAt;
      expect(next.isAfter(DateTime(2026, 3, 15, 12)), isTrue);
      expect(next, DateTime(2026, 4, 1, 9), reason: 'still the 1st');
    });

    test('the fixed-length cadences are plain addition', () {
      expect(
        make(
          cadence: NexCadence.hours,
          every: 8,
          dueAt: DateTime(2026, 3, 1, 8),
        ).met(DateTime(2026, 3, 1, 8, 5)).dueAt,
        DateTime(2026, 3, 1, 16),
      );
      expect(
        make(
          cadence: NexCadence.weeks,
          every: 1,
          dueAt: DateTime(2026, 3, 2, 9),
        ).met(DateTime(2026, 3, 2, 10)).dueAt,
        DateTime(2026, 3, 9, 9),
      );
      expect(
        make(
          cadence: NexCadence.days,
          every: 3,
          dueAt: DateTime(2026, 3, 2, 9),
        ).met(DateTime(2026, 3, 2, 10)).dueAt,
        DateTime(2026, 3, 5, 9),
      );
    });
  });

  group('the waking window', () {
    test('leaves an occurrence that already falls inside it alone', () {
      final water = make(
        cadence: NexCadence.hours,
        every: 2,
        dueAt: DateTime(2026, 3, 1, 10),
        windowStart: 8 * 60,
        windowEnd: 23 * 60,
      );
      expect(
        water.met(DateTime(2026, 3, 1, 10, 1)).dueAt,
        DateTime(2026, 3, 1, 12),
      );
    });

    test('pushes one that would land at night to the next morning', () {
      // Water every two hours is twelve times a day without this, three of
      // them while you are asleep. This is the whole reason the window
      // exists.
      final water = make(
        cadence: NexCadence.hours,
        every: 2,
        dueAt: DateTime(2026, 3, 1, 22),
        windowStart: 8 * 60,
        windowEnd: 23 * 60,
      );
      expect(
        water.met(DateTime(2026, 3, 1, 22, 1)).dueAt,
        DateTime(2026, 3, 2, 8),
      );
    });

    test('only the hourly cadence has one', () {
      // A monthly commitment with a window would be a monthly commitment
      // whose date could be silently moved, which is not a service.
      final monthly = make(
        cadence: NexCadence.months,
        every: 1,
        dueAt: DateTime(2026, 3, 1, 3),
        windowStart: 8 * 60,
        windowEnd: 23 * 60,
      );
      expect(
        monthly.met(DateTime(2026, 3, 1, 4)).dueAt,
        DateTime(2026, 4, 1, 3),
        reason: 'three in the morning, because that is what it was set to',
      );
    });
  });

  group('how far ahead it is worth saying', () {
    test('follows the cadence unless it has been told otherwise', () {
      // An insurance renewal eleven months out is not news; five days out it
      // is the most useful sentence the app has.
      expect(nexDefaultLead(NexCadence.years, 1), const Duration(days: 7));
      expect(nexDefaultLead(NexCadence.months, 1), const Duration(days: 2));
      expect(nexDefaultLead(NexCadence.weeks, 1), const Duration(days: 1));
      // A quarter of the gap. Zero was the first answer and it meant an
      // eight-hourly tablet was never mentioned until it was already due —
      // so the morning brief could never say the next one is at four.
      expect(nexDefaultLead(NexCadence.hours, 2), const Duration(minutes: 30));
      expect(nexDefaultLead(NexCadence.hours, 8), const Duration(hours: 2));
    });

    test('a lead that was set is kept, and one that was not follows', () {
      final asked = make(
        cadence: NexCadence.years,
        every: 1,
        dueAt: DateTime(2026, 6),
        lead: const Duration(days: 30),
      );
      expect(asked.effectiveLead, const Duration(days: 30));
      final left = make(
        cadence: NexCadence.years,
        every: 1,
        dueAt: DateTime(2026, 6),
      );
      expect(left.effectiveLead, const Duration(days: 7));
    });

    test('waiting is the lead window, and overdue is always waiting', () {
      final insurance = make(
        cadence: NexCadence.years,
        every: 1,
        dueAt: DateTime(2026, 6, 10, 9),
      );
      expect(insurance.isWaiting(DateTime(2026, 5, 10)), isFalse);
      expect(insurance.isWaiting(DateTime(2026, 6, 5)), isTrue);
      // Its moment passing does not make it stop mattering.
      expect(insurance.isWaiting(DateTime(2026, 7)), isTrue);
      expect(insurance.isOverdue(DateTime(2026, 7)), isTrue);
    });

    test('a paused commitment is never waiting and never overdue', () {
      final paused = make(
        cadence: NexCadence.months,
        every: 1,
        dueAt: DateTime(2025),
        paused: true,
      );
      expect(paused.isWaiting(DateTime(2026, 6)), isFalse);
      expect(paused.isOverdue(DateTime(2026, 6)), isFalse);
    });
  });

  group("today's tally", () {
    test('counts the hourly ones and nothing else', () {
      // Six identical lines saying water is due is not a brief, it is a
      // broken one — so the brief says "3 of 7 today" instead, and this is
      // where the 7 comes from.
      expect(
        make(
          cadence: NexCadence.hours,
          every: 2,
          dueAt: DateTime(2026, 3, 1, 10),
          windowStart: 8 * 60,
          windowEnd: 23 * 60,
        ).timesPerDay,
        7,
        reason: 'fifteen waking hours, one every two',
      );
      expect(
        make(
          cadence: NexCadence.hours,
          every: 8,
          dueAt: DateTime(2026, 3, 1, 8),
        ).timesPerDay,
        3,
        reason: 'no window, so the whole day',
      );
      expect(
        make(
          cadence: NexCadence.months,
          every: 1,
          dueAt: DateTime(2026, 3, 1),
        ).timesPerDay,
        isNull,
      );
    });

    test('resets itself when the day rolls over', () {
      // Without anything having to run at midnight: the stored day key simply
      // stops matching.
      final water = make(
        cadence: NexCadence.hours,
        every: 2,
        dueAt: DateTime(2026, 3, 1, 10),
        metToday: 3,
        metTodayOn: '2026-03-01',
      );
      expect(water.metOn(DateTime(2026, 3, 1, 22)), 3);
      expect(water.metOn(DateTime(2026, 3, 2, 9)), 0);
    });

    test('counting up starts again on a new day', () {
      final water = make(
        cadence: NexCadence.hours,
        every: 2,
        dueAt: DateTime(2026, 3, 1, 10),
        metToday: 3,
        metTodayOn: '2026-03-01',
      );
      expect(water.met(DateTime(2026, 3, 1, 12)).metToday, 4);
      expect(water.met(DateTime(2026, 3, 2, 9)).metToday, 1);
    });
  });
}
