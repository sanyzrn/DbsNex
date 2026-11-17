import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/parking/parking_screen.dart';
import 'package:nex_client/platform/nex_services.dart';

import '../../support/nex_harness.dart';
import '../../support/more_details.dart';
import 'parking_test_support.dart';

/// The rest of the parking screen, used the way a person uses it: deleting
/// with Undo, history, search, the editor's validation and persistence.
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

  group('deleting', () {
    testWidgets('one closed parking goes, and Undo brings it back', (
      tester,
    ) async {
      final h = await pumpScreen(tester);
      await createParking(tester, place: 'North lot');
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
      await createParking(tester, place: 'First stop');
      await tester.tap(find.byKey(const ValueKey('parking-found')));
      await tester.pumpAndSettle();
      await createParking(tester, place: 'Second stop');
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

  group('durations as words', () {
    Future<NexTestHarness> seedOpen(
      WidgetTester tester,
      Duration parked,
    ) async {
      final h = await pumpScreen(tester);
      await h.services.modulePut('parking', 'session', 'seed', {
        'v': 1,
        'place': 'North lot',
        'startedAt': DateTime.now().subtract(parked).toUtc().toIso8601String(),
      });
      await tester.pumpAndSettle();
      return h;
    }

    testWidgets('a whole number of hours says no zero minutes', (tester) async {
      await seedOpen(tester, const Duration(hours: 2));
      expect(find.text('Parked for 2 h'), findsOneWidget);
      expect(find.textContaining('2 h 0 min'), findsNothing);
    });

    testWidgets('a whole number of days says no zero hours', (tester) async {
      await seedOpen(tester, const Duration(days: 3));
      expect(find.text('Parked for 3 d'), findsOneWidget);
      expect(find.textContaining('3 d 0 h'), findsNothing);
    });

    testWidgets('mixed durations keep both units', (tester) async {
      await seedOpen(tester, const Duration(hours: 26, minutes: 1));
      expect(find.text('Parked for 1 d 2 h'), findsOneWidget);
    });
  });

  group('search', () {
    testWidgets('finds the place and remembers the query', (tester) async {
      final h = await pumpScreen(tester);
      await createParking(tester, place: 'North lot');
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

    testWidgets('a query with no matches says so', (tester) async {
      await pumpScreen(tester);
      await createParking(tester, place: 'North lot');
      await tester.tap(find.byKey(const ValueKey('parking-search')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('parking-field-search')),
        'museum',
      );
      await tester.pump();
      expect(find.text('Nothing matches “museum”.'), findsOneWidget);
      expect(find.text('North lot'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('the editor', () {
    testWidgets('a broken paid time is told in full words', (tester) async {
      await pumpScreen(tester);
      await tester.tap(find.byKey(const ValueKey('parking-park-details')));
      await tester.pumpAndSettle();
      await openMoreDetails(tester, 'parking-more-toggle');
      await tester.enterText(
        find.byKey(const ValueKey('parking-field-place')),
        'North lot',
      );
      await tester.enterText(
        find.byKey(const ValueKey('parking-field-expiry-date')),
        '2026/02/30',
      );
      await tester.enterText(
        find.byKey(const ValueKey('parking-field-expiry-time')),
        '12:00',
      );
      // The focused field schedules its own scroll; settle it before the
      // button is dragged into reach.
      await tester.pumpAndSettle();
      await tapSave(tester);
      expect(
        find.text('The date or the time is not written right'),
        findsOneWidget,
      );
      // The old, misleading "Not a number" is gone.
      expect(find.text('Not a number'), findsNothing);
      expect(find.byKey(const ValueKey('parking-save')), findsOneWidget);
    });

    testWidgets('a paid time can be taken back off the record', (tester) async {
      final h = await pumpScreen(tester);
      await createParking(
        tester,
        place: 'North lot',
        expiry: '2099/01/01 00:00',
      );
      final before = await h.services.moduleRecords('parking', 'session');
      expect(before.single.body.containsKey('expiresAt'), isTrue);

      // Edit the open parking and clear the paid time in one tap.
      await tester.tap(find.byKey(const ValueKey('parking-active-edit')));
      await tester.pumpAndSettle();
      final clear = find.byKey(const ValueKey('parking-clear-time'));
      await Scrollable.ensureVisible(tester.element(clear), alignment: 0.4);
      await tester.pumpAndSettle();
      await tester.tap(clear);
      await tester.pumpAndSettle();
      await tapSave(tester);

      final after = await h.services.moduleRecords('parking', 'session');
      expect(after.single.body.containsKey('expiresAt'), isFalse);
      // The large countdown is gone with it.
      expect(find.byKey(const ValueKey('parking-time-left')), findsNothing);
    });

    testWidgets('Today writes the date zero padded', (tester) async {
      await pumpScreen(tester);
      await tester.tap(find.byKey(const ValueKey('parking-park-details')));
      await tester.pumpAndSettle();
      await openMoreDetails(tester, 'parking-more-toggle');
      final chip = find.byKey(const ValueKey('parking-today'));
      await Scrollable.ensureVisible(tester.element(chip), alignment: 0.4);
      await tester.pumpAndSettle();
      await tester.tap(chip);
      await tester.pump();
      expect(
        fieldText(tester, const ValueKey('parking-field-expiry-date')),
        matches(RegExp(r'^\d{4}/\d{2}/\d{2}$')),
      );
    });
  });

  group('row actions', () {
    testWidgets('a double tap on edit opens one sheet, not two', (
      tester,
    ) async {
      await pumpScreen(tester);
      await createParking(tester, place: 'North lot');
      final edit = find.byKey(const ValueKey('parking-active-edit'));
      await tester.tap(edit);
      await tester.tap(edit);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('parking-save')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('persistence and isolation', () {
    testWidgets('a reopened screen finds everything where it was', (
      tester,
    ) async {
      final h = await pumpScreen(tester);
      await createParking(tester, place: 'North lot');
      await pumpParkingHome(
        tester,
        ParkingScreen(store: NexModuleStore(h.services, 'parking')),
      );
      expect(find.text('North lot'), findsWidgets);
    });

    testWidgets('another module sees none of it', (tester) async {
      final h = await pumpScreen(tester);
      await createParking(tester, place: 'North lot');
      expect(await h.services.moduleRecords('other', 'session'), isEmpty);
      expect(await h.services.moduleRecords('other', 'place'), isEmpty);
    });
  });
}
