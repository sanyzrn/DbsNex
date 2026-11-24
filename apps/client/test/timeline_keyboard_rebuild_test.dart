import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_ui/nex_ui.dart';

import 'support/nex_harness.dart';

/// The keyboard is a transient the timeline must not pay for. Asking for its
/// inset in the screen rebuilt the scroll view, every sliver and the dock on
/// each frame of the animation; the dock's own slot owns that dependency now.
void main() {
  testWidgets('the keyboard hides the dock without rebuilding the timeline', (
    tester,
  ) async {
    final harness = await NexTestHarness.create(name: 'nex_keyboard_budget_');
    addTearDown(harness.dispose);
    tester.view.physicalSize = const Size(400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await harness.preferences.setShowGreeting(false);
    await harness.preferences.setShowDaySummary(false);
    await harness.preferences.setShowTagRow(false);
    await harness.services.captureText('a note');
    await harness.services.refreshTimeline();

    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();
    expect(find.byType(NoteCard), findsWidgets);
    expect(find.byType(NexNavigationDock), findsOneWidget);

    var scrollRebuilds = 0;
    debugOnRebuildDirtyWidget = (element, _) {
      if (element.widget is CustomScrollView) scrollRebuilds++;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    expect(
      find.byType(NexNavigationDock),
      findsNothing,
      reason: 'the dock gives way to the keyboard',
    );
    expect(
      scrollRebuilds,
      0,
      reason:
          'a keyboard frame must not rebuild the timeline, only its dock slot',
    );

    // And it comes back when the keyboard leaves, still without the list
    // being rebuilt.
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pump();
    expect(find.byType(NexNavigationDock), findsOneWidget);
    expect(scrollRebuilds, 0);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
