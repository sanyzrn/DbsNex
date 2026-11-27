import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/medicine/medicine_detail.dart';
import 'package:nex_client/modules/medicine/medicine_repository.dart';
import 'package:nex_client/modules/medicine/medicine_screen.dart';
import 'package:nex_client/modules/medicine/medicine_strings.dart';
import 'package:nex_client/modules/medicine/medicine_today_page.dart';
import 'package:nex_client/modules/medicine/medicine_widgets.dart';

import '../../support/more_details.dart';
import '../../support/nex_harness.dart';

/// The audit pass (agent/module-medicine-audit): what the cabinet says
/// about today, the household filter, the duplicate-name question, the
/// history of a long-kept routine, and the words themselves — each held
/// by a test so it cannot quietly go back.
void main() {
  Future<NexModuleStore> harness(WidgetTester tester) async {
    final h = await NexTestHarness.create(name: 'medicine_audit_');
    addTearDown(h.dispose);
    return NexModuleStore(h.services, 'medicine');
  }

  Future<void> pump(WidgetTester tester, Widget home) async {
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

  String hhmm(DateTime at) =>
      '${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}';

  /// A routine time safely inside today: one minute ago at the earliest,
  /// never past the end of the day.
  String earlierToday() => '00:01';

  /// The last routine time of the day; always a moment today still holds.
  String lateToday() => '23:58';

  group('the cabinet on today’s routine', () {
    testWidgets('the Today card counts the moments still open, not all of '
        'them', (tester) async {
      final store = await harness(tester);
      await store.put('medicine', 'm1', {
        'v': 3,
        'name': 'Medicine A',
        'times': [earlierToday(), lateToday()],
      });
      await pump(tester, MedicineScreen(store: store));
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('medicine-today-card')),
          matching: find.text('2 doses today'),
        ),
        findsOneWidget,
      );

      // One moment answered: the card counts what is left to do.
      await MedicineRepository.log(
        store,
        'm1',
        'taken',
        at: DateTime(
          DateTime.now().year,
          DateTime.now().month,
          DateTime.now().day,
          0,
          1,
        ),
        slot: earlierToday(),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('medicine-today-card')),
          matching: find.text('1 dose today'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a fully logged day says so, instead of counting zero', (
      tester,
    ) async {
      final store = await harness(tester);
      await store.put('medicine', 'm1', {
        'v': 3,
        'name': 'Medicine A',
        'times': [earlierToday()],
      });
      final day = DateTime.now();
      await MedicineRepository.log(
        store,
        'm1',
        'taken',
        at: DateTime(day.year, day.month, day.day, 0, 1),
        slot: earlierToday(),
      );
      await pump(tester, MedicineScreen(store: store));
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('medicine-today-card')),
          matching: find.text('All of today’s doses are logged'),
        ),
        findsOneWidget,
      );
      // And the row says the same thing, quietly.
      expect(find.text('All of today’s doses are logged'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a dose logged from the detail sheet answers its moment on '
        'the card too', (tester) async {
      final store = await harness(tester);
      await store.put('medicine', 'm1', {
        'v': 3,
        'name': 'Medicine A',
        'times': [earlierToday(), lateToday()],
      });
      final day = DateTime.now();
      // No slot: the detail sheet’s «Taken», logged at the routine’s time.
      await MedicineRepository.log(
        store,
        'm1',
        'taken',
        at: DateTime(day.year, day.month, day.day, 0, 1),
      );
      await pump(tester, MedicineScreen(store: store));
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('medicine-today-card')),
          matching: find.text('1 dose today'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the row names the next dose still ahead', (tester) async {
      final store = await harness(tester);
      await store.put('medicine', 'm1', {
        'v': 3,
        'name': 'Medicine A',
        'times': [earlierToday(), lateToday()],
      });
      await pump(tester, MedicineScreen(store: store));
      final row = find.descendant(
        of: find.byKey(const ValueKey('medicine-row-m1')),
        matching: find.textContaining('Next at'),
      );
      expect(row, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('the household filter', () {
    testWidgets('“Me” sits beside the names, and filters to the person’s '
        'own', (tester) async {
      final store = await harness(tester);
      await store.put('medicine', 'mine', {'v': 3, 'name': 'Mine'});
      await store.put('medicine', 'sara', {
        'v': 3,
        'name': 'Sara’s',
        'person': {'name': 'Sara'},
      });
      await pump(tester, MedicineScreen(store: store));

      expect(find.byKey(const ValueKey('medicine-person-me')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('medicine-person-me')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('medicine-row-mine')), findsOneWidget);
      expect(find.byKey(const ValueKey('medicine-row-sara')), findsNothing);

      // Everyone puts the household back.
      await tester.tap(find.byKey(const ValueKey('medicine-person-all')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('medicine-row-sara')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no “Me” chip without a named person to tell it from', (
      tester,
    ) async {
      final store = await harness(tester);
      await store.put('medicine', 'mine', {'v': 3, 'name': 'Mine'});
      await pump(tester, MedicineScreen(store: store));
      expect(find.byKey(const ValueKey('medicine-person-me')), findsNothing);
      expect(find.byKey(const ValueKey('medicine-person-all')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('the duplicate-name question', () {
    testWidgets('says what the choice is, not “Delete it?”', (tester) async {
      final store = await harness(tester);
      await store.put('medicine', 'm1', {'v': 3, 'name': 'Metformin'});
      await pump(tester, MedicineScreen(store: store));

      await tester.tap(find.byKey(const ValueKey('medicine-fab')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('medicine-field-name')),
        'metformin',
      );
      await tester.tap(find.byKey(const ValueKey('medicine-save')));
      await tester.pumpAndSettle();

      // The old body reused the delete question («Delete metformin?»).
      expect(find.textContaining('Delete'), findsNothing);
      expect(
        find.text(
          'Keep both, or go back and change the name — nothing is saved yet.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('medicine-duplicate-keep')));
      await tester.pumpAndSettle();
      expect((await store.list('medicine')).length, 2);
      expect(tester.takeException(), isNull);
    });
  });

  group('the dose history of a long-kept routine', () {
    testWidgets('shows the newest slice first, and the rest on request', (
      tester,
    ) async {
      final store = await harness(tester);
      await store.put('medicine', 'm1', {'v': 3, 'name': 'Medicine A'});
      final day = DateTime(2026, 11, 20);
      for (var i = 0; i < 20; i++) {
        await MedicineRepository.log(
          store,
          'm1',
          'taken',
          at: day.add(Duration(minutes: i)),
        );
      }
      await pump(
        tester,
        Scaffold(
          body: MedicineDetailSheet(
            store: store,
            record: _record('m1', {'v': 3, 'name': 'Medicine A'}),
          ),
        ),
      );

      expect(find.byType(MedicineDoseRow), findsNWidgets(14));
      expect(find.text('Show all (20)'), findsOneWidget);

      final showAll = find.byKey(const ValueKey('medicine-history-show-all'));
      await tester.ensureVisible(showAll);
      await tester.tap(showAll);
      await tester.pumpAndSettle();
      expect(find.byType(MedicineDoseRow), findsNWidgets(20));
      expect(tester.takeException(), isNull);
    });
  });

  group('a routine with two day rules', () {
    testWidgets('the editor says which one counts', (tester) async {
      final store = await harness(tester);
      await pump(tester, MedicineScreen(store: store));

      await tester.tap(find.byKey(const ValueKey('medicine-empty-add')));
      await tester.pumpAndSettle();
      await openMoreDetails(tester, 'medicine-more-toggle');
      final monday = find.byKey(const ValueKey('medicine-day-1'));
      await tester.ensureVisible(monday);
      await tester.tap(monday);
      await tester.pumpAndSettle();
      final every = find.byKey(const ValueKey('medicine-field-every'));
      await tester.ensureVisible(every);
      await tester.enterText(every, '3');
      await tester.pumpAndSettle();

      expect(
        find.textContaining('The days of the week are the ones that count'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the detail sheet says it too', (tester) async {
      final store = await harness(tester);
      await store.put('medicine', 'm1', {
        'v': 3,
        'name': 'Medicine A',
        'times': ['08:00'],
        'weekdays': [1, 4],
        'everyDays': 3,
      });
      await pump(
        tester,
        Scaffold(
          body: MedicineDetailSheet(
            store: store,
            record: _record('m1', {
              'v': 3,
              'name': 'Medicine A',
              'times': ['08:00'],
              'weekdays': [1, 4],
              'everyDays': 3,
            }),
          ),
        ),
      );
      expect(
        find.textContaining('The days of the week are the ones that count'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('the Today page', () {
    testWidgets('the moment to act on carries its own heading', (tester) async {
      final store = await harness(tester);
      final soon = DateTime.now().add(const Duration(hours: 1));
      await store.put('medicine', 'm1', {
        'v': 3,
        'name': 'Medicine A',
        'times': [hhmm(soon)],
      });
      await pump(tester, MedicineTodayPage(store: store));
      expect(find.text('Next'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('logging one moment does not lock the others', (tester) async {
      final store = await harness(tester);
      await store.put('medicine', 'm1', {
        'v': 3,
        'name': 'Medicine A',
        'times': [earlierToday(), lateToday()],
      });
      await pump(tester, MedicineTodayPage(store: store));
      final day = DateTime.now();
      final key = 'medicine-today-taken-${day.year}-${day.month}-${day.day}-m1';

      // Two taps in one breath: the second must not be swallowed by the
      // first one's write still being in flight.
      await tester.tap(find.byKey(ValueKey('$key-00:01')));
      await tester.pump();
      await tester.tap(find.byKey(ValueKey('$key-23:58')));
      await tester.pumpAndSettle();

      expect((await store.list('dose')), hasLength(2));
      expect(tester.takeException(), isNull);
    });
  });

  group('the words themselves', () {
    test('every Persian line is Persian — no English left behind', () {
      final persian = RegExp(r'[\u0600-\u06FF]');
      final offenders = [
        for (final entry in medicineStrings.fa.entries)
          if (!persian.hasMatch(entry.value)) entry.key,
      ];
      expect(offenders, isEmpty, reason: 'keys with no Persian in them');
    });

    test('the person filter’s empty answer is Persian on the Persian side', () {
      expect(medicineStrings.fa['noMedicinesFor'], contains('دارو'));
    });
  });
}

ModuleRecord _record(String id, Map<String, Object?> body) => ModuleRecord(
  module: 'medicine',
  kind: 'medicine',
  id: id,
  body: body,
  updatedAt: DateTime.now(),
);
