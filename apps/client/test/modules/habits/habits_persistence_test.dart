import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/habits/habits_screen.dart';
import 'package:nex_client/modules/habits/habit_model.dart';

import '../../support/nex_harness.dart';

/// The screen is a window, not the data: records outlive the screen that
/// showed them, stay inside this module's shelf, and the week-start choice
/// persists on its own — independent of the language on screen.
void main() {
  late NexTestHarness harness;

  setUp(
    () async => harness = await NexTestHarness.create(name: 'nex_habits_kept_'),
  );
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

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 60));
    });
    await tester.pumpAndSettle();
  }

  testWidgets('records survive disposing and re-opening the screen', (
    tester,
  ) async {
    final store = await pumpHabits(tester);
    // One habit with today's check-in, written the way the screen writes it.
    await store.put('habit', 'h1', {
      'name': 'Morning stretch',
      'note': '',
      'schedule': 'daily',
      'target': 1,
      'archived': false,
      'createdAt': DateTime.now().toIso8601String(),
    });
    final today = dateKeyOf(DateTime.now());
    await store.put('check', HabitCheck.idFor('h1', today), {
      'habit': 'h1',
      'date': today,
      'at': DateTime.now().toIso8601String(),
    });
    await tester.pumpAndSettle();
    expect(find.text('Morning stretch'), findsOneWidget);

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
    await store.put('habit', 'h1', {
      'name': 'Morning stretch',
      'note': '',
      'schedule': 'daily',
      'target': 1,
      'archived': false,
      'createdAt': DateTime.now().toIso8601String(),
    });
    await tester.pumpAndSettle();

    final stranger = NexModuleStore(harness.services, 'smoke_free');
    expect(await stranger.list('habit'), isEmpty);
    expect(await stranger.list('check'), isEmpty);
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
    await pumpHabits(tester, locale: const Locale('fa'));
    await tester.tap(find.byKey(const ValueKey('habits-week-settings')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const ValueKey('habit-week-start-1')))
          .selected,
      isTrue,
      reason: 'the persisted choice, not the language, picks the chip',
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  });
}
