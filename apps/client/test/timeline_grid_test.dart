import 'package:flutter/material.dart';
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
    await open(tester);
    final header = find.text('Today');
    await tester.tap(header);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    // Mid-fold: the rows are still there, shrinking.
    final folding = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('grid-fold-'),
    );
    expect(folding, findsWidgets);
    expect(find.byType(SizeTransition), findsWidgets);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.byType(NexNoteGridCard), findsNothing);

    await tester.tap(header);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(folding, findsWidgets);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(folding, findsNothing, reason: 'back to the lazy grid');
    expect(find.byType(NexNoteGridCard), findsWidgets);
  });

  testWidgets('the hold menu has no Show in full on a tile', (tester) async {
    await open(tester);
    await tester.longPress(find.byType(NexNoteGridCard).first);
    await tester.pumpAndSettle();
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Show in full'), findsNothing);
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
}
