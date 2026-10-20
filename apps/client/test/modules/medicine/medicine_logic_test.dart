import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/medicine/medicine_logic.dart';

/// The medicine calculations, on their own: times as they are written,
/// stock as the person's own numbers move it, and the expiry and refill
/// states read on opening. Nothing here knows anything medical.
void main() {
  final now = DateTime(2026, 10, 12, 15, 0);

  group('routine times as written', () {
    test('missing zeros are filled in', () {
      expect(MedicineLogic.normalizeTime('8:3'), '08:03');
      expect(MedicineLogic.normalizeTime(' 21:5 '), '21:05');
    });

    test('Persian digits are read as the numbers they are', () {
      expect(MedicineLogic.normalizeTime('۰۸:۳۰'), '08:30');
      expect(MedicineLogic.normalizeTime('۲۱:۰۵'), '21:05');
    });

    test('a dot is accepted as the separator', () {
      expect(MedicineLogic.normalizeTime('8.30'), '08:30');
    });

    test('an impossible time is refused, not rounded', () {
      expect(MedicineLogic.normalizeTime('25:00'), isNull);
      expect(MedicineLogic.normalizeTime('12:75'), isNull);
      expect(MedicineLogic.normalizeTime('noon'), isNull);
      expect(MedicineLogic.normalizeTime(''), isNull);
    });
  });

  group('stock', () {
    test('falls by exactly the units the person wrote', () {
      expect(MedicineLogic.reduceStock(30, 1), 29);
      expect(MedicineLogic.reduceStock(30, 2), 28);
    });

    test('never below zero', () {
      expect(MedicineLogic.reduceStock(1, 4), 0);
      expect(MedicineLogic.reduceStock(0, 1), 0);
    });

    test('does not move when either number is absent', () {
      expect(MedicineLogic.reduceStock(null, 1), isNull);
      expect(MedicineLogic.reduceStock(30, null), 30);
      expect(MedicineLogic.reduceStock(30, 0), 30);
    });

    test('comes back when a log is deleted', () {
      expect(MedicineLogic.restoreStock(28, 2), 30);
      expect(MedicineLogic.restoreStock(0, 4), 4);
    });

    test('a log that took nothing restores nothing', () {
      expect(MedicineLogic.restoreStock(30, null), 30);
      expect(MedicineLogic.restoreStock(30, 0), 30);
      expect(MedicineLogic.restoreStock(null, 2), isNull);
    });

    test('a delete and an undo leave the stock where it began', () {
      var stock = 30;
      stock = MedicineLogic.reduceStock(stock, 2)!;
      stock = MedicineLogic.restoreStock(stock, 2)!;
      expect(stock, 30);
    });
  });

  group('the expiry date as read on opening', () {
    test('today and earlier are expired', () {
      expect(MedicineLogic.expiryOf(DateTime(2026, 10, 12), now), (
        expired: true,
        soon: false,
      ));
      expect(MedicineLogic.expiryOf(DateTime(2026, 10, 11), now), (
        expired: true,
        soon: false,
      ));
    });

    test('tomorrow through a week away is "soon"', () {
      expect(MedicineLogic.expiryOf(DateTime(2026, 10, 13), now), (
        expired: false,
        soon: true,
      ));
      expect(MedicineLogic.expiryOf(DateTime(2026, 10, 19), now), (
        expired: false,
        soon: true,
      ));
    });

    test('past a week, or none written, is neither', () {
      expect(MedicineLogic.expiryOf(DateTime(2026, 10, 20), now), (
        expired: false,
        soon: false,
      ));
      expect(MedicineLogic.expiryOf(DateTime(2027, 1, 1), now), (
        expired: false,
        soon: false,
      ));
      expect(MedicineLogic.expiryOf(null, now), (expired: false, soon: false));
    });

    test('midnight of a later day is that day, not the one before', () {
      // An expiry stored at 00:00 of the 13th is "the 13th".
      expect(MedicineLogic.expiryOf(DateTime(2026, 10, 13, 0, 0), now), (
        expired: false,
        soon: true,
      ));
    });
  });

  group('refill', () {
    test('at or under the threshold the person wrote', () {
      expect(MedicineLogic.needsRefill(4, 5), isTrue);
      expect(MedicineLogic.needsRefill(5, 5), isTrue);
      expect(MedicineLogic.needsRefill(6, 5), isFalse);
    });

    test('never without both numbers', () {
      expect(MedicineLogic.needsRefill(null, 5), isFalse);
      expect(MedicineLogic.needsRefill(4, null), isFalse);
    });
  });

  group('dose history', () {
    ModuleRecord dose(String id, Map<String, Object?> body) => ModuleRecord(
      module: 'medicine',
      kind: 'dose',
      id: id,
      body: body,
      updatedAt: DateTime.now(),
    );

    test('only the doses that belong to this medicine, in store order', () {
      final doses = [
        dose('d1', {'medicineId': 'a', 'action': 'taken'}),
        dose('d2', {'medicineId': 'b', 'action': 'skipped'}),
        dose('d3', {'medicineId': 'a', 'action': 'skipped'}),
      ];
      final mine = MedicineLogic.dosesFor(doses, 'a');
      expect(mine.map((d) => d.id), ['d1', 'd3']);
    });

    test('a broken medicineId belongs to no medicine', () {
      final doses = [
        dose('d1', {'medicineId': 5, 'action': 'taken'}),
        dose('d2', {'action': 'taken'}),
        dose('d3', {'medicineId': 'a', 'action': 'taken'}),
      ];
      expect(MedicineLogic.dosesFor(doses, 'a').map((d) => d.id), ['d3']);
    });
  });

  group('names', () {
    test('what a person would read as the same word', () {
      expect(MedicineLogic.sameName(' Aspirin ', 'aspirin'), isTrue);
      expect(MedicineLogic.sameName('آسپرین', 'آسپرین'), isTrue);
      expect(MedicineLogic.sameName('آسپرین', 'استامینوفن'), isFalse);
    });

    test('a name is the one thing worth requiring', () {
      expect(MedicineLogic.canSave('  Aspirin '), isTrue);
      expect(MedicineLogic.canSave('   '), isFalse);
    });
  });
}
