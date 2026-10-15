import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/smoke_free/quit_model.dart';
import 'package:nex_client/modules/smoke_free/smoke_math.dart';
import 'package:nex_client/modules/smoke_free/money_format.dart';

void main() {
  test(
    'savings floor in the selected currency and stop at the attempt end',
    () {
      final attempt = QuitAttempt(
        id: 'q',
        startedAt: DateTime(2026, 10, 1),
        cigarettesPerDay: 3,
        pricePerPackMinor: 1234,
        currency: 'USD',
        perPack: 20,
        endedAt: DateTime(2026, 10, 3),
        endedWhy: 'lapse',
      );
      final progress = SmokeMath.progress(attempt, DateTime(2026, 10, 12));
      expect(progress.days, 2);
      expect(progress.moneySavedMinor, BigInt.from(370));
      expect(QuitAttempt.fromBody('q', attempt.toJson()).currency, 'USD');
    },
  );
  test('very large savings preserve exact multiplication beyond int64', () {
    final attempt = QuitAttempt(
      id: 'q',
      startedAt: DateTime(1),
      cigarettesPerDay: 1000,
      pricePerPackMinor: 9007199254740991,
      currency: 'KWD',
      perPack: 1,
      endedAt: null,
      endedWhy: null,
    );
    final now = DateTime(9999, 12, 31);
    final progress = SmokeMath.progress(attempt, now);
    final expected =
        BigInt.from(SmokeMath.elapsedDays(attempt.startedAt, now)) *
        BigInt.from(1000) *
        BigInt.from(9007199254740991);
    expect(progress.moneySavedMinor, expected);
    expect(formatExactMoney(expected, 'KWD', 3, false), contains('KWD'));
  });
  test('legacy rials and stored precision survive a read/write cycle', () {
    final legacy = QuitAttempt.fromBody('q', {'pricePerPackRials': 250000});
    expect(legacy.pricePerPackMinor, 250000);
    expect(legacy.currency, 'IRR');
    expect(legacy.digits, 0);
    final custom = QuitAttempt.fromBody('q', {
      'pricePerPackMinor': 1,
      'currency': 'XYZ',
      'currencyDecimals': 3,
    });
    expect(custom.currency, 'XYZ');
    expect(custom.digits, 3);
  });
  test('duplicate and unknown trigger keys cannot inflate patterns', () {
    final craving = Craving.fromBody('c', {
      'triggers': ['stress', 'stress', 'unknown'],
      'coping': 'unknown',
      'intensity': double.nan,
    });
    expect(craving.triggers, ['stress']);
    expect(craving.coping, isNull);
    expect(craving.intensity, 1);
    expect(SmokeMath.triggerCounts([craving]).single.value, 1);
  });
  test('UTC instants are grouped by their device-local civil date', () {
    final moment = DateTime.utc(2026, 10, 11, 23, 30);
    expect(SmokeMath.cravingDayIndex(moment, moment.toLocal()), 0);
    expect(SmokeMath.elapsedDays(moment, moment.toLocal()), 0);
  });
}
