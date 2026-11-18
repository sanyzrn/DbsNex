import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/nex_services.dart';

/// The auto-sync retry ladder (see `NexAutoSyncServices`): the first failure
/// silences the scheduler exactly as long as it always did, and each further
/// consecutive failure doubles the quiet window up to a ceiling — so an
/// endpoint that is down is poked 5, 10, 20, 40 minutes and then hourly,
/// instead of every five minutes for as long as the app stays open, with
/// every attempt holding the database worker's single command lane for the
/// request's full timeout.
void main() {
  test('the first failure costs the cooldown it always did', () {
    expect(
      NexAutoSyncServices.autoSyncRetryDelayAfter(0),
      NexAutoSyncServices.autoSyncRetryDelay,
    );
    expect(
      NexAutoSyncServices.autoSyncRetryDelayAfter(1),
      NexAutoSyncServices.autoSyncRetryDelay,
    );
    expect(NexAutoSyncServices.autoSyncRetryDelay, const Duration(minutes: 5));
  });

  test('the ladder doubles per consecutive failure', () {
    expect(
      NexAutoSyncServices.autoSyncRetryDelayAfter(2),
      const Duration(minutes: 10),
    );
    expect(
      NexAutoSyncServices.autoSyncRetryDelayAfter(3),
      const Duration(minutes: 20),
    );
    expect(
      NexAutoSyncServices.autoSyncRetryDelayAfter(4),
      const Duration(minutes: 40),
    );
  });

  test('the ceiling holds however long the run of failures', () {
    expect(
      NexAutoSyncServices.autoSyncRetryDelayAfter(5),
      NexAutoSyncServices.autoSyncMaxRetryDelay,
    );
    expect(
      NexAutoSyncServices.autoSyncRetryDelayAfter(6),
      NexAutoSyncServices.autoSyncMaxRetryDelay,
    );
    // A run so long the naive exponent would overflow a smaller int: still
    // the ceiling, still a Duration, no exception.
    expect(
      NexAutoSyncServices.autoSyncRetryDelayAfter(99),
      NexAutoSyncServices.autoSyncMaxRetryDelay,
    );
    expect(NexAutoSyncServices.autoSyncMaxRetryDelay, const Duration(hours: 1));
  });

  test('an hourly ceiling means fewer futile cycles per day', () {
    // The old flat cooldown attempted ~12 cycles a day against a dead
    // endpoint (one per 5-minute window, for as long as the app ran). The
    // ladder's first 8 hours attempt 5+10+20+40+60+60+60+60 minutes of
    // waiting — and from then on, one an hour.
    var waited = Duration.zero;
    var attempts = 0;
    for (var rung = 1; rung <= 24; rung++) {
      waited += NexAutoSyncServices.autoSyncRetryDelayAfter(rung);
      attempts++;
    }
    expect(attempts, 24);
    expect(waited.inHours, greaterThanOrEqualTo(20));
    // …while the flat cooldown's first 24 attempts cover two hours.
    expect(
      const Duration(minutes: 5) * 24,
      const Duration(hours: 2),
    );
  });
}
