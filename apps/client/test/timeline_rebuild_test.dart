import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ui/nex_ui.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nex_client/app.dart';
import 'package:nex_client/feature_flags.dart';
import 'package:nex_client/platform/backup_policy.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/widgets/commit_receipt.dart';
import 'package:nex_client/screens/note_detail_sheet.dart';
import 'package:nex_client/screens/timeline_screen.dart';
import 'package:nex_client/widgets/empty_timeline.dart';

import 'support/in_process_db.dart';

/// What the timeline promises after the rebuild: it never lies about being
/// empty, it confirms a capture landed, it finds things without leaving, and
/// its chrome lines up with its content on a wide window.
void main() {
  late Directory tmp;
  late NexServices services;
  late NexPreferences preferences;

  Future<NexServices> build(Directory dir, {Duration? delay}) async {
    final dbPath = p.join(dir.path, 'nex.sqlite');
    final mediaDir = p.join(dir.path, 'media');
    final backupDir = p.join(dir.path, 'backups');
    Directory(mediaDir).createSync(recursive: true);
    Directory(backupDir).createSync(recursive: true);
    return NexServices.forTest(
      worker: InProcessDb(dbPath: dbPath, deviceId: 'test', readDelay: delay),
      deviceId: 'test',
      preferences: await NexPreferences.load(),
      backupPolicy: BackupPolicy(await SharedPreferences.getInstance()),
      dbPath: dbPath,
      mediaDir: mediaDir,
      backupDir: backupDir,
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('nex_timeline_');
    services = await build(tmp);
    preferences = await NexPreferences.load();
  });

  tearDown(() async {
    await services.dispose();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  testWidgets('a cold launch with notes never flashes the onboarding screen', (
    tester,
  ) async {
    await services.captureText('something already here');
    // Deliberately slow, so the "not loaded yet" state lasts long enough to
    // observe. `_all` was `const []` at field initialisation, which satisfies
    // "empty" — so every cold launch showed a user with a full library the
    // "capture in seconds" onboarding copy before their notes painted.
    final slow = await build(tmp, delay: const Duration(milliseconds: 300));
    addTearDown(slow.dispose);

    await tester.pumpWidget(NexApp(services: slow, preferences: preferences));
    await tester.pump();

    expect(find.byType(EmptyTimeline), findsNothing);
    expect(find.byType(NexCardSkeleton), findsWidgets);

    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    expect(find.byType(NexCardSkeleton), findsNothing);
    expect(find.text('something already here'), findsOneWidget);
  });

  testWidgets('a genuinely empty library still gets the onboarding screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();
    expect(find.byType(EmptyTimeline), findsOneWidget);
  });

  testWidgets('a captured note gets a receipt that clears itself', (
    tester,
  ) async {
    await services.captureText('older');
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();

    final timeline = tester.state<TimelineScreenState>(
      find.byType(TimelineScreen),
    );

    final note = (await services.captureText('just written'))!;
    timeline.markLanded(note.id);
    await services.refreshTimeline();
    await tester.pump();

    final active = tester
        .widgetList<CommitReceipt>(find.byType(CommitReceipt))
        .where((r) => r.active);
    expect(active.length, 1, reason: 'exactly one note is the new one');

    // And it is a moment, not a mark: the id used to be set and never cleared,
    // so the last captured note stayed nudged for the life of the widget.
    await tester.pumpAndSettle();
    expect(timeline.landedId, isNull);
  });

  testWidgets('a toast stays above a dialog opened while it is still showing', (
    tester,
  ) async {
    // Reported symptom: the capsule toast sometimes rendered behind other
    // UI, e.g. behind the note-edit dialog. A SnackBar is scoped to the
    // nearest registered Scaffold, and the timeline's own Scaffold sits
    // *under* whatever the Navigator pushes on top of it next — so a dialog
    // opened while the toast was still up painted right over it.
    final note = (await services.captureText('gone in a moment'))!;
    await services.refreshTimeline();
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();

    final timeline = tester.state<TimelineScreenState>(
      find.byType(TimelineScreen),
    );
    await timeline.deleteWithUndo(note);
    await tester.pump();
    expect(find.text('Undo'), findsOneWidget);

    unawaited(
      showDialog<void>(
        context: tester.element(find.byType(TimelineScreen)),
        builder: (ctx) => AlertDialog(
          title: const Text('something modal'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('close'),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Still there, still the thing that actually receives the tap — not the
    // dialog's barrier sitting on top of it.
    final undo = find.text('Undo');
    expect(undo, findsOneWidget);
    await tester.tap(undo);
    await tester.pumpAndSettle();

    expect(find.text('gone in a moment'), findsOneWidget);
  });

  testWidgets(
    'swipe-to-add-tag offers existing tags even when none are in use',
    (tester) async {
      // Reported symptom: delete every note (their tags survive, unused),
      // capture something new, then swipe it to add a tag — the picker said
      // "no tags" even though one plainly existed, because it was reading
      // filterTags (built from tag *usage counts*) instead of the tag list
      // itself. The detail sheet's own "Tag" button never had this bug, since
      // it always asked for every tag directly.
      await services.createTag('Idea');
      await services.captureText('a fresh note');
      await services.refreshTimeline();
      await tester.pumpWidget(
        NexApp(services: services, preferences: preferences),
      );
      await tester.pumpAndSettle();

      final card = tester.getRect(
        find
            .ancestor(
              of: find.text('a fresh note'),
              matching: find.byType(SwipeableNoteCard),
            )
            .first,
      );
      // The leading edge is bound to Add Tag by default (ADR-022 revised).
      await tester.dragFrom(
        Offset(card.left + 10, card.center.dy),
        Offset(card.width * 0.5, 0),
      );
      await tester.pumpAndSettle();
      // Lowercase 't': app_en.arb's own string, not the literal package/ui
      // tests use when they supply their own label directly.
      expect(find.text('Add tag'), findsOneWidget);
      await tester.tap(find.text('Add tag'));
      await tester.pumpAndSettle();

      expect(find.text('Idea'), findsOneWidget);
    },
  );

  testWidgets(
    'tapping a different card while one is swiped open only closes it',
    (tester) async {
      // Reported symptom: swipe a card open, tap a different one, and both
      // things happened on the same touch — the open card closed *and* the
      // tapped card's own detail sheet opened. The first tap while anything is
      // open now only resets it; opening a note takes a second, separate tap.
      await services.captureText('first note');
      await services.captureText('second note');
      await services.refreshTimeline();
      await tester.pumpWidget(
        NexApp(services: services, preferences: preferences),
      );
      await tester.pumpAndSettle();

      final firstCard = tester.getRect(
        find
            .ancestor(
              of: find.text('first note'),
              matching: find.byType(SwipeableNoteCard),
            )
            .first,
      );
      // Inside the trailing 20% of the card's own width, per the edge-zone
      // restriction — the only place a resting card opens from. Half the
      // card's width clears the "open" threshold (~0.25 of it) with room to
      // spare below the "commit and run the action" one (~0.62), whatever the
      // card's actual width turns out to be on this surface.
      await tester.dragFrom(
        Offset(firstCard.right - 10, firstCard.center.dy),
        Offset(-firstCard.width * 0.5, 0),
      );
      await tester.pumpAndSettle();
      expect(find.text('Delete'), findsOneWidget);

      await tester.tap(find.text('second note'));
      await tester.pumpAndSettle();

      expect(
        find.text('Delete'),
        findsNothing,
        reason: 'the open card is reset by the first tap',
      );
      expect(
        find.byType(NoteDetailSheet),
        findsNothing,
        reason: 'that same tap must not also open the tapped card',
      );

      // Nothing is open now, so the same tap behaves normally.
      await tester.tap(find.text('second note'));
      await tester.pumpAndSettle();
      expect(find.byType(NoteDetailSheet), findsOneWidget);
    },
  );

  testWidgets('pinning a note leads the timeline, and only one stays pinned', (
    tester,
  ) async {
    await services.captureText('older note');
    await services.captureText('newer note');
    await services.refreshTimeline();
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();

    // Newest first, before anything is pinned.
    expect(
      tester.getCenter(find.text('newer note')).dy,
      lessThan(tester.getCenter(find.text('older note')).dy),
    );

    await tester.tap(find.text('older note'));
    await tester.pumpAndSettle();
    // The detail sheet's action row is icon-only; its members are found by
    // tooltip rather than by label text.
    await tester.tap(find.byTooltip('Pin'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Unpin'), findsOneWidget);
    Navigator.of(tester.element(find.byType(NoteDetailSheet))).pop();
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.push_pin), findsOneWidget);
    expect(
      tester.getCenter(find.text('older note')).dy,
      lessThan(tester.getCenter(find.text('newer note')).dy),
      reason: 'the pinned note leads even though it is the older one',
    );

    // Only one note is ever pinned at a time — rather than silently
    // stealing the pin, the action on every other note is simply off while
    // one is already pinned.
    await tester.tap(find.text('newer note'));
    await tester.pumpAndSettle();
    final pinAction = tester.widget<InkWell>(
      find.descendant(
        of: find.byTooltip('Pin'),
        matching: find.byType(InkWell),
      ),
    );
    expect(pinAction.onTap, isNull);
    await tester.tap(find.byTooltip('Pin'));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(NoteDetailSheet))).pop();
    await tester.pumpAndSettle();

    expect(
      tester.getCenter(find.text('older note')).dy,
      lessThan(tester.getCenter(find.text('newer note')).dy),
      reason: 'a disabled Pin action must not have moved the pin',
    );

    // Unpinning first frees the action back up, and the new note takes over.
    await tester.tap(find.text('older note'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Unpin'));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(NoteDetailSheet))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('newer note'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Pin'));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(NoteDetailSheet))).pop();
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.push_pin), findsOneWidget);
    expect(
      tester.getCenter(find.text('newer note')).dy,
      lessThan(tester.getCenter(find.text('older note')).dy),
    );
  });

  testWidgets(
    'holding a card without moving opens quick actions, not a reorder',
    (tester) async {
      await services.captureText('a note to act on');
      await services.refreshTimeline();
      await tester.pumpWidget(
        NexApp(services: services, preferences: preferences),
      );
      await tester.pumpAndSettle();

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('a note to act on')),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.text('Pin'), findsOneWidget);
      await tester.tap(find.text('Pin'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.push_pin), findsOneWidget);
    },
    // The menu itself is paused behind kReorderQuickActionsEnabled — see
    // feature_flags.dart. The code this exercises is untouched, so flipping
    // the flag back on is all re-enabling it needs.
    skip: !kReorderQuickActionsEnabled,
  );

  testWidgets('holding and dragging a card past another reorders the list', (
    tester,
  ) async {
    await services.captureText('note A');
    await services.captureText('note B');
    await services.captureText('note C');
    await services.refreshTimeline();
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();

    // Newest first: C, then B, then A.
    expect(
      tester.getCenter(find.text('note C')).dy,
      lessThan(tester.getCenter(find.text('note B')).dy),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('note C')),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.moveBy(const Offset(0, 300));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    // Dragged well past B, so it now leads.
    expect(
      tester.getCenter(find.text('note B')).dy,
      lessThan(tester.getCenter(find.text('note C')).dy),
    );
    // Reported symptom: a real drag would still open the quick-actions
    // sheet on release, since onReorderEnd fires the instant the finger
    // lifts — well before onReorder, which only runs once the drop's
    // settle animation finishes ~250ms later.
    expect(find.text('Pin'), findsNothing);

    // The order survives a fresh read from the repository, not just the
    // in-memory list the drag rewrote directly.
    await services.refreshTimeline();
    await tester.pumpAndSettle();
    expect(
      tester.getCenter(find.text('note B')).dy,
      lessThan(tester.getCenter(find.text('note C')).dy),
    );
  });

  testWidgets('search happens on the timeline, without pushing a route', (
    tester,
  ) async {
    for (var i = 0; i < 10; i++) {
      await services.captureText('filler $i');
    }
    await services.captureText('a note about rockets');
    await services.captureText('a note about bread');
    await services.refreshTimeline();
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();

    // The field sits at the top of the list from the start. It used to begin
    // scrolled out of sight, revealed by pulling down — which never actually
    // worked on a device, and that gesture is a refresh now.
    final field = find.byType(TextField);
    expect(field, findsOneWidget);

    // Tapping the field itself is the only way in now — the AppBar's own
    // search icon was removed once the field became permanently visible,
    // since it pointed at something already on screen.
    await tester.tap(field);
    await tester.pumpAndSettle();

    // Same route. Search used to be a full-screen push behind this icon, which
    // put half the tagline a transition away from the list it searches.
    expect(find.byType(TimelineScreen), findsOneWidget);
    expect(field, findsOneWidget);
    expect(
      tester.getRect(field).top,
      greaterThanOrEqualTo(
        tester.getRect(find.byType(CustomScrollView)).top - 1,
      ),
    );

    await tester.enterText(field, 'rockets');
    await tester.pumpAndSettle();
    expect(find.text('a note about rockets'), findsOneWidget);
    expect(find.text('a note about bread'), findsNothing);
  });

  testWidgets('a library too short to scroll simply shows the field', (
    tester,
  ) async {
    await services.captureText('the only note');
    await services.refreshTimeline();
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();

    // With nothing to scroll there is nowhere to hide it, and that is the
    // honest outcome rather than a bug: with one note, search is right there.
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('pulling the timeline down refreshes it', (tester) async {
    for (var i = 0; i < 12; i++) {
      await services.captureText('note $i');
    }
    await services.refreshTimeline();
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();

    final list = find.byType(CustomScrollView);
    // The field is simply there, at the top, whatever the scroll is doing.
    expect(find.byType(TextField), findsOneWidget);

    // A note created behind the screen's back — the situation the gesture is
    // for. Nothing has told the timeline about it.
    await services.captureText('arrived while you were away');
    await tester.pumpAndSettle();

    await tester.fling(list, const Offset(0, 300), 1000);
    await tester.pumpAndSettle();

    expect(find.byType(RefreshIndicator), findsOneWidget);
    expect(find.text('arrived while you were away'), findsOneWidget);
  });

  testWidgets(
    'a tag created elsewhere reaches the filter row without a restart',
    (tester) async {
      // The reported symptom: delete the tags, make a new one, and the filter row
      // kept showing the old set until the app was closed and reopened. The row
      // is fed by its own query, which only ever ran once — in initState.
      final note = (await services.captureText('a note'))!;
      await services.refreshTimeline();
      await tester.pumpWidget(
        NexApp(services: services, preferences: preferences),
      );
      await tester.pumpAndSettle();

      expect(find.text('Rockets'), findsNothing);

      // Created and attached the way the tag picker actually does it — a tag
      // with nothing tagged with it does not belong in the filter row at all
      // (see the "unused tags" test below), so this has to put it on a note to
      // stay a test of the staleness bug rather than of that.
      await services.addTag(noteId: note.id, name: 'Rockets');
      await services.refreshTimeline();
      await tester.pumpAndSettle();

      expect(
        find.text('Rockets'),
        findsWidgets,
        reason: 'the filter row has to notice, without a cold launch',
      );
    },
  );

  testWidgets('a tag nothing is tagged with does not clutter the filter row', (
    tester,
  ) async {
    // Reported symptom: a tag with no notes on it any more still took up a
    // pill at the top, and selecting it just filtered to nothing.
    final note = (await services.captureText('a note'))!;
    final tag = await services.addTag(noteId: note.id, name: 'Errands');
    await services.refreshTimeline();
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();
    expect(find.text('Errands'), findsWidgets);

    await services.removeTag(noteId: note.id, tagId: tag.id);
    await services.refreshTimeline();
    await tester.pumpAndSettle();

    expect(
      find.text('Errands'),
      findsNothing,
      reason: 'nothing uses it any more, so it has nothing to filter to',
    );
  });

  testWidgets('the search header follows a theme change', (tester) async {
    // Reported from a device: switch to light and the strip around the search
    // field stayed black; on another phone, switching to dark left it white.
    // `SliverPersistentHeaderDelegate.shouldRebuild` decides whether the
    // cached subtree is thrown away, and it was comparing the delegate's own
    // fields — none of which a theme change touches. So the header kept the
    // colours of whichever theme the app launched in.
    await services.captureText('a note');
    await services.refreshTimeline();
    await preferences.setThemeMode(ThemeMode.light);
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();

    // The header's own background: the ColoredBox wrapping the search field.
    Color headerColor() => tester
        .widgetList<ColoredBox>(
          find.ancestor(
            of: find.byType(TextField),
            matching: find.byType(ColoredBox),
          ),
        )
        .first
        .color;

    final light = headerColor();
    expect(light, nexLightTheme().colorScheme.surface);

    await preferences.setThemeMode(ThemeMode.dark);
    await tester.pumpAndSettle();

    expect(
      headerColor(),
      nexDarkTheme().colorScheme.surface,
      reason: 'the header repainted in the theme the rest of the app is in',
    );
  });

  testWidgets('the empty state clears the capture button on a desktop window', (
    tester,
  ) async {
    // Seen on Windows. The empty state sits in a SliverFillRemaining under the
    // search field and the filter row, and it was taller than what those left
    // it — so it overflowed and its last line, "There is no Save button.",
    // came to rest directly behind the button it is talking about.
    //
    // Measured against the real widget tree on purpose: a bare Scaffold gives
    // the empty state the whole viewport, which is exactly the condition the
    // bug does not occur in.
    tester.view.physicalSize = const Size(1100, 726);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();

    final line = tester.getRect(find.text('There is no Save button.'));
    final fab = tester.getRect(find.byType(FloatingActionButton));

    expect(
      line.bottom,
      lessThanOrEqualTo(fab.top),
      reason: 'the copy must end above the button, not behind it',
    );

    // The AI paragraph sits below that line now. It is the one genuinely at
    // risk of running past the viewport on a short window, but that is a
    // reason for it to scroll — which SingleChildScrollView already does,
    // inside the space this Padding protects — not a reason to fail here.
    expect(
      find.text(
        'It can also read what you capture — voice becomes text, photos '
        'give up their words, tags get suggested. A provider in Settings '
        'adds summaries and search.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('the filter row and the cards share one edge on a wide window', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await services.captureText('a note');
    await services.refreshTimeline();
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();

    // The filter row used to be a sibling *above* the 760px column, so on a
    // wide window the pills started at the window edge and the cards did not.
    final row = tester.getRect(find.byType(TagFilterRow));
    final card = tester.getRect(find.byType(NoteCard));
    expect(row.left, greaterThan(0));
    expect(row.width, lessThanOrEqualTo(760));
    expect(row.center.dx, closeTo(card.center.dx, 1));
  });
}
