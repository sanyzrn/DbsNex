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
      expect(find.byKey(const ValueKey('medicine-fab')), findsOneWidget);
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
      expect(find.byKey(const ValueKey('medicine-fab')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
