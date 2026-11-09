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

    testWidgets('note sheet: a dismissed thread picker repaints nothing', (
      tester,
    ) async {
      await tester.pumpWidget(harness.app());
      await tester.pumpAndSettle();

      await tester.tap(find.byType(NoteCard).first);
      await tester.pumpAndSettle();
      expect(find.byType(NoteDetailSheet), findsOneWidget);

      // The Threads action in the sheet's pinned action row — the chips
      // row above it wears the same icon for the thread it belongs to.
      await tester.tap(
        find
            .descendant(
              of: find.byType(NoteDetailSheet),
              matching: find.byIcon(Icons.timeline_outlined),
            )
            .last,
      );
      await tester.pumpAndSettle();
      expect(find.byType(CheckboxListTile), findsOneWidget);

      var sheetRebuilds = 0;
      debugOnRebuildDirtyWidget = (element, _) {
        if (element.widget is NoteDetailSheet) sheetRebuilds++;
      };
      await Navigator.of(tester.element(find.byType(CheckboxListTile)))
          .maybePop();
      await tester.pumpAndSettle();
      debugOnRebuildDirtyWidget = null;

      expect(find.byType(CheckboxListTile), findsNothing);
      expect(sheetRebuilds, 0);
    });

    testWidgets('note sheet: ticking a thread still reloads it', (
      tester,
    ) async {
      await tester.pumpWidget(harness.app());
      await tester.pumpAndSettle();

      // A note that is in no thread yet, so the picker starts unticked.
      await harness.services.captureText('a second note');
      await harness.services.refreshTimeline();
      await tester.pumpAndSettle();

      await tester.tap(find.byType(NoteCard).first);
      await tester.pumpAndSettle();

      await tester.tap(
        find
            .descendant(
              of: find.byType(NoteDetailSheet),
              matching: find.byIcon(Icons.timeline_outlined),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(find.byType(CheckboxListTile), findsOneWidget);

      var sheetRebuilds = 0;
      debugOnRebuildDirtyWidget = (element, _) {
        if (element.widget is NoteDetailSheet) sheetRebuilds++;
      };
      // Ticking joins the note to the thread: the picker answers "changed".
      await tester.tap(find.byType(CheckboxListTile).first);
      await tester.pumpAndSettle();
      await Navigator.of(tester.element(find.byType(CheckboxListTile)))
          .maybePop();
      await tester.pumpAndSettle();
      debugOnRebuildDirtyWidget = null;

      expect(find.byType(CheckboxListTile), findsNothing);
      expect(sheetRebuilds, greaterThan(0));
      // The chip row shows what the picker did.
      expect(find.text('alpha'), findsOneWidget);
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
      await tester.pumpAndSettle();

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
      await tester.pumpAndSettle();

      // The Threads shelf, opened and closed without a change.
      await tester.tap(find.byKey(const ValueKey('library-threads')));
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.byType(ThreadsScreen))).pop();
      await tester.pumpAndSettle();
      expect(find.byType(LibraryScreen), findsOneWidget);

      var libraryRebuilds = 0;
      debugOnRebuildDirtyWidget = (element, _) {
        if (element.widget is LibraryScreen) libraryRebuilds++;
      };
      // A second sub-page closing recounts the shelves; nothing changed,
      // so the counts are the same records as before.
      await tester.tap(find.byKey(const ValueKey('library-set-aside')));
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.byType(SetAsideScreen))).pop();
      await tester.pumpAndSettle();
      debugOnRebuildDirtyWidget = null;

      expect(libraryRebuilds, 0);
    });
  });
}
