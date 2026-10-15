import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/parking/parking_models.dart';

/// The stored shapes: what goes in, what comes back, and what happens to
/// an old or broken record — every reader is defensive, because a record
/// written by an earlier version has to keep opening.
void main() {
  group('strings', () {
    test('a string round-trips', () {
      final body = ParkingModels.sessionBody(
        vehicle: 'ماشین',
        place: 'پارکینگِ صبا',
        floor: '-1',
        spot: 'B12',
        landmark: 'کنار آسانسور',
        startedAt: DateTime.utc(2026, 10, 12),
      );
      expect(ParkingModels.readString(body, 'place'), 'پارکینگِ صبا');
      expect(ParkingModels.readString(body, 'floor'), '-1');
      expect(ParkingModels.readString(body, 'vehicle'), 'ماشین');
    });

    test('surrounding space is trimmed on the way in', () {
      final body = ParkingModels.sessionBody(
        vehicle: ' car ',
        place: ' صبا ',
        floor: ' 2 ',
        spot: ' B3 ',
        landmark: 'x',
        startedAt: DateTime.utc(2026, 10, 12),
      );
      expect(body['vehicle'], 'car');
      expect(body['place'], 'صبا');
      expect(body['floor'], '2');
      expect(body['spot'], 'B3');
    });

    test('a missing or wrong-typed field reads as empty, never throws', () {
      const body = {'place': 12, 'floor': true};
      expect(ParkingModels.readString(body, 'place'), '');
      expect(ParkingModels.readString(body, 'floor'), '');
      expect(ParkingModels.readString(body, 'nope'), '');
    });
  });

  group('dates', () {
    test('a date round-trips as an instant', () {
      final at = DateTime.parse('2026-10-12T08:30:00+03:30');
      final body = ParkingModels.sessionBody(
        vehicle: '',
        place: 'x',
        floor: '',
        spot: '',
        landmark: '',
        startedAt: at,
        expiresAt: at.add(const Duration(hours: 2)),
      );
      expect(ParkingModels.readDate(body, 'startedAt')!.toUtc(), at.toUtc());
      expect(
        ParkingModels.readDate(body, 'expiresAt')!.toUtc(),
        at.add(const Duration(hours: 2)).toUtc(),
      );
    });

    test('null when missing, not a string, or unparsable', () {
      expect(ParkingModels.readDate({}, 'expiresAt'), isNull);
      expect(ParkingModels.readDate({'expiresAt': 5}, 'expiresAt'), isNull);
      expect(
        ParkingModels.readDate({'expiresAt': 'not a date'}, 'expiresAt'),
        isNull,
      );
    });

    test('foundAt is written only when there is one', () {
      final start = DateTime.utc(2026, 10, 12);
      final open = ParkingModels.sessionBody(
        vehicle: '',
        place: 'x',
        floor: '',
        spot: '',
        landmark: '',
        startedAt: start,
      );
      final closed = ParkingModels.sessionBody(
        vehicle: '',
        place: 'x',
        floor: '',
        spot: '',
        landmark: '',
        startedAt: start,
        foundAt: DateTime.utc(2026, 10, 12, 9),
      );
      expect(open.containsKey('foundAt'), isFalse);
      expect(closed.containsKey('foundAt'), isTrue);
    });
  });

  group('coordinates', () {
    test('in range, round-trips', () {
      final body = ParkingModels.sessionBody(
        vehicle: '',
        place: 'x',
        floor: '',
        spot: '',
        landmark: '',
        startedAt: DateTime.utc(2026, 10, 12),
        lat: 35.6892,
        lng: 51.389,
      );
      expect(
        ParkingModels.readCoord(
          body,
          'lat',
          min: ParkingModels.latMin,
          max: ParkingModels.latMax,
        ),
        35.6892,
      );
      expect(
        ParkingModels.readCoord(
          body,
          'lng',
          min: ParkingModels.lngMin,
          max: ParkingModels.lngMax,
        ),
        51.389,
      );
    });

    test('out of range is refused, not clamped', () {
      expect(
        ParkingModels.readCoord(
          {'lat': 91},
          'lat',
          min: ParkingModels.latMin,
          max: ParkingModels.latMax,
        ),
        isNull,
      );
      expect(
        ParkingModels.readCoord(
          {'lng': -1000},
          'lng',
          min: ParkingModels.lngMin,
          max: ParkingModels.lngMax,
        ),
        isNull,
      );
      expect(
        ParkingModels.readCoord(
          {'lat': double.nan},
          'lat',
          min: ParkingModels.latMin,
          max: ParkingModels.latMax,
        ),
        isNull,
      );
      expect(
        ParkingModels.readCoord(
          {'lng': 'not a number'},
          'lng',
          min: ParkingModels.lngMin,
          max: ParkingModels.lngMax,
        ),
        isNull,
      );
    });
  });

  group('counts', () {
    test('a use count reads back', () {
      final body = ParkingModels.placeBody(
        place: 'x',
        floor: '',
        spot: '',
        landmark: '',
        useCount: 3,
        lastUsedAt: DateTime.utc(2026, 10, 12),
      );
      expect(ParkingModels.readCount(body, 'useCount'), 3);
    });

    test('negative, fractional or wrong-typed reads as null', () {
      expect(ParkingModels.readCount({'useCount': -1}, 'useCount'), isNull);
      expect(ParkingModels.readCount({'useCount': 1.5}, 'useCount'), isNull);
      expect(ParkingModels.readCount({'useCount': '2'}, 'useCount'), isNull);
      expect(ParkingModels.readCount({}, 'useCount'), isNull);
    });
  });

  group('search records', () {
    test('the query and its time are stored', () {
      final body = ParkingModels.searchBody(
        query: ' صبا ',
        at: DateTime.utc(2026, 10, 12, 9),
      );
      expect(body['query'], 'صبا');
      expect(
        DateTime.parse(body['at']! as String),
        DateTime.utc(2026, 10, 12, 9),
      );
    });
  });
}
