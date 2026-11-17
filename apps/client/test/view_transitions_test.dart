import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ai/cloud.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/widgets/note_grid_card.dart';
import 'package:nex_ui/nex_ui.dart';

import 'support/nex_harness.dart';

/// The home's own changes of view are transitions, not cuts (2.8.2): list
/// or grid, a tag, and the brief folding.
void main() {
  late NexTestHarness harness;

  setUp(() async {
    harness = await NexTestHarness.create(
      name: 'nex_view_fade_',
      onboarded: true,
    );
    for (var i = 0; i < 6; i++) {
      final note = await harness.services.captureText('written $i');
      await harness.services.addTag(
        noteId: note!.id,
        name: i.isEven ? 'work' : 'home',
      );
    }
    await harness.services.refreshTimeline();
  });

  tearDown(() => harness.dispose());

  Future<void> open(WidgetTester tester) async {
    tester.view.devicePixelRatio = 2.75;
    tester.view.physicalSize = const Size(1080, 2340);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();
  }

  final dissolve = find.byKey(const ValueKey('timeline-view-dissolve'));

  double bodyOpacity(WidgetTester tester) => tester
      .widgetList<SliverFadeTransition>(find.byType(SliverFadeTransition))
      .first
      .opacity
      .value;

  testWidgets('list to grid and back: the old view fades out over the new '
      'one, and lets go of its picture after', (tester) async {
    await open(tester);
    expect(dissolve, findsNothing);
    for (final grid in [true, false]) {
      await tester.tap(find.byKey(const ValueKey('home-view-toggle')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      // Both at once: the new view arriving under the old one leaving.
      expect(dissolve, findsOneWidget);
      expect(bodyOpacity(tester), inExclusiveRange(0, 1));
      expect(find.byType(NexNoteGridCard).evaluate().isNotEmpty, grid);
      await tester.pumpAndSettle();
      expect(dissolve, findsNothing);
      expect(bodyOpacity(tester), 1);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('a tag: the same crossfade, onto the notes it narrows to', (
    tester,
  ) async {
    await open(tester);
    expect(find.byType(NoteCard), findsNWidgets(6));
    await tester.tap(
      find.descendant(
        of: find.byType(TagFilterRow),
        matching: find.text('home'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(dissolve, findsOneWidget);
    await tester.pumpAndSettle();
    expect(dissolve, findsNothing);
    expect(find.byType(NoteCard), findsNWidgets(3));
  });

  testWidgets('with animations off, a change of view is the plain cut', (
    tester,
  ) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: harness.app(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-view-toggle')));
    await tester.pump();
    expect(dissolve, findsNothing);
    await tester.pumpAndSettle();
    expect(find.byType(NexNoteGridCard), findsWidgets);
  });

  testWidgets('folding the brief: its last lines fade as the card closes '
      'over them, rather than leaving on the frame of the tap', (tester) async {
    await harness.preferences.setAiEnabled(true);
    await harness.preferences.setAiProvider(
      const AiProviderConfig(provider: AiProvider.openai, apiKey: 'k'),
    );
    await harness.preferences.setAiDaySummary(
      text: 'A calm day ahead\nCall the plumber\nFinish the draft',
      dateKey: 'cached',
    );
    await harness.preferences.setDaySummaryFolded(false);
    await tester.pumpWidget(harness.app());
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final recap = find.byKey(const ValueKey('timeline-recap'));
    final last = find.descendant(
      of: recap,
      matching: find.text('Finish the draft'),
    );
    expect(last, findsOneWidget);
    final open = tester.getSize(recap).height;

    await tester.tap(find.text('A calm day ahead'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    // Still there, on its way out, and fading.
    expect(last, findsOneWidget);
    final fading = tester.widget<FadeTransition>(
      find.ancestor(of: last, matching: find.byType(FadeTransition)).first,
    );
    expect(fading.opacity.value, inExclusiveRange(0, 1));
    final closing = tester.getSize(recap).height;
    expect(closing, lessThan(open));

    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(last, findsNothing);
    expect(tester.getSize(recap).height, lessThan(closing));
    expect(tester.takeException(), isNull);
  });
}
