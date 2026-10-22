import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/screens/library_screen.dart';
import 'package:nex_client/screens/set_aside_screen.dart';
import 'package:nex_ui/nex_ui.dart';

import 'support/nex_harness.dart';

/// Putting a note to one side: off the home screen, still in the library.
void main() {
  late NexTestHarness harness;
  late NexServices services;

  setUp(() async {
    harness = await NexTestHarness.create(name: 'nex_set_aside_');
    services = harness.services;
    for (final text in ['alpha note', 'beta note']) {
      await services.captureText(text);
    }
    await services.refreshTimeline();
  });

  tearDown(() => harness.dispose());

  Future<void> open(WidgetTester tester) async {
    tester.view.devicePixelRatio = 2.75;
    tester.view.physicalSize = const Size(1080, 2340);
    addTearDown(tester.view.reset);
    TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
      disableAnimations: true,
    );
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();
  }

  Finder card(String text) =>
      find.ancestor(of: find.text(text), matching: find.byType(NoteCard));

  /// Hold menu → Set aside → "Until I bring it back".
  Future<void> setAside(WidgetTester tester, String text) async {
    await tester.longPress(card(text));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set aside'));
    await tester.pumpAndSettle();
    expect(find.text('Set aside until…'), findsOneWidget);
    await tester.tap(find.text('Until I bring it back'));
    await tester.pumpAndSettle();
  }

  testWidgets('the hold menu sets a note aside and Undo brings it back', (
    tester,
  ) async {
    await open(tester);
    expect(card('alpha note'), findsOneWidget);

    await setAside(tester, 'alpha note');
    expect(card('alpha note'), findsNothing);
    expect(card('beta note'), findsOneWidget);
    expect(find.text('Set aside'), findsOneWidget, reason: 'the banner');

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(card('alpha note'), findsOneWidget);
  });

  testWidgets('the library lists what is set aside and brings it back', (
    tester,
  ) async {
    final alpha = (await services.worker.timeline(
      limit: 10,
    )).firstWhere((n) => n.content == 'alpha note');
    expect(await services.setAside(alpha.id), isTrue);
    await services.refreshTimeline();

    await open(tester);
    expect(card('alpha note'), findsNothing);

    await tester.tap(find.byIcon(Icons.inventory_2_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(LibraryScreen), findsOneWidget);
    expect(find.text('1 note set aside'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('library-set-aside')));
    await tester.pumpAndSettle();
    expect(find.byType(SetAsideScreen), findsOneWidget);
    expect(find.text('alpha note'), findsOneWidget);
    expect(find.text('Until you bring it back'), findsOneWidget);

    await tester.tap(find.text('Bring back'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Nothing set aside'), findsOneWidget);
    expect(await services.setAsideCount(), 0);
  });

  testWidgets('with everything set aside the home screen says so', (
    tester,
  ) async {
    for (final note in await services.worker.timeline(limit: 10)) {
      await services.setAside(note.id);
    }
    await services.refreshTimeline();
    await open(tester);
    expect(find.text('All clear'), findsOneWidget);
    expect(find.text('2 notes set aside'), findsOneWidget);

    await tester.tap(find.text('See what’s set aside'));
    await tester.pumpAndSettle();
    expect(find.byType(SetAsideScreen), findsOneWidget);
    expect(find.text('alpha note'), findsOneWidget);
    expect(find.text('beta note'), findsOneWidget);
  });

  testWidgets('a set-aside note stays findable and says why it is hidden', (
    tester,
  ) async {
    final beta = (await services.worker.timeline(
      limit: 10,
    )).firstWhere((n) => n.content == 'beta note');
    await services.setAside(beta.id);
    await services.refreshTimeline();
    await open(tester);
    expect(card('beta note'), findsNothing);

    await tester.tap(find.byIcon(Icons.search).first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).first, 'beta');
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(card('beta note'), findsOneWidget);
    expect(find.text('Set aside'), findsOneWidget);
  });
}
