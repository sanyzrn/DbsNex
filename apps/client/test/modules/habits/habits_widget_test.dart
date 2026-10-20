import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/habits/habit_model.dart';

import '../../support/nex_harness.dart';
import 'habits_test_tools.dart';

/// The habits module end to end: empty states, creating, checking in,
/// editing with history preserved, and the data surviving the screen
/// itself. Archiving and deleting-with-Undo live beside this file, in
/// `habits_archive_undo_test.dart`.
void main() {
  late NexTestHarness harness;

  setUp(() async => harness = await NexTestHarness.create(name: 'nex_habits_'));
  tearDown(() => harness.dispose());

  group('empty states', () {
    testWidgets('no habits yet: a clear message and a working first action', (
      tester,
    ) async {
      await pumpHabits(tester, harness);
      expect(
        find.text('No habits yet. Start with one small thing.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('habits-new')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('habits-new')));
      await tester.pumpAndSettle();
      expect(find.text('New habit'), findsWidgets);
    });

    testWidgets('all archived: the second empty state, equally actionable', (
      tester,
    ) async {
      final store = NexModuleStore(harness.services, 'habits');
      await store.put('habit', 'h1', {
        'name': 'Stretch',
        'note': '',
        'schedule': 'daily',
        'target': 1,
        'archived': true,
        'createdAt': DateTime.now().toIso8601String(),
      });
      await pumpHabits(tester, harness);
      expect(
        find.text(
          'All your habits are archived. Unarchive one, or start a new one.',
        ),
        findsOneWidget,
      );

      // The message offers two ways out and carries the buttons for both.
      await tester.tap(find.byKey(const ValueKey('habits-open-archived')));
      await tester.pumpAndSettle();
      expect(find.text('Archived'), findsOneWidget);
      expect(find.text('Stretch'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
    });

    testWidgets('no check-ins yet, on the detail page', (tester) async {
      final store = await pumpHabits(tester, harness);
      await createHabit(tester, store);
      await tester.tap(find.text('Morning stretch'));
      await tester.pumpAndSettle();
      expect(find.text('No check-ins yet.'), findsOneWidget);
    });
  });

  group('creating and checking in', () {
    testWidgets('a daily habit appears on Today and checks off in one tap', (
      tester,
    ) async {
      final store = await pumpHabits(tester, harness);
      final id = await createHabit(tester, store);

      expect(find.text('Morning stretch'), findsOneWidget);
      expect(find.text('0 of 1 done'), findsOneWidget);

      await tester.tap(find.byKey(ValueKey('habit-today-$id')));
      await settle(tester);
      expect(find.text('1 of 1 done'), findsOneWidget);

      // The check-in is a real record, keyed by the civil date.
      final checks = await store.list('check');
      expect(checks, hasLength(1));
      expect(checks.first.body['habit'], id);
      expect(checks.first.body['date'], dateKeyOf(DateTime.now()));

      // Tapping again takes it back — the honest undo — and says so, with
      // Undo for the accidental case.
      await tester.tap(find.byKey(ValueKey('habit-today-$id')));
      await settle(tester);
      expect(await store.list('check'), isEmpty);
      expect(find.text('0 of 1 done'), findsOneWidget);
      expect(find.text('Check-in removed'), findsOneWidget);
      // No timer may outlive the test: take the snackbar with us.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('two taps in quick succession never write two records', (
      tester,
    ) async {
      final store = await pumpHabits(tester, harness);
      final id = await createHabit(tester, store);
      final mark = find.byKey(ValueKey('habit-today-$id'));

      await tester.tap(mark);
      await tester.tap(mark);
      await settle(tester);

      // Whether the second tap landed before or after the first write, the
      // day can hold only one check-in: the record id is the habit and the
      // civil date.
      final checks = await store.list('check');
      expect(
        checks.length,
        lessThanOrEqualTo(1),
        reason: 'a day never holds two check-ins for one habit',
      );
    });

    testWidgets('a weekly habit shows its progress toward the target', (
      tester,
    ) async {
      final store = await pumpHabits(tester, harness);
      final id = await createHabit(
        tester,
        store,
        name: 'Gym',
        weekly: true,
        target: 3,
      );
      expect(find.text('0 of 3 this week'), findsOneWidget);

      await tester.tap(find.byKey(ValueKey('habit-today-$id')));
      await settle(tester);
      expect(find.text('1 of 3 this week'), findsOneWidget);
    });

    testWidgets('a nameless habit cannot be saved', (tester) async {
      await pumpHabits(tester, harness);
      await tester.tap(find.byKey(const ValueKey('habits-new')));
      await tester.pumpAndSettle();
      // The person's own words: the name one line in NexAutoDirection, the
      // note — more than one line — the shared NexTextField.
      expect(
        tester.widget(find.byKey(const ValueKey('habit-field-name'))),
        isA<TextField>(),
      );
      expect(
        tester.widget(find.byKey(const ValueKey('habit-field-note'))),
        isA<NexTextField>(),
      );
      await tester.tap(find.byKey(const ValueKey('habit-save')));
      await tester.pumpAndSettle();
      expect(find.text('Give the habit a name first'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('habit-field-name')),
        findsOneWidget,
        reason: 'the sheet is still open',
      );
    });

    testWidgets('the weekly target chips read naturally, one included', (
      tester,
    ) async {
      await pumpHabits(tester, harness);
      await tester.tap(find.byKey(const ValueKey('habits-new')));
      await tester.pumpAndSettle();
      // Tap the segment's own words, not the middle of the row: the seam
      // belongs to whichever segment the direction hands it.
      await tester.tap(find.text('Weekly'));
      await tester.pumpAndSettle();

      // The seven choices are counts; the first is also its own word, so
      // the English never reads “1 times a week”.
      expect(find.text('Once a week'), findsOneWidget);
      expect(find.text('2 times a week'), findsOneWidget);
      expect(find.text('1 times a week'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('the same chips read naturally in Persian', (tester) async {
      await pumpHabits(tester, harness, locale: const Locale('fa'));
      await tester.tap(find.byKey(const ValueKey('habits-new')));
      await tester.pumpAndSettle();
      // The segment's own words again: at the row's seam, right-to-left hit
      // testing hands the tap to «روزانه» instead of «هفتگی».
      await tester.tap(find.text('هفتگی'));
      await tester.pumpAndSettle();

      // «یک بار در هفته» via the {n} pipeline, so the digit is Persian.
      expect(find.text('۱ بار در هفته'), findsOneWidget);
      expect(find.text('۲ بار در هفته'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  });

  group('editing keeps history', () {
    testWidgets('renaming keeps every check-in', (tester) async {
      final store = await pumpHabits(tester, harness);
      final id = await createHabit(tester, store);
      await tester.tap(find.byKey(ValueKey('habit-today-$id')));
      await settle(tester);

      await tester.tap(find.text('Morning stretch'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('habit-edit')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('habit-field-name')),
        'Evening stretch',
      );
      await tester.tap(find.byKey(const ValueKey('habit-save')));
      await settle(tester);

      expect(find.text('Evening stretch'), findsOneWidget);
      final habits = await store.list('habit');
      expect(habits.first.body['name'], 'Evening stretch');
      // The check-in from before the rename is untouched.
      final checks = await store.list('check');
      expect(checks, hasLength(1));
      expect(checks.first.body['habit'], id);
    });
  });

  group('a meaningful journey', () {
    testWidgets('from nothing to a visible streak', (tester) async {
      final store = await pumpHabits(tester, harness);
      final id = await createHabit(tester, store);

      // A few days of history, written the way the store writes them.
      final today = DateTime.now();
      for (var back = 0; back < 3; back++) {
        final day = today.subtract(Duration(days: back));
        final key = dateKeyOf(day);
        await store.put('check', HabitCheck.idFor(id, key), {
          'habit': id,
          'date': key,
          'at': day.toIso8601String(),
        });
      }
      await tester.pumpAndSettle();

      await tester.tap(find.text('Morning stretch'));
      await tester.pumpAndSettle();
      expect(find.text('3-day streak'), findsOneWidget);
      expect(find.text('3 check-ins'), findsOneWidget);

      // Back navigation returns to Today.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Today'), findsOneWidget);
    });
  });
}
