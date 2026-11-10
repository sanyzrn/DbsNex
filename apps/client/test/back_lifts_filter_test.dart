import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/app.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/screens/timeline_screen.dart';

import 'support/nex_harness.dart';

/// Back on the home screen used to go: selection, search — and then the app,
/// straight out, with a filter still narrowing the list. The filter now goes
/// first, the way anything else open on the screen does.
void main() {
  testWidgets('Back lifts the active filter before it leaves the app', (
    tester,
  ) async {
    final harness = await NexTestHarness.create(name: 'nex_back_filter_');
    addTearDown(harness.dispose);

    final tagged = await harness.services.captureText('alpha carries the tag');
    await harness.services.addTag(noteId: tagged!.id, name: 'work');
    await harness.services.captureText('beta has none at all');
    await harness.services.refreshTimeline();

    await tester.pumpWidget(
      NexApp(services: harness.services, preferences: harness.preferences),
    );
    await tester.pumpAndSettle();

    // Both notes on screen, and the tag the first one wears is a pill.
    expect(find.text('alpha carries the tag'), findsOneWidget);
    expect(find.text('beta has none at all'), findsOneWidget);
    expect(find.text('work'), findsWidgets);

    // Filtering to the tag narrows the list to its one carrier.
    await tester.tap(find.text('work').first);
    await tester.pumpAndSettle();
    expect(find.text('alpha carries the tag'), findsOneWidget);
    expect(find.text('beta has none at all'), findsNothing);

    // Back: the filter comes off — the list is whole again, and the app has
    // not gone anywhere.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(
      find.text('beta has none at all'),
      findsOneWidget,
      reason: 'Back should lift the filter, not leave a narrowed list',
    );
    expect(find.byType(TimelineScreen), findsOneWidget);
  });
}
