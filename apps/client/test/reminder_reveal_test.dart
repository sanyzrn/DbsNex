import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_client/widgets/note_spotlight.dart';
import 'package:nex_core/nex_core.dart';
import 'package:nex_ui/nex_ui.dart';

import 'package:nex_client/platform/nex_services.dart';

import 'support/nex_harness.dart';

void main() {
  for (final density in NexCardDensity.values) {
    testWidgets('$density reminder reveals a note past the initial page', (
      tester,
    ) async {
      final h = await NexTestHarness.create();
      addTearDown(h.dispose);
      await h.preferences.setCardDensity(density);
      final target = (await h.db.captureText('The oldest reminder target'))!;
      for (var i = 0; i < 225; i++) {
        await h.db.captureText('Newer note $i');
      }
      await h.services.refreshTimeline();
      await tester.pumpWidget(h.app());
      await tester.pumpAndSettle();
      expect(find.text('The oldest reminder target'), findsNothing);
      h.services.reminders.onOpenNote!(target.id);
      Finder active() =>
          find.byWidgetPredicate((w) => w is NoteSpotlight && w.active);
      for (var i = 0; i < 150 && active().evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(active(), findsOneWidget);
      final card = find.descendant(
        of: active(),
        matching: find.byWidgetPredicate(
          (w) => w is NoteCard && w.note.id == target.id,
        ),
      );
      expect(card, findsOneWidget);
      final rect = tester.getRect(card);
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(
        rect.top,
        lessThan(
          tester.view.physicalSize.height / tester.view.devicePixelRatio,
        ),
      );
      expect(tester.widget<NoteCard>(card).note.type, NoteType.text);
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      // A second notification must still find an already-exhausted page.
      h.services.reminders.onOpenNote!(target.id);
      for (var i = 0; i < 150 && active().evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(active(), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
      '$density spotlight outline follows the actual card gutter and radius',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: NexCardDensityScope(
              density: density,
              child: Center(
                child: SizedBox(
                  width: 320,
                  height: 120,
                  child: NoteSpotlight(
                    active: true,
                    onDone: () {},
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
        );
        final outline = find.descendant(
          of: find.byType(NoteSpotlight),
          matching: find.byType(DecoratedBox),
        );
        final box = tester.widget<DecoratedBox>(outline);
        final decoration = box.decoration as BoxDecoration;
        expect(decoration.borderRadius, BorderRadius.circular(NexRadius.lg));
        final outer = tester.getRect(find.byType(NoteSpotlight));
        final inner = tester.getRect(outline);
        expect(inner, density.cardInsets.deflateRect(outer));
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
