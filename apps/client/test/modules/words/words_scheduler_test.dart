import 'package:flutter_test/flutter_test.dart';

import 'package:nex_client/modules/words/words_models.dart';
import 'package:nex_client/modules/words/words_scheduler.dart';

/// The deterministic ladder: every rule stated in the scheduler's docs,
/// checked against fixed days — including month ends, a year end and a
/// leap day. No clock is consulted anywhere.
void main() {
  WordCard card({
    String id = 'c1',
    String headword = 'serendipity',
    int step = 0,
    String due = '2026-10-12',
    int lapses = 0,
    int reps = 0,
    List<({String at, WordsGrade grade})> log = const [],
    String lastReviewIso = '',
    bool paused = false,
  }) => WordCard(
    id: id,
    headword: headword,
    language: 'English',
    createdAtIso: '2026-10-01T10:00:00',
    step: step,
    due: due,
    lapses: lapses,
    reps: reps,
    log: log,
    lastReviewIso: lastReviewIso,
    paused: paused,
  );

  group('addDays walks the calendar, not 24-hour spans', () {
    test('over a month end', () {
      expect(isoDay(addDays(DateTime(2026, 10, 30), 3)), '2026-11-02');
      expect(isoDay(addDays(DateTime(2026, 12, 31), 1)), '2027-01-01');
    });

    test('over a year end', () {
      expect(isoDay(addDays(DateTime(2026, 12, 30), 5)), '2027-01-04');
    });

    test('onto and past a leap day', () {
      // 2028 is a leap year; 2027 is not.
      expect(isoDay(addDays(DateTime(2028, 2, 28), 1)), '2028-02-29');
      expect(isoDay(addDays(DateTime(2028, 2, 28), 2)), '2028-03-01');
      expect(isoDay(addDays(DateTime(2027, 2, 28), 1)), '2027-03-01');
    });

    test('day arithmetic cannot land on a made-up date', () {
      // The DateTime constructor normalises, so nothing like
      // «2027-02-30» can ever be produced or stored.
      final day = addDays(DateTime(2027, 1, 31), 1);
      expect(isoDay(day), '2027-02-01');
      expect(day.day, lessThanOrEqualTo(28));
    });
  });

  group('the ladder, answer by answer', () {
    test('a new card, first learning: Good climbs to 3 days', () {
      final answered = answerCard(
        card(),
        WordsGrade.good,
        DateTime(2026, 10, 12, 9),
      );
      expect(answered.step, 1);
      expect(answered.due, '2026-10-15'); // tomorrow is not the rule: 3 days
      expect(answered.reps, 1);
      expect(answered.lapses, 0);
      expect(answered.log, hasLength(1));
      expect(answered.log.single.grade, WordsGrade.good);
    });

    test('Easy climbs two rungs', () {
      final answered = answerCard(
        card(),
        WordsGrade.easy,
        DateTime(2026, 10, 12),
      );
      expect(answered.step, 2);
      expect(answered.due, '2026-10-19'); // 7 days
    });

    test('Hard repeats the current interval', () {
      final answered = answerCard(
        card(step: 3, due: '2026-10-12'),
        WordsGrade.hard,
        DateTime(2026, 10, 12),
      );
      expect(answered.step, 3);
      expect(answered.due, '2026-10-26'); // ladder[3] = 14 again
    });

    test('Again starts over at one day and counts a lapse', () {
      final answered = answerCard(
        card(step: 4, due: '2026-10-12', lapses: 2, reps: 9),
        WordsGrade.again,
        DateTime(2026, 10, 12),
      );
      expect(answered.step, 0);
      expect(answered.due, '2026-10-13'); // tomorrow
      expect(answered.lapses, 3);
      expect(answered.reps, 10);
    });

    test('repeated Again keeps saying tomorrow, never loops longer', () {
      var current = card();
      for (var i = 0; i < 5; i++) {
        current = answerCard(current, WordsGrade.again, DateTime(2026, 10, 12));
        expect(current.due, '2026-10-13');
        expect(current.step, 0);
      }
      expect(current.lapses, 5);
      expect(current.log, hasLength(5));
    });

    test('the ladder tops out at 60 days', () {
      final top = card(step: 5, due: '2026-10-12');
      expect(
        answerCard(top, WordsGrade.good, DateTime(2026, 10, 12)).due,
        '2026-12-11',
      );
      expect(
        answerCard(top, WordsGrade.easy, DateTime(2026, 10, 12)).due,
        '2026-12-11',
      );
      expect(
        answerCard(top, WordsGrade.hard, DateTime(2026, 10, 12)).due,
        '2026-12-11',
      );
    });

    test('the whole climb, from new to learned', () {
      var current = card();
      // Every answer happens on the same day, so every due date is that
      // day plus the new interval — the ladder itself, laid out in dates.
      final reviewedOn = DateTime(2026, 10, 12);
      final dues = <String>[];
      final steps = <int>[];
      for (var i = 0; i < 6; i++) {
        current = answerCard(current, WordsGrade.good, reviewedOn);
        dues.add(current.due);
        steps.add(current.step);
      }
      // 3, 7, 14, 30, then 60 and 60 again — the top of the ladder.
      expect(dues, [
        '2026-10-15',
        '2026-10-19',
        '2026-10-26',
        '2026-11-11',
        '2026-12-11',
        '2026-12-11',
      ]);
      expect(steps, [1, 2, 3, 4, 5, 5]);
    });
  });

  group('an overdue card is scheduled from the day it was answered', () {
    test('a week late, answered Good today', () {
      final overdue = card(step: 1, due: '2026-10-05');
      final answered = answerCard(
        overdue,
        WordsGrade.good,
        DateTime(2026, 10, 12),
      );
      // From today, not from the old due date: 7 days from the 12th.
      expect(answered.due, '2026-10-19');
    });

    test('a card from last year', () {
      final stale = card(step: 2, due: '2025-12-01');
      final answered = answerCard(stale, WordsGrade.good, DateTime(2026, 1, 2));
      expect(answered.due, '2026-01-16'); // step 3 = 14 days from Jan 2
    });
  });

  group('due and overdue words', () {
    test('daysUntil is signed and calendar-based', () {
      expect(daysUntil('2026-10-12', '2026-10-12'), 0);
      expect(daysUntil('2026-10-12', '2026-10-13'), 1);
      expect(daysUntil('2026-10-12', '2026-10-10'), -2);
      expect(daysUntil('2026-10-12', '2026-11-01'), 20);
      // Across a month end, still calendar days, not 24-hour spans.
      expect(daysUntil('2026-10-01', '2026-11-01'), 31);
    });

    test('dueWords separates today, tomorrow, later and overdue', () {
      expect(dueWords('2026-10-12', '2026-10-12').today, isTrue);
      expect(dueWords('2026-10-12', '2026-10-13').tomorrow, isTrue);
      final later = dueWords('2026-10-12', '2026-10-20');
      expect(later.days, 8);
      expect(later.overdue, isFalse);
      final overdue = dueWords('2026-10-12', '2026-10-09');
      expect(overdue.overdue, isTrue);
      expect(overdue.days, 3);
    });

    test('isDueOn: due means on or before today, never paused, never new', () {
      final today = '2026-10-12';
      expect(card(due: today).isDueOn(today), isFalse); // new card
      expect(card(due: today, lastReviewIso: 'x').isDueOn(today), isTrue);
      expect(
        card(due: '2026-10-11', lastReviewIso: 'x').isDueOn(today),
        isTrue,
      );
      expect(
        card(due: '2026-10-13', lastReviewIso: 'x').isDueOn(today),
        isFalse,
      );
      expect(
        card(
          due: '2026-10-10',
          lastReviewIso: 'x',
          paused: true,
        ).isDueOn(today),
        isFalse,
      );
    });
  });

  group('the session queue', () {
    test('due cards first, most overdue first; then new cards in order', () {
      final today = '2026-10-12';
      final session = buildSession(
        cards: [
          card(id: 'new1', headword: 'alpha'),
          card(
            id: 'due2',
            headword: 'beta',
            due: '2026-10-10',
            lastReviewIso: 'x',
          ),
          card(
            id: 'due1',
            headword: 'gamma',
            due: '2026-10-08',
            lastReviewIso: 'x',
          ),
          card(id: 'new2', headword: 'delta'),
          card(
            id: 'future',
            headword: 'eps',
            due: '2026-10-20',
            lastReviewIso: 'x',
          ),
        ],
        todayIso: today,
        newPerDay: 10,
      );
      expect(session.due.map((c) => c.id), ['due1', 'due2']);
      expect(session.fresh.map((c) => c.id), ['new1', 'new2']);
    });

    test('paused and future cards are left out', () {
      final session = buildSession(
        cards: [
          card(id: 'p', due: '2026-10-01', lastReviewIso: 'x', paused: true),
          card(id: 'f', due: '2026-12-01', lastReviewIso: 'x'),
        ],
        todayIso: '2026-10-12',
        newPerDay: 10,
      );
      expect(session.due, isEmpty);
      expect(session.fresh, isEmpty);
    });

    test('the daily cap counts what today already introduced', () {
      final today = '2026-10-12';
      final cards = [
        // Introduced earlier today: its first log entry is this morning.
        card(
          id: 'intro',
          due: '2026-10-15',
          lastReviewIso: '2026-10-12T08:00:00',
          log: [(at: '2026-10-12T08:00:00', grade: WordsGrade.good)],
        ),
        card(id: 'n1'),
        card(id: 'n2'),
        card(id: 'n3'),
      ];
      final session = buildSession(cards: cards, todayIso: today, newPerDay: 3);
      // 3 allowed, 1 already introduced → 2 more today.
      expect(session.fresh.map((c) => c.id), ['n1', 'n2']);
      expect(session.due, isEmpty); // the introduced card is not due yet
    });

    test('no cap means every new card', () {
      final session = buildSession(
        cards: [
          card(id: 'n1'),
          card(id: 'n2'),
          card(id: 'n3'),
        ],
        todayIso: '2026-10-12',
        newPerDay: 0,
      );
      expect(session.fresh, hasLength(3));
    });

    test('a card introduced yesterday does not eat today\'s allowance', () {
      final session = buildSession(
        cards: [
          card(
            id: 'yesterday',
            due: '2026-10-14',
            lastReviewIso: '2026-10-11T08:00:00',
            log: [(at: '2026-10-11T08:00:00', grade: WordsGrade.good)],
          ),
          card(id: 'n1'),
          card(id: 'n2'),
        ],
        todayIso: '2026-10-12',
        newPerDay: 2,
      );
      expect(session.fresh, hasLength(2));
    });
  });

  group('preview matches what the answer will do', () {
    test('the interval under each button is the interval that happens', () {
      final c = card(step: 2, due: '2026-10-12');
      expect(previewIntervalDays(c, WordsGrade.again), 1);
      expect(previewIntervalDays(c, WordsGrade.hard), 7);
      expect(previewIntervalDays(c, WordsGrade.good), 14);
      expect(previewIntervalDays(c, WordsGrade.easy), 30);
      for (final grade in WordsGrade.values) {
        final answered = answerCard(c, grade, DateTime(2026, 10, 12));
        expect(
          daysUntil('2026-10-12', answered.due),
          previewIntervalDays(c, grade),
        );
      }
    });
  });

  group('a huge history stays bounded', () {
    test('the log is capped, the counters are not', () {
      var current = card();
      final day = DateTime(2026, 1, 1);
      for (var i = 0; i < 1000; i++) {
        current = answerCard(current, WordsGrade.good, day);
      }
      expect(current.log.length, WordCard.maxLog);
      expect(current.reps, 1000);
      expect(current.step, 5);
      // The newest entry is the last one given.
      expect(current.log.last.grade, WordsGrade.good);
      // Every answer scheduled from the same day, so the final due is one
      // top-of-ladder interval away from it: 2026-01-01 + 60 days.
      expect(current.due, '2026-03-02');
    });
  });
}
