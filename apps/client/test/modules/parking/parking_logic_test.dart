import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/parking/parking_logic.dart';
import 'package:nex_client/modules/parking/parking_models.dart';

/// The parking calculations, on their own: active vs closed, vehicle
/// separation, elapsed time across midnight and a daylight change, the
/// paid-time states, search and history ordering. Every case passes its
/// own clock, so nothing races the real one.
void main() {
  // A fixed "now" every case shares where it is not the point under test.
  final now = DateTime.utc(2026, 10, 12, 10, 0);

  Map<String, Object?> session({
    String vehicle = 'ماشین',
    String place = 'پارکینگِ صبا',
    String floor = '',
    String spot = '',
    String landmark = '',
    DateTime? started,
    DateTime? found,
    DateTime? expires,
    double? lat,
    double? lng,
  }) => ParkingModels.sessionBody(
    vehicle: vehicle,
    place: place,
    floor: floor,
    spot: spot,
    landmark: landmark,
    startedAt: started ?? DateTime.utc(2026, 10, 12, 8, 0),
    foundAt: found,
    expiresAt: expires,
    lat: lat,
    lng: lng,
  );

  group('active and closed', () {
    test('no foundAt is active', () {
      expect(ParkingLogic.isActive(session()), isTrue);
    });

    test('a foundAt closes it', () {
      expect(
        ParkingLogic.isActive(session(found: DateTime.utc(2026, 10, 12, 9))),
        isFalse,
      );
    });
  });

  group('elapsed', () {
    test('an open session counts to the clock it is given', () {
      final body = session(started: DateTime.utc(2026, 10, 12, 8, 30));
      expect(ParkingLogic.elapsedOf(body, now), const Duration(minutes: 90));
    });

    test('a closed session measures to its foundAt, not the clock', () {
      final body = session(
        started: DateTime.utc(2026, 10, 12, 8, 0),
        found: DateTime.utc(2026, 10, 12, 8, 45),
      );
      expect(ParkingLogic.elapsedOf(body, now), const Duration(minutes: 45));
    });

    test('a session with no readable start reads as zero, not negative', () {
      final body = {'v': 1, 'place': 'x'};
      expect(ParkingLogic.elapsedOf(body, now), Duration.zero);
    });

    test('a clock before the start (skew) reads as zero', () {
      final body = session(started: DateTime.utc(2026, 10, 12, 12, 0));
      expect(ParkingLogic.elapsedOf(body, now), Duration.zero);
    });

    test('crossing midnight is the same minutes on either side', () {
      final body = session(started: DateTime.utc(2026, 10, 11, 23, 50));
      final afterMidnight = DateTime.utc(2026, 10, 12, 0, 10);
      expect(
        ParkingLogic.elapsedOf(body, afterMidnight),
        const Duration(minutes: 20),
      );
    });

    test('a daylight-saving change does not change the duration', () {
      // Instants, not wall times: Europe left summer time at
      // 2026-10-25 01:00 UTC. Parking from the evening before to the
      // morning after spans the change: the clock falls back an hour,
      // so eight wall-clock hours hold nine real ones — and nine hours
      // of parking is what elapsedOf says.
      final body = session(
        started: DateTime.parse('2026-10-24T20:00:00+02:00'),
      );
      final after = DateTime.parse('2026-10-25T04:00:00+01:00');
      expect(ParkingLogic.elapsedOf(body, after), const Duration(hours: 9));
    });

    test('storing and reading round-trips an instant exactly', () {
      final started = DateTime.parse('2026-10-24T20:00:00+02:00');
      final body = session(started: started);
      expect(
        ParkingModels.readDate(body, 'startedAt')!.toUtc(),
        started.toUtc(),
      );
    });
  });

  group('one open parking per vehicle', () {
    test('the same name, different case and space, is the same vehicle', () {
      expect(ParkingModels.sameVehicle(' Car ', 'car'), isTrue);
      expect(ParkingModels.sameVehicle('ماشین', 'ماشین'), isTrue);
      expect(ParkingModels.sameVehicle('ماشین', 'موتور'), isFalse);
    });

    test('another open parking for that vehicle is found', () {
      final open = session(vehicle: 'Car');
      final closed = session(vehicle: 'Car', found: now);
      final other = session(vehicle: 'موتور');
      final found = ParkingLogic.activeForVehicle([open, closed, other], 'CAR');
      expect(found, hasLength(1));
      expect(found.single, same(open));
    });
  });

  group('the paid time', () {
    test('none written reads as none', () {
      expect(ParkingLogic.expiryOf(session(), now), (over: false, minutes: 0));
    });

    test('time still on the meter', () {
      final body = session(expires: DateTime.utc(2026, 10, 12, 11, 30));
      expect(ParkingLogic.expiryOf(body, now), (over: false, minutes: 90));
    });

    test('past it says so, with the minutes since', () {
      final body = session(expires: DateTime.utc(2026, 10, 12, 9, 30));
      expect(ParkingLogic.expiryOf(body, now), (over: true, minutes: 30));
    });

    test('the exact moment counts as past, politely', () {
      final body = session(expires: DateTime.utc(2026, 10, 12, 10, 0));
      expect(ParkingLogic.expiryOf(body, now), (over: true, minutes: 0));
    });
  });

  group('search', () {
    test('an empty query matches everything', () {
      expect(ParkingLogic.matchesQuery(session(), '  '), isTrue);
    });

    test('the place, vehicle and landmark are searched, case-blind', () {
      final body = session(landmark: 'کنار آسانسورها');
      expect(ParkingLogic.matchesQuery(body, 'saba'), isFalse);
      expect(ParkingLogic.matchesQuery(session(), 'صبا'), isTrue);
      expect(ParkingLogic.matchesQuery(body, 'آسانسور'), isTrue);
      expect(
        ParkingLogic.matchesQuery(session(vehicle: 'Pride'), 'pride'),
        isTrue,
      );
    });
  });

  group('history', () {
    test('closed sessions, the latest start first', () {
      final older = session(
        place: 'old',
        started: DateTime.utc(2026, 10, 1),
        found: now,
      );
      final newer = session(
        place: 'new',
        started: DateTime.utc(2026, 10, 2),
        found: now,
      );
      final open = session(place: 'open');
      final history = ParkingLogic.historyOf([open, older, newer]);
      expect(history.map((s) => s['place']), ['new', 'old']);
    });
  });

  group('durations as they are shown', () {
    test('under an hour, minutes', () {
      final t = ParkingLogic.split(const Duration(minutes: 42));
      expect(t, (days: 0, hours: 0, minutes: 42));
    });

    test('under a day, hours and minutes', () {
      final t = ParkingLogic.split(const Duration(hours: 5, minutes: 7));
      expect(t, (days: 0, hours: 5, minutes: 7));
    });

    test('over a day, days and hours', () {
      final t = ParkingLogic.split(const Duration(hours: 26, minutes: 59));
      expect(t, (days: 1, hours: 2, minutes: 59));
    });

    test('a negative duration reads as zero', () {
      expect(
        ParkingLogic.split(const Duration(minutes: -3)),
        ParkingLogic.split(Duration.zero),
      );
    });
  });

  group('search history', () {
    test('a fresh query goes to the front', () {
      final kept = ParkingLogic.rememberQueries(['a', 'b'], 'c');
      expect(kept, ['c', 'a', 'b']);
    });

    test('a repeat moves it up rather than doubling it', () {
      final kept = ParkingLogic.rememberQueries(['a', 'b', 'c'], 'B');
      expect(kept, ['B', 'a', 'c']);
    });

    test('only the newest eight are kept', () {
      // The list holds the queries newest first, so the oldest — the one
      // at the end — is the one that goes.
      final kept = ParkingLogic.rememberQueries(
        List.generate(8, (i) => 'q$i'),
        'new',
      );
      expect(kept, hasLength(8));
      expect(kept.first, 'new');
      expect(kept, isNot(contains('q7')));
    });

    test('a blank query changes nothing', () {
      final kept = ParkingLogic.rememberQueries(['a'], '  ');
      expect(kept, ['a']);
    });
  });

  group('remembered places', () {
    test('same place, floor and spot are the same place', () {
      final a = session(place: 'صبا', floor: '1', spot: 'B2');
      final b = session(place: 'صبا ', floor: '1', spot: 'b2');
      final c = session(place: 'صبا', floor: '2', spot: 'B2');
      expect(ParkingLogic.samePlace(a, b), isTrue);
      expect(ParkingLogic.samePlace(a, c), isFalse);
    });
  });
}
