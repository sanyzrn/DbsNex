import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/parking/parking_screen.dart';
import 'package:nex_client/platform/nex_services.dart';

import '../../support/nex_harness.dart';
import '../../support/more_details.dart';
import 'parking_test_support.dart';

/// The parking screen, used the way a person uses it: empty at first, a
/// parking saved, found and edited — with the vehicle question checked on
/// the way.
void main() {
  Future<NexTestHarness> pumpScreen(
    WidgetTester tester, {
    NexTestHarness? harness,
  }) async {
    final h = harness ?? await NexTestHarness.create(name: 'parking_ui_');
    if (harness == null) addTearDown(h.dispose);
    await pumpParkingHome(
      tester,
      ParkingScreen(store: NexModuleStore(h.services, 'parking')),
    );
    return h;
  }

  group('empty and creation', () {
    testWidgets('says what to do when nothing is parked yet', (tester) async {
      await pumpScreen(tester);
      expect(find.byKey(const ValueKey('parking-empty')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('parking-park-details')),
        findsOneWidget,
      );
      // The first action lives in the empty state itself, not only on the
      // floating button.
      expect(find.byKey(const ValueKey('parking-empty-add')), findsOneWidget);
      expect(find.text('I parked'), findsOneWidget);
      expect(find.text('Park with details'), findsOneWidget);
    });

    testWidgets('one tap parks the car with nothing filled in', (tester) async {
      final h = await pumpScreen(tester);
      await tester.tap(find.byKey(const ValueKey('parking-empty-add')));
      await tester.pumpAndSettle();

      final sessions = await h.services.moduleRecords('parking', 'session');
      expect(sessions, hasLength(1));
      expect(sessions.single.body['place'], '');
      expect(sessions.single.body.containsKey('foundAt'), isFalse);
      expect(find.byKey(const ValueKey('parking-empty')), findsNothing);
      // Every other field is offered from the card afterwards.
      expect(find.byKey(const ValueKey('parking-add-where')), findsOneWidget);
      expect(find.byKey(const ValueKey('parking-found')), findsOneWidget);
    });

    testWidgets('a second one-tap parking remembers the last vehicle', (
      tester,
    ) async {
      final h = await pumpScreen(tester);
      await createParking(tester, place: 'North lot', vehicle: 'Car');
      await tester.tap(find.byKey(const ValueKey('parking-found')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('parking-fab')));
      await tester.pumpAndSettle();

      final open = (await h.services.moduleRecords(
        'parking',
        'session',
      )).where((r) => !r.body.containsKey('foundAt')).toList();
      expect(open, hasLength(1));
      expect(open.single.body['vehicle'], 'Car');
      expect(open.single.body['place'], '');
    });

    testWidgets('writes a parking and shows it as the open one', (
      tester,
    ) async {
      final h = await pumpScreen(tester);
      await createParking(
        tester,
        place: 'Saba mall',
        vehicle: 'Car',
        floor: '-1',
      );

      final sessions = await h.services.moduleRecords('parking', 'session');
      expect(sessions, hasLength(1));
      expect(sessions.single.body['place'], 'Saba mall');
      expect(sessions.single.body['vehicle'], 'Car');
      expect(sessions.single.body.containsKey('foundAt'), isFalse);

      expect(find.byKey(const ValueKey('parking-active-card')), findsNothing);
      expect(find.text('Saba mall'), findsWidgets);
      expect(find.byKey(const ValueKey('parking-found')), findsOneWidget);
    });

    testWidgets('every field is optional, even the place', (tester) async {
      final h = await pumpScreen(tester);
      await tester.tap(find.byKey(const ValueKey('parking-park-details')));
      await tester.pumpAndSettle();
      await openMoreDetails(tester, 'parking-more-toggle');
      await tester.enterText(
        find.byKey(const ValueKey('parking-field-vehicle')),
        'Car',
      );
      await tapSave(tester);

      final sessions = await h.services.moduleRecords('parking', 'session');
      expect(sessions, hasLength(1));
      expect(sessions.single.body['vehicle'], 'Car');
      expect(sessions.single.body['place'], '');
      expect(find.byKey(const ValueKey('parking-save')), findsNothing);
    });

    testWidgets('the place is remembered as somewhere to park again', (
      tester,
    ) async {
      await pumpScreen(tester);
      await createParking(tester, place: 'Saba mall', floor: '1');
      expect(find.byKey(const ValueKey('parking-empty')), findsNothing);
      expect(find.text('Saba mall'), findsWidgets);

      // From the remembered place, the editor comes prefilled.
      await tester.tap(find.text('Saba mall').last);
      await tester.pumpAndSettle();
      expect(
        fieldText(tester, const ValueKey('parking-field-place')),
        'Saba mall',
      );
      expect(fieldText(tester, const ValueKey('parking-field-floor')), '1');

      // Nothing was typed by hand, so leaving asks nothing and closes.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('parking-save')), findsNothing);
    });
  });

  group('finding the car', () {
    testWidgets('records foundAt and keeps it in history', (tester) async {
      final h = await pumpScreen(tester);
      await createParking(tester, place: 'Saba mall');
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
      await createParking(tester, place: 'North lot', vehicle: 'Car');
      await createParking(tester, place: 'South lot', vehicle: 'Motorbike');
      expect(find.byKey(const ValueKey('parking-found')), findsNWidgets(2));

      // The same vehicle again: the question appears.
      await createParking(
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
        await createParking(tester, place: 'North lot', vehicle: 'Car');
        await createParking(
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
          fieldText(tester, const ValueKey('parking-field-place')),
          'East lot',
        );
        // The answer used to leave the editor open without a word.
        expect(
          find.text('The earlier parking stays open; this one was not saved.'),
          findsOneWidget,
        );
      },
    );

    testWidgets('backing out of the question writes nothing new', (
      tester,
    ) async {
      final h = await pumpScreen(tester);
      await createParking(tester, place: 'North lot', vehicle: 'Car');
      await createParking(
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
      await createParking(tester, place: 'North lot', vehicle: 'Car');
      await tester.tap(find.byKey(const ValueKey('parking-found')));
      await tester.pumpAndSettle();
      await createParking(tester, place: 'South lot', vehicle: 'Car');
      await createParking(tester, place: 'East lot', vehicle: 'Motorbike');

      // Edit the open parking.
      await tester.tap(find.byKey(const ValueKey('parking-active-edit')).first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('parking-field-place')),
        'West lot',
      );
      await tapSave(tester);
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
}
