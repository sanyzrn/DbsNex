import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/habits/habits_screen.dart';
import 'package:nex_client/modules/habits/habit_model.dart';

import '../../support/nex_harness.dart';

/// The habits module end to end: empty states, creating, checking in,
/// editing with history preserved, archiving, deleting with Undo, and the
/// data surviving the screen itself.
void main() {
  late NexTestHarness harness;

  setUp(() async => harness = await NexTestHarness.create(name: 'nex_habits_'));
  tearDown(() => harness.dispose());

  Future<NexModuleStore> pumpHabits(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
  }) async {
    final store = NexModuleStore(harness.services, 'habits');
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: HabitsScreen(store: store),
      ),
    );
    await tester.pumpAndSettle();
    return store;
  }

  /// Lets a write started by a tap reach the store, exactly as the gate
  /// test's own flows do.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 60));
    });
    await tester.pumpAndSettle();
  }

  /// Creates a habit through the real sheet, and returns the id the store
  /// gave it — a UUID v7, never a guess.
  Future<String> createHabit(
    WidgetTester tester,
    NexModuleStore store, {
    String name = 'Morning stretch',
    bool weekly = false,
    int target = 3,
  }) async {
    await tester.tap(find.byKey(const ValueKey('habits-new')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('habit-field-name')),
      name,
    );
    if (weekly) {
      await tester.tap(find.byKey(const ValueKey('habit-field-schedule')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('habit-target-$target')));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(const ValueKey('habit-save')));
    await settle(tester);
    final habits = await store.list('habit');
    expect(habits, hasLength(1), reason: 'the habit was really saved');
    return habits.first.id;
  }

  group('empty states', () {
    testWidgets('no habits yet: a clear message and a working first action', (
      tester,
    ) async {
      await pumpHabits(tester);
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
      await pumpHabits(tester);
      expect(
        find.text(
          'All your habits are archived. Unarchive one, or start a new one.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('no check-ins yet, on the detail page', (tester) async {
      final store = await pumpHabits(tester);
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
      final store = await pumpHabits(tester);
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

      // Tapping again takes it back — the honest undo.
      await tester.tap(find.byKey(ValueKey('habit-today-$id')));
      await settle(tester);
      expect(await store.list('check'), isEmpty);
      expect(find.text('0 of 1 done'), findsOneWidget);
    });

    testWidgets('two taps in quick succession never write two records', (
      tester,
    ) async {
      final store = await pumpHabits(tester);
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
      final store = await pumpHabits(tester);
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
      await pumpHabits(tester);
      await tester.tap(find.byKey(const ValueKey('habits-new')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('habit-save')));
      await tester.pumpAndSettle();
      expect(find.text('Give the habit a name first'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('habit-field-name')),
        findsOneWidget,
        reason: 'the sheet is still open',
      );
    });
  });

  group('editing keeps history', () {
    testWidgets('renaming keeps every check-in', (tester) async {
      final store = await pumpHabits(tester);
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

  group('archiving', () {
    testWidgets('archived habits leave Today and come back', (tester) async {
      final store = await pumpHabits(tester);
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
      expect(find.text('No archived habits.'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Morning stretch'), findsOneWidget);
    });
  });

  group('deleting with Undo', () {
    testWidgets('Undo restores the habit with its whole history', (
      tester,
    ) async {
      final store = await pumpHabits(tester);
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

  group('the screen is a window, not the data', () {
    testWidgets('records survive disposing and re-opening the screen', (
      tester,
    ) async {
      final store = await pumpHabits(tester);
      final id = await createHabit(tester, store);
      await tester.tap(find.byKey(ValueKey('habit-today-$id')));
      await settle(tester);

      // The screen goes away entirely.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      // …and a brand-new store and screen find everything where it was.
      final reopened = NexModuleStore(harness.services, 'habits');
      expect(await reopened.list('habit'), hasLength(1));
      expect(await reopened.list('check'), hasLength(1));

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: HabitsScreen(store: reopened),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Morning stretch'), findsOneWidget);
      expect(find.text('1 of 1 done'), findsOneWidget);
    });

    testWidgets('another module’s store cannot see these records', (
      tester,
    ) async {
      final store = await pumpHabits(tester);
      await createHabit(tester, store);

      final stranger = NexModuleStore(harness.services, 'smoke_free');
      expect(await stranger.list('habit'), isEmpty);
      expect(await stranger.list('check'), isEmpty);
    });
  });

  group('a meaningful journey', () {
    testWidgets('from nothing to a visible streak', (tester) async {
      final store = await pumpHabits(tester);
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

  testWidgets('week start is persisted independently of the UI language', (
    tester,
  ) async {
    final store = await pumpHabits(tester);
    await tester.tap(find.byKey(const ValueKey('habits-week-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('habit-week-start-1')));
    await tester.tap(find.byKey(const ValueKey('habit-week-save')));
    await settle(tester);
    expect((await store.get('settings', 'week'))?['firstDay'], 1);
    await tester.pumpWidget(const SizedBox());
    await pumpHabits(tester);
    await tester.tap(find.byKey(const ValueKey('habits-week-settings')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const ValueKey('habit-week-start-1')))
          .selected,
      isTrue,
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  });
}
