part of 'warranty_reliability_test.dart';

void _registerWarrantyCases(
  FaultStore Function() getStore,
  NexModuleStore Function() getInner,
  Widget Function(Widget) host,
) {
  test('decimal tomans are exact and multiplication cannot overflow', () {
    expect(WarrantyParse.rials('۱٫۵', inTomans: true), 15);
    expect(WarrantyParse.rials('1.55', inTomans: true), isNull);
    expect(WarrantyParse.rials('900719925474099.2', inTomans: true), isNull);
    expect(WarrantyParse.date('2026/02/29'), WarrantyParse.invalid);
  });
  test('missing parent cannot be recreated or gain an orphan claim', () async {
    await expectLater(
      WarrantyRepository.save(
        getStore(),
        'missing',
        {'product': 'Example'},
        ['product'],
        existing: true,
      ),
      throwsStateError,
    );
    await expectLater(
      WarrantyRepository.claim(getStore(), 'missing', 'c', 'claim', 'Typed'),
      throwsStateError,
    );
    expect(await getInner().list('claim'), isEmpty);
    expect(await getInner().list('warranty'), isEmpty);
  });
  test('edits and Undo preserve unknown claims and draft bodies', () async {
    await getInner().put('warranty', 'w', {
      'product': 'Old',
      'amountRials': 15,
      'future': true,
    });
    await getInner().put('claim', 'c', {
      'warrantyId': 'w',
      'note': 'Typed',
      'unknown': true,
    });
    await getInner().put('draft', 'warranty:w', {'raw': 'input'});
    await WarrantyRepository.save(
      getStore(),
      'w',
      {'product': 'Edited'},
      ['product'],
      existing: true,
    );
    expect((await getInner().get('warranty', 'w'))!['amountRials'], 15);
    final undo = await LocalWrites.delete(
      getStore(),
      'warranty',
      'w',
      children: 'claim',
      parentField: 'warrantyId',
    );
    expect(await getInner().get('draft', 'warranty:w'), isNull);
    await undo();
    expect((await getInner().get('claim', 'c'))!['unknown'], isTrue);
    expect(await getInner().get('draft', 'warranty:w'), {'raw': 'input'});
  });
  testWidgets('date labels are not currency-grouped', (tester) async {
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) =>
              Text(WarrantyFields.dayLabel(context, DateTime(2026, 10, 13))),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('2026/10/13'), findsOneWidget);
    expect(find.text('2,026/10/13'), findsNothing);
  });
  testWidgets('invalid coverage explains why Save cannot proceed', (
    tester,
  ) async {
    await tester.pumpWidget(host(WarrantyEditorSheet(store: getStore())));
    await tester.pumpAndSettle();
    expect(find.text('Purchase date'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('warranty-field-product')),
      'Example',
    );
    await tester.enterText(
      find.byKey(const ValueKey('warranty-field-purchase')),
      '2026/10/13',
    );
    await tester.enterText(
      find.byKey(const ValueKey('warranty-field-duration')),
      '9007199254740991',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(
      tester.element(find.byKey(const ValueKey('warranty-save'))),
      alignment: 0.4,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('warranty-save')));
    await tester.pumpAndSettle();
    expect(await getInner().list('warranty'), isEmpty);
    expect(
      find.text('Enter a valid end date or 1–2400 months ending by 2100.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('a missing legacy purchase date stays empty, never invented', (
    tester,
  ) async {
    final raw = {'product': 'Example', 'coverageEnd': '2027-10-13'};
    await getInner().put('warranty', 'w', raw);
    await tester.pumpWidget(
      host(
        WarrantyEditorSheet(
          store: getStore(),
          existing: ModuleRecord(
            module: 'warranty',
            kind: 'warranty',
            id: 'w',
            body: raw,
            updatedAt: DateTime.now(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('warranty-field-purchase')),
          )
          .controller!
          .text,
      isEmpty,
    );
    expect(await getInner().get('warranty', 'w'), raw);
  });
}
