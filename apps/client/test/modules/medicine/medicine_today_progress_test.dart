import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/medicine/medicine_models.dart';
import 'package:nex_client/modules/medicine/medicine_today_state.dart';

/// Where one medicine's routine stands today (the audit pass): the moments
/// it names, the ones a log answers, and the next one still ahead. The
/// logs a person writes from the detail sheet carry no slot, so their own
/// clock time must answer a moment — exactly as the Today page reads it.
void main() {
  ModuleRecord record(String kind, String id, Map<String, Object?> body) =>
      ModuleRecord(
        module: 'medicine',
        kind: kind,
        id: id,
        body: body,
        updatedAt: DateTime(2026),
      );

  final now = DateTime(2026, 11, 27, 12, 0);

  ModuleRecord medicine(Map<String, Object?> extra) =>
      record('medicine', 'm1', {
        'v': 3,
        'name': 'Medicine A',
        'times': const ['08:00', '14:00', '20:00'],
        ...extra,
      });

  ModuleRecord doseAt(DateTime at, {String? slot, String action = 'taken'}) =>
      record(
        'dose',
        'd${at.hashCode}${slot.hashCode}',
        MedicineModels.doseBody(
          medicineId: 'm1',
          action: action,
          at: at,
          slot: slot,
        ),
      );

  test('no logs: three open moments, the afternoon one is next', () {
    final p = MedicineTodayProgress.of(medicine(const {}), const [], now);
    expect((p.total, p.open), (3, 3));
    expect(p.next, DateTime(2026, 11, 27, 14));
    expect(p.allLogged, isFalse);
    expect(p.nothingToday, isFalse);
  });

  test('a slot log answers exactly its moment', () {
    final p = MedicineTodayProgress.of(medicine(const {}), [
      doseAt(DateTime(2026, 11, 27, 14), slot: '14:00'),
    ], now);
    expect((p.total, p.open), (3, 2));
    expect(p.next, DateTime(2026, 11, 27, 20));
  });

  test('explicit slot takes precedence over the log clock time', () {
    final p = MedicineTodayProgress.of(medicine(const {}), [
      doseAt(DateTime(2026, 11, 27, 14), slot: '08:00'),
    ], now);
    expect((p.total, p.open), (3, 2));
    expect(p.next, DateTime(2026, 11, 27, 14));
  });

  test('midnight is included in today and can be answered', () {
    final m = medicine(const {
      'times': ['00:00', '14:00'],
    });
    final p = MedicineTodayProgress.of(m, [
      doseAt(DateTime(2026, 11, 27), slot: '00:00'),
    ], now);
    expect((p.total, p.open), (2, 1));
    expect(p.next, DateTime(2026, 11, 27, 14));
  });

  test('a log from the detail sheet answers the moment at its own time', () {
    final p = MedicineTodayProgress.of(medicine(const {}), [
      doseAt(DateTime(2026, 11, 27, 8)),
    ], now);
    expect((p.total, p.open), (3, 2), reason: 'no slot, but logged at 08:00');
    expect(p.next, DateTime(2026, 11, 27, 14));
  });

  test('a log at a time the routine does not name answers nothing', () {
    final p = MedicineTodayProgress.of(medicine(const {}), [
      doseAt(DateTime(2026, 11, 27, 12, 30)),
    ], now);
    expect((p.total, p.open), (3, 3));
  });

  test('a skipped log is an answer too', () {
    final p = MedicineTodayProgress.of(medicine(const {}), [
      doseAt(DateTime(2026, 11, 27, 8), action: 'skipped'),
    ], now);
    expect((p.total, p.open), (3, 2));
  });

  test('every moment answered: all logged, and nothing is next', () {
    final p = MedicineTodayProgress.of(medicine(const {}), [
      doseAt(DateTime(2026, 11, 27, 8), slot: '08:00'),
      doseAt(DateTime(2026, 11, 27, 14), slot: '14:00'),
      doseAt(DateTime(2026, 11, 27, 20), slot: '20:00'),
    ], now);
    expect(p.open, 0);
    expect(p.allLogged, isTrue);
    expect(p.next, isNull);
  });

  test('yesterday’s log does not answer today', () {
    final p = MedicineTodayProgress.of(medicine(const {}), [
      doseAt(DateTime(2026, 11, 26, 8), slot: '08:00'),
    ], now);
    expect((p.total, p.open), (3, 3));
  });

  test('open moments all in the past: open, but nothing is next', () {
    final morning = MedicineTodayProgress.of(
      medicine(const {
        'times': ['06:00', '07:00'],
      }),
      const [],
      now,
    );
    expect((morning.total, morning.open), (2, 2));
    expect(morning.next, isNull, reason: 'the day’s moments have passed');
  });

  test('a weekday the routine does not name, or no times, or archived', () {
    expect(
      MedicineTodayProgress.of(
        // 2026-11-27 is a Friday (Dart 5).
        medicine(const {
          'weekdays': [1, 2],
        }),
        const [],
        now,
      ).nothingToday,
      isTrue,
    );
    expect(
      MedicineTodayProgress.of(
        medicine(const {'times': []}),
        const [],
        now,
      ).nothingToday,
      isTrue,
    );
    expect(
      MedicineTodayProgress.of(
        medicine(const {'archived': true}),
        const [],
        now,
      ).nothingToday,
      isTrue,
    );
  });

  test('a log for another medicine answers nothing here', () {
    final other = record(
      'dose',
      'other',
      MedicineModels.doseBody(
        medicineId: 'm2',
        action: 'taken',
        at: DateTime(2026, 11, 27, 8),
        slot: '08:00',
      ),
    );
    final p = MedicineTodayProgress.of(medicine(const {}), [other], now);
    expect((p.total, p.open), (3, 3));
  });

  test('the day itself is read from the clock passed in', () {
    final p = MedicineTodayProgress.of(
      medicine(const {}),
      const [],
      DateTime(2026, 11, 27, 23, 30),
    );
    expect(p.total, 3, reason: 'even at the end of the day');
    expect(p.next, isNull);
  });

  test('an ended routine names nothing after its end day', () {
    final p = MedicineTodayProgress.of(
      medicine(const {'endsOn': '2026-11-26'}),
      const [],
      now,
    );
    expect(p.nothingToday, isTrue);
  });
}
