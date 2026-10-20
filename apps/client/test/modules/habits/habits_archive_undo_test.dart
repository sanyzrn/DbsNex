import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/nex_harness.dart';
import 'habits_test_tools.dart';

/// Every delete path and its Undo: archiving keeps history, deleting a
/// habit brings back its whole check-in history, and taking a day's
/// check-in back — from Today and from the detail page — restores the exact
/// original record, the moment it was first made included.
void main() {
  late NexTestHarness harness;

  setUp(() async => harness = await NexTestHarness.create(name: 'nex_habits_'));
  tearDown(() => harness.dispose());

  group('archiving', () {
    testWidgets('archived habits leave Today and come back', (tester) async {
      final store = await pumpHabits(tester, harness);
      final id = await createHabit(tester, store);
      await tester.tap(find.byKey(ValueKey('habit-today-$id')));
      await settle(tester);

      await tester.tap(find.text('Morning stretch'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('habit-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Archive'));
      await settle(tester);

      // The detail page stays open on the archived habit; going back to
      // Today is where it has vanished.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Morning stretch'), findsNothing);
      expect(
        find.text(
          'All your habits are archived. Unarchive one, or start a new one.',
        ),
        findsOneWidget,
      );
      // …history intact.
      expect(await store.list('check'), isNotEmpty);

      await tester.tap(find.byKey(const ValueKey('habits-archive')));
      await tester.pumpAndSettle();
      expect(find.text('Morning stretch'), findsOneWidget);

      await tester.tap(find.byKey(ValueKey('unarchive-$id')));
      await settle(tester);
      // The empty archive says where archiving happens and carries the way
      // back — its button, not a hunt for the app bar's back.
      expect(
        find.text(
          'Nothing is archived yet. Archive a habit from its own page to take '
          'a break without losing history.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('habits-archive-back')));
      await tester.pumpAndSettle();
      expect(find.text('Morning stretch'), findsOneWidget);
    });
  });

  group('deleting with Undo', () {
    testWidgets('removing a check-in offers Undo, and Undo restores the '
        'exact original record', (tester) async {
      final store = await pumpHabits(tester, harness);
      final id = await createHabit(tester, store);
      await tester.tap(find.byKey(ValueKey('habit-today-$id')));
      await settle(tester);
      final before = (await store.list('check')).single;

      // An accidental second tap takes the check-in back…
      await tester.tap(find.byKey(ValueKey('habit-today-$id')));
      await settle(tester);
      expect(await store.list('check'), isEmpty);
      expect(find.text('Check-in removed'), findsOneWidget);

      // …and Undo writes the very same record back — id, day and original
      // moment — not a re-created one.
      await tester.tap(find.text('Undo'));
      await settle(tester);
      final after = (await store.list('check')).single;
      expect(after.id, before.id);
      expect(after.body, before.body);
      expect(after.body['at'], before.body['at']);
      expect(find.text('1 of 1 done'), findsOneWidget);
    });

    testWidgets('the detail page’s check-in button has the same Undo', (
      tester,
    ) async {
      final store = await pumpHabits(tester, harness);
      final id = await createHabit(tester, store);
      await tester.tap(find.byKey(ValueKey('habit-today-$id')));
      await settle(tester);
      final before = (await store.list('check')).single;

      await tester.tap(find.text('Morning stretch'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('habit-toggle-$id')));
      await settle(tester);
      expect(await store.list('check'), isEmpty);
      expect(find.text('Check-in removed'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await settle(tester);
      final after = (await store.list('check')).single;
      expect(after.id, before.id);
      expect(after.body, before.body);
      // The button reads as checked-in again: it offers to take it back.
      expect(find.text('Undo today’s check-in'), findsOneWidget);
    });

    testWidgets('Undo restores the habit with its whole history', (
      tester,
    ) async {
      final store = await pumpHabits(tester, harness);
      final id = await createHabit(tester, store);
      await tester.tap(find.byKey(ValueKey('habit-today-$id')));
      await settle(tester);
      expect(await store.list('check'), hasLength(1));

      await tester.tap(find.text('Morning stretch'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('habit-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await settle(tester);

      expect(find.text('Morning stretch'), findsNothing);
      expect(await store.list('habit'), isEmpty);
      expect(await store.list('check'), isEmpty);
      expect(find.text('Habit deleted'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await settle(tester);

      expect(await store.list('habit'), hasLength(1));
      expect(
        await store.list('check'),
        hasLength(1),
        reason: 'the check-in came back too, not only the name',
      );
      expect(find.text('Morning stretch'), findsOneWidget);
      expect(find.text('1 of 1 done'), findsOneWidget);
    });
  });
}
