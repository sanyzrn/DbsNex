import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/screens/timeline_screen.dart';

import 'support/nex_harness.dart';

/// What the home screen does *besides* the change the person asked for.
///
/// The daily brief reads the habits, the whole candidate library and the
/// attention engine. It used to start that reading on the delivery of every
/// write and on every preference change — so a delete shared its frames with
/// it (the Undo notice got the blame) and so did the list/grid switch (the
/// crossfade got the blame). These tests hold the rule that replaced it: the
/// brief is read once, after a burst of writes has settled, and never for a
/// preference that is not about the brief.
void main() {
  late NexTestHarness harness;

  setUp(() async {
    harness = await NexTestHarness.create(
      name: 'nex_home_brief_',
      // The report style needs no provider, which is what lets a test reach
      // the pass at all: with a model style and no key there is nothing to
      // build, and the count would stay zero for the wrong reason.
      preferences: {'brief.style': 'report'},
    );
    for (var i = 0; i < 4; i++) {
      await harness.services.captureText('home brief note $i');
    }
    await harness.services.refreshTimeline();
  });

  tearDown(() => harness.dispose());

  Future<TimelineScreenState> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();
    return tester.state<TimelineScreenState>(find.byType(TimelineScreen));
  }

  /// Lets the trailing brief pass land, so the next assertion is about a new
  /// pass rather than the one the open library earned.
  Future<void> settleBrief(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
  }

  testWidgets('a delete leaves at once and the brief waits for the burst', (
    tester,
  ) async {
    final state = await open(tester);
    await settleBrief(tester);
    final passes = state.debugBriefPasses;
    expect(passes, greaterThan(0), reason: 'the open library earned one pass');
    final note = state.model.all!.first;

    await state.deleteWithUndo(note);
    await tester.pump();

    expect(state.model.byId(note.id), isNull);
    expect(find.text('Note deleted'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
    expect(
      state.debugBriefPasses,
      passes,
      reason: 'the Undo notice shared its frame with a library reading',
    );

    await settleBrief(tester);
    expect(
      state.debugBriefPasses,
      passes + 1,
      reason: 'one pass after the burst, not one per write',
    );
    expect(find.text(note.content!), findsNothing);
  });

  testWidgets('Undo puts the note back', (tester) async {
    final state = await open(tester);
    final note = state.model.all!.first;
    await state.deleteWithUndo(note);
    await tester.pumpAndSettle();
    expect(state.model.byId(note.id), isNull);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(state.model.byId(note.id), isNotNull);
    // The card is back; the brief's own line may name the same note too.
    expect(find.text(note.content!), findsWidgets);
  });

  testWidgets('changing the home layout never rebuilds the brief', (
    tester,
  ) async {
    final state = await open(tester);
    await settleBrief(tester);
    final passes = state.debugBriefPasses;
    expect(passes, greaterThan(0));

    await harness.preferences.setTimelineGrid(true);
    await tester.pumpAndSettle();
    expect(
      state.debugBriefPasses,
      passes,
      reason: 'the list/grid switch reread the library for the brief',
    );

    await harness.preferences.setTimelineGrid(false);
    await tester.pumpAndSettle();
    expect(
      state.debugBriefPasses,
      passes,
      reason: 'switching back reread the library for the brief',
    );
  });
}
