import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/screens/library_screen.dart';
import 'package:nex_client/screens/note_detail_sheet.dart';
import 'package:nex_client/screens/set_aside_screen.dart';
import 'package:nex_client/screens/threads_screen.dart';
import 'package:nex_client/screens/timeline_screen.dart';
import 'package:nex_client/widgets/collection_page.dart';
import 'package:nex_ui/nex_ui.dart';

import 'support/nex_harness.dart';

/// The timeline is not the only screen that re-reads the database when a
/// page above it closes. Threads, the archive, the note sheet and the
/// library shelves all reload on the way back — and the same rule the
/// timeline got in 2.6.11 holds for each of them: an unchanged answer must
/// not repaint the screen mid pop-transition, and a real change must still
/// surface.
void main() {
  group('collection no-op reload', () {
    late NexTestHarness harness;
    late String noteId;

    setUp(() async {
      harness = await NexTestHarness.create(name: 'nex_noop_pages_');
      noteId = (await harness.services.captureText('a plain note'))!.id;
      final thread = await harness.services.createThread('alpha');
      await harness.services.addToThread(thread.id, noteId);
      await harness.services.refreshTimeline();
    });

    tearDown(() async {
      debugOnRebuildDirtyWidget = null;
      await harness.dispose();
    });

    Future<void> pushThreads(WidgetTester tester) async {
      final nav = Navigator.of(tester.element(find.byType(TimelineScreen)));
      unawaited(
        nav.push(
          MaterialPageRoute<void>(
            builder: (_) => ThreadsScreen(
              services: harness.services,
              preferences: harness.preferences,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Finder threadCards() => find.descendant(
      of: find.byType(ThreadScreen),
      matching: find.byType(NoteCard),
    );

    // Pump bounded frames: the Library has continuously animated placeholders.
    Future<void> finishRoute(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump();
    }

    // Background database reads are independent of the Flutter frame clock.
    Future<void> waitFor(WidgetTester tester, Finder finder) async {
      for (var i = 0; i < 20; i++) {
        await finishRoute(tester);
        if (finder.evaluate().isNotEmpty) return;
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      expect(finder, findsOneWidget);
    }

    testWidgets('thread notes: read-only note close repaints no cards', (
      tester,
    ) async {
      await tester.pumpWidget(harness.app());
      await tester.pumpAndSettle();
      await pushThreads(tester);

      await tester.tap(find.text('alpha'));
      await tester.pumpAndSettle();
      expect(threadCards(), findsOneWidget);

      await tester.tap(threadCards().first);
      await tester.pumpAndSettle();
      expect(find.byType(NoteDetailSheet), findsOneWidget);

      var cardRebuilds = 0;
      debugOnRebuildDirtyWidget = (element, _) {
        if (element.widget is NoteCard) cardRebuilds++;
      };
      Navigator.of(tester.element(find.byType(NoteDetailSheet))).pop();
      await tester.pumpAndSettle();
      debugOnRebuildDirtyWidget = null;

      expect(find.byType(NoteDetailSheet), findsNothing);
      // The sheet closed without touching the note; the thread's re-read
      // answered with new objects and the same content.
      expect(cardRebuilds, lessThanOrEqualTo(1));
    });

    testWidgets('thread notes: a real change still repaints the card', (
      tester,
    ) async {
      await tester.pumpWidget(harness.app());
      await tester.pumpAndSettle();
      await pushThreads(tester);

      await tester.tap(find.text('alpha'));
      await tester.pumpAndSettle();

      await tester.tap(threadCards().first);
      await tester.pumpAndSettle();

      // The urgency flag is local-only metadata: nothing else about the
      // row moves, so this is exactly the change a field-blind comparison
      // would have swallowed.
      await harness.services.setUrgent(noteId, true);
      await tester.pumpAndSettle();

      var cardRebuilds = 0;
      debugOnRebuildDirtyWidget = (element, _) {
        if (element.widget is NoteCard) cardRebuilds++;
      };
      Navigator.of(tester.element(find.byType(NoteDetailSheet))).pop();
      await tester.pumpAndSettle();
      debugOnRebuildDirtyWidget = null;

      expect(cardRebuilds, greaterThan(0));
    });

    testWidgets('threads list: unchanged thread return repaints no tiles', (
      tester,
    ) async {
      await tester.pumpWidget(harness.app());
      await tester.pumpAndSettle();
      await pushThreads(tester);

      // Viewed, not edited: the back gesture is the whole visit.
      await tester.tap(find.text('alpha'));
      await tester.pumpAndSettle();

      var tileRebuilds = 0;
      debugOnRebuildDirtyWidget = (element, _) {
        if (element.widget is NexCollectionTile) tileRebuilds++;
      };
      Navigator.of(tester.element(find.byType(ThreadScreen))).pop();
      await tester.pumpAndSettle();
      debugOnRebuildDirtyWidget = null;

      // Back on the threads list, which re-read it on the way in — the
      // visit changed nothing, so its answer is the same rows.
      expect(find.byType(ThreadsScreen), findsOneWidget);
      expect(tileRebuilds, lessThanOrEqualTo(1));
    });

    testWidgets('note sheet: unchanged thread visit repaints nothing', (
      tester,
    ) async {
      await tester.pumpWidget(harness.app());
      await tester.pumpAndSettle();
      await tester.tap(find.byType(NoteCard).first);
      await waitFor(tester, find.widgetWithText(ActionChip, 'alpha'));

      // Follow the real thread-chip route and return to the sheet.
      final chip = tester.widget<ActionChip>(
        find.widgetWithText(ActionChip, 'alpha'),
      );
      expect(chip.onPressed, isNotNull);
      chip.onPressed!();
      await waitFor(tester, find.byType(ThreadScreen));

      var sheetRebuilds = 0;
      debugOnRebuildDirtyWidget = (element, _) {
        if (element.widget is NoteDetailSheet) sheetRebuilds++;
      };
      Navigator.of(tester.element(find.byType(ThreadScreen))).pop();
      await finishRoute(tester);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      debugOnRebuildDirtyWidget = null;

      expect(find.byType(NoteDetailSheet), findsOneWidget);
      expect(sheetRebuilds, 0);
    });

    testWidgets('note sheet: changed note after thread visit repaints', (
      tester,
    ) async {
      await tester.pumpWidget(harness.app());
      await tester.pumpAndSettle();
      await tester.tap(find.byType(NoteCard).first);
      await waitFor(tester, find.widgetWithText(ActionChip, 'alpha'));

      final chip = tester.widget<ActionChip>(
        find.widgetWithText(ActionChip, 'alpha'),
      );
      chip.onPressed!();
      await waitFor(tester, find.byType(ThreadScreen));
      await harness.services.setUrgent(noteId, true);
      var sheetRebuilds = 0;
      debugOnRebuildDirtyWidget = (element, _) {
        if (element.widget is NoteDetailSheet) sheetRebuilds++;
      };
      Navigator.of(tester.element(find.byType(ThreadScreen))).pop();
      await finishRoute(tester);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      debugOnRebuildDirtyWidget = null;

      expect(find.byType(NoteDetailSheet), findsOneWidget);
      expect(sheetRebuilds, greaterThan(0));
    });

    testWidgets('set-aside: read-only note close repaints no rows', (
      tester,
    ) async {
      await harness.services.setAside(noteId);
      await harness.services.refreshTimeline();
      await tester.pumpWidget(harness.app());
      await tester.pumpAndSettle();

      final nav = Navigator.of(tester.element(find.byType(TimelineScreen)));
      unawaited(
        nav.push(
          MaterialPageRoute<void>(
            builder: (_) => SetAsideScreen(
              services: harness.services,
              preferences: harness.preferences,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(NexCollectionTile), findsWidgets);

      await tester.tap(find.byType(NexCollectionTile).first);
      await tester.pumpAndSettle();
      expect(find.byType(NoteDetailSheet), findsOneWidget);

      var tileRebuilds = 0;
      debugOnRebuildDirtyWidget = (element, _) {
        if (element.widget is NexCollectionTile) tileRebuilds++;
      };
      Navigator.of(tester.element(find.byType(NoteDetailSheet))).pop();
      await tester.pumpAndSettle();
      debugOnRebuildDirtyWidget = null;

      expect(find.byType(NoteDetailSheet), findsNothing);
      expect(tileRebuilds, 0);
    });

    testWidgets('library: unchanged sub-page return repaints no shelves', (
      tester,
    ) async {
      await tester.pumpWidget(harness.app());
      await finishRoute(tester);

      final nav = Navigator.of(tester.element(find.byType(TimelineScreen)));
      unawaited(
        nav.push(
          MaterialPageRoute<void>(
            builder: (_) => LibraryScreen(
              services: harness.services,
              preferences: harness.preferences,
            ),
          ),
        ),
      );
      await finishRoute(tester);

      // The Threads shelf, opened and closed without a change.
      await tester.tap(find.byKey(const ValueKey('library-threads')));
      await finishRoute(tester);
      Navigator.of(tester.element(find.byType(ThreadsScreen))).pop();
      await finishRoute(tester);
      expect(find.byType(LibraryScreen), findsOneWidget);

      var libraryRebuilds = 0;
      debugOnRebuildDirtyWidget = (element, _) {
        if (element.widget is LibraryScreen) libraryRebuilds++;
      };
      // A second sub-page closing recounts the shelves; nothing changed,
      // so the counts are the same records as before.
      await tester.tap(find.byKey(const ValueKey('library-set-aside')));
      // Empty-state animations may keep scheduling frames indefinitely.
      // Pump through the route transition without waiting for every ticker.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump();
      expect(find.byType(SetAsideScreen), findsOneWidget);

      Navigator.of(tester.element(find.byType(SetAsideScreen))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump();
      debugOnRebuildDirtyWidget = null;

      expect(libraryRebuilds, 0);
    });
  });
}
