import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/medicine/medicine_models.dart';

/// The stored shapes: what goes in, what comes back, and what happens to
/// an old or broken record — every reader is defensive, because a record
/// written by an earlier version has to keep opening. Test entries are
/// neutral placeholders, never anyone's real medicines.
void main() {
  group('medicine bodies', () {
    test('round-trips every field', () {
      final body = MedicineModels.medicineBody(
        name: ' Medicine A ',
        strength: '100 mg',
        packageUnit: 'box',
        instructions: 'One in the morning',
        times: const ['08:00', '21:30'],
        days: 'every day',
        purpose: 'a private note',
        quantity: 30,
        doseUnits: 1,
        expiresAt: DateTime.utc(2027, 1, 1),
        refillThreshold: 5,
        archived: false,
      );
      expect(MedicineModels.readString(body, 'name'), 'Medicine A');
      expect(MedicineModels.readString(body, 'strength'), '100 mg');
      expect(MedicineModels.readString(body, 'package'), 'box');
      expect(
        MedicineModels.readString(body, 'instructions'),
        'One in the morning',
      );
      expect(MedicineModels.readTimes(body), ['08:00', '21:30']);
      expect(MedicineModels.readString(body, 'days'), 'every day');
      expect(MedicineModels.readCount(body, 'quantity'), 30);
      expect(MedicineModels.readCount(body, 'doseUnits'), 1);
      expect(
        MedicineModels.readDate(body, 'expiresAt'),
        DateTime.utc(2027, 1, 1),
      );
      expect(MedicineModels.readCount(body, 'refillThreshold'), 5);
      expect(MedicineModels.readArchived(body), isFalse);
    });

    test('absent numbers stay absent, not zero', () {
      final body = MedicineModels.medicineBody(
        name: 'Medicine B',
        strength: '',
        packageUnit: '',
        instructions: '',
        times: const [],
        days: '',
        purpose: '',
        quantity: null,
        doseUnits: null,
        expiresAt: null,
        refillThreshold: null,
        archived: false,
      );
      expect(body['quantity'], isNull);
      expect(body['doseUnits'], isNull);
      expect(body.containsKey('expiresAt'), isFalse);
      expect(body['refillThreshold'], isNull);
      expect(MedicineModels.readTimes(body), isEmpty);
    });

    test('malformed fields read as empty or null, never throw', () {
      const body = {
        'name': 42,
        'strength': true,
        'quantity': -5,
        'doseUnits': 'two',
        'expiresAt': 2027,
        'times': ['08:00', 5, null, '21:30'],
        'refillThreshold': 1.5,
      };
      expect(MedicineModels.readString(body, 'name'), '');
      expect(MedicineModels.readString(body, 'strength'), '');
      expect(MedicineModels.readCount(body, 'quantity'), isNull);
      expect(MedicineModels.readCount(body, 'doseUnits'), isNull);
      expect(MedicineModels.readDate(body, 'expiresAt'), isNull);
      expect(MedicineModels.readCount(body, 'refillThreshold'), isNull);
      expect(MedicineModels.readTimes(body), ['08:00', '21:30']);
      expect(MedicineModels.readArchived(body), isFalse);
    });

    test('archived reads true only for true', () {
      expect(MedicineModels.readArchived({'archived': true}), isTrue);
      expect(MedicineModels.readArchived({'archived': 'yes'}), isFalse);
      expect(MedicineModels.readArchived(const {}), isFalse);
    });
  });

  group('dose bodies', () {
    test('a taken dose with stock', () {
      final body = MedicineModels.doseBody(
        medicineId: 'm1',
        action: MedicineModels.taken,
        at: DateTime.utc(2026, 10, 12, 8),
        takenUnits: 2,
      );
      expect(body['medicineId'], 'm1');
      expect(body['action'], 'taken');
      expect(body['takenUnits'], 2);
      expect(
        DateTime.parse(body['at']! as String),
        DateTime.utc(2026, 10, 12, 8),
      );
    });

    test('a dose that took nothing stores no takenUnits', () {
      final body = MedicineModels.doseBody(
        medicineId: 'm1',
        action: MedicineModels.skipped,
        at: DateTime.utc(2026, 10, 12, 8),
      );
      expect(body.containsKey('takenUnits'), isFalse);
    });

    test('a zero or negative takenUnits stores none', () {
      final body = MedicineModels.doseBody(
        medicineId: 'm1',
        action: MedicineModels.taken,
        at: DateTime.utc(2026, 10, 12, 8),
        takenUnits: 0,
      );
      expect(body.containsKey('takenUnits'), isFalse);
    });
  });
}
