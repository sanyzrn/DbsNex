import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/parking/parking_screen.dart';
import 'package:nex_client/platform/nex_services.dart';

import '../../support/nex_harness.dart';

/// The parking screen, used the way a person uses it: empty at first, a
/// parking saved, found, edited, deleted and undone — with the vehicle
/// question and persistence checked on the way.
void main() {
  Future<NexTestHarness> pumpScreen(
    WidgetTester tester, {
    NexTestHarness? harness,
  }) async {
    final h = harness ?? await NexTestHarness.create(name: 'parking_ui_');
    if (harness == null) addTearDown(h.dispose);
    await _pump(
      tester,
      ParkingScreen(store: NexModuleStore(h.services, 'parking')),
    );
    return h;
  }

  group('empty and creation', () {
    testWidgets('says what to do when nothing is parked yet', (tester) async {
      await pumpScreen(tester);
      expect(find.byKey(const ValueKey('parking-empty')), findsOneWidget);
      expect(find.byKey(const ValueKey('parking-fab')), findsOneWidget);
    });

    testWidgets('writes a parking and shows it as the open one', (
      tester,
    ) async {
      final h = await pumpScreen(tester);
      await _create(tester, place: 'Saba mall', vehicle: 'Car', floor: '-1');

      final sessions = await h.services.moduleRecords('parking', 'session');
      expect(sessions, hasLength(1));
      expect(sessions.single.body['place'], 'Saba mall');
      expect(sessions.single.body['vehicle'], 'Car');
      expect(sessions.single.body.containsKey('foundAt'), isFalse);

      expect(find.byKey(const ValueKey('parking-active-card')), findsNothing);
      expect(find.text('Saba mall'), findsWidgets);
      expect(find.byKey(const ValueKey('parking-found')), findsOneWidget);
    });

    testWidgets('without a place it says so and saves nothing', (tester) async {
      final h = await pumpScreen(tester);
      await tester.tap(find.byKey(const ValueKey('parking-fab')));
      await tester.pumpAndSettle();
      // Something is written, so leaving would lose work — but a place
      // is still missing, and saving says so.
      await tester.enterText(
        find.byKey(const ValueKey('parking-field-vehicle')),
        'Car',
      );
      await _tapSave(tester);
      expect(find.text('Write where you parked.'), findsOneWidget);
      expect(await h.services.moduleRecords('parking', 'session'), isEmpty);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('parking-discard')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('parking-save')), findsNothing);
    });

    testWidgets('the place is remembered as somewhere to park again', (
      tester,
    ) async {
      await pumpScreen(tester);
      await _create(tester, place: 'Saba mall', floor: '1');
      expect(find.byKey(const ValueKey('parking-empty')), findsNothing);
      expect(find.text('Saba mall'), findsWidgets);

      // From the remembered place, the editor comes prefilled.
      await tester.tap(find.text('Saba mall').last);
      await tester.pumpAndSettle();
      expect(
        _fieldText(tester, const ValueKey('parking-field-place')),
        'Saba mall',
      );
      expect(_fieldText(tester, const ValueKey('parking-field-floor')), '1');

      // Nothing was typed by hand, so leaving asks nothing and closes.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('parking-save')), findsNothing);
    });
  });

  group('finding the car', () {
    testWidgets('records foundAt and keeps it in history', (tester) async {
      final h = await pumpScreen(tester);
      await _create(tester, place: 'Saba mall');
      await tester.tap(find.byKey(const ValueKey('parking-found')));
      await tester.pumpAndSettle();

      final sessions = await h.services.moduleRecords('parking', 'session');
      expect(sessions.single.body.containsKey('foundAt'), isTrue);
      expect(find.byKey(const ValueKey('parking-found')), findsNothing);
      expect(find.byKey(const ValueKey('parking-empty')), findsNothing);
    });
  });

  group('vehicles', () {
    testWidgets('two vehicles park at once; the same one is asked about', (
      tester,
    ) async {
      final h = await pumpScreen(tester);
      await _create(tester, place: 'North lot', vehicle: 'Car');
      await _create(tester, place: 'South lot', vehicle: 'Motorbike');
      expect(find.byKey(const ValueKey('parking-found')), findsNWidgets(2));

      // The same vehicle again: the question appears.
      await _create(
        tester,
        place: 'East lot',
        vehicle: 'CAR',
        expectSave: false,
      );
      expect(
        find.byKey(const ValueKey('parking-conflict-close')),
        findsOneWidget,
      );

      // Closing the earlier one leaves one open parking for that vehicle.
      await tester.tap(find.byKey(const ValueKey('parking-conflict-close')));
      await tester.pumpAndSettle();
      final sessions = await h.services.moduleRecords('parking', 'session');
      final car = sessions
          .where((r) => (r.body['vehicle'] as String).toLowerCase() == 'car')
          .toList();
      expect(car, hasLength(2));
      expect(car.where((r) => r.body.containsKey('foundAt')), hasLength(1));
      expect(find.byKey(const ValueKey('parking-found')), findsNWidgets(2));
    });

    testWidgets(
      'answering "keep it open" keeps the sole active session and the editor',
      (tester) async {
        final h = await pumpScreen(tester);
        await _create(tester, place: 'North lot', vehicle: 'Car');
        await _create(
          tester,
          place: 'East lot',
          vehicle: 'Car',
          expectSave: false,
        );
        await tester.tap(find.byKey(const ValueKey('parking-conflict-keep')));
        await tester.pumpAndSettle();

        final sessions = await h.services.moduleRecords('parking', 'session');
        expect(sessions, hasLength(1));
        expect(sessions.single.body['place'], 'North lot');
        expect(sessions.single.body.containsKey('foundAt'), isFalse);
        expect(find.byKey(const ValueKey('parking-save')), findsOneWidget);
        expect(
          _fieldText(tester, const ValueKey('parking-field-place')),
          'East lot',
        );
      },
    );

    testWidgets('backing out of the question writes nothing new', (
      tester,
    ) async {
      final h = await pumpScreen(tester);
      await _create(tester, place: 'North lot', vehicle: 'Car');
      await _create(
        tester,
        place: 'East lot',
        vehicle: 'Car',
        expectSave: false,
      );
      // Tapping outside the question dismisses it, and the second
      // parking is not written.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      final sessions = await h.services.moduleRecords('parking', 'session');
      expect(sessions, hasLength(1));
      expect(sessions.single.body['place'], 'North lot');
    });
  });

  group('editing', () {
    testWidgets('a corrected place is saved and history is untouched', (
      tester,
    ) async {
      final h = await pumpScreen(tester);
      await _create(tester, place: 'North lot', vehicle: 'Car');
      await tester.tap(find.byKey(const ValueKey('parking-found')));
      await tester.pumpAndSettle();
      await _create(tester, place: 'South lot', vehicle: 'Car');
      await _create(tester, place: 'East lot', vehicle: 'Motorbike');

      // Edit the open parking.
      await tester.tap(find.byKey(const ValueKey('parking-active-edit')).first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('parking-field-place')),
        'West lot',
      );
      await _tapSave(tester);
      await tester.pumpAndSettle();

      final sessions = await h.services.moduleRecords('parking', 'session');
      final open = sessions
          .where((r) => !r.body.containsKey('foundAt'))
          .toList();
      expect(open, hasLength(2));
      expect(open.where((r) => r.body['place'] == 'West lot'), hasLength(1));
      // The closed parking from earlier is still in the list.
      expect(
        sessions.where((r) => r.body.containsKey('foundAt')),
        hasLength(1),
      );
    });
  });

  group('deleting', () {
    testWidgets('one closed parking goes, and Undo brings it back', (
      tester,
    ) async {
      final h = await pumpScreen(tester);
      await _create(tester, place: 'North lot');
      await tester.tap(find.byKey(const ValueKey('parking-found')));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('parking-delete-confirm')));
      await tester.pumpAndSettle();
      expect(await h.services.moduleRecords('parking', 'session'), isEmpty);

      // Undo restores exactly what was there.
      await tester.tap(find.byKey(const ValueKey('parking-undo')));
      await tester.pumpAndSettle();
      final restored = await h.services.moduleRecords('parking', 'session');
      expect(restored, hasLength(1));
      expect(restored.single.body['place'], 'North lot');
      expect(find.text('North lot'), findsWidgets);
    });

    testWidgets('clearing the whole history is undoable in one piece', (
      tester,
    ) async {
      final h = await pumpScreen(tester);
      await _create(tester, place: 'First stop');
      await tester.tap(find.byKey(const ValueKey('parking-found')));
      await tester.pumpAndSettle();
      await _create(tester, place: 'Second stop');
      await tester.tap(find.byKey(const ValueKey('parking-found')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('parking-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear past parking'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('parking-clear-confirm')));
      await tester.pumpAndSettle();
      expect(await h.services.moduleRecords('parking', 'session'), isEmpty);

      await tester.tap(find.byKey(const ValueKey('parking-undo')));
      await tester.pumpAndSettle();
      expect(
        await h.services.moduleRecords('parking', 'session'),
        hasLength(2),
      );
    });
  });

  group('search', () {
    testWidgets('finds the place and remembers the query', (tester) async {
      final h = await pumpScreen(tester);
      await _create(tester, place: 'North lot');
      await tester.tap(find.byKey(const ValueKey('parking-search')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('parking-field-search')),
        'north',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('North lot'), findsWidgets);

      final queries = await h.services.moduleRecords('parking', 'search');
      expect(queries, hasLength(1));
      expect(queries.single.body['query'], 'north');
    });
  });

  group('persistence and isolation', () {
    testWidgets('a reopened screen finds everything where it was', (
      tester,
    ) async {
      final h = await pumpScreen(tester);
      await _create(tester, place: 'North lot');
      await _pump(
        tester,
        ParkingScreen(store: NexModuleStore(h.services, 'parking')),
      );
      expect(find.text('North lot'), findsWidgets);
    });

    testWidgets('another module sees none of it', (tester) async {
      final h = await pumpScreen(tester);
      await _create(tester, place: 'North lot');
      expect(await h.services.moduleRecords('other', 'session'), isEmpty);
      expect(await h.services.moduleRecords('other', 'place'), isEmpty);
    });
  });
}

// ------------------------------------------------------------------ helpers

Future<void> _pump(WidgetTester tester, Widget home) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    ),
  );
  await tester.pumpAndSettle();
}

/// Writes a parking through the sheet, as a person would.
Future<void> _create(
  WidgetTester tester, {
  String place = 'North lot',
  String vehicle = '',
  String floor = '',
  bool expectSave = true,
}) async {
  await tester.tap(find.byKey(const ValueKey('parking-fab')));
  await tester.pumpAndSettle();
  if (vehicle.isNotEmpty) {
    await tester.enterText(
      find.byKey(const ValueKey('parking-field-vehicle')),
      vehicle,
    );
  }
  await tester.enterText(
    find.byKey(const ValueKey('parking-field-place')),
    place,
  );
  if (floor.isNotEmpty) {
    await tester.enterText(
      find.byKey(const ValueKey('parking-field-floor')),
      floor,
    );
  }
  await _tapSave(tester);
  if (expectSave) {
    await tester.pumpAndSettle();
  }
}

Future<void> _tapSave(WidgetTester tester) async {
  // `ensureVisible` can leave the button half under the screen edge, so
  // the sheet's list is dragged until the button is actually tappable.
  final sheetList = find
      .descendant(
        of: find.byType(SingleChildScrollView),
        matching: find.byType(Scrollable),
      )
      .first;
  final save = find.byKey(const ValueKey('parking-save'));
  for (var attempt = 0; attempt < 10; attempt++) {
    if (save.hitTestable().evaluate().isNotEmpty) break;
    await tester.drag(sheetList, const Offset(0, -120));
    await tester.pumpAndSettle();
  }
  await tester.tap(save);
  await tester.pumpAndSettle();
}

String _fieldText(WidgetTester tester, Key key) =>
    (tester.widget<TextField>(find.byKey(key)).controller!).text;
