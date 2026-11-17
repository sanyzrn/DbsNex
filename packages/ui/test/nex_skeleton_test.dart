import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nex_ui/nex_ui.dart';

/// The app had no loading affordance at all: every async surface went from
/// stale content straight to new content with nothing saying work was in
/// flight.
void main() {
  Widget host(Widget child, {bool animations = true}) => MaterialApp(
    theme: nexLightTheme(),
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: !animations),
      child: Scaffold(body: child),
    ),
  );

  testWidgets('a card skeleton occupies exactly the space its card will', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const SizedBox(width: 400, child: NexCardSkeleton())),
    );

    // Same box as NoteCard, so the list does not reflow when the notes land on
    // top of it — which is the whole point of showing one.
    expect(
      tester.getSize(find.byType(NexCardSkeleton)).height,
      nexCardHeight + nexCardInsets.vertical,
    );
  });

  testWidgets('the shimmer stops when animations are off', (tester) async {
    await tester.pumpWidget(
      host(const SizedBox(width: 200, child: NexSkeleton()), animations: false),
    );

    // Reduce-motion is resolved through MediaQuery, which already carries the
    // in-app preference — so this needs no preference of its own.
    // Scoped to the skeleton: the Cupertino page transition contributes a
    // DecoratedBox of its own, and it is not a BoxDecoration.
    final decoration =
        tester
                .widget<DecoratedBox>(
                  find.descendant(
                    of: find.byType(NexSkeleton),
                    matching: find.byType(DecoratedBox),
                  ),
                )
                .decoration
            as BoxDecoration;
    expect(decoration.gradient, isNull);
    expect(decoration.color, isNotNull);

    // And it is not left running off screen: pumping forever would time out if
    // a repeating controller were still ticking.
    await tester.pumpAndSettle();
  });

  testWidgets('the shimmer moves without rebuilding anything', (tester) async {
    await tester.pumpWidget(
      host(const SizedBox(width: 200, child: NexSkeleton())),
    );

    // The band travels by repainting (the painter listens to the
    // animation), not by rebuilding a fresh DecoratedBox per tick: a
    // timeline's first load shows sixteen skeletons at once, and the
    // rebuilds were churn on exactly the frames the real cards needed.
    // The skeleton's own widgets only — the framework's focus scopes
    // rebuild during any pump, and they are nobody's business here.
    var rebuilds = 0;
    debugOnRebuildDirtyWidget = (element, _) {
      final name = element.widget.runtimeType.toString();
      if (name == 'CustomPaint' || name == 'DecoratedBox') rebuilds++;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);
    final before = NexSkeleton.debugPaints;
    await tester.pump(const Duration(milliseconds: 300));
    final later = NexSkeleton.debugPaints;

    expect(later, greaterThan(before)); // the band still moves
    expect(rebuilds, 0); // and no widget of the skeleton was rebuilt for it
  });
}
