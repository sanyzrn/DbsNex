import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/app.dart';
import 'package:nex_client/platform/nex_services.dart';

import 'support/nex_harness.dart';

/// A pin from the hold menu used to be silent and invisible: the card left
/// the finger's neighbourhood for the pinned section with no word, and the
/// limit at five was a refusal with no way past it. Both now say what
/// happened and offer the trip to the pins.
void main() {
  testWidgets('pinning from the hold menu says so, and offers the pins', (
    tester,
  ) async {
    final harness = await NexTestHarness.create(name: 'nex_pin_banner_');
    addTearDown(harness.dispose);

    await harness.services.captureText('pin me to the top');
    await harness.services.refreshTimeline();

    await tester.pumpWidget(
      NexApp(services: harness.services, preferences: harness.preferences),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.text('pin me to the top'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pin'));
    await tester.pumpAndSettle();

    // The receipt: what became of the card, and the way to see it. "Pinned"
    // is also the section the card moved to — the banner's action label is
    // the one thing only the banner says.
    expect(find.text('Pinned'), findsWidgets);
    final showPinned = find.text('Show pinned');
    expect(showPinned, findsOneWidget);

    // The banner's action is a scroll that lands on the pins — here the
    // only note is the pin, at the top already, and the trip is a no-op
    // that must not so much as throw.
    await tester.tap(showPinned);
    await tester.pumpAndSettle();
    expect(showPinned, findsOneWidget);
  });

  testWidgets('the fifth pin wall answers with the trip, not just "no"', (
    tester,
  ) async {
    final harness = await NexTestHarness.create(name: 'nex_pin_wall_');
    addTearDown(harness.dispose);

    for (var i = 1; i <= 6; i++) {
      final note = await harness.services.captureText('pinned number $i');
      if (i <= 5) {
        await harness.services.pinNote(note.id);
      }
    }
    await harness.services.refreshTimeline();

    // Tall, so the sixth note is on screen with the five pinned above it —
    // no scrolling, and no depending on which scrollable is which.
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 2400);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      NexApp(services: harness.services, preferences: harness.preferences),
    );
    await tester.pumpAndSettle();

    // The sixth note, unpinned, below the five that are.
    await tester.longPress(find.text('pinned number 6'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pin'));
    await tester.pumpAndSettle();

    // The limit is still a limit — but it comes with the way forward: the
    // five are one tap away, to lift one.
    expect(find.text('You can pin up to 5 notes'), findsOneWidget);
    expect(find.text('Show pinned'), findsOneWidget);
  });
}
