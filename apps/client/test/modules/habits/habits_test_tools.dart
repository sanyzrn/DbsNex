import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/modules/module_api.dart';
import 'package:nex_client/modules/habits/habits_screen.dart';

import '../../support/nex_harness.dart';

/// The shared plumbing of the habits widget tests: the module's screen on
/// screen over a harness library, a way to let a tapped write land, and a
/// habit created through the real editor sheet.

/// Puts [HabitsScreen] on screen over a fresh store for [harness]'s library.
Future<NexModuleStore> pumpHabits(
  WidgetTester tester,
  NexTestHarness harness, {
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
  await tester.enterText(find.byKey(const ValueKey('habit-field-name')), name);
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
