import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/brief_refresh.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A brief written from facts stops being true when the clock passes them.
///
/// The audit behind 2.9.0 found the same hole in three places: nothing writes
/// a row at 11:20, and nothing wrote one at midnight, so the card, the
/// home-screen widget and the notification could each republish words that had
/// quietly stopped describing the library. These are the rules that decide
/// whether the words on file may be shown at all.
///
/// Two clocks are involved and they are tested apart on purpose: whether the
/// words may be *published* is asked of the wall clock
/// ([NexPreferences.currentAiBrief], which reads `DateTime.now`), and whether
/// a replacement may be *asked for* is asked of the refresh service's injected
/// clock, which a test can move.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late NexPreferences prefs;
  late DateTime now;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await NexPreferences.load();
    now = DateTime.now();
  });
  tearDown(() => prefs.dispose());

  Future<void> write({
    required DateTime validUntil,
    String text = 'the brief',
  }) => prefs.setAiDaySummary(
    text: text,
    dateKey: NexPreferences.daySummaryDateKey(DateTime.now()),
    validUntil: validUntil,
  );

  test('a brief is published until the moment it says it holds', () async {
    await write(validUntil: DateTime.now().add(const Duration(minutes: 5)));
    expect(prefs.currentAiBrief, 'the brief');

    await write(
      validUntil: DateTime.now().subtract(const Duration(minutes: 1)),
    );
    expect(
      prefs.currentAiBrief,
      isNull,
      reason: 'the moment it was written for has passed',
    );
    expect(prefs.aiDaySummaryText, 'the brief', reason: 'kept, not deleted');
  });

  test('a brief written for another day is not published', () async {
    await prefs.setAiDaySummary(
      text: 'yesterday',
      dateKey: '2020-01-01',
      validUntil: DateTime.now().add(const Duration(hours: 3)),
    );
    expect(prefs.currentAiBrief, isNull);
  });

  test('a brief with no stated moment keeps the behaviour it had', () async {
    await prefs.setAiDaySummary(
      text: 'old cache',
      dateKey: NexPreferences.daySummaryDateKey(DateTime.now()),
    );
    expect(
      prefs.currentAiBrief,
      'old cache',
      reason: 'a cache written before 2.9.0 is not treated as expired',
    );
  });

  test('an expired brief is replaced without waiting for the hour', () async {
    var calls = 0;
    final refresh = NexBriefRefresh(prefs, clock: () => now);
    Future<void> ask(DateTime validUntil) => refresh.refresh(
      fingerprint: 'facts',
      dateKey: NexPreferences.daySummaryDateKey(now),
      validUntil: validUntil,
      request: () async {
        calls++;
        return 'the brief';
      },
    );

    await ask(now.add(const Duration(minutes: 30)));
    expect(calls, 1);
    now = now.add(const Duration(minutes: 31));
    expect(
      refresh.needs('facts'),
      isTrue,
      reason: 'an hour of cooldown must not keep words that are no longer true',
    );
    await ask(now.add(const Duration(hours: 2)));
    expect(calls, 2);
  });

  test(
    'an expired brief waits out the short retry, not the long one',
    () async {
      var calls = 0;
      final refresh = NexBriefRefresh(prefs, clock: () => now);
      await refresh.refresh(
        fingerprint: 'facts',
        dateKey: NexPreferences.daySummaryDateKey(now),
        validUntil: now.add(const Duration(seconds: 30)),
        request: () async {
          calls++;
          return 'the brief';
        },
      );
      expect(calls, 1);

      now = now.add(const Duration(seconds: 60));
      expect(
        refresh.needs('facts'),
        isFalse,
        reason: 'a minute since the last attempt is inside the retry window',
      );

      now = now.add(const Duration(minutes: 2));
      expect(refresh.needs('facts'), isTrue);
    },
  );
}
