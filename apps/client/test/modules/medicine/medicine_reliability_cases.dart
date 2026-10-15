part of 'medicine_reliability_test.dart';

void _registerStockCases(
  FaultStore Function() getStore,
  NexModuleStore Function() getInner,
  Widget Function(Widget) host,
) {
  test(
    'insufficient stock correction restores only the actual deduction',
    () async {
      await getInner().put('medicine', 'm', {
        'name': 'Example',
        'quantity': 3,
        'doseUnits': 5,
        'unknown': true,
      });
      await MedicineRepository.log(getStore(), 'm', 'taken');
      final dose = (await getInner().list('dose')).single;
      expect(dose.body['takenUnits'], 3);
      expect(dose.body['stockLimited'], isTrue);
      expect((await getInner().get('medicine', 'm'))!['quantity'], 0);
      final undo = await MedicineRepository.deleteDose(
        getStore(),
        'm',
        dose.id,
      );
      expect((await getInner().get('medicine', 'm'))!['quantity'], 3);
      await undo();
      expect((await getInner().get('medicine', 'm'))!['quantity'], 0);
      expect((await getInner().get('medicine', 'm'))!['unknown'], isTrue);
    },
  );
  test(
    'stock write failure rolls back the dose even after the write committed',
    () async {
      final original = {'quantity': 10, 'doseUnits': 2};
      await getInner().put('medicine', 'm', original);
      getStore().failPut = 'medicine';
      getStore().after = true;
      await expectLater(
        MedicineRepository.log(getStore(), 'm', 'taken'),
        throwsStateError,
      );
      expect(await getInner().get('medicine', 'm'), original);
      expect(await getInner().list('dose'), isEmpty);
      await MedicineRepository.log(getStore(), 'm', 'taken');
      expect((await getInner().get('medicine', 'm'))!['quantity'], 8);
    },
  );
  test(
    'text edit preserves fresh stock; recount isolates old corrections',
    () async {
      await getInner().put('medicine', 'm', {
        'quantity': 10,
        'doseUnits': 2,
        'future': 'keep',
        'name': 'Example',
      });
      await MedicineRepository.log(getStore(), 'm', 'taken');
      final dose = (await getInner().list('dose')).single;
      await MedicineRepository.save(
        getStore(),
        'm',
        {'name': 'Edited', 'quantity': 10},
        ['name'],
        existing: true,
      );
      expect((await getInner().get('medicine', 'm'))!['quantity'], 8);
      await MedicineRepository.save(
        getStore(),
        'm',
        {'quantity': 20},
        ['quantity'],
        existing: true,
      );
      await MedicineRepository.deleteDose(getStore(), 'm', dose.id);
      expect((await getInner().get('medicine', 'm'))!['quantity'], 20);
      expect((await getInner().get('medicine', 'm'))!['future'], 'keep');
    },
  );
  test('valid pending time and invalid refill are handled explicitly', () {
    expect(MedicineParse.count('oops'), isNull);
    expect(MedicineParse.expiry('2026/04/31'), MedicineParse.invalid);
  });
  testWidgets('pending valid time is saved; invalid refill is rejected', (
    tester,
  ) async {
    await tester.pumpWidget(host(MedicineEditorSheet(store: getStore())));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('medicine-field-name')),
      'Example',
    );
    await tester.enterText(
      find.byKey(const ValueKey('medicine-field-time')),
      '٠٨:٣٠',
    );
    await tester.enterText(
      find.byKey(const ValueKey('medicine-field-refill')),
      'oops',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final save = find.byKey(const ValueKey('medicine-save'));
    await Scrollable.ensureVisible(tester.element(save), alignment: 0.4);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(await getInner().list('medicine'), isEmpty);
    await tester.enterText(
      find.byKey(const ValueKey('medicine-field-refill')),
      '0',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(tester.element(save), alignment: 0.4);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    final body = (await getInner().list('medicine')).single.body;
    expect(body['times'], ['08:30']);
    expect(body['refillThreshold'], 0);
    expect(tester.takeException(), isNull);
  });
  test('unknown and skipped legacy actions do not invent stock', () async {
    await getInner().put('medicine', 'm', {'quantity': 3, 'doseUnits': 2});
    await expectLater(
      MedicineRepository.log(getStore(), 'm', 'unknown'),
      throwsArgumentError,
    );
    await getInner().put('dose', 'd', {
      'medicineId': 'm',
      'action': 'skipped',
      'takenUnits': 5,
    });
    await MedicineRepository.deleteDose(getStore(), 'm', 'd');
    expect((await getInner().get('medicine', 'm'))!['quantity'], 3);
  });
  testWidgets('a seventh pending reference time is refused visibly', (
    tester,
  ) async {
    final raw = {
      'name': 'Example',
      'times': ['01:00', '02:00', '03:00', '04:00', '05:00', '06:00'],
    };
    await getInner().put('medicine', 'm', raw);
    await tester.pumpWidget(
      host(
        MedicineEditorSheet(
          store: getStore(),
          existing: ModuleRecord(
            module: 'medicine',
            kind: 'medicine',
            id: 'm',
            body: raw,
            updatedAt: DateTime.now(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('medicine-field-time')),
      '07:00',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(
      tester.element(find.byKey(const ValueKey('medicine-save'))),
      alignment: 0.4,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('medicine-save')));
    await tester.pumpAndSettle();
    expect(await getInner().get('medicine', 'm'), raw);
    expect(
      find.text('Up to 6 times. Remove one or clear this entry.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
