import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderSliver;
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/platform/hold_menu.dart';
import 'package:nex_client/platform/nex_services.dart';
import 'package:nex_client/widgets/note_grid_card.dart';
import 'package:nex_ui/nex_ui.dart';

import 'support/nex_harness.dart';

/// The grid view as the owner tested it on a phone (2.6.28): the card size
/// sets how many tiles fit a row, a day folds with motion, the hold menu has
/// no "Show in full", and a tile says when its reminder rings.
void main() {
  late NexTestHarness harness;

  setUp(() async {
    harness = await NexTestHarness.create(
      name: 'nex_grid_',
      preferences: {
        'appearance.timeline_grid': true,
        'hold_menu.actions': ['expand', 'copy'],
      },
    );
    for (var i = 0; i < 7; i++) {
      await harness.services.captureText('grid note $i');
    }
    final urgent = (await harness.services.captureText('urgent with time'))!;
    await harness.services.setUrgent(urgent.id, true);
    await harness.services.setDueAt(
      urgent.id,
      DateTime.now().toUtc().add(const Duration(hours: 3)),
    );
    await harness.services.refreshTimeline();
  });

  tearDown(() => harness.dispose());

  Future<void> open(WidgetTester tester) async {
    tester.view.devicePixelRatio = 2.75;
    tester.view.physicalSize = const Size(1080, 2340);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness.app());
    await tester.pumpAndSettle();
  }

  int perRow(WidgetTester tester) {
    final tiles = find.byType(NexNoteGridCard);
    final top = tester.getRect(tiles.first).top;
    return tiles
        .evaluate()
        .where((e) => tester.getRect(find.byWidget(e.widget)).top == top)
        .length;
  }

  for (final (density, columns) in [
    (NexCardDensity.compact, 3),
    (NexCardDensity.standard, 2),
    (NexCardDensity.readable, 2),
  ]) {
    testWidgets('$density card size: $columns tiles to a row', (tester) async {
      await harness.preferences.setCardDensity(density);
      await open(tester);
      expect(perRow(tester), columns);
    });
  }

  testWidgets('a day folds and opens with motion, not a cut', (tester) async {
    final longNote = (await harness.services.captureText(
      List.filled(7, 'Longer preview').join('\n'),
    ))!;
    await harness.services.refreshTimeline();
    await open(tester);
    final longTile = find.byKey(ValueKey('grid-${longNote.id}'));
    final briefTile = find.ancestor(
      of: find.text('grid note 6'),
      matching: find.byType(NexNoteGridCard),
    );
    final longHeight = tester.getSize(longTile).height;
    final briefHeight = tester.getSize(briefTile).height;
    expect(longHeight, greaterThan(briefHeight));
    final header = find.text('Today');
    final body = find.byKey(const ValueKey('group-body-today'));
    double extent() =>
        tester.renderObject<RenderSliver>(body).geometry!.paintExtent;
    final openExtent = extent();
    final originalTile = tester.element(longTile);

    await tester.tap(header);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));
    expect(extent(), lessThan(openExtent));
    expect(extent(), greaterThan(0));
    expect(tester.element(longTile), same(originalTile));
    expect(tester.getSize(longTile).height, longHeight);

    // Reverse it before the close completes. The same grid should continue
    // from its current extent and keep the same mounted tile.
    final closingExtent = extent();
    await tester.tap(header);
    await tester.pump();
    expect(extent(), closeTo(closingExtent, 1));
    await tester.pumpAndSettle();
    expect(tester.element(longTile), same(originalTile));
    expect(extent(), closeTo(openExtent, 1));

    await tester.tap(header);
    await tester.pumpAndSettle();
    expect(find.byType(NexNoteGridCard), findsNothing);

    await tester.tap(header);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));
    expect(extent(), lessThan(openExtent));
    expect(extent(), greaterThan(0));
    final openingTile = tester.element(longTile);
    await tester.pumpAndSettle();
    expect(tester.element(longTile), same(openingTile));
    expect(tester.getSize(longTile).height, longHeight);
    expect(tester.getSize(briefTile).height, briefHeight);
  });

  testWidgets('reduced motion folds a group in one frame', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await open(tester);
    final header = find.text('Today');

    await tester.tap(header);
    await tester.pump();
    expect(find.byType(NexNoteGridCard), findsNothing);

    await tester.tap(header);
    await tester.pump();
    expect(find.byType(NexNoteGridCard), findsWidgets);
  });

  testWidgets('the hold menu has no Show in full on a tile', (tester) async {
    await open(tester);
    await tester.longPress(find.byType(NexNoteGridCard).first);
    await tester.pumpAndSettle();
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Show in full'), findsNothing);
  });

  testWidgets('a caption resizes its row and selecting keeps it in place', (
    tester,
  ) async {
    await open(tester);
    final tile = find.ancestor(
      of: find.text('grid note 6'),
      matching: find.byType(NexNoteGridCard),
    );
    final id = tester.widget<NexNoteGridCard>(tile).note.id;
    final short = tester.getSize(tile).height;

    await harness.services.setCaption(id, 'First line\nSecond line');
    await harness.services.refreshTimeline();
    await tester.pumpAndSettle();
    final withCaption = tester.getRect(tile);
    expect(withCaption.height, greaterThan(short));
    expect(find.text('First line\nSecond line'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('note-pick-$id')));
    await tester.pumpAndSettle();
    expect(tester.widget<NexNoteGridCard>(tile).selected, isTrue);
    expect(tester.getRect(tile), withCaption);
  });

  testWidgets(
    'a tile shows the list card\'s urgent mark and its reminder time',
    (tester) async {
      await open(tester);
      final tile = find.ancestor(
        of: find.text('urgent with time'),
        matching: find.byType(NexNoteGridCard),
      );
      expect(
        find.descendant(
          of: tile,
          matching: find.byIcon(Icons.local_fire_department_outlined),
        ),
        findsOneWidget,
      );
      final reminder = find.descendant(
        of: tile,
        matching: find.byKey(const ValueKey('grid-reminder')),
      );
      expect(reminder, findsOneWidget);
      final label = tester
          .widgetList<Text>(
            find.descendant(of: reminder, matching: find.byType(Text)),
          )
          .map((t) => t.data)
          .join();
      expect(label, contains('3'));
    },
  );

  // Like Pin: filled while it is on, outlined while it is off (2.6.28).
  testWidgets('urgent and remind look on in the menu when they are on', (
    tester,
  ) async {
    await harness.preferences.setHoldMenuActions([NexHoldAction.remind]);
    await open(tester);
    await tester.longPress(
      find.ancestor(
        of: find.text('urgent with time'),
        matching: find.byType(NexNoteGridCard),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.local_fire_department), findsOneWidget);
    expect(find.byIcon(Icons.notifications_active), findsOneWidget);
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();

    await tester.longPress(
      find.ancestor(
        of: find.text('grid note 6'),
        matching: find.byType(NexNoteGridCard),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.local_fire_department_outlined), findsWidgets);
    expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
  });

  testWidgets('a scroll moves the tiles without rebuilding them (2.7.2)', (
    tester,
  ) async {
    // Each day's grid used to sit in a SliverLayoutBuilder, which rebuilds on
    // every frame of a scroll — and with it every tile on screen. The tile a
    // short scroll leaves on screen must be the same widget after it.
    await open(tester);
    final tile = find.byType(NexNoteGridCard).first;
    final before = tester.widget(tile);
    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, -24),
    );
    await tester.pump();
    expect(identical(tester.widget(tile), before), isTrue);
  });
}
