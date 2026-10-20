import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/smoke_free/quit_model.dart';

/// Records read defensively: an old or corrupt attempt or craving opens
/// the screen instead of breaking it.
void main() {
  ModuleRecord record(
    String id,
    Map<String, Object?> body, {
    String kind = 'quit',
  }) => ModuleRecord(
    module: 'smoke_free',
    kind: kind,
    id: id,
    body: body,
    updatedAt: DateTime(2026, 10, 12),
  );

  group('QuitAttempt', () {
    test('reads a well-formed record', () {
      final a = QuitAttempt.fromRecord(
        record('q1', {
          'startedAt': '2026-10-01T09:00:00.000',
          'cigarettesPerDay': 15,
          'pricePerPackRials': 300000,
          'perPack': 20,
          'endedAt': '2026-10-05T20:00:00.000',
          'endedWhy': 'lapse',
        }),
      );
      expect(a.startedAt, DateTime.parse('2026-10-01T09:00:00.000'));
      expect(a.cigarettesPerDay, 15);
      expect(a.pricePerPackMinor, 300000);
      expect(a.perPack, 20);
      expect(a.isActive, isFalse);
      expect(a.endedWhy, 'lapse');
    });

    test('missing fields read as their defaults', () {
      final a = QuitAttempt.fromRecord(
        record('q1', {'startedAt': '2026-10-01T09:00:00.000'}),
      );
      expect(a.cigarettesPerDay, 0);
      expect(a.pricePerPackMinor, 0);
      expect(a.perPack, 20, reason: 'the customary pack size, not 1');
      expect(a.isActive, isTrue);
      expect(a.endedWhy, isNull);
    });

    test('wrong-typed fields read as their defaults', () {
      final a = QuitAttempt.fromRecord(
        record('q1', {
          'startedAt': 'nonsense',
          'cigarettesPerDay': 'many',
          'pricePerPackRials': 12.5,
          'perPack': 'twenty',
          'endedAt': 42,
        }),
      );
      expect(a.startedAt.year, greaterThanOrEqualTo(2026));
      expect(a.cigarettesPerDay, 0);
      expect(
        a.pricePerPackMinor,
        0,
        reason: 'fractional stored minor units are malformed',
      );
      expect(a.perPack, 20);
      expect(a.isActive, isTrue);
    });

    test('out-of-range values are clamped, not crashed on', () {
      final a = QuitAttempt.fromRecord(
        record('q1', {
          'startedAt': '2026-10-01T09:00:00.000',
          'cigarettesPerDay': -5,
          'pricePerPackRials': 99999999999999,
          'perPack': 0,
        }),
      );
      expect(a.cigarettesPerDay, 0);
      expect(a.pricePerPackMinor, 99999999999999);
      expect(a.perPack, 1);
    });

    test('toJson round-trips', () {
      final a = QuitAttempt(
        id: 'q1',
        startedAt: DateTime(2026, 10, 1, 9),
        cigarettesPerDay: 15,
        pricePerPackRials: 300000,
        perPack: 20,
        endedAt: null,
        endedWhy: null,
      );
      final again = QuitAttempt.fromBody('q1', a.toJson());
      expect(again.startedAt, a.startedAt);
      expect(again.cigarettesPerDay, 15);
      expect(again.pricePerPackMinor, 300000);
      expect(again.perPack, 20);
      expect(again.isActive, isTrue);
    });

    test('ending an attempt is an explicit override, never a silent one', () {
      final a = QuitAttempt(
        id: 'q1',
        startedAt: DateTime(2026, 10, 1),
        cigarettesPerDay: 10,
        pricePerPackRials: 100000,
        perPack: 20,
        endedAt: null,
        endedWhy: null,
      );
      final body = a.toJson(
        endedAt: DateTime(2026, 10, 5, 20),
        endedWhy: 'restart',
      );
      expect(body['endedWhy'], 'restart');
      final again = QuitAttempt.fromBody('q1', body);
      expect(again.isActive, isFalse);
    });
  });

  group('Craving', () {
    test('reads a well-formed record', () {
      final c = Craving.fromRecord(
        record('c1', {
          'at': '2026-10-12T13:20:00.000',
          'intensity': 3,
          'triggers': ['stress', 'coffee'],
          'coping': 'water',
          'note': 'after the meeting',
        }, kind: 'craving'),
      );
      expect(c.at, DateTime.parse('2026-10-12T13:20:00.000'));
      expect(c.intensity, 3);
      expect(c.triggers, ['stress', 'coffee']);
      expect(c.coping, 'water');
      expect(c.note, 'after the meeting');
    });

    test('missing and wrong-typed fields read as their defaults', () {
      final c = Craving.fromRecord(
        record('c1', {
          'at': 'not a date',
          'intensity': 'high',
          'triggers': 'stress',
          'coping': 7,
          'note': null,
        }, kind: 'craving'),
      );
      expect(c.at.year, greaterThanOrEqualTo(2026));
      expect(c.intensity, 1);
      expect(c.triggers, isEmpty);
      expect(c.coping, isNull);
      expect(c.note, '');
    });

    test('intensity is clamped into 1–3', () {
      Craving from(int v) => Craving.fromBody('c', {
        'at': DateTime.now().toIso8601String(),
        'intensity': v,
        'triggers': [],
      });
      expect(from(-2).intensity, 1);
      expect(from(9).intensity, 3);
      expect(from(2).intensity, 2);
    });

    test('non-string entries in triggers are dropped', () {
      final c = Craving.fromBody('c', {
        'at': DateTime.now().toIso8601String(),
        'triggers': ['stress', 5, null, 'coffee'],
      });
      expect(c.triggers, ['stress', 'coffee']);
    });

    test('toJson round-trips', () {
      final c = Craving(
        id: 'c1',
        at: DateTime(2026, 10, 12, 13, 20),
        intensity: 2,
        triggers: ['stress'],
        coping: 'walk',
        note: '',
      );
      final again = Craving.fromBody('c1', c.toJson());
      expect(again.at, c.at);
      expect(again.intensity, 2);
      expect(again.triggers, ['stress']);
      expect(again.coping, 'walk');
      expect(again.note, '');
    });
  });

  test('the vocabularies are fixed and stable', () {
    expect(cravingTriggerKeys, containsAll(['stress', 'other']));
    expect(cravingCopingKeys, containsAll(['water', 'waited']));
    expect(cravingTriggerKeys.toSet().length, cravingTriggerKeys.length);
    expect(cravingCopingKeys.toSet().length, cravingCopingKeys.length);
  });
}
