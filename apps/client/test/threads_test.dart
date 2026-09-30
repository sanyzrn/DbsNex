import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/app.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/screens/threads_screen.dart';
import 'package:nex_client/screens/timeline_screen.dart';
import 'package:nex_ui/nex_ui.dart';

import 'support/nex_harness.dart';

/// Threads (W5.3): offered after a capture only when clear, added only with a
/// tap, and a view over notes that never moves one.
void main() {
  late NexTestHarness harness;
  late NexServices services;
  late NexPreferences preferences;

  setUp(() async {
    harness = await NexTestHarness.create(
      name: 'nex_threads_ui_',
      onboarded: true,
    );
    services = harness.services;
    preferences = harness.preferences;
  });

  tearDown(() => harness.dispose());

  Future<void> offer(WidgetTester tester, String noteId) async {
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();
    await tester
        .state<TimelineScreenState>(find.byType(TimelineScreen))
        .offerThreadFor(noteId);
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets('a capture that continues a thread is offered to it', (
    tester,
  ) async {
    final first = await services.captureText(
      'Kitchen renovation: cabinets measured, tiles ordered',
    );
    final thread = await services.createThread('Kitchen', noteIds: [first!.id]);
    final next = await services.captureText(
      'Kitchen renovation: tiles arrived, cabinets next week',
    );
    await offer(tester, next!.id);

    expect(find.text('Continues “Kitchen”?'), findsOneWidget);
    // Nothing is added until the tap.
    expect(await services.threadNotes(thread.id), hasLength(1));

    await tester.tap(find.text('Add'));
    await tester.pump(const Duration(milliseconds: 600));
    expect((await services.threadNotes(thread.id)).map((n) => n.id), [
      first.id,
      next.id,
    ]);
    await tester.pumpAndSettle(const Duration(seconds: 10));
  });

  testWidgets('an unrelated capture is offered nothing', (tester) async {
    await services.captureText('Buy milk and bread');
    final other = await services.captureText('Call the dentist on Tuesday');
    await offer(tester, other!.id);
    expect(find.textContaining('Continues'), findsNothing);
    expect(find.textContaining('Start a thread'), findsNothing);
    await tester.pumpAndSettle(const Duration(seconds: 10));
  });

  testWidgets('turned off, nothing is offered', (tester) async {
    await preferences.setThreadSuggestions(false);
    final first = await services.captureText(
      'Kitchen renovation: cabinets measured, tiles ordered',
    );
    await services.createThread('Kitchen', noteIds: [first!.id]);
    final next = await services.captureText(
      'Kitchen renovation: tiles arrived, cabinets next week',
    );
    await offer(tester, next!.id);
    expect(find.text('Continues “Kitchen”?'), findsNothing);
    await tester.pumpAndSettle(const Duration(seconds: 10));
  });

  testWidgets('a thread reads oldest first, and a note can leave it', (
    tester,
  ) async {
    final a = await services.captureText('garden: plan the beds');
    final b = await services.captureText('garden: buy compost');
    await services.createThread('Garden', noteIds: [a!.id, b!.id]);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ThreadsScreen(services: services, preferences: preferences),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Garden'), findsOneWidget);
    expect(find.text('2 notes'), findsOneWidget);

    await tester.tap(find.text('Garden'));
    await tester.pumpAndSettle();
    final cards = find.byType(NoteCard);
    expect(cards, findsNWidgets(2));
    expect(
      tester.getTopLeft(find.text('garden: plan the beds')).dy,
      lessThan(tester.getTopLeft(find.text('garden: buy compost')).dy),
    );

    await tester.tap(find.byTooltip('Remove from thread').first);
    await tester.pumpAndSettle();
    expect(find.byType(NoteCard), findsOneWidget);
    // Leaving a thread is not being deleted.
    expect(await services.getById(a.id), isNotNull);
  });
}
