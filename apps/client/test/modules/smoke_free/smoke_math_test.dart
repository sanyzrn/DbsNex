import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/smoke_free/money_format.dart';
import 'package:nex_client/modules/smoke_free/quit_model.dart';
import 'package:nex_client/modules/smoke_free/smoke_math.dart';

/// The arithmetic of quitting: whole civil days, integer rials, floors
/// instead of overstatements, and nothing negative — ever.
void main() {
  QuitAttempt attempt({
    required DateTime startedAt,
    int perDay = 20,
    int price = 250000,
    int perPack = 20,
    DateTime? endedAt,
  }) => QuitAttempt(
    id: 'q1',
    startedAt: startedAt,
    cigarettesPerDay: perDay,
    pricePerPackRials: price,
    perPack: perPack,
    endedAt: endedAt,
    endedWhy: endedAt == null ? null : 'lapse',
  );

  group('elapsed days', () {
    test('zero on the first day', () {
      expect(
        SmokeMath.elapsedDays(
          DateTime(2026, 10, 12, 9),
          DateTime(2026, 10, 12, 21),
        ),
        0,
      );
    });

    test('a quit at 23:00 yesterday is one day at 07:00 today', () {
      expect(
        SmokeMath.elapsedDays(
          DateTime(2026, 10, 11, 23),
          DateTime(2026, 10, 12, 7),
        ),
        1,
      );
    });

    test('across midnight, not after 24 hours', () {
      // 25 hours elapsed but only one calendar turn.
      expect(
        SmokeMath.elapsedDays(
          DateTime(2026, 10, 10, 22),
          DateTime(2026, 10, 11, 23),
        ),
        1,
      );
    });

    test('never negative for a future start', () {
      expect(
        SmokeMath.elapsedDays(DateTime(2026, 10, 15), DateTime(2026, 10, 12)),
        0,
      );
    });

    test('a leap day is just a day', () {
      expect(
        SmokeMath.elapsedDays(DateTime(2024, 2, 28), DateTime(2024, 3, 1)),
        2,
      );
    });

    test('a DST boundary cannot shift the count', () {
      expect(
        SmokeMath.elapsedDays(DateTime(2026, 10, 24), DateTime(2026, 10, 27)),
        3,
      );
    });
  });

  group('estimates', () {
    test('the whole arithmetic, exactly', () {
      final p = SmokeMath.progress(
        attempt(
          startedAt: DateTime(2026, 10, 2),
          perDay: 20,
          price: 250000,
          perPack: 20,
        ),
        DateTime(2026, 10, 12),
      );
      expect(p.days, 10);
      expect(p.cigarettesAvoided, 200);
      expect(p.rialsSaved, 2500000);
    });

    test('money is floored, never overstated', () {
      // 2 cigarettes, 100 rials a pack of 7: 200/7 = 28.57 -> 28.
      final p = SmokeMath.progress(
        attempt(
          startedAt: DateTime(2026, 10, 11),
          perDay: 2,
          price: 100,
          perPack: 7,
        ),
        DateTime(2026, 10, 12),
      );
      expect(p.rialsSaved, 28);
    });

    test('a zero baseline estimates zero, without crashing', () {
      final p = SmokeMath.progress(
        attempt(startedAt: DateTime(2026, 10, 2), perDay: 0, price: 0),
        DateTime(2026, 10, 12),
      );
      expect(p.days, 10);
      expect(p.cigarettesAvoided, 0);
      expect(p.rialsSaved, 0);
    });

    test('very large amounts stay exact integers', () {
      final p = SmokeMath.progress(
        attempt(
          startedAt: DateTime(2026, 9, 12),
          perDay: 40,
          price: 1000000000,
        ),
        DateTime(2026, 10, 12),
      );
      expect(p.cigarettesAvoided, 1200);
      expect(p.rialsSaved, 60000000000);
    });

    test('a future start yields zeros, not negatives', () {
      final p = SmokeMath.progress(
        attempt(startedAt: DateTime(2026, 10, 20)),
        DateTime(2026, 10, 12),
      );
      expect(p.days, 0);
      expect(p.cigarettesAvoided, 0);
      expect(p.rialsSaved, 0);
    });
  });

  group('attempts', () {
    test('the active attempt is the newest running one', () {
      final running = attempt(startedAt: DateTime(2026, 10, 1));
      final older = attempt(startedAt: DateTime(2026, 9, 1));
      final ended = attempt(
        startedAt: DateTime(2026, 8, 1),
        endedAt: DateTime(2026, 8, 3),
      );
      expect(SmokeMath.activeAttempt([ended, older, running])!.id, running.id);
      expect(SmokeMath.pastAttempts([ended, older, running]), [ended]);
    });

    test('no active attempt when everything has ended', () {
      final ended = attempt(
        startedAt: DateTime(2026, 8, 1),
        endedAt: DateTime(2026, 8, 3),
      );
      expect(SmokeMath.activeAttempt([ended]), isNull);
    });

    test('the same-instant running attempts resolve deterministically', () {
      final start = DateTime(2026, 10, 1, 9);
      final first = QuitAttempt(
        id: 'q-0001',
        startedAt: start,
        cigarettesPerDay: 10,
        pricePerPackRials: 1000,
        perPack: 20,
        endedAt: null,
        endedWhy: null,
      );
      final second = QuitAttempt(
        id: 'q-0002',
        startedAt: start,
        cigarettesPerDay: 10,
        pricePerPackRials: 1000,
        perPack: 20,
        endedAt: null,
        endedWhy: null,
      );
      // Both orders pick the same, later record — never quicksort's whim.
      expect(SmokeMath.activeAttempt([first, second])!.id, 'q-0002');
      expect(SmokeMath.activeAttempt([second, first])!.id, 'q-0002');
    });

    test('same-start ended attempts keep a deterministic history order', () {
      final start = DateTime(2026, 10, 1, 9);
      QuitAttempt ended(String id) => QuitAttempt(
        id: id,
        startedAt: start,
        cigarettesPerDay: 10,
        pricePerPackRials: 1000,
        perPack: 20,
        endedAt: DateTime(2026, 10, 3),
        endedWhy: 'lapse',
      );
      final a = ended('q-0001');
      final b = ended('q-0002');
      expect(SmokeMath.pastAttempts([a, b]).map((x) => x.id), [
        'q-0002',
        'q-0001',
      ]);
      expect(SmokeMath.pastAttempts([b, a]).map((x) => x.id), [
        'q-0002',
        'q-0001',
      ]);
    });

    test('an attempt ending the same day reports zero calendar boundaries', () {
      final ended = attempt(
        startedAt: DateTime(2026, 8, 1, 9),
        endedAt: DateTime(2026, 8, 1, 21),
      );
      expect(SmokeMath.attemptSpanDays(ended), 0);
      expect(
        SmokeMath.attemptSpanDays(
          attempt(
            startedAt: DateTime(2026, 8, 1),
            endedAt: DateTime(2026, 8, 6),
          ),
        ),
        5,
      );
    });
  });

  group('craving ordering', () {
    Craving craving(String id, DateTime at) => Craving(
      id: id,
      at: at,
      intensity: 2,
      triggers: const [],
      coping: null,
      note: '',
    );

    test('newest first, regardless of insertion order', () {
      final now = DateTime(2026, 10, 12, 15);
      final ordered = SmokeMath.cravingsNewestFirst([
        craving('old', now.subtract(const Duration(days: 2))),
        craving('new', now),
      ]);
      expect(ordered.map((c) => c.id), ['new', 'old']);
    });

    test('the same-instant cravings keep a deterministic order', () {
      final at = DateTime(2026, 10, 12, 15);
      final a = craving('c-0001', at);
      final b = craving('c-0002', at);
      expect(SmokeMath.cravingsNewestFirst([a, b]).map((c) => c.id), [
        'c-0002',
        'c-0001',
      ]);
      expect(SmokeMath.cravingsNewestFirst([b, a]).map((c) => c.id), [
        'c-0002',
        'c-0001',
      ]);
    });

    test('the input list is never reordered in place', () {
      final now = DateTime(2026, 10, 12, 15);
      final input = [
        craving('old', now.subtract(const Duration(days: 1))),
        craving('new', now),
      ];
      SmokeMath.cravingsNewestFirst(input);
      expect(input.map((c) => c.id), ['old', 'new']);
    });
  });

  group('craving grouping and patterns', () {
    test('relative day indices', () {
      final now = DateTime(2026, 10, 12, 15);
      expect(SmokeMath.cravingDayIndex(DateTime(2026, 10, 12, 8), now), 0);
      expect(SmokeMath.cravingDayIndex(DateTime(2026, 10, 11, 22), now), 1);
      expect(SmokeMath.cravingDayIndex(DateTime(2026, 10, 2), now), 10);
    });

    test('trigger counts, most frequent first, ties alphabetical', () {
      final cravings = [
        Craving(
          id: 'a',
          at: DateTime.now(),
          intensity: 2,
          triggers: ['stress', 'coffee'],
          coping: null,
          note: '',
        ),
        Craving(
          id: 'b',
          at: DateTime.now(),
          intensity: 1,
          triggers: ['stress'],
          coping: null,
          note: '',
        ),
        Craving(
          id: 'c',
          at: DateTime.now(),
          intensity: 3,
          triggers: ['boredom'],
          coping: 'water',
          note: '',
        ),
      ];
      final counts = SmokeMath.triggerCounts(cravings);
      expect(counts.first.key, 'stress');
      expect(counts.first.value, 2);
      expect(counts[1].key, 'boredom');
      expect(counts[2].key, 'coffee');
    });

    test('an empty history has no pattern', () {
      expect(SmokeMath.triggerCounts([]), isEmpty);
    });
  });

  group('supportive words', () {
    test('the day thresholds', () {
      expect(supportMessageKey(0), 'supportDay0');
      expect(supportMessageKey(1), 'supportDay1');
      expect(supportMessageKey(2), 'supportDays');
      expect(supportMessageKey(6), 'supportDays');
      expect(supportMessageKey(7), 'supportWeek');
      expect(supportMessageKey(29), 'supportWeek');
      expect(supportMessageKey(30), 'supportMonth');
      expect(supportMessageKey(364), 'supportMonth');
      expect(supportMessageKey(365), 'supportYear');
    });
  });

  group('money formatting', () {
    test('grouped thousands in English digits', () {
      expect(formatNumber(0, false), '0');
      expect(formatNumber(500, false), '500');
      expect(formatNumber(2500000, false), '2,500,000');
      expect(formatNumber(60000000000, false), '60,000,000,000');
    });

    test('Persian digits and separators on the Persian side', () {
      expect(formatNumber(500000, true), '۵۰۰٬۰۰۰');
      expect(formatNumber(0, true), '۰');
      expect(formatNumber(2500000, true), '۲٬۵۰۰٬۰۰۰');
    });
  });
}
