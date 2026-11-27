import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/medicine/medicine_models.dart';
import 'package:nex_client/modules/medicine/medicine_shared.dart';

/// Medicine in the shape every module shares (docs/18, 2.8.4): the times a
/// routine names, answered or not; each box's expiry; a line per medicine;
/// the person as `{"name": …}`; all of it private.
void main() {
  ModuleRecord record(String kind, String id, Map<String, Object?> body) =>
      ModuleRecord(
        module: 'medicine',
        kind: kind,
        id: id,
        body: body,
        updatedAt: DateTime(2026),
      );

  test('the times of a routine, and the boxes that expire', () {
    final shared = MedicineShared(
      medicines: [
        record('medicine', 'm1', {
          'v': 3,
          'name': 'Medicine A',
          'times': ['08:00', '20:00'],
        }),
        record('medicine', 'gone', {
          'name': 'Archived',
          'archived': true,
          'times': ['09:00'],
        }),
      ],
      doses: [
        record(
          'dose',
          'd1',
          MedicineModels.doseBody(
            medicineId: 'm1',
            action: MedicineModels.taken,
            at: DateTime(2026, 11, 20, 8, 5),
            slot: '08:00',
          ),
        ),
      ],
      boxes: [
        record(
          'box',
          'b1',
          MedicineModels.boxBody(
            medicineId: 'm1',
            expiresAt: DateTime(2026, 11, 21),
            addedAt: DateTime(2026, 1, 1),
          ),
        ),
      ],
    );
    final dues = shared.duesBetween(
      DateTime(2026, 11, 20),
      DateTime(2026, 11, 21, 23, 59),
    );
    final doses = dues.where((d) => d.kind == 'dose').toList();
    expect(doses, hasLength(4), reason: 'two a day, two days');
    expect(doses.first.at, DateTime(2026, 11, 20, 8));
    expect(doses.first.done, isTrue, reason: 'a log answers it');
    expect(doses[1].done, isFalse);
    expect(doses.every((d) => d.title == 'Medicine A'), isTrue);
    final expiry = dues.singleWhere((d) => d.kind == 'expiry');
    expect((expiry.title, expiry.at), ('Medicine A', DateTime(2026, 11, 21)));
    expect(dues.every((d) => d.private), isTrue);
  });

  test('a log from the detail sheet answers the moment at its own time', () {
    // A dose logged with no slot — the detail sheet’s «Taken» — must still
    // mark the routine moment it answers, or a person who never opens the
    // Today page reads “0 of 2 doses today” having taken both.
    final shared = MedicineShared(
      medicines: [
        record('medicine', 'm1', {
          'v': 3,
          'name': 'Medicine A',
          'times': ['08:00', '20:00'],
        }),
      ],
      doses: [
        record(
          'dose',
          'd1',
          MedicineModels.doseBody(
            medicineId: 'm1',
            action: MedicineModels.taken,
            at: DateTime(2026, 11, 20, 8),
          ),
        ),
      ],
    );
    final dues = shared.duesBetween(
      DateTime(2026, 11, 20),
      DateTime(2026, 11, 20, 23, 59),
    );
    final doses = dues.where((d) => d.kind == 'dose').toList();
    expect(doses, hasLength(2));
    expect(doses.first.done, isTrue, reason: 'logged at the routine’s time');
    expect(doses.last.done, isFalse);
  });

  test('a log whose action is neither taken nor skipped answers nothing', () {
    final shared = MedicineShared(
      medicines: [
        record('medicine', 'm1', {
          'v': 3,
          'name': 'Medicine A',
          'times': ['08:00'],
        }),
      ],
      doses: [
        record('dose', 'd1', {
          'v': 2,
          'medicineId': 'm1',
          'action': 'something-else',
          'at': DateTime(2026, 11, 20, 8).toUtc().toIso8601String(),
          'slot': '08:00',
        }),
      ],
    );
    final dues = shared.duesBetween(
      DateTime(2026, 11, 20),
      DateTime(2026, 11, 20, 23, 59),
    );
    expect(dues.singleWhere((d) => d.kind == 'dose').done, isFalse);
  });

  test('a line per medicine, with whose it is; the person as an object', () {
    final body = MedicineModels.medicineBody(
      name: 'Medicine A',
      strength: '500 mg',
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
      person: 'Sara',
    );
    expect(body['person'], {'name': 'Sara'});
    expect(MedicineModels.readPerson(body), 'Sara');
    expect(MedicineModels.readPerson({'person': 'Old string'}), 'Old string');
    expect(MedicineModels.readPerson(const {}), '');
    final line = MedicineShared.summarize(record('medicine', 'm1', body))!;
    expect(
      (line.title, line.detail, line.private),
      ('Medicine A', 'Sara · 500 mg', true),
    );
    expect(MedicineShared.summarize(record('dose', 'd', const {})), isNull);
    expect(
      MedicineModels.medicineBody(
        name: 'Mine',
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
      ).containsKey('person'),
      isFalse,
      reason: 'me is the absence of someone else',
    );
  });
}
