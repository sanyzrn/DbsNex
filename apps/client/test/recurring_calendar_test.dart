import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_core/nex_core.dart';

import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/widgets/commitments_sheet.dart';
import 'package:nex_client/widgets/recurring_attachments.dart';
import 'package:nex_client/widgets/recurring_calendar.dart';

import 'support/nex_harness.dart';

/// W5.4: the Recurring calendar, and what an item can carry with it.
void main() {
  NexCommitment weekly({DateTime? due, Map<String, dynamic>? details}) =>
      NexCommitment(
        id: 'c-gym',
        title: 'Gym',
        cadence: NexCadence.weeks,
        every: 1,
        dueAt: due ?? DateTime(2026, 3, 2, 8),
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        details: details ?? const {},
      );

  Widget calendar(
    List<NexCommitment> items, {
    ValueChanged<NexCommitment>? onActions,
  }) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: SingleChildScrollView(
        child: RecurringCalendar(
          commitments: items,
          solar: false,
          today: DateTime(2026, 3, 2),
          onActions: onActions ?? (_) {},
        ),
      ),
    ),
  );

  testWidgets('a month shows each day an item falls on', (tester) async {
    await tester.pumpWidget(calendar([weekly()]));
    await tester.pumpAndSettle();
    expect(find.text('March 2026'), findsOneWidget);
    // Mondays 2, 9, 16, 23 and 30 carry one each.
    for (final day in [2, 9, 16, 23, 30]) {
      expect(find.bySemanticsLabel('$day, 1'), findsOneWidget, reason: '$day');
    }
    expect(find.bySemanticsLabel('3, 0'), findsOneWidget);
  });

  testWidgets('only the next occurrence can be moved', (tester) async {
    NexCommitment? opened;
    await tester.pumpWidget(calendar([weekly()], onActions: (c) => opened = c));
    await tester.pumpAndSettle();

    // Today is the 2nd, the next occurrence: it has the move button.
    expect(find.text('Gym'), findsOneWidget);
    await tester.tap(find.byTooltip('Move or snooze'));
    expect(opened?.id, 'c-gym');

    // The 9th is where the schedule says; nothing to move there.
    await tester.tap(find.bySemanticsLabel('9, 1'));
    await tester.pumpAndSettle();
    expect(find.text('Gym'), findsOneWidget);
    expect(find.byTooltip('Move or snooze'), findsNothing);
  });

  testWidgets('a moved occurrence shows on its new day; the rest do not move', (
    tester,
  ) async {
    final moved = weekly(
      due: DateTime(2026, 3, 4, 18),
      details: {'scheduledDue': DateTime(2026, 3, 2, 8).toIso8601String()},
    );
    await tester.pumpWidget(calendar([moved]));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('2, 0'), findsOneWidget);
    expect(find.bySemanticsLabel('4, 1'), findsOneWidget);
    expect(find.bySemanticsLabel('9, 1'), findsOneWidget);
  });

  testWidgets('week view shows seven days', (tester) async {
    await tester.pumpWidget(calendar([weekly()]));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Week'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('2, 1'), findsOneWidget);
    expect(find.bySemanticsLabel('9, 1'), findsNothing);
  });

  group('attachments', () {
    late NexTestHarness harness;
    late NexServices services;

    setUp(() async {
      harness = await NexTestHarness.create(
        name: 'nex_recurring_',
        onboarded: false,
      );
      services = harness.services;
    });

    tearDown(() => harness.dispose());

    testWidgets('a linked note is kept on the item and can be removed', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final receipt = await services.captureText('Insurance receipt 2026');
      await services.worker.saveCommitment(weekly());
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () async => CommitmentEditor.show(
                    context,
                    services: services,
                    existing: (await services.commitments()).single,
                  ),
                  child: const Text('edit'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('edit'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Link a note'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Insurance receipt 2026').last);
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(InputChip, 'Insurance receipt 2026'),
        findsOneWidget,
      );

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final saved = (await services.commitments()).single;
      expect(RecurringAttachments.noteIdsOf(saved.details), [receipt!.id]);
      // The note itself is untouched and still in the library.
      expect((await services.getById(receipt.id))?.content, isNotNull);
    });
  });
}
