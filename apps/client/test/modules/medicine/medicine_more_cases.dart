part of 'medicine_widget_test.dart';

void _registerMedicineMore(
  Future<NexTestHarness> Function(WidgetTester) pumpScreen,
) {
  group('archived and deleted', () {
    testWidgets('archiving moves a medicine out of the list', (tester) async {
      final h = await pumpScreen(tester);
      await _add(tester, name: 'Medicine A');
      await tester.tap(find.text('Medicine A'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('medicine-detail-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Archived'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('medicine-archive-confirm')));
      await tester.pumpAndSettle();

      final stored = await h.services.moduleRecords('medicine', 'medicine');
      expect(stored.single.body['archived'], isTrue);
      expect(find.text('Medicine A'), findsNothing);

      // And it comes back with its history intact.
      await tester.tap(find.byKey(const ValueKey('medicine-archived-toggle')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('medicine-archived-toggle')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show archived'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(ValueKey('medicine-unarchive-${stored.single.id}')),
      );
      await tester.pumpAndSettle();
      final back = await h.services.moduleRecords('medicine', 'medicine');
      expect(back.single.body['archived'], isFalse);
    });

    testWidgets('deleting a medicine takes its history, and undo returns it', (
      tester,
    ) async {
      final h = await pumpScreen(tester);
      await _add(tester, name: 'Medicine A', quantity: '30', doseUnits: '1');
      await tester.tap(find.text('Medicine A'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('medicine-taken')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('medicine-taken')));
      await tester.pumpAndSettle();
      expect(await h.services.moduleRecords('medicine', 'dose'), hasLength(2));

      await tester.tap(find.byKey(const ValueKey('medicine-detail-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('medicine-delete-confirm')));
      await tester.pumpAndSettle();
      expect(await h.services.moduleRecords('medicine', 'medicine'), isEmpty);
      expect(await h.services.moduleRecords('medicine', 'dose'), isEmpty);

      await tester.tap(find.byKey(const ValueKey('medicine-undo')));
      await tester.pumpAndSettle();
      expect(
        await h.services.moduleRecords('medicine', 'medicine'),
        hasLength(1),
      );
      expect(await h.services.moduleRecords('medicine', 'dose'), hasLength(2));
    });
  });

  group('persistence and isolation', () {
    testWidgets('a reopened screen finds everything where it was', (
      tester,
    ) async {
      final h = await pumpScreen(tester);
      await _add(tester, name: 'Medicine A');
      await _pump(
        tester,
        MedicineScreen(store: NexModuleStore(h.services, 'medicine')),
      );
      expect(find.text('Medicine A'), findsWidgets);
    });

    testWidgets('another module sees none of it', (tester) async {
      final h = await pumpScreen(tester);
      await _add(tester, name: 'Medicine A');
      expect(await h.services.moduleRecords('other', 'medicine'), isEmpty);
      expect(await h.services.moduleRecords('other', 'dose'), isEmpty);
    });
  });

  group('dates on the reader’s calendar', () {
    testWidgets('the expiry day reads on the shared label (English)', (
      tester,
    ) async {
      await pumpScreen(tester);
      await _add(tester, name: 'Medicine A', expiry: '2030/10/13');
      await tester.tap(find.text('Medicine A'));
      await tester.pumpAndSettle();
      // Civil `yyyy/MM/dd` for an English reader — from the same stored day.
      expect(find.text('2030/10/13'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('expiry and dose days read Jalali in Persian', (tester) async {
      final h = await NexTestHarness.create(name: 'medicine_fa_dates_');
      addTearDown(h.dispose);
      final store = NexModuleStore(h.services, 'medicine');
      await store.put('medicine', 'm1', {
        'v': 2,
        'name': 'داروی نمونه',
        'expiresAt': '2030-10-13T00:00:00.000',
      });
      await store.put('dose', 'd1', {
        'v': 2,
        'medicineId': 'm1',
        'action': 'taken',
        'at': '2026-10-13T15:30:00.000Z',
        'stockDelta': 0,
      });
      await _pump(
        tester,
        MedicineScreen(store: store),
        locale: const Locale('fa'),
      );
      await tester.tap(find.text('داروی نمونه'));
      await tester.pumpAndSettle();
      // The stored civil day, shown as the Jalali day in Persian digits —
      // never a Gregorian year a Persian reader has to work out.
      expect(find.text('۱۴۰۹/۰۷/۲۱'), findsOneWidget);
      expect(find.text('۱۴۰۵/۰۷/۲۱ ساعت ۱۵:۳۰'), findsOneWidget);
      expect(find.textContaining(RegExp('20[0-9][0-9]/')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an impossible expiry says so in its own words', (
      tester,
    ) async {
      final h = await pumpScreen(tester);
      await tester.tap(addButton('medicine-fab', 'medicine-empty-add'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('medicine-field-name')),
        'Medicine A',
      );
      await tester.enterText(
        find.byKey(const ValueKey('medicine-field-expiry')),
        '1405/07/21',
      );
      await _tapSave(tester);
      // A date error in the date field's words, not the number fields'.
      expect(find.text('Not a date'), findsOneWidget);
      expect(find.text('Write a whole number, 0 or more'), findsNothing);
      expect(await h.services.moduleRecords('medicine', 'medicine'), isEmpty);
    });
  });

  group('the one-time reminder control', () {
    // Scheduling itself needs the platform's notification permission and a
    // rolled-out module, so these tests stay honest to what a test build can
    // observe: the shared control sits where a person manages an active
    // medicine, and an archived one offers nothing (the platform cancels
    // its reminders with the archive).
    ModuleRecord medicine(String id, Map<String, Object?> body) => ModuleRecord(
      module: 'medicine',
      kind: 'medicine',
      id: id,
      body: body,
      updatedAt: DateTime.now(),
    );

    testWidgets('an active medicine offers it on the detail sheet', (
      tester,
    ) async {
      final h = await NexTestHarness.create(name: 'medicine_reminder_');
      addTearDown(h.dispose);
      final store = NexModuleStore(h.services, 'medicine');
      await store.put('medicine', 'm1', {'v': 2, 'name': 'Medicine A'});
      await _pump(
        tester,
        Scaffold(
          body: MedicineDetailSheet(
            store: store,
            record: medicine('m1', {'v': 2, 'name': 'Medicine A'}),
          ),
        ),
      );
      expect(find.text('Pick a time…'), findsOneWidget);
      expect(find.text('Remove reminder'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an archived medicine offers no reminder', (tester) async {
      // A tall surface, so "not there" is a real answer and not a scroll
      // view that simply has not built that far.
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final h = await NexTestHarness.create(name: 'medicine_reminder_');
      addTearDown(h.dispose);
      final store = NexModuleStore(h.services, 'medicine');
      final body = {'v': 2, 'name': 'Medicine A', 'archived': true};
      await store.put('medicine', 'm1', body);
      await _pump(
        tester,
        Scaffold(
          body: MedicineDetailSheet(store: store, record: medicine('m1', body)),
        ),
      );
      expect(find.text('Pick a time…'), findsNothing);
      expect(find.text('Remove reminder'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('appearance', () {
    testWidgets('Persian reads right to left, in Persian words', (
      tester,
    ) async {
      final h = await NexTestHarness.create(name: 'medicine_fa_');
      addTearDown(h.dispose);
      await _pump(
        tester,
        MedicineScreen(store: NexModuleStore(h.services, 'medicine')),
        locale: const Locale('fa'),
      );
      expect(find.text('جعبه دارو'), findsOneWidget);
      expect(addButton('medicine-fab', 'medicine-empty-add'), findsOneWidget);
      expect(
        Directionality.of(tester.state(find.byType(Scaffold)).context),
        TextDirection.rtl,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('dark, twice the text, a small phone', (tester) async {
      final h = await NexTestHarness.create(name: 'medicine_look_');
      addTearDown(h.dispose);
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.dark),
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(2)),
            child: child ?? const SizedBox.shrink(),
          ),
          home: MedicineScreen(store: NexModuleStore(h.services, 'medicine')),
        ),
      );
      await tester.pumpAndSettle();
      expect(addButton('medicine-fab', 'medicine-empty-add'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
