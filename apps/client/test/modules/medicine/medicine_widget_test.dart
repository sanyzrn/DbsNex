import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/medicine/medicine_detail.dart';
import 'package:nex_client/modules/medicine/medicine_screen.dart';
import 'package:nex_client/platform/nex_services.dart';

import '../../support/add_button.dart';
import '../../support/more_details.dart';
import '../../support/nex_harness.dart';

part 'medicine_more_cases.dart';
part 'medicine_test_helpers.dart';

/// The medicine cabinet, used the way a person uses it: added, logged
/// taken and skipped, corrected, archived, deleted and undone — with the
/// stock following the person's own numbers and nothing else. Entries are
/// neutral placeholders, never anyone's real medicines.
void main() {
  Future<NexTestHarness> pumpScreen(WidgetTester tester) async {
    final h = await NexTestHarness.create(name: 'medicine_ui_');
    addTearDown(h.dispose);
    await _pump(
      tester,
      MedicineScreen(store: NexModuleStore(h.services, 'medicine')),
    );
    return h;
  }

  group('the list', () {
    testWidgets('says what to do when the cabinet is empty', (tester) async {
      await pumpScreen(tester);
      expect(find.byKey(const ValueKey('medicine-empty')), findsOneWidget);
      expect(addButton('medicine-fab', 'medicine-empty-add'), findsOneWidget);
    });

    testWidgets('the empty state’s own button adds the first medicine', (
      tester,
    ) async {
      final h = await pumpScreen(tester);
      await tester.tap(find.byKey(const ValueKey('medicine-empty-add')));
      await tester.pumpAndSettle();
      await openMoreDetails(tester, 'medicine-more-toggle');
      expect(find.byKey(const ValueKey('medicine-save')), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('medicine-field-name')),
        'Medicine A',
      );
      await _tapSave(tester);
      expect(find.text('Medicine A'), findsWidgets);
      expect(
        await h.services.moduleRecords('medicine', 'medicine'),
        hasLength(1),
      );
    });

    testWidgets('adds a medicine and shows it', (tester) async {
      final h = await pumpScreen(tester);
      await _add(tester, name: 'Medicine A', strength: '10 mg');
      expect(find.text('Medicine A'), findsWidgets);
      expect(
        await h.services.moduleRecords('medicine', 'medicine'),
        hasLength(1),
      );
    });

    testWidgets('without a name it says so and saves nothing', (tester) async {
      final h = await pumpScreen(tester);
      await tester.tap(addButton('medicine-fab', 'medicine-empty-add'));
      await tester.pumpAndSettle();
      await openMoreDetails(tester, 'medicine-more-toggle');
      await _tapSave(tester);
      expect(find.text('Write the medicine’s name.'), findsOneWidget);
      expect(await h.services.moduleRecords('medicine', 'medicine'), isEmpty);
    });

    testWidgets('a duplicate name is asked about, and can be kept', (
      tester,
    ) async {
      final h = await pumpScreen(tester);
      await _add(tester, name: 'Medicine A');
      await _add(tester, name: 'medicine a', expectSave: false);
      expect(
        find.byKey(const ValueKey('medicine-duplicate-keep')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('medicine-duplicate-keep')));
      await tester.pumpAndSettle();
      expect(
        await h.services.moduleRecords('medicine', 'medicine'),
        hasLength(2),
      );
    });

    testWidgets('a duplicate name can be stopped, words kept on screen', (
      tester,
    ) async {
      final h = await pumpScreen(tester);
      await _add(tester, name: 'Medicine A');
      await _add(tester, name: 'Medicine A', expectSave: false);
      await tester.tap(find.byKey(const ValueKey('medicine-duplicate-cancel')));
      await tester.pumpAndSettle();
      // The editor is still open with the name written; nothing was saved.
      expect(find.byKey(const ValueKey('medicine-save')), findsOneWidget);
      expect(
        await h.services.moduleRecords('medicine', 'medicine'),
        hasLength(1),
      );
      // Leaving asks, because the words would be lost.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('medicine-discard')));
      await tester.pumpAndSettle();
      expect(
        await h.services.moduleRecords('medicine', 'medicine'),
        hasLength(1),
      );
    });

    testWidgets('malformed numbers are refused, not accepted silently', (
      tester,
    ) async {
      final h = await pumpScreen(tester);
      await tester.tap(addButton('medicine-fab', 'medicine-empty-add'));
      await tester.pumpAndSettle();
      await openMoreDetails(tester, 'medicine-more-toggle');
      await tester.enterText(
        find.byKey(const ValueKey('medicine-field-name')),
        'Medicine A',
      );
      await tester.enterText(
        find.byKey(const ValueKey('medicine-field-quantity')),
        'plenty',
      );
      await _tapSave(tester);
      expect(find.text('Write a whole number, 0 or more'), findsOneWidget);
      expect(await h.services.moduleRecords('medicine', 'medicine'), isEmpty);
    });

    testWidgets('a long name and long instructions hold up', (tester) async {
      final h = await pumpScreen(tester);
      final longName = List.filled(60, 'اسم').join();
      final longText = List.filled(200, 'word').join(' ');
      await _add(tester, name: longName, instructions: longText);
      expect(
        (await h.services.moduleRecords(
          'medicine',
          'medicine',
        )).single.body['name'],
        longName,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('logging doses', () {
    testWidgets('taken writes a log and falls by the person’s own units', (
      tester,
    ) async {
      final h = await pumpScreen(tester);
      await _add(
        tester,
        name: 'Medicine A',
        quantity: '30',
        doseUnits: '2',
        packageUnit: 'box',
      );

      await tester.tap(find.text('Medicine A'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('medicine-taken')));
      await tester.pumpAndSettle();

      final stored = await h.services.moduleRecords('medicine', 'medicine');
      expect(stored.single.body['quantity'], 28);
      final doses = await h.services.moduleRecords('medicine', 'dose');
      expect(doses, hasLength(1));
      expect(doses.single.body['action'], 'taken');
      expect(doses.single.body['takenUnits'], 2);
      // Close the sheet and read the list as the person would.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('28 box left'), findsOneWidget);
    });

    testWidgets('skipped writes a log and touches no stock', (tester) async {
      final h = await pumpScreen(tester);
      await _add(tester, name: 'Medicine A', quantity: '30', doseUnits: '2');

      await tester.tap(find.text('Medicine A'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('medicine-skipped')));
      await tester.pumpAndSettle();

      final stored = await h.services.moduleRecords('medicine', 'medicine');
      expect(stored.single.body['quantity'], 30);
      final doses = await h.services.moduleRecords('medicine', 'dose');
      expect(doses.single.body['action'], 'skipped');
      expect(doses.single.body.containsKey('takenUnits'), isFalse);
    });

    testWidgets('stock never falls without the person’s own numbers', (
      tester,
    ) async {
      final h = await pumpScreen(tester);
      // No quantity, no units per dose: logging is still possible.
      await _add(tester, name: 'Medicine A');
      await tester.tap(find.text('Medicine A'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('medicine-taken')));
      await tester.pumpAndSettle();
      final stored = await h.services.moduleRecords('medicine', 'medicine');
      expect(stored.single.body.containsKey('quantity'), isFalse);
      final doses = await h.services.moduleRecords('medicine', 'dose');
      expect(doses.single.body.containsKey('takenUnits'), isFalse);
    });

    testWidgets('deleting a taken log puts the stock back', (tester) async {
      final h = await pumpScreen(tester);
      await _add(tester, name: 'Medicine A', quantity: '30', doseUnits: '2');
      await tester.tap(find.text('Medicine A'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('medicine-taken')));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      final stored = await h.services.moduleRecords('medicine', 'medicine');
      expect(stored.single.body['quantity'], 30);
      expect(await h.services.moduleRecords('medicine', 'dose'), isEmpty);
    });

    testWidgets('undoing a deleted log takes the stock off again', (
      tester,
    ) async {
      final h = await pumpScreen(tester);
      await _add(tester, name: 'Medicine A', quantity: '30', doseUnits: '2');
      await tester.tap(find.text('Medicine A'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('medicine-taken')));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('medicine-undo')));
      await tester.pumpAndSettle();

      final stored = await h.services.moduleRecords('medicine', 'medicine');
      expect(stored.single.body['quantity'], 28);
      expect(await h.services.moduleRecords('medicine', 'dose'), hasLength(1));
    });
  });

  group('expiry and refill as read on opening', () {
    testWidgets('an expired date shows discreetly and in red', (tester) async {
      await pumpScreen(tester);
      await _add(tester, name: 'Medicine A', expiry: '2020/01/01');
      expect(find.text('Expired'), findsOneWidget);
    });

    testWidgets('a date this week shows as soon', (tester) async {
      await pumpScreen(tester);
      final soon = DateTime.now().add(const Duration(days: 3));
      await _add(
        tester,
        name: 'Medicine A',
        expiry: '${soon.year}/${soon.month}/${soon.day}',
      );
      expect(find.text('Expiring soon'), findsOneWidget);
    });

    testWidgets('a future date shows no warning', (tester) async {
      await pumpScreen(tester);
      await _add(tester, name: 'Medicine A', expiry: '2030/01/01');
      expect(find.text('Expiring soon'), findsNothing);
      expect(find.text('Expired'), findsNothing);
    });

    testWidgets('a quantity at the refill threshold says so', (tester) async {
      await pumpScreen(tester);
      await _add(
        tester,
        name: 'Medicine A',
        quantity: '4',
        refill: '5',
        packageUnit: 'box',
      );
      expect(find.text('Time to refill'), findsOneWidget);
    });
  });

  group('routine times', () {
    testWidgets('a time as written becomes a chip', (tester) async {
      final h = await pumpScreen(tester);
      await tester.tap(addButton('medicine-fab', 'medicine-empty-add'));
      await tester.pumpAndSettle();
      await openMoreDetails(tester, 'medicine-more-toggle');
      await tester.enterText(
        find.byKey(const ValueKey('medicine-field-name')),
        'Medicine A',
      );
      await tester.enterText(
        find.byKey(const ValueKey('medicine-field-time')),
        '8:30',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('medicine-time-08:30')), findsOneWidget);
      await _tapSave(tester);
      expect(
        (await h.services.moduleRecords(
          'medicine',
          'medicine',
        )).single.body['times'],
        ['08:30'],
      );
    });

    testWidgets('a time that is not a time says so', (tester) async {
      final h = await pumpScreen(tester);
      await tester.tap(addButton('medicine-fab', 'medicine-empty-add'));
      await tester.pumpAndSettle();
      await openMoreDetails(tester, 'medicine-more-toggle');
      await tester.enterText(
        find.byKey(const ValueKey('medicine-field-name')),
        'Medicine A',
      );
      await tester.enterText(
        find.byKey(const ValueKey('medicine-field-time')),
        'whenever',
      );
      await _tapSave(tester);
      expect(find.text('Not a time'), findsOneWidget);
      expect(await h.services.moduleRecords('medicine', 'medicine'), isEmpty);
    });
  });

  _registerMedicineMore(pumpScreen);
}
