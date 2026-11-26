import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/smoke_free/quit_model.dart';
import 'package:nex_client/modules/smoke_free/quit_calendar_math.dart';
import 'package:nex_client/modules/smoke_free/quit_review_math.dart';
import 'package:nex_client/modules/smoke_free/sos_clock.dart';

void main() {
  final now = DateTime(2026, 11, 15, 12);
  QuitAttempt attempt(Map<String, Object?> extra) => QuitAttempt.fromBody('a', {
    'startedAt': DateTime(2026, 11, 1).toIso8601String(),
    ...extra,
  });
  Craving craving(int before, int? after, int daysAgo) => Craving(
    id: 'c',
    at: now.subtract(Duration(days: daysAgo)),
    intensity: before,
    afterIntensity: after,
    triggers: const ['stress'],
    coping: 'walk',
    note: '',
  );

  test('legacy identity remains stable when a custom habit is renamed', () {
    final old = attempt({'habit': 'custom', 'name': 'Nail biting'});
    expect(old.key, 'custom:nail biting');
    final renamed = attempt({
      'habit': 'custom',
      'name': 'A new title',
      'habitKey': old.key,
      'nextStep': 'After tea I will walk.',
    });
    expect(renamed.key, old.key);
    expect(renamed.toJson()['nextStep'], 'After tea I will walk.');
    expect(renamed.toJson()['habitKey'], old.key);
    expect(attempt({'habit': 'caffeine', 'habitKey': old.key}).key, 'caffeine');
    expect(
      attempt({'habit': 'custom', 'name': 'X', 'habitKey': 22}).key,
      'custom:x',
    );
    expect(attempt({'nextStep': 77}).nextStep, isEmpty);
  });

  test(
    'after-ratings are optional and invalid historical values stay unknown',
    () {
      for (final value in [null, 0, 4, 1.5, '2', double.nan, double.infinity]) {
        expect(
          Craving.fromBody('c', {'afterIntensity': value}).afterIntensity,
          isNull,
        );
      }
      final rated = Craving.fromBody('c', {
        'afterIntensity': 1,
        'intensity': 3,
      });
      expect(rated.toJson()['afterIntensity'], 1);
      expect(
        Craving.fromBody('old', {}).toJson().containsKey('afterIntensity'),
        isFalse,
      );
    },
  );

  test('the 30-day review excludes future/old logs and never fills missing ratings', () {
    final data = QuitInsights([
      craving(3, 1, 0),
      craving(2, 2, 1),
      craving(1, 3, 29),
      craving(3, null, 2),
      craving(3, 1, 30),
      craving(3, 1, -1),
    ], now);
    expect(data.recent.length, 4);
    expect(data.rated, 3);
    expect(data.eased, 1);
    expect(QuitInsights([], now).eased, 0);
  });

  test(
    'calendar does not mark unlogged days successful or count future reports',
    () {
      final current = attempt({});
      final past = attempt({
        'startedAt': DateTime(2026, 10, 20).toIso8601String(),
        'endedAt': DateTime(2026, 10, 30).toIso8601String(),
        'endedWhy': 'lapse',
      });
      final cells = quitCalendarDays(
        current,
        [past],
        [craving(2, null, 0), craving(3, 1, -1)],
        now,
      );
      expect(cells.length, 35);
      expect(cells.map((c) => c.day).toSet().length, 35);
      expect(cells.last.status, QuitDayStatus.craving);
      expect(
        cells.where((c) => c.day == DateTime(2026, 11, 14)).single.status,
        QuitDayStatus.unlogged,
      );
      expect(
        cells.where((c) => c.day == DateTime(2026, 10, 30)).single.status,
        QuitDayStatus.lapse,
      );
      expect(
        cells.where((c) => c.day == DateTime(2026, 10, 31)).single.status,
        QuitDayStatus.outside,
      );
      final planned = attempt({
        'startedAt': DateTime(2026, 12, 1).toIso8601String(),
      });
      expect(
        quitCalendarDays(
          planned,
          [],
          [],
          now,
        ).every((c) => c.status == QuitDayStatus.outside),
        isTrue,
      );
    },
  );

  test('the five-week grid follows the week and names days not yet', () {
    final current = attempt({});
    final monday = quitCalendarDays(current, const [], const [], now);
    expect(monday.first.day.weekday, DateTime.monday);
    expect(monday.first.day, DateTime(2026, 10, 12));
    expect(monday.last.day, DateTime(2026, 11, 15));

    final saturday = quitCalendarDays(
      current,
      const [],
      const [],
      now,
      weekStartsOn: DateTime.saturday,
    );
    expect(saturday.first.day.weekday, DateTime.saturday);
    expect(saturday.first.day, DateTime(2026, 10, 17));
    expect(saturday.last.day, DateTime(2026, 11, 20));
    expect(
      saturday.where((c) => c.day == DateTime(2026, 11, 15)).single.status,
      QuitDayStatus.unlogged,
    );
    // Tomorrow is not an unlogged day: it has not happened.
    expect(
      saturday.where((c) => c.day == DateTime(2026, 11, 16)).single.status,
      QuitDayStatus.future,
    );
    expect(
      saturday.where((c) => c.day == DateTime(2026, 11, 20)).single.status,
      QuitDayStatus.future,
    );
  });

  test('the review names a clear time of day, and a tie says nothing', () {
    Craving at(DateTime moment) => Craving(
      id: moment.toIso8601String(),
      at: moment,
      intensity: 2,
      triggers: const ['stress'],
      coping: null,
      note: '',
    );
    final morning = QuitInsights([
      at(DateTime(2026, 11, 10, 8)),
      at(DateTime(2026, 11, 11, 9)),
      at(DateTime(2026, 11, 12, 20)),
    ], now);
    expect(morning.peakPeriod, 'morning');
    expect(morning.peakPeriodCount, 2);
    expect(cravingPeriodKey(DateTime(2026, 11, 10, 23)), 'night');

    final tied = QuitInsights([
      at(DateTime(2026, 11, 10, 8)),
      at(DateTime(2026, 11, 11, 9)),
      at(DateTime(2026, 11, 12, 20)),
      at(DateTime(2026, 11, 13, 21)),
    ], now);
    expect(tied.peakPeriod, isNull);
    expect(tied.peakPeriodCount, 0);
  });

  test('deadline rounds remaining fractions up and expires after delayed callbacks', () {
    expect(sosSecondsLeft(now.add(const Duration(milliseconds: 1)), now), 1);
    expect(sosSecondsLeft(now.add(const Duration(minutes: 10)), now), 600);
    expect(
      sosSecondsLeft(
        now.add(const Duration(minutes: 10)),
        now.add(const Duration(seconds: 61)),
      ),
      539,
    );
    expect(sosSecondsLeft(now, now), 0);
    expect(sosSecondsLeft(now, now.add(const Duration(minutes: 20))), 0);
  });
}
