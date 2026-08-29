import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nex_client/app.dart';
import 'package:nex_client/l10n/app_localizations.dart';
import 'package:nex_client/platform/backup_policy.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/widgets/commit_receipt.dart';
import 'package:nex_client/screens/note_detail_sheet.dart';
import 'package:nex_client/screens/assistant_screen.dart';
import 'package:nex_client/screens/timeline_screen.dart';
import 'package:nex_client/screens/profile_screen.dart';
import 'package:nex_client/widgets/assistant_settings.dart';
import 'package:nex_client/widgets/empty_timeline.dart';
import 'package:nex_client/widgets/note_spotlight.dart';
import 'package:nex_client/widgets/first_run_tour.dart';

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
    // Every one of these tests starts from an empty preference store, which
    // is exactly what a first-ever launch looks like — so without this they
    // would all open on the onboarding screen instead of the timeline.
    // Onboarding has its own test file.
    await preferences.completeOnboarding();
    await preferences.completeTour();
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

  group('the first-run tour', () {
    testWidgets('runs once and never again', (tester) async {
      // Undone deliberately: `setUp` marks it seen so every other test in
      // this file can tap things. This one is about the launch where it has
      // not been seen.
      SharedPreferences.setMockInitialValues({'onboarding.complete': true});
      final fresh = await NexPreferences.load();
      expect(fresh.tourComplete, isFalse);

      await tester.pumpWidget(NexApp(services: services, preferences: fresh));
      await tester.pumpAndSettle();
      expect(find.byType(FirstRunTour), findsOneWidget);

      // Skipping counts. Someone who leaves on step one has decided.
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(find.byType(FirstRunTour), findsNothing);
      expect(fresh.tourComplete, isTrue);

      // A relaunch on the same store does not bring it back.
      final again = await NexPreferences.load();
      await tester.pumpWidget(NexApp(services: services, preferences: again));
      await tester.pumpAndSettle();
      expect(find.byType(FirstRunTour), findsNothing);
    });

    testWidgets('an install that already has preferences never sees it', (
      tester,
    ) async {
      // The upgrade case: a store with keys in it but no onboarding flag is
      // someone who has been using the app, not a first launch.
      SharedPreferences.setMockInitialValues({'appearance.comfort': false});
      final upgraded = await NexPreferences.load();
      expect(upgraded.onboardingComplete, isTrue);
      expect(upgraded.tourComplete, isTrue);

      await tester.pumpWidget(
        NexApp(services: services, preferences: upgraded),
      );
      await tester.pumpAndSettle();
      expect(find.byType(FirstRunTour), findsNothing);
    });
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

  testWidgets('the profile screen saves name and bio', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ProfileScreen(services: services, preferences: preferences),
      ),
    );
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(2));
    await tester.enterText(fields.first, 'Sany');
    await tester.enterText(fields.last, 'I write music and collect ideas.');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(preferences.displayName, 'Sany');
    expect(preferences.profileBio, 'I write music and collect ideas.');
  });

  test(
    'biometric-only lock also enables app lock, and disabling clears both',
    () async {
      await preferences.setAppLockBiometricOnly(true);
      expect(preferences.appLockEnabled, isTrue);
      expect(preferences.appLockBiometricOnly, isTrue);

      await preferences.setAppLockEnabled(false);
      expect(preferences.appLockEnabled, isFalse);
      expect(preferences.appLockBiometricOnly, isFalse);
    },
  );

  testWidgets('a freshly captured note reads "now" on its card', (
    tester,
  ) async {
    await services.captureText('brand new');
    await services.refreshTimeline();
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();

    expect(find.text('brand new'), findsOneWidget);
    expect(
      find.text('now'),
      findsOneWidget,
      reason: 'the relative-time line under the preview',
    );
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

  testWidgets('pinning keeps up to five notes at the top', (tester) async {
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

    // Pinning another note keeps the first one pinned as well.
    await tester.tap(find.text('newer note'));
    await tester.pumpAndSettle();
    final pinAction = tester.widget<InkWell>(
      find.descendant(
        of: find.byTooltip('Pin'),
        matching: find.byType(InkWell),
      ),
    );
    expect(pinAction.onTap, isNotNull);
    await tester.tap(find.byTooltip('Pin'));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(NoteDetailSheet))).pop();
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.push_pin), findsNWidgets(2));
    expect(
      tester.getCenter(find.text('newer note')).dy,
      lessThan(tester.getCenter(find.text('older note')).dy),
    );
  });

  testWidgets('a pinned note cannot be dragged, and nothing lands above it', (
    tester,
  ) async {
    await services.captureText('note A');
    await services.captureText('note B');
    await services.refreshTimeline();
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();

    // Pin the older one, which moves it to the top.
    await tester.tap(find.text('note A'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Pin'));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(NoteDetailSheet))).pop();
    await tester.pumpAndSettle();
    expect(
      tester.getCenter(find.text('note A')).dy,
      lessThan(tester.getCenter(find.text('note B')).dy),
    );

    // Holding the pinned card and dragging it down does nothing: it is held
    // in place, so it carries no reorder gesture at all.
    final pinned = await tester.startGesture(
      tester.getCenter(find.text('note A')),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await pinned.moveBy(const Offset(0, 200));
    await tester.pump();
    await pinned.up();
    await tester.pumpAndSettle();
    expect(
      tester.getCenter(find.text('note A')).dy,
      lessThan(tester.getCenter(find.text('note B')).dy),
      reason: 'a pinned card must not be draggable',
    );

    // Dragging the other card up over it must not displace it either — the
    // pinned-first sort would only snap it back on the next read.
    final other = await tester.startGesture(
      tester.getCenter(find.text('note B')),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await other.moveBy(const Offset(0, -200));
    await tester.pump();
    await other.up();
    await tester.pumpAndSettle();
    expect(
      tester.getCenter(find.text('note A')).dy,
      lessThan(tester.getCenter(find.text('note B')).dy),
      reason: 'nothing may land above the pinned note',
    );

    await services.refreshTimeline();
    await tester.pumpAndSettle();
    expect(
      tester.getCenter(find.text('note A')).dy,
      lessThan(tester.getCenter(find.text('note B')).dy),
      reason: 'and the order survives a fresh read',
    );
  });

  testWidgets('the timeline is grouped by date, and the groups fold', (
    tester,
  ) async {
    await services.captureText('note A');
    await services.captureText('note B');
    await services.refreshTimeline();
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();

    // Both captured now, so both sit under one heading rather than in a flat
    // list with nothing saying when any of it happened.
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('note A'), findsOneWidget);
    expect(find.text('note B'), findsOneWidget);

    // The whole heading row is the fold control, not a 16-pixel caret.
    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();

    expect(find.text('note A'), findsNothing);
    expect(find.text('note B'), findsNothing);
    // Folded, the heading says what it is hiding. Open, the list says it.
    expect(find.textContaining('2 notes'), findsOneWidget);

    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();
    expect(find.text('note A'), findsOneWidget);
  });

  testWidgets('date group edges align with cards in English and Persian', (
    tester,
  ) async {
    await services.captureText('aligned note');
    await services.refreshTimeline();

    for (final (locale, label, direction) in [
      ('en', 'Today', TextDirection.ltr),
      ('fa', 'امروز', TextDirection.rtl),
    ]) {
      await preferences.setLocale(locale);
      await tester.pumpWidget(
        NexApp(services: services, preferences: preferences),
      );
      await tester.pumpAndSettle();

      final cardWidget = tester.getRect(find.byType(NoteCard));
      final card = Rect.fromLTRB(
        cardWidget.left + nexCardInsets.left,
        cardWidget.top + nexCardInsets.top,
        cardWidget.right - nexCardInsets.right,
        cardWidget.bottom - nexCardInsets.bottom,
      );
      final heading = tester.getRect(find.text(label));
      final menu = tester.getRect(
        find.byWidgetPredicate((widget) => widget is PopupMenuButton).first,
      );

      if (direction == TextDirection.ltr) {
        expect(heading.left, closeTo(card.left, 0.5));
        expect(menu.right, closeTo(card.right, 0.5));
      } else {
        expect(heading.right, closeTo(card.right, 0.5));
        expect(menu.left, closeTo(card.left, 0.5));
      }
    }
  });

  testWidgets('folding a group animates instead of cutting to it', (
    tester,
  ) async {
    await services.captureText('note A');
    await services.refreshTimeline();
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();

    final row = find.byWidgetPredicate(
      (widget) => widget is SizeTransition,
      description: 'a folding row',
    );
    final openHeight = tester.getSize(row.first).height;
    expect(openHeight, greaterThan(0));

    await tester.tap(find.text('Today'));
    // Mid-flight, not settled. The fold used to be a jump cut: the rows were
    // simply absent on the very next frame. They have to still be there, and
    // shorter than they were.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 110));
    expect(find.text('note A'), findsOneWidget);
    final midHeight = tester.getSize(row.first).height;
    expect(midHeight, lessThan(openHeight));
    expect(midHeight, greaterThan(0));

    // And only then does it actually go.
    await tester.pumpAndSettle();
    expect(find.text('note A'), findsNothing);
  });

  testWidgets('folding one group leaves the groups below it alone', (
    tester,
  ) async {
    // `SliverList` matches its children by index, so folding a run shortens
    // the list and every row below it arrives at a new index with fresh
    // state. A row that animated itself in on creation then played the
    // entrance animation, and every group below the one being folded
    // flickered open — which is the report this guards.
    await services.captureText('today note');
    final older = await services.captureText('yesterday note');
    // Capture stamps `now`, so the second group has to be made by hand.
    (services.worker as InProcessDb).backdate(
      older!.id,
      DateTime.now().subtract(const Duration(days: 1)),
    );
    await services.refreshTimeline();
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();

    final below = find.ancestor(
      of: find.text('yesterday note'),
      matching: find.byWidgetPredicate((widget) => widget is SizeTransition),
    );
    expect(below, findsWidgets);
    final restingHeight = tester.getSize(below.first).height;

    await tester.tap(find.text('Today'));
    // One frame into the fold. The row below must be exactly where it was.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    expect(tester.getSize(below.first).height, restingHeight);

    await tester.pumpAndSettle();
    expect(tester.getSize(below.first).height, restingHeight);
  });

  testWidgets('a folded group stays folded across a rebuild', (tester) async {
    await services.captureText('note A');
    await services.refreshTimeline();
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();
    expect(find.text('note A'), findsNothing);

    // Folding is a statement about how someone wants the list to look.
    // Having it spring open on the next launch means saying it every day.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();

    expect(find.text('note A'), findsNothing);
    expect(find.text('Today'), findsOneWidget);
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

  testWidgets('coming back to the app re-reads the library', (tester) async {
    // This replaces pull-to-refresh, which was removed because it had nothing
    // left to do: every capture path re-fires the timeline stream itself, so
    // the list can only be stale if something wrote a note while this screen
    // was not running. Resuming is exactly when that is true — and exactly
    // when nobody would think to pull.
    await services.captureText('before');
    await services.refreshTimeline();
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();
    expect(find.text('before'), findsOneWidget);

    // Written without telling the screen — what the home-screen widget or a
    // share target does while the app is in the background.
    await services.captureText('arrived while you were away');
    await tester.pumpAndSettle();
    expect(find.text('arrived while you were away'), findsNothing);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.text('arrived while you were away'), findsOneWidget);
  });

  testWidgets('the timeline offers no pull-to-refresh', (tester) async {
    // A gesture that re-reads data which is already current does nothing, and
    // this screen's own history is the argument: the pull used to be "reveal
    // the search field" and was replaced precisely because it never revealed
    // anything.
    await services.captureText('a note');
    await services.refreshTimeline();
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();

    expect(find.byType(RefreshIndicator), findsNothing);
  });

  testWidgets('scrolling toward the bottom loads notes past the first 200', (
    tester,
  ) async {
    // Past 200 notes, refreshTimeline's window used to be a fixed 200 with
    // no way to ask for more — the rest were not off-screen, they had never
    // been fetched at all.
    for (var i = 0; i < 210; i++) {
      await services.captureText('note $i');
    }
    await services.refreshTimeline();
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();

    final timeline = tester.state<TimelineScreenState>(
      find.byType(TimelineScreen),
    );
    expect(timeline.notes, hasLength(200));

    final list = find.byType(CustomScrollView);
    for (var i = 0; i < 20 && timeline.notes.length < 210; i++) {
      await tester.fling(list, const Offset(0, -3000), 3000);
      await tester.pumpAndSettle();
    }

    expect(timeline.notes, hasLength(210));
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

  testWidgets(
    'untagging a note down to zero notices without a manual refresh',
    (tester) async {
      // Reported symptom: untag a note's last tag from the detail sheet's
      // own remove button (not deleting the tag, not through the service
      // directly) and the pill stayed in the filter row. removeTag's caller
      // only reloaded the detail sheet's own note, never the timeline that
      // feeds the filter row — addTag's equivalent path already refreshed it.
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final note = (await services.captureText('a note'))!;
      await services.addTag(noteId: note.id, name: 'Errands');
      await services.refreshTimeline();
      await tester.pumpWidget(
        NexApp(services: services, preferences: preferences),
      );
      await tester.pumpAndSettle();
      expect(find.text('Errands'), findsWidgets);

      await tester.tap(find.text('a note'));
      await tester.pumpAndSettle();
      expect(find.byType(NoteDetailSheet), findsOneWidget);

      final chip = find.descendant(
        of: find.byType(NoteDetailSheet),
        matching: find.widgetWithText(InputChip, 'Errands'),
      );
      expect(chip, findsOneWidget);
      // The chip's own delete affordance — there's no avatar on an
      // uncoloured tag, so this is the only icon inside it.
      await tester.tap(find.descendant(of: chip, matching: find.byType(Icon)));
      await tester.pumpAndSettle();
      expect(
        find.byType(NoteDetailSheet),
        findsOneWidget,
        reason: 'removing a tag must not itself close the sheet',
      );

      Navigator.of(tester.element(find.byType(NoteDetailSheet))).pop();
      await tester.pumpAndSettle();

      expect(
        find.text('Errands'),
        findsNothing,
        reason: 'nothing uses it any more, and this needed no manual refresh',
      );
    },
  );

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

  testWidgets('the capture button hides while searching', (tester) async {
    await services.captureText('a note');
    await services.refreshTimeline();
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();
    expect(find.byType(FloatingActionButton), findsOneWidget);

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    // Capture is a timeline action; showing it here read as part of search
    // itself rather than what it actually did — open an unrelated note.
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('tapping a search result opens it, rather than closing search', (
    tester,
  ) async {
    // Reported symptom: the search field's own "tap anywhere outside closes
    // search" handling fires on pointer-down — before a tapped result card's
    // own onTap can resolve — so the card never got a chance to open. Search
    // silently closed back to the plain timeline instead.
    await services.captureText('a rare word: platypus');
    await services.captureText('something else entirely');
    await services.refreshTimeline();
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'platypus');
    await tester.pumpAndSettle(const Duration(milliseconds: 200));

    expect(find.text('a rare word: platypus'), findsOneWidget);
    // Not a plain tester.tap(): on a real device, `onTapOutside` (which fires
    // on pointer-*down*, well before the finger lifts) has time to run a
    // whole frame — removing the result card via _exitSearch's setState —
    // before pointer-*up* resolves the tap. A bare tap() sends both with no
    // pump in between, so it never actually exercised the race.
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('a rare word: platypus')),
    );
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.byType(NoteDetailSheet), findsOneWidget);
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

  testWidgets('the AI day summary never appears without a usable provider', (
    tester,
  ) async {
    await services.captureText('a note from today');

    // AI off entirely — the default.
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.auto_awesome), findsNothing);

    // AI on, but no provider configured — still nothing to show, and
    // nothing tries to reach a network the app has no address for.
    await preferences.setAiEnabled(true);
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.auto_awesome), findsNothing);
  });

  group('a tapped reminder', () {
    testWidgets('points at the note it was about, then stops', (tester) async {
      await services.captureText('call the plumber');
      await services.captureText('and something else');

      await tester.pumpWidget(
        NexApp(services: services, preferences: preferences),
      );
      await tester.pumpAndSettle();

      final target = (await services.worker.timeline()).firstWhere(
        (note) => note.content == 'call the plumber',
      );

      // What the notification handler does. Before this it did nothing at
      // all: the callback existed and nothing was ever assigned to it, so a
      // tapped reminder opened the app onto the same list as always and left
      // the reader to find the note themselves.
      services.reminders.onOpenNote!(target.id);
      await tester.pump();

      final marked = tester
          .widgetList<NoteSpotlight>(find.byType(NoteSpotlight))
          .where((widget) => widget.active);
      expect(marked, hasLength(1));

      // And it is a moment, not a mark: nothing is left highlighted once the
      // pulses are over, or the next reminder would arrive on a timeline that
      // is already pointing somewhere.
      await tester.pumpAndSettle(const Duration(seconds: 4));
      expect(
        tester
            .widgetList<NoteSpotlight>(find.byType(NoteSpotlight))
            .where((widget) => widget.active),
        isEmpty,
      );
    });
  });

  group('a reminder that has already rung', () {
    setUp(() {
      // Library measures the storage figure by walking directories — real
      // async I/O, which never resolves inside flutter_test's fake-async
      // zone, so its skeleton shimmers for the whole test and nothing ever
      // settles. These two tests only need Library as *somewhere else*, so
      // they ask the platform for the reduced motion it already offers.
      TestWidgetsFlutterBinding.ensureInitialized()
          .platformDispatcher
          .accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
        disableAnimations: true,
      );
      addTearDown(
        TestWidgetsFlutterBinding.ensureInitialized()
            .platformDispatcher
            .clearAccessibilityFeaturesTestValue,
      );
    });

    testWidgets('shows once more, then gives the slot back', (tester) async {
      await services.captureText('call the plumber');
      final note = (await services.worker.timeline()).single;
      // Already past. The notification for this went out an hour ago.
      await services.setDueAt(
        note.id,
        DateTime.now().toUtc().subtract(const Duration(hours: 1)),
      );

      await tester.pumpWidget(
        NexApp(services: services, preferences: preferences),
      );
      await tester.pumpAndSettle();

      // One last showing: the reader gets to see what it was for.
      expect(find.byIcon(Icons.notifications_active_outlined), findsOneWidget);

      // Leaving the timeline and coming back is what counts as having seen
      // it. Library is the nearest screen with a route of its own.
      await tester.tap(find.byIcon(Icons.inventory_2_outlined));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.notifications_active_outlined), findsNothing);
    });

    testWidgets('putting the app away counts as leaving', (tester) async {
      await services.captureText('call the plumber');
      final note = (await services.worker.timeline()).single;
      await services.setDueAt(
        note.id,
        DateTime.now().toUtc().subtract(const Duration(hours: 1)),
      );

      await tester.pumpWidget(
        NexApp(services: services, preferences: preferences),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.notifications_active_outlined), findsOneWidget);

      // How a spent reminder is actually met: the notification arrives, the
      // app is opened to read the note, and the app is put away again. No
      // route is ever pushed, so `didPushNext` never fires — and the chip
      // used to stay on the card until the reminder was deleted by hand.
      // The whole cycle, in order. Flutter asserts on each transition, and
      // between `resumed` and `paused` there are two more states in both
      // directions — `inactive` on the way out and `hidden` either side of
      // the bottom. Shortcutting any of them throws, which is fair: no device
      // makes those jumps either.
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pumpAndSettle();
      for (final state in [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.notifications_active_outlined), findsNothing);
    });

    testWidgets('a repeating reminder is never spent', (tester) async {
      await services.captureText('call the plumber');
      final note = (await services.worker.timeline()).single;
      // The normal state of a repeat that has already fired: its stored time
      // is when the series started, so by the one-off rule it looks lapsed.
      await services.setDueAt(
        note.id,
        DateTime.now().toUtc().subtract(const Duration(days: 3)),
        repeat: NoteRepeat.daily,
      );

      await tester.pumpWidget(
        NexApp(services: services, preferences: preferences),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.inventory_2_outlined));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      // It is still going to ring tomorrow, so the chip stays — and it says
      // how often rather than counting down to a moment that has gone.
      expect(find.byIcon(Icons.notifications_active_outlined), findsOneWidget);
      expect(find.text('Every day'), findsOneWidget);
    });

    testWidgets('a reminder still ahead keeps its chip', (tester) async {
      await services.captureText('call the plumber');
      final note = (await services.worker.timeline()).single;
      await services.setDueAt(
        note.id,
        DateTime.now().toUtc().add(const Duration(hours: 3)),
      );

      await tester.pumpWidget(
        NexApp(services: services, preferences: preferences),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.inventory_2_outlined));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      // Nothing about it has been delivered yet, so there is nothing to have
      // seen. This is the half the chip was added for.
      expect(find.byIcon(Icons.notifications_active_outlined), findsOneWidget);
    });
  });

  group('the home layout control', () {
    testWidgets('turns the four things above the notes off', (tester) async {
      await services.captureText('a note');
      await tester.pumpWidget(
        NexApp(services: services, preferences: preferences),
      );
      await tester.pumpAndSettle();

      // The tag row is the one of the four that is unmistakable in a test:
      // "All" is its own chip and nothing else on the screen says it.
      expect(find.text('All'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.dashboard_customize_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tag row'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      expect(find.text('All'), findsNothing);
      expect(find.text('a note'), findsOneWidget);
    });

    testWidgets('hiding the search box brings its icon back', (tester) async {
      await services.captureText('a note');
      await tester.pumpWidget(
        NexApp(services: services, preferences: preferences),
      );
      await tester.pumpAndSettle();

      // Removed from the app bar when the field became permanent, because it
      // pointed at something already on screen. With the field off it is the
      // only way to search at all.
      expect(find.byTooltip('Search'), findsNothing);

      await tester.tap(find.byIcon(Icons.dashboard_customize_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Search box'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);
      expect(find.byTooltip('Search'), findsOneWidget);

      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
    });
  });

  group('a date heading', () {
    testWidgets('can delete its whole run, after asking', (tester) async {
      await services.captureText('first');
      await services.captureText('second');
      await tester.pumpWidget(
        NexApp(services: services, preferences: preferences),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Group actions').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete this group'));
      await tester.pumpAndSettle();

      // Asked, not undone: a heading's menu takes a whole day away in one
      // tap, and an undo banner is not a safety net for that much.
      expect(find.text('first'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('first'), findsNothing);
      expect(find.text('second'), findsNothing);
      expect((await services.worker.timeline()), isEmpty);
    });

    testWidgets('the menu does not fold the group on the way past', (
      tester,
    ) async {
      await services.captureText('first');
      await tester.pumpWidget(
        NexApp(services: services, preferences: preferences),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Group actions').first);
      await tester.pumpAndSettle();
      // Dismiss without choosing anything.
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      expect(find.text('first'), findsOneWidget);
    });
  });

  group('the assistant settings', () {
    testWidgets('are one screen, opened from two places', (tester) async {
      // The Settings row and the chat's own panel render the same body, so
      // there is one place where a control can be added or renamed. Before
      // this the chat had no way to reach them at all.
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AssistantScreen(preferences: preferences),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AssistantSettingsBody), findsOneWidget);
      // The settings are organised around the user, voice, and reach rather
      // than a flat run of unrelated controls.
      expect(find.text('About you'), findsOneWidget);
      final list = find.descendant(
        of: find.byType(AssistantSettingsBody),
        matching: find.byType(ListView),
      );
      await tester.drag(list, const Offset(0, -650));
      await tester.pumpAndSettle();
      expect(find.text('How it talks'), findsOneWidget);
      expect(find.text('Romantic'), findsOneWidget);
      await tester.drag(list, const Offset(0, -900));
      await tester.pumpAndSettle();
      expect(find.text('What it can see'), findsOneWidget);
    });
  });
}
