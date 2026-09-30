import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_core/nex_core.dart';

import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/widgets/commitments_sheet.dart';

import 'support/nex_harness.dart';

/// The recurring page, which used to be a title, a plus and a list.
///
/// It was reachable only from Settings, which is where the app's own
/// configuration lives — and a list of somebody's bills and medication is
/// their data, not a preference. It has a place in the bar along the bottom
/// now, and this is the page that place opens.
void main() {
  late NexTestHarness harness;
  late NexServices services;

  setUp(() async {
    harness = await NexTestHarness.create(
      name: 'nex_commitments_',
      onboarded: false,
    );
    services = harness.services;
  });

  tearDown(() => harness.dispose());

  // Straight to the worker, not through `services.saveCommitment`: that one
  // also schedules a real alarm, and this page never asks it to.
  Future<void> add(String title, DateTime due, {bool paused = false}) =>
      services.worker.saveCommitment(
        NexCommitment(
          id: 'c-$title',
          title: title,
          cadence: NexCadence.months,
          every: 1,
          dueAt: due,
          paused: paused,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
      );

  Future<AppLocalizations> open(WidgetTester tester) async {
    // Tall, so the whole list is laid out. A `SliverList` only lays out what
    // the viewport reaches, and the ordering assertions below need to be
    // able to measure every row rather than the first three.
    tester.view.physicalSize = const Size(800, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: RecurringScreen(services: services)),
      ),
    );
    await tester.pumpAndSettle();
    return AppLocalizations.of(tester.element(find.byType(RecurringScreen)));
  }

  testWidgets(
    'snoozing preserves the occurrence and undo restores its due date',
    (tester) async {
      final due = DateTime.now().add(const Duration(days: 1));
      await add('rent', due);
      await open(tester);
      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();
      await tester.tap(find.text('In one hour'));
      await tester.pumpAndSettle();
      final changed = (await services.commitments()).single;
      expect(changed.dueAt.isBefore(due), isTrue);
      expect(changed.scheduledDue, due);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect((await services.commitments()).single.dueAt, due);
    },
  );
  Future<void> launcher(WidgetTester tester, void Function(BuildContext) go) =>
      tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => go(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

  testWidgets('Recurring is a page of its own, not a sheet', (tester) async {
    // It was a sheet over the timeline — the size of a question, for a list
    // of bills and medication.
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await launcher(
      tester,
      (context) => RecurringScreen.show(context, services: services),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(RecurringScreen), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('open'), findsNothing, reason: 'it covers the screen');
    final l10n = AppLocalizations.of(
      tester.element(find.byType(RecurringScreen)),
    );
    // The empty page says what to do, with a button to do it.
    await tester.tap(find.text(l10n.commitmentAdd));
    await tester.pumpAndSettle();
    expect(find.byType(CommitmentEditor), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('the editor is a page: close asks only when something changed', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await launcher(
      tester,
      (context) => CommitmentEditor.show(context, services: services),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(CommitmentEditor)),
    );
    expect(find.byType(BottomSheet), findsNothing);
    // Save waits for a name.
    final save = find.widgetWithText(FilledButton, l10n.save).first;
    expect(tester.widget<FilledButton>(save).onPressed, isNull);

    await tester.tap(find.byTooltip(l10n.cancel));
    await tester.pumpAndSettle();
    expect(find.byType(CommitmentEditor), findsNothing);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Gym');
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
    await tester.tap(find.byTooltip(l10n.cancel));
    await tester.pumpAndSettle();
    expect(find.text(l10n.unsavedChanges), findsOneWidget);
    await tester.tap(find.text(l10n.discard));
    await tester.pumpAndSettle();
    expect(find.byType(CommitmentEditor), findsNothing);
  });

  testWidgets('a new item saved from the page is on the page', (tester) async {
    await open(tester);
    final l10n = AppLocalizations.of(
      tester.element(find.byType(RecurringScreen)),
    );
    await tester.tap(find.text(l10n.commitmentAdd));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Water bill');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, l10n.save).first);
    await tester.pumpAndSettle();
    expect(find.byType(CommitmentEditor), findsNothing);
    expect(find.text('Water bill'), findsOneWidget);
    expect(find.text(l10n.commitmentsCount(1)), findsOneWidget);
  });

  testWidgets('back asks before discarding only when something changed', (
    tester,
  ) async {
    // It asked every time: any rebuild of the editor counted as an edit, so
    // opening it and going straight back still offered to discard changes.
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  CommitmentEditor.show(context, services: services),
              child: const Text('open editor'),
            ),
          ),
        ),
      ),
    );
    Future<void> back() async {
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
    }

    // Untouched: back simply closes it.
    await tester.tap(find.text('open editor'));
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(CommitmentEditor)),
    );
    await back();
    expect(find.text(l10n.unsavedChanges), findsNothing);
    expect(find.byType(CommitmentEditor), findsNothing);

    // Typed and then erased again: nothing to lose, nothing to ask.
    await tester.tap(find.text('open editor'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Gym');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '');
    await tester.pumpAndSettle();
    await back();
    expect(find.text(l10n.unsavedChanges), findsNothing);
    expect(find.byType(CommitmentEditor), findsNothing);

    // Typed and left: back asks first, and Keep editing keeps it open.
    await tester.tap(find.text('open editor'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Gym');
    await tester.pumpAndSettle();
    await back();
    expect(find.text(l10n.unsavedChanges), findsOneWidget);
    await tester.tap(find.text(l10n.keepEditing));
    await tester.pumpAndSettle();
    expect(find.byType(CommitmentEditor), findsOneWidget);
  });

  testWidgets('the numbers at the top show just those when tapped', (
    tester,
  ) async {
    final now = DateTime.now();
    await add('rent', now.subtract(const Duration(days: 9)));
    await add('insurance', now.add(const Duration(days: 2)));
    await add('passport', now.add(const Duration(days: 40)));
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('recurring-stat-overdue')));
    await tester.pumpAndSettle();
    expect(find.text('rent'), findsOneWidget);
    expect(find.text('insurance'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('recurring-stat-week')));
    await tester.pumpAndSettle();
    expect(find.text('insurance'), findsOneWidget);
    expect(find.text('rent'), findsNothing);
    // Tapped again, back to everything.
    await tester.tap(find.byKey(const ValueKey('recurring-stat-week')));
    await tester.pumpAndSettle();
    expect(find.text('passport'), findsOneWidget);
  });

  testWidgets('the page says what a recurring item is for', (tester) async {
    // It said nothing at all. A title, a plus and an empty list is a page
    // that only makes sense to whoever built it.
    final l10n = await open(tester);
    expect(find.text(l10n.commitmentsAbout), findsOneWidget);
  });

  testWidgets('an empty page invites rather than reports', (tester) async {
    final l10n = await open(tester);
    expect(find.text(l10n.commitmentsEmpty), findsOneWidget);
    // And no count beside the title, which would be a nought nobody needs.
    expect(find.text(l10n.commitmentsCount(0)), findsNothing);
  });

  testWidgets('what has slipped is at the top, whatever its date', (
    tester,
  ) async {
    final now = DateTime.now();
    // Deliberately out of date order relative to each other: sorted flat,
    // the overdue one would sit below both of the ones that are fine.
    await add('rent', now.subtract(const Duration(days: 9)));
    await add('insurance', now.add(const Duration(days: 2)));
    await add('passport', now.add(const Duration(days: 40)));
    await add('gym', now.add(const Duration(days: 5)), paused: true);

    final l10n = await open(tester);
    expect(find.text(l10n.commitmentsCount(4)), findsOneWidget);

    double y(String text) => tester.getTopLeft(find.text(text).last).dy;
    expect(y(l10n.commitmentsOverdue), lessThan(y('rent')));
    expect(y('rent'), lessThan(y(l10n.commitmentsComingUp)));
    expect(y(l10n.commitmentsComingUp), lessThan(y('insurance')));
    expect(y('insurance'), lessThan(y('passport')));
    expect(y('passport'), lessThan(y(l10n.commitmentsRested)));
    expect(y(l10n.commitmentsRested), lessThan(y('gym')));
  });

  testWidgets('a group with nothing in it is not drawn', (tester) async {
    await add('insurance', DateTime.now().add(const Duration(days: 2)));
    final l10n = await open(tester);
    expect(find.text(l10n.commitmentsComingUp), findsOneWidget);
    // The number at the top and the filter chip, but no heading.
    expect(find.text(l10n.commitmentsOverdue), findsNWidgets(2));
    expect(find.text(l10n.commitmentsRested), findsNothing);
  });
}
