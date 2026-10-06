import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/reminders.dart';
import 'package:nex_client/screens/cycle/cycle_report_screen.dart';
import 'package:nex_client/screens/cycle/cycle_ring.dart';
import 'package:nex_client/screens/cycle_screen.dart';
import 'package:nex_core/nex_core.dart';

import 'support/nex_harness.dart';

/// «Cycle»: the first questions, the one big button, a day's log, and
/// deleting it all.
/// Back to Tools if on the cycle page, then into it again.
Future<void> reopen(WidgetTester tester) async {
  if (find.byType(CycleScreen).evaluate().isNotEmpty) {
    Navigator.of(tester.element(find.byType(CycleScreen))).pop();
    await tester.pumpAndSettle();
  }
  await tester.tap(find.byIcon(Icons.water_drop_outlined).first);
  await tester.pumpAndSettle();
  expect(find.byType(CycleScreen), findsOneWidget);
}

Future<void> scrollTo(WidgetTester tester, Finder target) =>
    tester.scrollUntilVisible(
      target,
      300,
      scrollable: find
          .descendant(
            of: find.byType(CycleScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );

void main() {
  Future<NexTestHarness> openCycle(
    WidgetTester tester, {
    Map<String, Object> preferences = const {},
  }) async {
    tester.view.devicePixelRatio = 2.75;
    tester.view.physicalSize = const Size(1080, 2340);
    addTearDown(tester.view.reset);
    final harness = await pumpNexApp(tester, preferences: preferences);
    await tester.tap(find.byIcon(Icons.space_dashboard_outlined));
    await tester.pumpAndSettle();
    await reopen(tester);
    return harness;
  }

  DateTime today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  testWidgets('first use asks, then one tap starts a period', (tester) async {
    final harness = await openCycle(tester);
    expect(find.text('A few questions to begin'), findsOneWidget);
    // Nothing known: no date, and the lengths left as they are.
    await scrollTo(tester, find.byKey(const ValueKey('cycle-welcome-begin')));
    await tester.tap(find.byKey(const ValueKey('cycle-welcome-begin')));
    await tester.pumpAndSettle();
    expect(harness.preferences.cycleSetUp, isTrue);
    expect(find.text('Period started'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('cycle-primary')));
    await tester.pumpAndSettle();
    expect(find.text('Period, day 1'), findsOneWidget);
    expect(find.text('Period ended'), findsOneWidget);
    final periods = await harness.services.cyclePeriods();
    expect(periods.single.start, CycleDate.of(today()));
    expect(periods.single.isOpen, isTrue);

    await tester.tap(find.byKey(const ValueKey('cycle-primary')));
    await tester.pumpAndSettle();
    expect((await harness.services.cyclePeriods()).single.isOpen, isFalse);
  });

  testWidgets('a known history shows where the cycle is and what is next', (
    tester,
  ) async {
    final harness = await openCycle(
      tester,
      preferences: {'cycle.set_up': true},
    );
    final services = harness.services;
    // Three 29-day cycles; the last began ten days ago.
    final last = today().subtract(const Duration(days: 10));
    for (var k = 3; k >= 0; k--) {
      final start = last.subtract(Duration(days: 29 * k));
      final p = await services.cycleStartPeriod(start);
      await services.cycleEndPeriod(p.id, start.add(const Duration(days: 4)));
    }
    await reopen(tester);

    expect(find.text('19 days until your period'), findsOneWidget);
    expect(find.text('Day 11 of your cycle'), findsOneWidget);
    expect(find.text('Based on your regular cycles'), findsOneWidget);
    expect(find.textContaining('Likely between'), findsOneWidget);
    await scrollTo(tester, find.text('29 days'));
    expect(find.text('29 days'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets("today's log is saved and summarised", (tester) async {
    final harness = await openCycle(
      tester,
      preferences: {'cycle.set_up': true},
    );
    await tester.tap(find.byKey(const ValueKey('cycle-log-today')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Heavy'));
    await tester.tap(find.text('Cramps'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('cycle-day-save')));
    await tester.tap(find.byKey(const ValueKey('cycle-day-save')));
    await tester.pumpAndSettle();

    final log = (await harness.services.cycleDays(today(), today())).single;
    expect(log.flow, CycleFlow.heavy);
    expect(log.symptoms, {CycleSymptom.cramps});
    expect(find.text('Heavy · Cramps'), findsOneWidget);
  });

  testWidgets('delete all takes the cycle back to its first questions', (
    tester,
  ) async {
    final harness = await openCycle(
      tester,
      preferences: {'cycle.set_up': true},
    );
    await harness.services.cycleStartPeriod(today());
    await tester.tap(find.byTooltip('Cycle settings'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('cycle-delete-all')));
    await tester.tap(find.byKey(const ValueKey('cycle-delete-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cycle-delete-all-confirm')));
    await tester.pumpAndSettle();

    expect(await harness.services.cyclePeriods(), isEmpty);
    expect(harness.preferences.cycleSetUp, isFalse);
    expect(find.text('A few questions to begin'), findsOneWidget);
  });

  testWidgets('in Persian with the solar calendar, nothing overflows', (
    tester,
  ) async {
    final harness = await openCycle(
      tester,
      preferences: {
        'cycle.set_up': true,
        'appearance.locale': 'fa',
        'appearance.solar_calendar': true,
      },
    );
    await harness.services.cycleStartPeriod(
      today().subtract(const Duration(days: 2)),
    );
    await reopen(tester);
    expect(find.text('پریود، روز ۳'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test(
    'the cycle alarms have their own ids, clear of notes and each other',
    () {
      final ids = {
        for (final key in NexReminders.cycleKeys) NexReminders.cycleIdFor(key),
      };
      expect(ids, hasLength(NexReminders.cycleKeys.length));
      expect(ids.every((id) => id >= NexReminders.reservedIds), isTrue);
      expect(ids, isNot(contains(NexReminders.idFor('soon'))));
    },
  );

  group('modes', () {
    Future<void> history(NexTestHarness harness, {int daysAgo = 3}) async {
      final last = today().subtract(Duration(days: daysAgo));
      for (var k = 3; k >= 0; k--) {
        final start = last.subtract(Duration(days: 28 * k));
        final p = await harness.services.cycleStartPeriod(start);
        await harness.services.cycleEndPeriod(
          p.id,
          start.add(const Duration(days: 4)),
        );
      }
    }

    testWidgets('trying to conceive puts the fertile window first', (
      tester,
    ) async {
      final harness = await openCycle(
        tester,
        preferences: {'cycle.set_up': true, 'cycle.mode': 'conceive'},
      );
      // Day 7 of a 28-day cycle, the period over: the fertile window opens
      // on day 10.
      await history(harness, daysAgo: 6);
      await reopen(tester);
      expect(find.text('3 days to your fertile window'), findsOneWidget);
      expect(find.textContaining('Likely ovulation'), findsOneWidget);
      expect(find.text('Trying to conceive'), findsOneWidget);
    });

    testWidgets('pregnancy counts weeks and hides the period button', (
      tester,
    ) async {
      final start = CycleDate.of(today()).addDays(-86);
      final harness = await openCycle(
        tester,
        preferences: {
          'cycle.set_up': true,
          'cycle.mode': 'pregnant',
          'cycle.pregnancy_start': '$start',
        },
      );
      expect(harness.preferences.cyclePregnancyStart, start);
      expect(find.text('Week 12, day 2'), findsOneWidget);
      expect(find.textContaining('Due date'), findsOneWidget);
      expect(find.textContaining('Trimester 1'), findsOneWidget);
      expect(find.byKey(const ValueKey('cycle-primary')), findsNothing);
      expect(find.byType(CycleRing), findsNothing);
    });

    testWidgets('menopause logs without predicting', (tester) async {
      final harness = await openCycle(
        tester,
        preferences: {'cycle.set_up': true, 'cycle.mode': 'menopause'},
      );
      await history(harness);
      await reopen(tester);
      expect(find.byType(CycleRing), findsNothing);
      expect(find.textContaining('Predictions are off'), findsOneWidget);
      expect(find.textContaining('Likely between'), findsNothing);
      expect(find.byKey(const ValueKey('cycle-primary')), findsOneWidget);
    });
  });

  testWidgets('patterns show, and the report opens on its A4 page', (
    tester,
  ) async {
    final harness = await openCycle(
      tester,
      preferences: {'cycle.set_up': true},
    );
    final services = harness.services;
    final last = today().subtract(const Duration(days: 10));
    for (var k = 3; k >= 0; k--) {
      final start = last.subtract(Duration(days: 28 * k));
      final p = await services.cycleStartPeriod(start);
      await services.cycleEndPeriod(p.id, start.add(const Duration(days: 4)));
      if (k > 0) {
        // A headache two days before each of the next periods.
        await services.cycleSaveDay(
          CycleDayLog(
            day: CycleDate.of(start.add(const Duration(days: 26))),
            symptoms: {CycleSymptom.headache},
          ),
        );
      }
    }
    await reopen(tester);
    await scrollTo(tester, find.textContaining('Headache: usually'));
    expect(
      find.text('Headache: usually about 2 days before your period'),
      findsOneWidget,
    );

    await scrollTo(tester, find.byKey(const ValueKey('cycle-report')));
    await tester.tap(find.byKey(const ValueKey('cycle-report')));
    await tester.pumpAndSettle();
    expect(find.byType(CycleReportScreen), findsOneWidget);
    expect(find.text('Cycle report'), findsOneWidget);
    expect(find.text('Recent periods'), findsOneWidget);
    expect(find.byKey(const ValueKey('cycle-report-save')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
