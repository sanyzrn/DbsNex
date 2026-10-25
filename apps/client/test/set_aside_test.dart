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
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();
    expect(find.text('Archive until…'), findsOneWidget);
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
    expect(find.text('Archived'), findsOneWidget, reason: 'the banner');

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
    expect(find.text('1 archived note'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('library-set-aside')));
    await tester.pumpAndSettle();
    expect(find.byType(SetAsideScreen), findsOneWidget);
    expect(find.text('alpha note'), findsOneWidget);
    expect(find.text('Waiting for you'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('archive-back-${alpha.id}')));
    await tester.pumpAndSettle();
    expect(find.textContaining('The archive is empty'), findsOneWidget);
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
    expect(find.text('2 archived notes'), findsOneWidget);

    await tester.tap(find.text('Open the archive'));
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
    expect(find.text('Archived'), findsOneWidget);
  });

  testWidgets('one unarchive has an Undo; the "all" actions ask first', (
    tester,
  ) async {
    for (final note in await services.worker.timeline(limit: 10)) {
      await services.setAside(note.id);
    }
    await services.refreshTimeline();
    await open(tester);
    await tester.tap(find.byIcon(Icons.inventory_2_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('library-set-aside')));
    await tester.pumpAndSettle();

    final alpha = (await services.listSetAside()).firstWhere(
      (n) => n.content == 'alpha note',
    );
    await tester.tap(find.byKey(ValueKey('archive-back-${alpha.id}')));
    await tester.pumpAndSettle();
    expect(await services.setAsideCount(), 1);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(await services.setAsideCount(), 2);
    expect(find.text('alpha note'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('archive-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete all'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await services.setAsideCount(), 2, reason: 'nothing without a yes');

    await tester.tap(find.byKey(const ValueKey('archive-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete all'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(await services.setAsideCount(), 0);
    expect(await services.deletedNotes(), hasLength(2));
  });

  testWidgets('a note restored or deleted for good in the trash has an Undo', (
    tester,
  ) async {
    final notes = await services.worker.timeline(limit: 10);
    for (final note in notes) {
      await services.deleteNote(note.id);
    }
    await services.refreshTimeline();
    await open(tester);
    await tester.tap(find.byIcon(Icons.inventory_2_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trash'));
    await tester.pumpAndSettle();

    final first = notes.first;
    await tester.tap(find.byKey(ValueKey('trash-restore-${first.id}')));
    await tester.pumpAndSettle();
    expect(await services.deletedNotes(), hasLength(1));
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(await services.deletedNotes(), hasLength(2));

    // Deleting for good waits for its Undo, and the Undo keeps the note.
    await tester.tap(find.byKey(ValueKey('trash-purge-${first.id}')));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('trash-${first.id}')), findsNothing);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 8));
    expect(await services.deletedNotes(), hasLength(2));
    expect(find.byKey(ValueKey('trash-${first.id}')), findsWidgets);

    // Left alone, it goes.
    await tester.tap(find.byKey(ValueKey('trash-purge-${first.id}')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 8));
    await tester.pumpAndSettle();
    expect(await services.deletedNotes(), hasLength(1));
  });

  testWidgets('from a card, a swipe back leaves; its buttons act', (
    tester,
  ) async {
    for (final note in await services.worker.timeline(limit: 10)) {
      await services.setAside(note.id);
    }
    await services.refreshTimeline();
    await open(tester);
    await tester.tap(find.byIcon(Icons.inventory_2_outlined));
    await tester.pumpAndSettle();
    Future<void> enterArchive() async {
      await tester.tap(find.byKey(const ValueKey('library-set-aside')));
      await tester.pumpAndSettle();
      expect(find.byType(SetAsideScreen), findsOneWidget);
    }

    await enterArchive();
    final alpha = (await services.listSetAside()).firstWhere(
      (n) => n.content == 'alpha note',
    );
    final cardOf = find.byKey(ValueKey('archive-${alpha.id}'));
    // The back direction, starting on the card: the page goes.
    await tester.drag(cardOf, const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(find.byType(SetAsideScreen), findsNothing);
    expect(await services.setAsideCount(), 2, reason: 'nothing unarchived');

    // A card's actions are its two buttons (2.3.3): delete is one of them.
    await enterArchive();
    await tester.tap(find.byKey(ValueKey('archive-delete-${alpha.id}')));
    await tester.pumpAndSettle();
    expect(await services.setAsideCount(), 1);
    expect(find.text('Undo'), findsOneWidget);
  });

  testWidgets('an archived note opens read only', (tester) async {
    for (final note in await services.worker.timeline(limit: 10)) {
      await services.setAside(note.id);
    }
    await services.refreshTimeline();
    await open(tester);
    await tester.tap(find.byIcon(Icons.inventory_2_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('library-set-aside')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('alpha note'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('detail-archived')), findsOneWidget);
    expect(find.text('Tag'), findsNothing);
    // Everything the note offers, the row and the rest of its actions.
    await tester.tap(find.text('More actions'));
    await tester.pumpAndSettle();
    for (final gone in ['Edit', 'Remind', 'Pin', 'Threads']) {
      expect(find.text(gone), findsNothing, reason: gone);
    }
    expect(find.text('Unarchive'), findsOneWidget);
    expect(find.byKey(const ValueKey('note-ai-workspace')), findsNothing);
  });

  test('hidden AI results stay hidden for that note', () async {
    final prefs = harness.preferences;
    expect(prefs.aiResultsHidden('n1'), isFalse);
    await prefs.setAiResultsHidden('n1', true);
    expect(prefs.aiResultsHidden('n1'), isTrue);
    expect(prefs.aiResultsHidden('n2'), isFalse);
    await prefs.setAiResultsHidden('n1', false);
    expect(prefs.aiResultsHidden('n1'), isFalse);
  });
}
