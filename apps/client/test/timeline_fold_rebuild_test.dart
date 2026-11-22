import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderProxySliver;
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/app.dart';
import 'package:nex_client/platform/backup_policy.dart';
import 'package:nex_client/platform/nex_preferences.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/widgets/note_grid_card.dart';
import 'package:nex_ui/nex_ui.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/in_process_db.dart';

/// What a fold is allowed to touch: its own heading, the presence of its own
/// body — and not one card more.
///
/// A fold used to be announced to the whole screen, twice per toggle: the
/// model's notification rebuilt the screen on the frame the fold started,
/// and the settle frame rebuilt it again, and the preference write that
/// remembers the fold rebuilt it a third time. A screen rebuild means every
/// visible card: fresh builder closures, a new sliver delegate, and the
/// framework rebuilds every mounted child of a sliver whose delegate
/// changed. These tests hold the fix to its promise — a fold moves a
/// heading, and the cards on screen do not so much as rebuild.
void main() {
  late Directory tmp;
  late NexServices services;
  late NexPreferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('nex_fold_rebuild_');
    final dbPath = p.join(tmp.path, 'nex.sqlite');
    final mediaDir = p.join(tmp.path, 'media');
    Directory(mediaDir).createSync(recursive: true);
    Directory(p.join(tmp.path, 'backups')).createSync(recursive: true);
    services = NexServices.forTest(
      worker: InProcessDb(dbPath: dbPath, deviceId: 'test'),
      deviceId: 'test',
      preferences: await NexPreferences.load(),
      backupPolicy: BackupPolicy(await SharedPreferences.getInstance()),
      dbPath: dbPath,
      mediaDir: mediaDir,
      backupDir: p.join(tmp.path, 'backups'),
    );
    preferences = await NexPreferences.load();
    await preferences.setLocale('en');
    await preferences.completeOnboarding();
    await preferences.completeTour();
  });

  tearDown(() async {
    await services.dispose();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
  }

  Future<void> seed() async {
    for (var i = 0; i < 6; i++) {
      await services.captureText('today note $i');
    }
    final older = await services.captureText('yesterday note');
    (services.worker as InProcessDb).backdate(
      older!.id,
      DateTime.now().subtract(const Duration(days: 1)),
    );
    await services.refreshTimeline();
  }

  double offset(WidgetTester tester) {
    final state = tester.state<ScrollableState>(find.byType(Scrollable).first);
    final position = state.position;
    return position.hasContentDimensions ? position.pixels : 0;
  }

  /// The cards a fold must not rebuild, built or cached alike — a card in
  /// the scroll cache is as mounted as one on screen, and finders skip it
  /// only because it is offstage, which is why none of these tests may use
  /// an ordinary finder to count cards.
  Finder allCards() => find.byWidgetPredicate(
    (widget) => widget is NoteCard || widget is NexNoteGridCard,
    skipOffstage: false,
  );

  Finder cardText(String text) => find.text(text, skipOffstage: false);

  /// Counts rebuilds of the cards that existed when it was installed.
  int Function() watchCards(Set<Element> cards) {
    var rebuilds = 0;
    debugOnRebuildDirtyWidget = (element, _) {
      if (cards.contains(element)) rebuilds++;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);
    return () => rebuilds;
  }

  testWidgets('folding a group rebuilds no card, either way', (tester) async {
    phone(tester);
    await seed();
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();
    final before = allCards().evaluate().toSet();
    expect(before, isNotEmpty);
    // The list starts at the top, so the offset is already the one to keep.
    final offsetBefore = offset(tester);

    final rebuilds = watchCards(before);
    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();
    expect(cardText('today note 5'), findsNothing);
    expect(find.text('yesterday note'), findsOneWidget);
    // And back open, through the reveal and its settle.
    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();
    expect(cardText('today note 5'), findsOneWidget);
    // The group's tail may sit in the scroll cache rather than on screen;
    // being built is the promise, and a cached card is an offstage one to
    // the ordinary finders.
    expect(cardText('today note 0'), findsOneWidget);

    expect(rebuilds(), 0, reason: 'a fold rebuilt a card already on screen');
    expect(
      offset(tester),
      offsetBefore,
      reason: 'the list sits where it was left',
    );
  });

  testWidgets('folding a grid group rebuilds no tile, either way', (
    tester,
  ) async {
    phone(tester);
    await preferences.setTimelineGrid(true);
    await seed();
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();
    final before = allCards().evaluate().toSet();
    expect(before, isNotEmpty);

    final rebuilds = watchCards(before);
    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();
    expect(cardText('today note 5'), findsNothing);
    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();
    expect(cardText('today note 5'), findsOneWidget);

    expect(rebuilds(), 0, reason: 'a fold rebuilt a tile already on screen');
  });

  testWidgets('a pinch folds and opens every group without rebuilding a card', (
    tester,
  ) async {
    phone(tester);
    await seed();
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();
    final before = allCards().evaluate().toSet();
    final rebuilds = watchCards(before);

    final point = tester.getCenter(find.byType(CustomScrollView).first);
    final first = await tester.startGesture(
      point - const Offset(90, 0),
      pointer: 1,
    );
    final second = await tester.startGesture(
      point + const Offset(90, 0),
      pointer: 2,
    );
    await first.moveTo(point - const Offset(35, 0));
    await second.moveTo(point + const Offset(35, 0));
    await first.up();
    await second.up();
    await tester.pumpAndSettle();
    expect(cardText('today note 5'), findsNothing);
    expect(preferences.collapsedTimelineGroups, contains('today'));

    final a = await tester.startGesture(
      point - const Offset(35, 0),
      pointer: 3,
    );
    final b = await tester.startGesture(
      point + const Offset(35, 0),
      pointer: 4,
    );
    await a.moveTo(point - const Offset(95, 0));
    await b.moveTo(point + const Offset(95, 0));
    await a.up();
    await b.up();
    await tester.pumpAndSettle();
    expect(cardText('today note 5'), findsOneWidget);
    expect(preferences.collapsedTimelineGroups, isEmpty);

    expect(rebuilds(), 0, reason: 'a pinch rebuilt a card already on screen');
  });

  testWidgets('a card keeps its element while its group folds shut', (
    tester,
  ) async {
    phone(tester);
    await seed();
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();
    // The same promise the reveal makes, held from the card's side: the
    // element — and with it every piece of state under it — survives the
    // fold that is folding it away.
    final card = tester.element(find.byType(NoteCard).first);

    await tester.tap(find.text('Today'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(tester.element(find.byType(NoteCard).first), same(card));

    await tester.pumpAndSettle();
    // Yesterday's card may well be on screen now; the folded group's cards
    // are gone, the card that folded among them.
    expect(cardText('today note 5'), findsNothing);
    expect(find.byType(NoteCard).evaluate(), isNot(contains(card)));
  });

  testWidgets('a second tap reverses an in-progress group fold', (
    tester,
  ) async {
    phone(tester);
    await seed();
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();

    final heading = find.text('Today');
    final card = tester.element(find.byType(NoteCard).first);
    await tester.tap(heading);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 45));
    await tester.tap(heading);
    await tester.pumpAndSettle();

    expect(preferences.collapsedTimelineGroups, isEmpty);
    expect(tester.element(find.byType(NoteCard).first), same(card));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the settled reveal builds its whole group into the cache', (
    tester,
  ) async {
    phone(tester);
    await seed();
    await tester.pumpWidget(
      NexApp(services: services, preferences: preferences),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();

    // The frame the animation settles on is the frame the reveal hands its
    // sliver back to the viewport's own layout, cache and all. Everything
    // the group holds is built by then — nothing is left for a later scroll
    // to pay for — and the sliver's geometry says so plainly.
    final reveal = tester.renderObject<RenderProxySliver>(
      find.byKey(const ValueKey('group-body-today')),
    );
    expect(reveal.geometry!.scrollExtent, greaterThan(500));
    expect(cardText('today note 0'), findsOneWidget);
    expect(
      cardText('today note 5'),
      findsOneWidget,
      reason: 'every row of the reopened group is built',
    );
  });
}
