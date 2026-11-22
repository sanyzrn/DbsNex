import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/nex_harness.dart';
import 'habits_test_tools.dart';

/// Rest days on screen (2.9.0): taken from the habit's own page, visible on
/// Today while they last, and ended again with one tap.
void main() {
  late NexTestHarness harness;
  setUp(
    () async =>
        harness = await NexTestHarness.create(name: 'nex_habits_pause_'),
  );
  tearDown(() => harness.dispose());

  testWidgets('a rest is taken, shown on Today, and ended again', (
    tester,
  ) async {
    final store = await pumpHabits(tester, harness);
    final id = await createHabit(tester, store);

    await tester.tap(find.text('Morning stretch'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('habit-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Take a rest…'));
    await tester.pumpAndSettle();
    expect(find.text('Rest days'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('habit-pause-7')));
    await settle(tester);

    final body = await store.get('habit', id);
    final pauses = body?['pauses'];
    expect(pauses, isA<List<Object?>>(), reason: 'the rest is in the record');
    expect((pauses! as List<Object?>).single, isA<Map<Object?, Object?>>());
    expect(find.byKey(const ValueKey('habit-paused-banner')), findsOneWidget);

    // Back on Today the resting habit is visible, not folded away.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Rest days'), findsOneWidget);
    expect(find.byKey(ValueKey('habit-tile-$id')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(ValueKey('habit-tile-$id')),
        matching: find.textContaining('Resting until'),
      ),
      findsOneWidget,
    );

    // Ending the rest makes today a habit day again.
    await tester.tap(find.text('Morning stretch'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('habit-pause-end')));
    await settle(tester);
    expect((await store.get('habit', id))?['pauses'] ?? const [], isEmpty);
    expect(find.text('Check in for today'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('editing keeps a field this version does not know', (
    tester,
  ) async {
    final store = await pumpHabits(tester, harness);
    final id = await createHabit(tester, store);
    await store.put('habit', id, {
      ...?await store.get('habit', id),
      'future': {'kept': true},
    });
    await tester.pumpAndSettle();

    await tester.tap(find.text('Morning stretch'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('habit-edit')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('habit-field-name')),
      'Evening stretch',
    );
    await tapHabitControl(tester, find.byKey(const ValueKey('habit-save')));
    await settle(tester);

    final saved = await store.get('habit', id);
    expect(saved?['name'], 'Evening stretch');
    expect(saved?['future'], {'kept': true});
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('the ideas include the everyday Iranian ones, in Persian', (
    tester,
  ) async {
    await pumpHabits(tester, harness, locale: const Locale('fa'));
    await tester.tap(find.byKey(const ValueKey('habits-new')));
    await tester.pumpAndSettle();

    expect(find.text('نمازهای روزانه'), findsOneWidget);
    expect(find.text('قرآن خواندن'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('habit-template-prayer')));
    await tester.pumpAndSettle();
    expect(find.text('نمازهای روزانه'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
