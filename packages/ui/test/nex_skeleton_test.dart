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

  testWidgets('the shimmer moves when animations are on', (tester) async {
    await tester.pumpWidget(
      host(const SizedBox(width: 200, child: NexSkeleton())),
    );

    BoxDecoration decoration() =>
        tester
                .widget<DecoratedBox>(
                  find.descendant(
                    of: find.byType(NexSkeleton),
                    matching: find.byType(DecoratedBox),
                  ),
                )
                .decoration
            as BoxDecoration;

    final first = (decoration().gradient! as LinearGradient).begin;
    await tester.pump(const Duration(milliseconds: 300));
    final later = (decoration().gradient! as LinearGradient).begin;
    expect(later, isNot(first));
  });
}
